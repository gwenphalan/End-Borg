"""Actual Blender round-trip: packed assets, pixel projection, sensor-sized render."""
import json
import os
from pathlib import Path
import shutil
import subprocess

import cv2
import numpy as np
import pytest

from blender_export import export_blend
from geometry import output_geometry, spatial_camera_matrix
from spatial import calibrate_plane


@pytest.mark.skipif(not shutil.which('blender'),reason='Blender not installed')
@pytest.mark.parametrize('coefficients',[[-.1,.01],[.08,.01]])
def test_blender_packed_camera_and_render(tmp_path,coefficients):
    size=(160,90); calibration=dict(coefficients=coefficients,hfov=98.8)
    k=np.array(spatial_camera_matrix(size,calibration['coefficients'],calibration['hfov']))
    output=output_geometry(size,calibration['coefficients'],calibration['hfov'])['size']
    world=np.array([[0,0,0],[2,0,0],[2,3,0],[0,3,0]],float)
    points=cv2.projectPoints(world,np.array([2.6,0,0]),np.array([-1.,1,6]),k,None)[0].reshape(4,2)
    plane=calibrate_plane(dict(corners=points.tolist(),width=2,depth=3),k,output,'test')
    yy,xx=np.indices((90,160)); image=np.zeros((90,160,3),np.uint8);image[:,:,0]=xx;image[:,:,1]=yy
    target=tmp_path/'camera.blend';export_blend(target,image,calibration,plane,dict(objects=[]),size)
    script=tmp_path/'verify.py'
    script.write_text('''import bpy,json,numpy as np
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
workspace=bpy.data.scenes['Calibrated camera - undistorted workspace']
output=bpy.data.scenes['Calibrated camera - distorted sensor output']
p=json.loads(output['lens_cap_plane']);k=np.array(p['cameraMatrix']);r=np.array(p['rotationMatrix']);t=np.array(p['tvec'])
for vertex in bpy.data.objects['Measured reference plane'].data.vertices:
 v=np.array(vertex.co);q=r@v+t;expected=(k@q)[:2]/q[2]
 uv=world_to_camera_view(workspace,workspace.camera,Vector(v));actual=np.array([uv.x*workspace.render.resolution_x-.5,(1-uv.y)*workspace.render.resolution_y-.5]);assert np.max(abs(expected-actual))<.001
im=bpy.data.images['Exact Brown radial redistortion STMap'];assert im.is_float and len(im.packed_files)==1
assert len(bpy.data.images['Undistorted reference (packed)'].packed_files)==1
for s in bpy.data.scenes:s.cycles.samples=1
output.render.filepath='''+repr(str(tmp_path/'render.png'))+'''
bpy.ops.render.render(write_still=True,scene=output.name)
''')
    result=subprocess.run([shutil.which('blender'),'-b',str(target),'--python-exit-code','1','--python',str(script)],capture_output=True,text=True,timeout=90,env=dict(os.environ,ALSOFT_DRIVERS='null'))
    assert result.returncode==0,result.stdout+result.stderr
    rendered=cv2.imread(str(tmp_path/'render.png'))
    assert rendered.shape==image.shape
    # Two bilinear samplings introduce subpixel blur, not geometric rescaling.
    assert np.percentile(abs(rendered.astype(float)-image),95)<=2
    assert np.mean(abs(rendered.astype(float)-image))<1
    assert sorted(p.name for p in tmp_path.iterdir())==['camera.blend','render.png','verify.py']


@pytest.mark.skipif(not shutil.which('blender'),reason='Blender not installed')
@pytest.mark.parametrize('engine',['CYCLES','BLENDER_EEVEE'])
@pytest.mark.parametrize('coefficients',[[-.1,.01],[.08,.01]])
def test_rendered_reference_surface_aligns_after_distortion(tmp_path,engine,coefficients):
    """A solid, not just the image background, must use the corrected pixel domain."""
    from geometry import output_to_original
    size=(320,180);calibration=dict(coefficients=coefficients,hfov=98.8)
    k=np.array(spatial_camera_matrix(size,coefficients,98.8))
    geometry=output_geometry(size,coefficients,98.8)
    world=np.array([[0,0,0],[3,0,0],[3,3,0],[0,3,0]],float)
    points=cv2.projectPoints(world,np.array([2.6,0,0]),np.array([-1.5,1.,6.]),k,None)[0].reshape(4,2)
    plane=calibrate_plane(dict(corners=points.tolist(),width=3,depth=3),k,geometry['size'],'solid-test')
    target=tmp_path/'solid.blend'
    export_blend(target,np.zeros((180,320,3),np.uint8),calibration,plane,dict(objects=[]),size)
    script=tmp_path/'render_solid.py'
    script.write_text('''import bpy
surface=bpy.data.objects['Measured reference plane'];surface.hide_render=False
material=bpy.data.materials.new('Alignment emission');material.use_nodes=True
nodes=material.node_tree.nodes;nodes.clear();emission=nodes.new('ShaderNodeEmission');emission.inputs['Color'].default_value=(1,1,1,1);emission.inputs['Strength'].default_value=1
out=nodes.new('ShaderNodeOutputMaterial');material.node_tree.links.new(emission.outputs[0],out.inputs['Surface']);surface.data.materials.clear();surface.data.materials.append(material)
for scene in bpy.data.scenes:
 scene.render.engine='''+repr(engine)+'''
 scene.cycles.samples=1
output=bpy.data.scenes['Calibrated camera - distorted sensor output'];output.render.filepath='''+repr(str(tmp_path/'solid.png'))+'''
bpy.ops.render.render(write_still=True,scene=output.name)
''')
    result=subprocess.run([shutil.which('blender'),'-b',str(target),'--python-exit-code','1','--python',str(script)],capture_output=True,text=True,timeout=90,env=dict(os.environ,ALSOFT_DRIVERS='null'))
    assert result.returncode==0,result.stdout+result.stderr
    rendered=cv2.imread(str(tmp_path/'solid.png'),cv2.IMREAD_GRAYSCALE)
    assert rendered.shape==(180,320)
    samples=np.concatenate([points[i]+np.linspace(0,1,300)[:,None]*(points[(i+1)%4]-points[i]) for i in range(4)])
    distorted=output_to_original(samples,size,coefficients,98.8)
    expected=np.zeros_like(rendered);cv2.fillPoly(expected,[np.rint(distorted).astype(np.int32)],255)
    actual=(rendered>127).astype(np.uint8)
    intersection=np.count_nonzero(actual & (expected>0));union=np.count_nonzero(actual | (expected>0))
    assert intersection/union>.96
    # Anti-aliasing and two image filters may move the raster contour by one pixel.
    contour=cv2.findContours(actual,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)[0][0].reshape(-1,2)
    distance=np.min(np.linalg.norm(contour[:,None,:]-distorted[None,:,:],axis=2),axis=1)
    assert np.percentile(distance,95)<1.25
