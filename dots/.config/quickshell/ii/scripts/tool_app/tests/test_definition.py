import copy
import json
from pathlib import Path
import subprocess
import sys
import pytest
from ..definition import DefinitionError,compile_definition,load_definition

ROOT=Path(__file__).resolve().parents[3]
EXAMPLE=ROOT/'modules/common/tool_app/examples/starter/app.yaml'


def minimal():return dict(version=1,app=dict(id='org.example.Test',name='Test',icon='edit'))


def test_defaults_do_not_mutate_input():
    source=minimal();before=copy.deepcopy(source)
    result=compile_definition(source,Path('/tmp'))
    assert source==before
    assert result['utilities']['actions']==['undo','redo']
    assert result['state']['canUndo'] is False
    assert result['actions']['undo']['target']==dict(kind='qml',handler='undo')
    assert result['settings']['defaults']=={}


def test_yaml_example_resolves_paths_and_groups():
    result=load_definition(EXAMPLE)
    assert result['backends']['worker']['command'][1]==str(EXAMPLE.parent/'backend.py')
    assert result['components']['profiles']==(EXAMPLE.parent/'qml/ProfileEditor.qml').as_uri()
    assert result['toolbar'][0]['actions']==['settings']
    assert result['settings']['defaults']['processing.quality']=='balanced'
    assert result['utilities']['actions']==['undo','redo','reset']
    assert result['actions']['save']['enabledWhen']=={'all':['hasDocument',{'not':'busy'}]}
    json.dumps(result,allow_nan=False)


@pytest.mark.parametrize('patch,message',[
    ({'versoin':1},'unknown fields'),
    ({'version':2},'version'),
    ({'tools':['missing']},'unknown action'),
    ({'tools':['undo','undo']},'unique'),
    ({'utilities':{'includeHistory':'false'}},'boolean'),
    ({'contextActions':{'actions':['undo'],'placement':'topRight'}},'cannot share'),
    ({'state':{'busy':float('nan')}},'finite JSON'),
    ({'components':{'editor':'missing.qml'}},'existing .qml'),
    ({'toolbar':'undo'},'list'),
])
def test_invalid_definitions_fail_with_context(patch,message):
    with pytest.raises(DefinitionError,match=message):compile_definition(minimal()|patch,Path('/tmp'))


def test_conditions_targets_and_shortcuts_are_validated():
    action=dict(label='Run',icon='play_arrow',target=dict(kind='qml',handler='run'))
    for patch in ({'enabledWhen':'typo'},{'enabledWhen':{'eval':'evil()'}},{'target':{'kind':'shell','handler':'x'}},{'target':{'kind':'backend','backend':'missing','operation':'run'}}):
        with pytest.raises(DefinitionError):compile_definition(minimal()|{'actions':{'run':action|patch}},Path('/tmp'))
    with pytest.raises(DefinitionError,match='duplicate shortcuts'):
        compile_definition(minimal()|{'actions':{'run':action|{'shortcut':'Ctrl+Z'}}},Path('/tmp'))


def test_duplicate_yaml_keys_and_unsafe_tags_rejected(tmp_path):
    file=tmp_path/'bad.yaml';file.write_text('version: 1\nversion: 2\n')
    with pytest.raises(DefinitionError,match='duplicate key'):load_definition(file)
    file.write_text('!!python/object/apply:os.system ["touch should-never-exist"]')
    with pytest.raises(DefinitionError):load_definition(file)
    assert not (tmp_path/'should-never-exist').exists()


def test_setting_defaults_ranges_duplicates_and_unknown_components():
    group=dict(id='main',title='Main',icon='tune',items=[dict(kind='field',path='amount',type='real',label='Amount',default=1,min=0,max=10)])
    doc=minimal()|{'settings':{'groups':[group]}}
    assert compile_definition(doc,Path('/tmp'))['settings']['defaults']=={'amount':1}
    group['items'][0]['default']=11
    with pytest.raises(DefinitionError,match='outside bounds'):compile_definition(doc,Path('/tmp'))
    group['items'][0]['default']='1'
    with pytest.raises(DefinitionError,match='type'):compile_definition(doc,Path('/tmp'))
    group['items']=[dict(kind='component',component='missing')]
    with pytest.raises(DefinitionError,match='unknown component'):compile_definition(doc,Path('/tmp'))


def test_cli_has_deterministic_output_and_no_side_effects(tmp_path):
    script=Path(__file__).resolve().parents[1]/'definition.py'
    completed=subprocess.run([sys.executable,str(script),str(EXAMPLE)],capture_output=True,text=True,check=True)
    assert json.loads(completed.stdout)==load_definition(EXAMPLE)
    assert not list(tmp_path.iterdir())


def field_document(item):
    return minimal()|dict(settings=dict(groups=[dict(id='main',title='Main',icon='tune',items=[item])]))


@pytest.mark.parametrize('patch',[
    {'app':{1:'bad','id':'org.Test','name':'Test','icon':'edit'}},
    {'actions':{'run':dict(label='Run',icon='play_arrow',target=dict(kind='backend',backend=[],operation='run'))}},
    {'actions':{'run':dict(label='Run',icon='play_arrow',target=dict(kind='qml',handler='run'),enabledWhen={'eq':[[],True]})}},
    {'utilities':{'placement':[]}},
    {'contextActions':{'placement':{}}},
    {'settings':{'title':[]}},
    {'state':{'canUndo':'false'}},
])
def test_malformed_types_always_produce_contextual_definition_errors(patch):
    with pytest.raises(DefinitionError,match=': '):compile_definition(minimal()|patch,Path('/tmp'))


@pytest.mark.parametrize('item,message',[
    (dict(kind='action',action='undo',path='ignored'),'unknown fields'),
    (dict(kind='component',component='missing',label='ignored'),'unknown fields'),
    (dict(kind='field',path='flag',type='bool',label='Flag',default=True,action='undo'),'unknown fields'),
    (dict(kind='field',path='flag',type='bool',label='Flag',default=True,min=0),'numeric bounds'),
    (dict(kind='field',path='count',type='int',label='Count',default=1,min=0,max=10,step=.5),'integer bounds'),
    (dict(kind='field',path='mode',type='string',label='Mode',default='one',choices=[dict(name='One',value='one'),dict(name='Two',value=2)]),'choice value'),
    (dict(kind='field',path='amount',type='real',label='Amount',default=1,min=0,max=2,choices=[dict(name='One',value=1),dict(name='Outside',value=3)]),'choice value outside bounds'),
    (dict(kind='field',path='status',type='label',label='Status',default='Ready',readOnly=False),'must be readOnly'),
])
def test_field_kind_specific_schema_and_choice_types(item,message):
    with pytest.raises(DefinitionError,match=message):compile_definition(field_document(item),Path('/tmp'))


def test_label_fields_normalize_as_readonly():
    result=compile_definition(field_document(dict(kind='field',path='status',type='label',label='Status',default='Ready')),Path('/tmp'))
    assert result['settings']['groups'][0]['items'][0]['setting']['readOnly'] is True


def test_setting_predicates_support_forward_references_without_eval():
    document=field_document(dict(kind='field',path='amount',type='real',label='Amount',default=1,min=0,max=2,
        enabledWhen={'all':['settings.custom',{'eq':['settings.mode','manual']}]},visibleWhen='settings.custom'))
    document['settings']['groups'][0]['items'] += [
        dict(kind='field',path='custom',type='bool',label='Custom',default=False),
        dict(kind='field',path='mode',type='string',label='Mode',default='manual')]
    result=compile_definition(document,Path('/tmp'))
    assert result['settings']['groups'][0]['items'][0]['enabledWhen']=={'all':['settings.custom',{'eq':['settings.mode','manual']}]}
    document['settings']['groups'][0]['items'][0]['enabledWhen']='settings.typo'
    with pytest.raises(DefinitionError,match='unknown state'):compile_definition(document,Path('/tmp'))
    with pytest.raises(DefinitionError,match='reserved'):
        compile_definition(minimal()|dict(state={'settings.fake':False}),Path('/tmp'))


def test_cycles_deep_nesting_and_yaml_alias_expansion_are_bounded(tmp_path):
    recursive=[];recursive.append(recursive)
    with pytest.raises(DefinitionError,match='recursive'):
        compile_definition(minimal()|dict(state=dict(loop=recursive)),Path('/tmp'))
    nested=True
    for _ in range(70):nested=[nested]
    with pytest.raises(DefinitionError,match='deeply nested'):
        compile_definition(minimal()|dict(state=dict(deep=nested)),Path('/tmp'))
    expanded=['value']
    for _ in range(18):expanded=[expanded,expanded]
    with pytest.raises(DefinitionError,match='too large'):
        compile_definition(minimal()|dict(state=dict(expanded=expanded)),Path('/tmp'))
    source=tmp_path/'recursive.yaml'
    source.write_text('version: 1\napp: {id: org.Test, name: Test, icon: edit}\nstate: {loop: &loop [*loop]}\n')
    with pytest.raises(DefinitionError,match='recursive'):load_definition(source)


def test_yaml_timestamps_and_nonstring_nested_keys_rejected(tmp_path):
    source=tmp_path/'types.yaml'
    source.write_text('version: 1\napp: {id: org.Test, name: Test, icon: edit}\nstate: {date: 2026-01-01}\n')
    with pytest.raises(DefinitionError,match='definition.state.date'):load_definition(source)
    with pytest.raises(DefinitionError,match='mapping keys'):
        compile_definition(minimal()|dict(state=dict(object={1:'bad'})),Path('/tmp'))


def test_invalid_cli_is_one_json_error_without_traceback_or_output_file(tmp_path):
    source=tmp_path/'invalid.yaml';target=tmp_path/'must-not-exist.json'
    source.write_text('version: 1\napp: {id: org.Test, name: Test, icon: edit}\nactions:\n  run:\n    label: Run\n    icon: play_arrow\n    target: {kind: qml, handler: run}\n    enabledWhen: {eq: [[], true]}\n')
    script=Path(__file__).resolve().parents[1]/'definition.py'
    first=subprocess.run([sys.executable,str(script),str(source),'--output',str(target)],capture_output=True,text=True)
    second=subprocess.run([sys.executable,str(script),str(source),'--output',str(target)],capture_output=True,text=True)
    assert first.returncode==second.returncode==1 and first.stdout==''
    assert first.stderr==second.stderr and len(first.stderr.splitlines())==1
    assert 'actions.run.enabledWhen' in json.loads(first.stderr)['error']
    assert not target.exists()


def test_unrepresentable_integer_is_a_contextual_error():
    with pytest.raises(DefinitionError,match='finite JSON'):
        compile_definition(minimal()|dict(state=dict(number=10**1000)),Path('/tmp'))


@pytest.mark.parametrize('bounds',[{},dict(min=-10),dict(max=10),dict(choices=[])])
def test_numeric_controls_require_both_explicit_bounds(bounds):
    item=dict(kind='field',path='amount',type='real',label='Amount',default=-1)|bounds
    with pytest.raises(DefinitionError,match='require explicit min and max'):
        compile_definition(field_document(item),Path('/tmp'))


def test_negative_numeric_controls_and_bounded_choice_controls_are_valid():
    item=dict(kind='field',path='offset',type='real',label='Offset',default=-5,min=-10,max=10)
    result=compile_definition(field_document(item),Path('/tmp'))
    assert result['settings']['defaults']['offset']==-5
    choice=dict(kind='field',path='order',type='int',label='Order',default=1,
        choices=[dict(name='First',value=1),dict(name='Second',value=2)])
    result=compile_definition(field_document(choice),Path('/tmp'))
    assert result['settings']['defaults']['order']==1


def test_dirty_when_is_validated_and_normalized():
    source=minimal()|{'state':{'dirty':False},'actions':{'save':dict(label='Save',icon='save',target=dict(kind='qml',handler='save'),dirtyWhen='dirty')}}
    compiled=compile_definition(source,Path('/tmp'))
    assert compiled['actions']['save']['dirtyWhen']=='dirty'
    assert compiled['actions']['undo']['dirtyWhen'] is False
    source['actions']['save']['dirtyWhen']='typo'
    with pytest.raises(DefinitionError,match='unknown state'):compile_definition(source,Path('/tmp'))
