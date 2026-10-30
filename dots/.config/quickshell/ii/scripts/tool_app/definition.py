"""Versioned, strict YAML -> JSON tool-app definitions. Loading never executes code.

CLI: python definition.py app.yaml [--output app.json]
Relative component/script paths resolve against app.yaml, never the shell cwd.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
import re
import sys

IDENTIFIER = re.compile(r'^[A-Za-z][A-Za-z0-9_.-]*$')
BUILTINS = {
    'undo': dict(label='Undo',icon='undo',shortcut='Ctrl+Z',enabledWhen='canUndo',target=dict(kind='qml',handler='undo')),
    'redo': dict(label='Redo',icon='redo',shortcut='Ctrl+Shift+Z',enabledWhen='canRedo',target=dict(kind='qml',handler='redo')),
}

class DefinitionError(ValueError):
    pass


def fail(where, message):
    raise DefinitionError(f'{where}: {message}')


def mapping(value, where, allowed, required=()):
    if not isinstance(value, dict): fail(where,'expected a mapping')
    if any(not isinstance(key,str) for key in value): fail(where,'mapping keys must be strings')
    unknown=set(value)-set(allowed)
    if unknown: fail(where,'unknown fields: '+', '.join(sorted(unknown)))
    missing=set(required)-set(value)
    if missing: fail(where,'missing fields: '+', '.join(sorted(missing)))
    return value


def string(value, where, identifier=False):
    if not isinstance(value,str) or not value.strip(): fail(where,'expected a nonempty string')
    if identifier and not IDENTIFIER.fullmatch(value): fail(where,'invalid identifier')
    return value


def array(value, where):
    if not isinstance(value,list): fail(where,'expected a list')
    return value


def finite_json(value, where):
    active=set();remaining=100000
    def visit(item,location,depth=0):
        nonlocal remaining
        remaining-=1
        if remaining<0 or depth>64:fail(location,'JSON data is too large or deeply nested')
        if item is None or type(item) in (bool,str):return
        if type(item) is int:
            try:finite=math.isfinite(item)
            except OverflowError:finite=False
            if not finite:fail(location,'expected finite JSON data')
            return
        if type(item) is float:
            if not math.isfinite(item):fail(location,'expected finite JSON data')
            return
        if not isinstance(item,(dict,list)):fail(location,'expected finite JSON data')
        if id(item) in active:fail(location,'recursive aliases are not supported')
        active.add(id(item))
        if isinstance(item,dict):
            for key,child in item.items():
                if not isinstance(key,str):fail(location,'mapping keys must be strings')
                visit(child,location+'.'+key,depth+1)
        else:
            for index,child in enumerate(item):visit(child,f'{location}[{index}]',depth+1)
        active.remove(id(item))
    visit(value,where)
    try:
        json.dumps(value,allow_nan=False)
        return copy.deepcopy(value)
    except (ValueError,TypeError,RecursionError):fail(where,'expected finite JSON data')


def condition(value, where, states):
    if isinstance(value,bool): return value
    if isinstance(value,str):
        if value not in states: fail(where,f'unknown state {value!r}')
        return value
    mapping(value,where,('all','any','not','eq'),())
    if len(value)!=1: fail(where,'use exactly one condition operator')
    op,operand=next(iter(value.items()))
    if op in ('all','any'):
        items=array(operand,where+'.'+op)
        if not items: fail(where,'condition list cannot be empty')
        return {op:[condition(item,where+'.'+op,states) for item in items]}
    if op=='not': return {op:condition(operand,where+'.not',states)}
    items=array(operand,where+'.eq')
    if len(items)!=2 or not isinstance(items[0],str) or items[0] not in states: fail(where,'eq must contain a known state and a literal')
    return {'eq':[items[0],finite_json(items[1],where)]}


def resolve_file(value, base, where, suffix):
    source=(base/string(value,where)).resolve()
    if source.suffix.lower()!=suffix or not source.is_file(): fail(where,f'expected an existing {suffix} file')
    return str(source)


def compile_definition(document, base: Path):
    """Validate and normalize one document; return a fresh JSON-compatible mapping."""
    finite_json(document,'definition')
    try:base=Path(base).resolve()
    except (TypeError,ValueError):fail('definition','invalid source directory')
    mapping(document,'definition',('version','app','state','backends','actions','toolbar','tools','utilities','contextActions','settings','components'),('version','app'))
    if type(document['version']) is not int or document['version']!=1: fail('version','only version 1 is supported')
    app=mapping(document['app'],'app',('id','name','icon'),('id','name','icon'))
    result=dict(version=1,app={key:string(value,'app.'+key,key=='id') for key,value in app.items()})
    state=document.get('state',{})
    if not isinstance(state,dict): fail('state','expected a mapping')
    result['state']={string(key,'state key',True):finite_json(value,'state.'+key) for key,value in state.items()}
    result['state'].setdefault('canUndo',False);result['state'].setdefault('canRedo',False)
    for builtin in ('canUndo','canRedo'):
        if type(result['state'][builtin]) is not bool:fail('state.'+builtin,'expected boolean')
    if any(key.startswith('settings.') for key in result['state']):
        fail('state','settings.* names are reserved for declared setting fields')
    states=set(result['state'])
    declared_settings=mapping(document.get('settings',{}),'settings',('title','groups'))
    for group_index,group in enumerate(array(declared_settings.get('groups',[]),'settings.groups')):
        where=f'settings.groups[{group_index}]'
        mapping(group,where,('id','title','icon','visibleWhen','items'),('id','title','icon','items'))
        for item_index,item in enumerate(array(group['items'],where+'.items')):
            location=where+f'.items[{item_index}]'
            if not isinstance(item,dict):fail(location,'expected a mapping')
            if item.get('kind')=='field':
                if 'path' not in item:fail(location,'missing path')
                states.add('settings.'+string(item['path'],location+'.path',True))
    backends=document.get('backends',{})
    if not isinstance(backends,dict): fail('backends','expected a mapping')
    result['backends']={}
    for key,value in backends.items():
        string(key,'backend id',True)
        mapping(value,'backends.'+key,('program','script','args'),('program','script'))
        args=array(value.get('args',[]),'backend args')
        if not all(isinstance(arg,str) for arg in args): fail('backend args','all arguments must be strings')
        result['backends'][key]=dict(command=[string(value['program'],'backend program'),resolve_file(value['script'],base,'backend script','.py'),*args])
    components=document.get('components',{})
    if not isinstance(components,dict): fail('components','expected a mapping')
    result['components']={string(key,'component id',True):Path(resolve_file(value,base,'components.'+key,'.qml')).as_uri() for key,value in components.items()}
    actions=copy.deepcopy(BUILTINS)
    supplied=document.get('actions',{})
    if not isinstance(supplied,dict): fail('actions','expected a mapping')
    actions.update(supplied)
    result['actions']={}
    for key,value in actions.items():
        string(key,'action id',True)
        mapping(value,'actions.'+key,('label','icon','tooltip','shortcut','enabledWhen','visibleWhen','checkedWhen','dirtyWhen','target','arguments'),('label','icon','target'))
        target=mapping(value['target'],'action target',('kind','handler','backend','operation'),('kind',))
        if target['kind']=='qml':
            mapping(target,'qml target',('kind','handler'),('kind','handler'))
            string(target['handler'],'qml handler',True)
        elif target['kind']=='backend':
            mapping(target,'backend target',('kind','backend','operation'),('kind','backend','operation'))
            string(target['backend'],'backend target.backend',True)
            if target['backend'] not in backends: fail('action target','unknown backend')
            string(target['operation'],'backend operation',True)
        else: fail('action target','kind must be qml or backend')
        item=dict(label=string(value['label'],'action label'),icon=string(value['icon'],'action icon'),target=copy.deepcopy(target),arguments=finite_json(value.get('arguments',{}),'action arguments'))
        if not isinstance(item['arguments'],dict): fail('action arguments','expected a mapping')
        for field in ('tooltip','shortcut'):
            if field in value:item[field]=string(value[field],field)
        for field,default in (('enabledWhen',True),('visibleWhen',True),('checkedWhen',False),('dirtyWhen',False)):
            item[field]=condition(value.get(field,default),'actions.'+key+'.'+field,states)
        result['actions'][key]=item
    shortcuts=[a['shortcut'] for a in result['actions'].values() if 'shortcut' in a]
    if len(shortcuts)!=len(set(shortcuts)): fail('actions','duplicate shortcuts')
    def action_list(value,where):
        items=array(value,where)
        if not all(isinstance(i,str) for i in items) or len(items)!=len(set(items)): fail(where,'use unique action identifiers')
        for item in items:
            if item not in actions: fail(where,f'unknown action {item!r}')
        return items.copy()
    toolbar=[]
    for index,group in enumerate(array(document.get('toolbar',[]),'toolbar')):
        if group=='stretch': toolbar.append(dict(stretch=True));continue
        toolbar.append(dict(actions=action_list(group,f'toolbar[{index}]')))
    result['toolbar']=toolbar
    result['tools']=action_list(document.get('tools',[]),'tools')
    utilities=mapping(document.get('utilities',{}),'utilities',('includeHistory','actions','placement'))
    if type(utilities.get('includeHistory',True)) is not bool: fail('utilities.includeHistory','expected boolean')
    utility_actions=action_list(utilities.get('actions',[]),'utilities.actions')
    utility_actions=list(dict.fromkeys((['undo','redo'] if utilities.get('includeHistory',True) else [])+utility_actions))
    placement=utilities.get('placement','topRight')
    if placement not in ('topRight','bottomLeft'):fail('utilities.placement','expected topRight or bottomLeft')
    result['utilities']=dict(actions=utility_actions,placement=placement)
    context=mapping(document.get('contextActions',{}),'contextActions',('actions','placement','visibleWhen'))
    placement=context.get('placement','belowTools')
    if placement not in ('topRight','belowTools'):fail('contextActions.placement','expected topRight or belowTools')
    if placement=='topRight' and result['utilities']['placement']=='topRight' and context.get('actions') and utility_actions:
        fail('contextActions.placement','context and utility pills cannot share topRight')
    result['contextActions']=dict(actions=action_list(context.get('actions',[]),'contextActions.actions'),placement=placement,visibleWhen=condition(context.get('visibleWhen',True),'contextActions.visibleWhen',states))
    settings=mapping(document.get('settings',{}),'settings',('title','groups'))
    title=string(settings.get('title','Project settings'),'settings.title')
    groups=[];paths=set();defaults={}
    for index,group in enumerate(array(settings.get('groups',[]),'settings.groups')):
        where=f'settings.groups[{index}]'
        mapping(group,where,('id','title','icon','visibleWhen','items'),('id','title','icon','items'))
        string(group['id'],where+'.id',True)
        if any(g['id']==group['id'] for g in groups):fail(where,'duplicate group id')
        items=[]
        for index,item in enumerate(array(group['items'],where+'.items')):
            location=where+f'.items[{index}]'
            mapping(item,location,('kind','path','label','icon','type','default','min','max','step','unit','choices','enabledWhen','visibleWhen','readOnly','action','component'),('kind',))
            kind=item['kind']
            normalized={'kind':kind}
            if kind=='field':
                mapping(item,location,('kind','path','label','icon','type','default','min','max','step','unit','choices','enabledWhen','visibleWhen','readOnly'))
                for field in ('path','label','type','default'):
                    if field not in item:fail(location,'missing '+field)
                field_path=string(item['path'],location+'.path',True)
                if field_path in paths:fail(location,'duplicate setting path')
                paths.add(field_path)
                field_type=item['type']
                if field_type not in ('bool','int','real','string','label'):fail(location,'unsupported field type')
                default=finite_json(item['default'],location+'.default')
                valid=(type(default) is bool if field_type=='bool' else type(default) is int if field_type=='int' else type(default) in (int,float) if field_type=='real' else isinstance(default,str))
                if not valid:fail(location,'default does not match field type')
                if field_type in ('int','real') and not item.get('choices') and any(bound not in item for bound in ('min','max')):
                    fail(location,'numeric fields without choices require explicit min and max')
                setting={key:copy.deepcopy(item[key]) for key in ('path','label','type','icon','min','max','step','unit','choices','readOnly') if key in item}
                string(setting['label'],location+'.label')
                for text_field in ('icon','unit'):
                    if text_field in setting:string(setting[text_field],location+'.'+text_field)
                if field_type not in ('int','real') and any(bound in setting for bound in ('min','max','step')):
                    fail(location,'numeric bounds require an int or real field')
                if field_type=='label':
                    if setting.get('readOnly') is False:fail(location,'label fields must be readOnly')
                    setting.setdefault('readOnly',True)
                for bound in ('min','max','step'):
                    if bound in setting and (type(setting[bound]) not in (int,float) or not math.isfinite(setting[bound])):fail(location,'invalid numeric bound')
                if 'min' in setting and 'max' in setting and setting['min']>setting['max']:fail(location,'min exceeds max')
                if field_type=='int' and any(type(setting[bound]) is not int for bound in ('min','max','step') if bound in setting):fail(location,'int fields require integer bounds and step')
                if setting.get('step',1)<=0:fail(location,'step must be positive')
                if field_type in ('int','real') and (default<setting.get('min',-math.inf) or default>setting.get('max',math.inf)):fail(location,'default outside bounds')
                if 'readOnly' in setting and type(setting['readOnly']) is not bool:fail(location,'readOnly must be boolean')
                if 'choices' in setting:
                    choices=array(setting['choices'],location+'.choices');values=[]
                    for choice in choices:
                        mapping(choice,location+'.choice',('name','value'),('name','value'))
                        string(choice['name'],location+'.choice.name');finite_json(choice['value'],location)
                        candidate=choice['value']
                        matches=(type(candidate) is bool if field_type=='bool' else type(candidate) is int if field_type=='int' else type(candidate) in (int,float) if field_type=='real' else isinstance(candidate,str))
                        if not matches:fail(location+'.choices','choice value does not match field type')
                        if field_type in ('int','real') and (candidate<setting.get('min',-math.inf) or candidate>setting.get('max',math.inf)):
                            fail(location+'.choices','choice value outside bounds')
                        if choice['value'] in values:fail(location,'duplicate choice value')
                        values.append(choice['value'])
                    if default not in values:fail(location,'default missing from choices')
                normalized['setting']=setting;defaults[field_path]=default
            elif kind=='action':
                mapping(item,location,('kind','action','enabledWhen','visibleWhen'),('kind','action'))
                string(item['action'],location+'.action',True)
                if item.get('action') not in actions:fail(location,'unknown action')
                normalized['action']=item['action']
            elif kind=='component':
                mapping(item,location,('kind','component','enabledWhen','visibleWhen'),('kind','component'))
                string(item['component'],location+'.component',True)
                if item.get('component') not in components:fail(location,'unknown component')
                normalized['component']=item['component']
            else:fail(location,'kind must be field, action, or component')
            for field in ('enabledWhen','visibleWhen'): normalized[field]=condition(item.get(field,True),location+'.'+field,states)
            items.append(normalized)
        groups.append(dict(id=group['id'],title=string(group['title'],where+'.title'),icon=string(group['icon'],where+'.icon'),visibleWhen=condition(group.get('visibleWhen',True),where+'.visibleWhen',states),items=items))
    result['settings']=dict(title=title,groups=groups,defaults=defaults)
    return result


def load_definition(filename):
    import yaml
    class StrictLoader(yaml.SafeLoader):
        pass
    def unique_mapping(loader,node,deep=False):
        result={}
        for key_node,value_node in node.value:
            key=loader.construct_object(key_node,deep=deep)
            if not isinstance(key,str):fail('yaml','mapping keys must be strings')
            if key in result:fail('yaml',f'duplicate key {key!r} at line {key_node.start_mark.line+1}')
            result[key]=loader.construct_object(value_node,deep=deep)
        return result
    StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,unique_mapping)
    source=Path(filename).resolve()
    try:
        if source.stat().st_size>1024*1024: fail('yaml','definition exceeds 1 MiB')
        document=yaml.load(source.read_text(),Loader=StrictLoader)
        return compile_definition(document,source.parent)
    except DefinitionError:raise
    except (yaml.YAMLError,RecursionError,ValueError) as error:raise DefinitionError(f'yaml: {error}') from error


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('definition');parser.add_argument('--output')
    args=parser.parse_args()
    try:
        result=load_definition(args.definition)
        encoded=json.dumps(result,ensure_ascii=False,allow_nan=False,indent=2)+'\n'
        if args.output:Path(args.output).write_text(encoded)
        else:print(encoded,end='')
    except (OSError,ValueError,ImportError) as error:
        print(json.dumps(dict(error=str(error))),file=sys.stderr);return 1
    return 0

if __name__=='__main__':raise SystemExit(main())
