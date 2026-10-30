import json
import os
from pathlib import Path
import subprocess
import sys
import types
import xml.etree.ElementTree as ET
import pytest
from .files import local_path,atomic_json,rename_no_replace
from .history import History
from . import native_picker
from .native_picker import FileFilter,PickerSpec,request_options
from . import registration
from .registration import FileTypeSpec


def test_paths_atomic_json_and_failed_write_preserve_original(tmp_path):
    target=tmp_path/'space ü.json'
    assert local_path(target.as_uri())==target
    atomic_json(target,dict(answer=42))
    raw=target.read_bytes()
    with pytest.raises(ValueError):atomic_json(target,dict(value=float('nan')))
    assert target.read_bytes()==raw
    assert list(tmp_path.iterdir())==[target]


def test_shared_rename_refuses_overwrite(tmp_path):
    source=tmp_path/'source';target=tmp_path/'target'
    source.write_bytes(b'original');target.write_bytes(b'other')
    with pytest.raises(FileExistsError):rename_no_replace(source,target)
    assert source.read_bytes()==b'original' and target.read_bytes()==b'other'
    target.unlink();rename_no_replace(source,target)
    assert not source.exists() and target.read_bytes()==b'original'


def test_history_is_app_scoped_and_extension_configurable(tmp_path,monkeypatch):
    monkeypatch.setenv('XDG_STATE_HOME',str(tmp_path/'state'))
    first=History('photo-tool',('.photojob',));second=History('audio-tool',('.audioproject',))
    project=tmp_path/'sample.photojob';project.touch()
    first.update('source',[project.as_uri()],project=True)
    assert first.projects()==[str(project)] and second.projects()==[]
    assert first.folder('source','fallback')==str(tmp_path)
    assert second.filename==tmp_path/'state/audio-tool/recent.json'
    with pytest.raises(ValueError):History('../outside')
    first.filename.write_text('[]')
    assert first.read()=={}


def test_native_picker_typed_options_and_basename(tmp_path):
    spec=PickerSpec('org.example.PhotoTool','Photo Tool',(FileFilter('Projects',('*.photojob','*.oldphoto')),),'Untitled.photojob')
    options=request_options(spec,'save',tmp_path,multiple=False)
    assert options['current_name']==('s','Untitled.photojob')
    assert options['current_folder']==('ay',list(os.fsencode(tmp_path)+b'\0'))
    assert options['filters']==('a(sa(us))',[('Projects',[(0,'*.photojob'),(0,'*.oldphoto')])])
    with pytest.raises(ValueError,match='basename'):request_options(spec,'save',tmp_path,name='../bad.photojob')


def test_native_picker_uses_real_portal_signature_with_configurable_identity(tmp_path,monkeypatch):
    calls=[]
    class Variant:
        def __init__(self,signature,value):self.signature,self.value=signature,value
    class Result:
        def unpack(self):return 0,dict(uris=['file:///tmp/one.photojob','file:///tmp/two.photojob'])
    class Bus:
        def call_sync(self,*args):calls.append(args);return Result()
    gio=types.SimpleNamespace(BusType=types.SimpleNamespace(SESSION=1),DBusCallFlags=types.SimpleNamespace(NONE=0),bus_get_sync=lambda *args:Bus())
    glib=types.SimpleNamespace(Variant=Variant,VariantType=types.SimpleNamespace(new=lambda value:value))
    gi=types.ModuleType('gi');gi.require_version=lambda *args:None
    repository=types.ModuleType('gi.repository');repository.Gio=gio;repository.GLib=glib
    monkeypatch.setitem(sys.modules,'gi',gi);monkeypatch.setitem(sys.modules,'gi.repository',repository)
    spec=PickerSpec('org.example.PhotoTool','Photo Tool',(FileFilter('Photos',('*.png',)),))
    result=native_picker.choose(spec,'open',tmp_path,multiple=True)
    assert result['paths']==['file:///tmp/one.photojob','file:///tmp/two.photojob']
    args=calls[0]
    assert args[0]=='org.gnome.Nautilus' and args[3]=='OpenFile'
    assert args[4].signature=='(osssa{sv})'
    assert args[4].value[1:4]==('org.example.PhotoTool','','Photo Tool - Open')
    assert args[4].value[4]['multiple'].value is True


def test_picker_descriptor_and_history_policy_are_generic(tmp_path,monkeypatch):
    monkeypatch.setenv('XDG_STATE_HOME',str(tmp_path/'state'))
    seen=[]
    def choose(spec,mode,folder,history,purpose,multiple=False,name=None):
        seen.append((spec,mode,folder,history,purpose,multiple,name));return dict(ok=True,cancelled=True)
    monkeypatch.setattr(native_picker,'choose_with_history',choose)
    descriptor=dict(appId='org.example.PhotoTool',appName='Photo Tool',mode='save',
        filters=[dict(name='Project',patterns=['*.photojob'])],folder=str(tmp_path),name='sample.photojob',
        purpose='project',historyNamespace='photo-tool',primaryExtension='.photojob',extensions=['.oldphoto'],multiple=False)
    assert native_picker.choose_request(descriptor)==dict(ok=True,cancelled=True)
    spec,mode,folder,history,purpose,multiple,name=seen[0]
    assert spec.app_name=='Photo Tool' and spec.filters[0].patterns==('*.photojob',)
    assert history.extensions==('.photojob','.oldphoto')
    assert history.filename==tmp_path/'state/photo-tool/recent.json'
    assert (mode,purpose,name)==('save','project','sample.photojob')


def test_picker_remembers_folders_only_after_success(tmp_path,monkeypatch):
    history=History('test-tool',filename=tmp_path/'recent.json')
    project=tmp_path/'project.job';project.touch()
    spec=PickerSpec('org.example.Tool','Tool',(FileFilter('All',('*',)),))
    monkeypatch.setattr(native_picker,'choose',lambda *args:dict(ok=True,path=project.as_uri(),paths=[project.as_uri()]))
    native_picker.choose_with_history(spec,'open',tmp_path,history,'project')
    raw=history.filename.read_bytes()
    assert history.folder('project','other')==str(tmp_path)
    monkeypatch.setattr(native_picker,'choose',lambda *args:dict(ok=True,cancelled=True))
    native_picker.choose_with_history(spec,'open',tmp_path,history,'project')
    assert history.filename.read_bytes()==raw


def example_registration():
    return FileTypeSpec('org.example.PhotoTool','Photo Tool',('/path with spaces/photo-tool','%f'),
        'application/x-photo-job',('.photojob','.oldphoto'),'Photo & metadata',('Graphics',),
        startup_wm_class='org.quickshell',icon_svg='<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16"/></svg>')


def test_registration_renders_mime_desktop_and_icon_without_os_changes(tmp_path,monkeypatch):
    calls=[];monkeypatch.setattr(registration.subprocess,'run',lambda *args,**kwargs:calls.append(args))
    spec=example_registration();files=registration.render(spec)
    assert len(files)==3
    desktop=files['applications/org.example.PhotoTool.desktop']
    assert 'Exec="/path with spaces/photo-tool" %f\n' in desktop
    assert 'MimeType=application/x-photo-job;' in desktop
    xml=ET.fromstring(files['mime/packages/org.example.PhotoTool.xml'])
    ns={'m':'http://www.freedesktop.org/standards/shared-mime-info'}
    assert [item.attrib['pattern'] for item in xml.findall('.//m:glob',ns)]==['*.photojob','*.oldphoto']
    targets=registration.install(spec,data_home=tmp_path)
    assert all(Path(target).is_relative_to(tmp_path) for target in targets)
    assert calls==[]
    assert (tmp_path/'icons/hicolor/scalable/apps/org.example.PhotoTool.svg').exists()


def test_registration_refresh_and_default_are_explicit_argument_vectors(tmp_path,monkeypatch):
    calls=[];monkeypatch.setattr(registration.subprocess,'run',lambda command,**kwargs:calls.append((command,kwargs)))
    registration.install(example_registration(),tmp_path,refresh=True,set_default=True)
    assert [command[0] for command,_ in calls]==['update-desktop-database','update-mime-database','xdg-mime']
    assert calls[-1][0]==['xdg-mime','default','org.example.PhotoTool.desktop','application/x-photo-job']
    assert all(kwargs==dict(check=True) for _,kwargs in calls)


def test_registration_cli_is_dry_run_by_default(tmp_path):
    from dataclasses import asdict
    specfile=tmp_path/'spec.json';specfile.write_text(json.dumps(asdict(example_registration())))
    destination=tmp_path/'not-written'
    completed=subprocess.run([sys.executable,str(Path(registration.__file__)),str(specfile),'--data-home',str(destination)],capture_output=True,text=True,check=True)
    assert 'applications/org.example.PhotoTool.desktop' in json.loads(completed.stdout)
    assert not destination.exists()
    bad=FileTypeSpec('../outside','Bad',('/bin/true',),'application/x-job',('.job',))
    with pytest.raises(ValueError):registration.render(bad)


def test_generated_desktop_exec_passes_freedesktop_validator(tmp_path):
    import shutil
    validator=shutil.which('desktop-file-validate')
    if not validator:pytest.skip('desktop-file-validate is unavailable')
    spec=FileTypeSpec('org.example.Quoted','Quoted Tool',('/tmp/path with spaces/$test`quote".sh','100% literal','%f'),
        'application/x-quoted-project',('.quoted',))
    target=tmp_path/'org.example.Quoted.desktop'
    target.write_text(registration.render(spec)['applications/org.example.Quoted.desktop'])
    subprocess.run([validator,str(target)],check=True,capture_output=True,text=True)
