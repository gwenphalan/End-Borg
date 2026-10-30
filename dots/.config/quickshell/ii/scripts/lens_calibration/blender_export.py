"""Standalone calibrated Blender scene export, using Blender's background process."""
import copy
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import cv2
import numpy as np

from geometry import corrected_image, output_geometry, original_to_output
from spatial import object_geometry, reference_basis


def export_blend(target, source_image, calibration, plane, native_scene, size):
    blender=shutil.which('blender')
    if not blender:
        raise ValueError('Blender is required to export a Blender scene.')
    if not plane or plane.get('stale'):
        raise ValueError('Calculate 3D space for the current reference plane first.')
    target=Path(target).resolve()
    with tempfile.TemporaryDirectory(prefix='lens-cap-blender-') as temporary:
        work=Path(temporary)
        coefficients=calibration['coefficients']; hfov=calibration.get('hfov')
        geometry=output_geometry(size,coefficients,hfov)
        corrected=corrected_image(source_image,coefficients,hfov)
        w,h=size; cw,ch=geometry['size']
        # Blender renders referenced scenes at the final scene's raster size.
        # Equal aspect ratios let the compositor resize that render back to the
        # overscan raster without changing its calibrated camera projection.
        divisor=math.gcd(w,h);unit_w,unit_h=w//divisor,h//divisor
        multiple=max(divisor,math.ceil(cw/unit_w),math.ceil(ch/unit_h))
        ow,oh=unit_w*multiple,unit_h*multiple
        offset=np.array([(ow-cw)//2,(oh-ch)//2])
        corrected=cv2.copyMakeBorder(corrected,int(offset[1]),oh-ch-int(offset[1]),int(offset[0]),ow-cw-int(offset[0]),cv2.BORDER_CONSTANT)
        cv2.imwrite(str(work/'reference.png'),corrected)
        plane=copy.deepcopy(plane)
        pk=np.array(plane['cameraMatrix']); pk[:2,2]+=offset; plane['cameraMatrix']=pk.tolist()
        plane['corners']=(np.array(plane['corners'])+offset).tolist()
        padx=(ow-w)//2; pady=(oh-h)//2
        yy,xx=np.indices((oh,ow),dtype=float); xx-=padx; yy-=pady
        points=original_to_output(np.column_stack((np.clip(xx,0,w-1).ravel(),np.clip(yy,0,h-1).ravel())),size,coefficients,hfov).reshape(oh,ow,2)+offset
        # Blender image pixels are bottom-up. UV sampling uses pixel centres.
        uv=np.zeros((oh,ow,4),dtype=np.float32)
        uv[:,:,0]=(points[:,:,0]+.5)/ow
        uv[:,:,1]=1-(points[:,:,1]+.5)/oh
        uv[:,:,2:]=1
        np.save(work/'distortion.npy',uv[::-1].copy())
        basis=reference_basis(plane.get('referenceAxes',['x','y']))
        local=np.array([[0,0,0],[plane['width'],0,0],[plane['width'],plane['depth'],0],[0,plane['depth'],0]])
        objects=[]
        for obj in native_scene.get('objects',[]):
            local_object=dict(obj,position=[0,0,0],yaw=0,rotationMatrix=np.eye(3).tolist())
            vertices,faces,_=object_geometry(local_object)
            angle=np.deg2rad(obj.get('yaw',0));c,s=np.cos(angle),np.sin(angle)
            rotation=np.array([[c,-s,0],[s,c,0],[0,0,1]])@np.asarray(obj.get('rotationMatrix',np.eye(3)))
            transform=np.eye(4);transform[:3,:3]=rotation;transform[:3,3]=obj['position']
            objects.append(dict(id=obj['id'],name=obj.get('label',obj['id']),vertices=vertices.tolist(),faces=faces,matrixWorld=transform.tolist(),color=obj.get('color','#cba6f7')))
        data=dict(plane=plane,calibration=calibration,sourceSize=list(size),outputSize=[ow,oh],referenceVertices=(local@basis.T).tolist(),objects=objects)
        (work/'scene.json').write_text(json.dumps(data))
        # Atomic final replacement, including cross-filesystem destinations.
        fd,staged=tempfile.mkstemp(prefix='.lens-cap-',suffix='.blend',dir=target.parent)
        os.close(fd)
        try:
            result=subprocess.run([blender,'--background','--factory-startup','--python-exit-code','1','--python',str(Path(__file__).with_name('blender_scene.py')),'--',str(work),staged],capture_output=True,text=True,timeout=240,env=dict(os.environ,ALSOFT_DRIVERS='null'))
            if result.returncode or not Path(staged).stat().st_size:
                raise ValueError('Blender export failed: '+(result.stderr or result.stdout)[-2000:])
            os.replace(staged,target)
        finally:
            Path(staged).unlink(missing_ok=True)
    return dict(path=str(target),format='blend',message='Blender scene exported')
