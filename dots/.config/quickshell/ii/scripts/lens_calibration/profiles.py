"""Named lens profiles; only explicitly registered files can be modified."""
import json
import uuid
from pathlib import Path
from tool_app.files import atomic_json, local_path


def manage_profile(request, worker, history):
    operation=request['op']
    profiles=history.profiles()
    name=str(request.get('name','')).strip()
    if operation in ('save_profile','rename_profile'):
        if not name or len(name)>120:
            raise ValueError('Enter a profile name between 1 and 120 characters.')
        if any(p['name'].casefold()==name.casefold() and p['path']!=request.get('path') for p in profiles):
            raise ValueError('A lens profile with that name already exists.')
    if operation=='save_profile':
        folder=history.filename.parent/'profiles'
        folder.mkdir(parents=True,exist_ok=True)
        filename=folder/(str(uuid.uuid4())+'.json')
    else:
        filename=local_path(request['path'])
        match=next((p for p in profiles if local_path(p['path'])==filename),None)
        if match is None:raise ValueError('Lens profile is no longer available.')
        if operation=='update_profile':name=match['name']
    if operation=='delete_profile':
        filename.unlink()
        document=history.read()
        document['profiles']=[p for p in document.get('profiles',[]) if local_path(p)!=filename]
        atomic_json(history.filename,document)
        return dict(profilePath='',message='Lens profile deleted')
    if operation in ('save_profile','update_profile'):
        result=worker.handle(dict(request,op='save_preset',path=str(filename)))
    elif operation=='rename_profile':result={}
    else:raise ValueError('Unknown profile operation.')
    document=json.loads(filename.read_text())
    document['name']=name
    atomic_json(filename,document)
    history.remember_profile(filename)
    result.update(profilePath=str(filename),message='Lens profile renamed' if operation=='rename_profile' else 'Lens profile saved')
    return result
