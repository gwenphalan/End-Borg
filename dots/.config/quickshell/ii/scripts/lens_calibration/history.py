"""Lens Cap history policy using the shared tool-app history implementation."""
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tool_app.files import local_path, atomic_json
from tool_app.history import History as ToolHistory


class History(ToolHistory):
    def __init__(self,filename=None):
        super().__init__('lens-calibration',('.lenscap','.lensproject'),filename=filename)

    def remember_profile(self, filename):
        document=self.read()
        previous=document.get('profiles',[])
        if not isinstance(previous,list):previous=[]
        document['profiles']=list(dict.fromkeys([str(local_path(filename))]+[p for p in previous if isinstance(p,str)]))
        self.filename.parent.mkdir(parents=True,exist_ok=True)
        atomic_json(self.filename,document)

    def profiles(self):
        result=[]
        filenames=self.read().get('profiles',[])
        if not isinstance(filenames,list):return result
        for filename in filenames:
            if not isinstance(filename,str):continue
            try:
                profile=json.loads(Path(filename).read_text())
                if profile.get('type')!='lens-calibration-preset' or profile.get('version')!=1:continue
                result.append(dict(name=profile.get("name") or Path(filename).stem,path=filename,size=profile['size']))
            except (OSError,ValueError,KeyError,TypeError):continue
        return result


def purpose_group(action):
    if action in ('load','save','save_as','convert_legacy'):return 'project'
    if action in ('open','add_images'):return 'image'
    if action in ('load_preset','save_preset'):return 'preset'
    return action
