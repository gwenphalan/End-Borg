"""Configurable GNOME Files chooser via Nautilus' installed portal interface.

Uses system Python's Gio lazily. No desktop-wide preferences are modified.
"""
from dataclasses import dataclass
import argparse
import json
import os
from pathlib import Path
import uuid
if __package__ in (None,''):
    import sys
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
    from tool_app.history import History
else:
    from .history import History


@dataclass(frozen=True)
class FileFilter:
    label:str
    patterns:tuple[str,...]


@dataclass(frozen=True)
class PickerSpec:
    app_id:str
    app_name:str
    filters:tuple[FileFilter,...]
    default_basename:str|None=None


def request_options(spec,mode,folder,multiple=False,name=None):
    if mode not in ('open','save'):raise ValueError('Choose open or save mode.')
    if not spec.filters or any(not item.patterns for item in spec.filters):
        raise ValueError('At least one file filter is required.')
    options={'modal':('b',True),'multiple':('b',bool(multiple)),
        'filters':('a(sa(us))',[(item.label,[(0,p) for p in item.patterns]) for item in spec.filters]),
        'accept_label':('s','Save' if mode=='save' else 'Open')}
    folder=Path(folder).expanduser()
    if folder.is_dir():options['current_folder']=('ay',list(os.fsencode(folder)+b'\0'))
    if mode=='save' and (name or spec.default_basename):
        basename=name or spec.default_basename
        if Path(basename).name!=basename or '\x00' in basename:
            raise ValueError('The suggested filename must be a basename.')
        options['current_name']=('s',basename)
    return options


def choose(spec,mode,folder,multiple=False,name=None):
    import gi
    gi.require_version('Gio','2.0')
    from gi.repository import Gio,GLib
    options={key:GLib.Variant(signature,value) for key,(signature,value) in request_options(spec,mode,folder,multiple,name).items()}
    bus=Gio.bus_get_sync(Gio.BusType.SESSION,None)
    handle='/org/gnome/Nautilus/tool_app_'+uuid.uuid4().hex
    result=bus.call_sync('org.gnome.Nautilus','/org/freedesktop/portal/desktop',
        'org.freedesktop.impl.portal.FileChooser','SaveFile' if mode=='save' else 'OpenFile',
        GLib.Variant('(osssa{sv})',(handle,spec.app_id,'',spec.app_name+(' - Save' if mode=='save' else ' - Open'),options)),
        GLib.VariantType.new('(ua{sv})'),Gio.DBusCallFlags.NONE,2147483647,None)
    code,values=result.unpack()
    uris=values.get('uris',[])
    if code==0 and uris:return dict(ok=True,path=uris[0],paths=uris)
    if code==1:return dict(ok=True,cancelled=True)
    raise ValueError('Files could not complete the file selection.')


def choose_with_history(spec,mode,folder,history,purpose,multiple=False,name=None):
    result=choose(spec,mode,history.folder(purpose,folder),multiple,name)
    if result.get('path'):
        try:history.update(purpose,result.get('paths',[result['path']]))
        except OSError:pass
    return result


def choose_request(request):
    filters=tuple(FileFilter(item['name'],tuple(item['patterns'])) for item in request['filters'])
    spec=PickerSpec(request['appId'],request['appName'],filters,request.get('name'))
    extensions=list(request.get('extensions',[]))
    primary=request.get('primaryExtension')
    if primary and primary not in extensions:extensions.insert(0,primary)
    history=History(request.get('historyNamespace',request['appId']),extensions)
    return choose_with_history(spec,request['mode'],request.get('folder',str(Path.home())),history,
        request.get('purpose','files'),request.get('multiple',False),request.get('name'))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request',help='JSON tool-app picker descriptor')
    parser.add_argument('mode',nargs='?',choices=['open','save'])
    parser.add_argument('folder',nargs='?')
    parser.add_argument('--app-id')
    parser.add_argument('--app-name')
    parser.add_argument('--filter-label')
    parser.add_argument('--pattern',action='append')
    parser.add_argument('--default-name')
    parser.add_argument('--multiple',action='store_true')
    parser.add_argument('--purpose',default='files')
    parser.add_argument('--state-id')
    args=parser.parse_args()
    try:
        if args.request:
            result=choose_request(json.loads(args.request))
        else:
            if not all((args.mode,args.folder,args.app_id,args.app_name,args.filter_label,args.pattern,args.state_id)):
                raise ValueError('Pass --request or the complete chooser configuration.')
            spec=PickerSpec(args.app_id,args.app_name,(FileFilter(args.filter_label,tuple(args.pattern)),),args.default_name)
            result=choose_with_history(spec,args.mode,args.folder,History(args.state_id),args.purpose,args.multiple)
    except Exception as exc:result=dict(ok=False,error=str(exc))
    print(json.dumps(result),flush=True)


if __name__=='__main__':main()
