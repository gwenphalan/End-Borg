"""Safe, background-only extraction of rectangular box regions from Blender files."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from spatial import validate_scene


def import_blend(source):
    source=Path(source).expanduser().resolve()
    if source.suffix.lower()!='.blend' or not source.is_file():
        raise ValueError('Choose an existing .blend file.')
    blender=shutil.which('blender')
    if not blender:raise ValueError('Blender is required to import Blender regions.')
    with tempfile.TemporaryDirectory(prefix='lens-cap-blender-import-') as temporary:
        output=Path(temporary)/'regions.json'
        try:
            result=subprocess.run([blender,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',str(Path(__file__).with_name('blender_read.py')),'--',str(source),str(output)],capture_output=True,text=True,timeout=180,env=dict(os.environ,ALSOFT_DRIVERS='null'))
        except subprocess.TimeoutExpired:
            raise ValueError('Blender import timed out; the project was not changed.') from None
        if result.returncode or not output.is_file():
            raise ValueError('Blender import failed: '+(result.stderr or result.stdout)[-1800:])
        payload=json.loads(output.read_text())
    payload['objects']=validate_scene(dict(objects=payload['objects']))['objects']
    return payload
