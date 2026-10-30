"""Refresh a Blender scene's calibration while preserving authored scene data."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from blender_export import export_blend


def recalibrate_blend(source,target,source_image,calibration,plane,native_scene,size):
    source=Path(source).expanduser().resolve();target=Path(target).expanduser().resolve()
    if not source.is_file() or source.suffix.lower()!='.blend':
        raise ValueError('Choose an existing .blend file to recalibrate.')
    if target.suffix.lower()!='.blend':raise ValueError('Choose a .blend filename for the recalibrated copy.')
    if source==target or (target.exists() and os.path.samefile(source,target)):
        raise ValueError('Save the recalibrated Blender file as a separate copy.')
    blender=shutil.which('blender')
    if not blender:raise ValueError('Blender is required to recalibrate a Blender file.')
    with tempfile.TemporaryDirectory(prefix='lens-cap-recalibrate-') as temporary:
        template=Path(temporary)/'calibration.blend'
        # The existing Blender file, not the app's scene, owns authored geometry.
        export_blend(template,source_image,calibration,plane,dict(objects=[]),size)
        fd,staged=tempfile.mkstemp(prefix='.lens-cap-',suffix='.blend',dir=target.parent);os.close(fd)
        try:
            try:
                result=subprocess.run([blender,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',str(Path(__file__).with_name('blender_recalibrate_scene.py')),'--',str(source),str(template),staged],capture_output=True,text=True,timeout=240,env=dict(os.environ,ALSOFT_DRIVERS='null'))
            except subprocess.TimeoutExpired:
                raise ValueError('Blender recalibration timed out; the original file was not changed.') from None
            if result.returncode or not Path(staged).stat().st_size:
                raise ValueError('Blender recalibration failed: '+(result.stderr or result.stdout)[-2000:])
            os.replace(staged,target)
        finally:Path(staged).unlink(missing_ok=True)
    return dict(path=str(target),message='Recalibrated Blender copy saved')
