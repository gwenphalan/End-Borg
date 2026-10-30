"""Per-application recent projects and per-purpose chooser folders."""
import json
import os
from pathlib import Path
import re
from .files import local_path, atomic_json


class History:
    def __init__(self, app_id, project_extensions=(), filename=None, limit=12):
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', app_id):
            raise ValueError('Invalid application history identifier.')
        if not isinstance(limit,int) or limit < 1:
            raise ValueError('History limit must be positive.')
        self.filename=Path(filename) if filename else Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state')))/app_id/'recent.json'
        self.extensions=tuple(extension.lower() for extension in project_extensions)
        self.limit=limit

    def read(self):
        try:
            document=json.loads(self.filename.read_text())
            return document if isinstance(document,dict) else {}
        except (OSError,ValueError):
            return {}

    def update(self,purpose,filenames,project=False):
        paths=[local_path(filename) for filename in filenames]
        if not paths:
            return
        document=self.read()
        folders=document.get('folders',{})
        if not isinstance(folders,dict):folders={}
        folders[purpose]=str(paths[0].parent)
        document['folders']=folders
        if project:
            previous=document.get('projects',[])
            if not isinstance(previous,list):previous=[]
            document['projects']=list(dict.fromkeys([str(p) for p in paths]+[p for p in previous if isinstance(p,str)]))[:self.limit]
        self.filename.parent.mkdir(parents=True,exist_ok=True)
        atomic_json(self.filename,document)

    def projects(self):
        paths=self.read().get('projects',[])
        if not isinstance(paths,list):return []
        return [p for p in paths if isinstance(p,str) and (not self.extensions or p.lower().endswith(self.extensions)) and Path(p).is_file()][:self.limit]

    def folder(self,purpose,fallback):
        folders=self.read().get('folders',{})
        if isinstance(folders,dict):
            candidate=folders.get(purpose)
            if isinstance(candidate,str) and Path(candidate).is_dir():return candidate
        return str(fallback)
