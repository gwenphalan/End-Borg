"""Recalibration preserves authored Blender data and changes only calibration helpers."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import cv2
import numpy as np
import pytest

from blender_export import export_blend
from blender_recalibrate import recalibrate_blend
from geometry import output_geometry,spatial_camera_matrix
from spatial import calibrate_plane


def calibration_fixture(coefficients,width=2,depth=3,changed=False):
    size=(160,90);cal=dict(coefficients=coefficients,hfov=98.8)
    geometry=output_geometry(size,coefficients,98.8);k=np.array(spatial_camera_matrix(size,coefficients,98.8))
    world=np.array([[0,0,0],[width,0,0],[width,depth,0],[0,depth,0]],float)
    rv=np.array([2.6,.1,0]) if changed else np.array([2.6,0,0])
    tv=np.array([-1.3,1.2,7]) if changed else np.array([-1.,1.,6.])
    points=cv2.projectPoints(world,rv,tv,k,None)[0].reshape(4,2)
    plane=calibrate_plane(dict(corners=points.tolist(),width=width,depth=depth),k,geometry['size'],'changed' if changed else 'original')
    return size,cal,plane


def blender_script(path,script,tmp_path):
    filename=tmp_path/'script.py';filename.write_text(script)
    result=subprocess.run([shutil.which('blender'),'-b','--disable-autoexec',str(path),'--python-exit-code','1','--python',str(filename)],capture_output=True,text=True,timeout=120,env=dict(os.environ,ALSOFT_DRIVERS='null'))
    assert result.returncode==0,result.stdout+result.stderr


@pytest.mark.skipif(not shutil.which('blender'),reason='Blender not installed')
def test_recalibrate_preserves_authored_scene_and_is_repeatable(tmp_path):
    size,cal,plane=calibration_fixture([-.1,.01])
    image=np.zeros((90,160,3),np.uint8)
    source=tmp_path/'source.blend';target=tmp_path/'recalibrated.blend';again=tmp_path/'again.blend'
    box=dict(id='region-1',kind='cuboid',label='Authored box',position=[0,0,0],size=[1,2,.4],yaw=20,color='#123456')
    export_blend(source,image,cal,plane,dict(objects=[box]),size)
    before=tmp_path/'before.json';after=tmp_path/'after.json'
    snapshot='''def snapshot():
 objects={}
 for o in bpy.data.objects:
  if o.get('lens_cap_role') in ('calibrated_camera','reference_plane'):continue
  objects[o.name]=dict(matrix=[list(row) for row in o.matrix_world],type=o.type,vertices=[list(v.co) for v in o.data.vertices] if o.type=='MESH' else [],materials=[m.name for m in o.data.materials] if o.type=='MESH' else [],collections=sorted(set(c.name for c in o.users_collection)))
 return objects
'''
    blender_script(source,'''import bpy,json
from mathutils import Euler
box=bpy.data.objects['Authored box'];box.location=(.3,.5,.2);box.rotation_euler=(.1,.2,.3);box.scale=(1.2,.8,1.1)
bpy.ops.mesh.primitive_uv_sphere_add(location=(2,1,.5));sphere=bpy.context.object;sphere.name='Authored sphere'
material=bpy.data.materials.new('User custom material');sphere.data.materials.append(material)
light=bpy.data.lights.new('User light','AREA');obj=bpy.data.objects.new('User light',light);bpy.context.scene.collection.objects.link(obj);obj.location=(1,2,3)
collection=bpy.data.collections.new('User collection');bpy.context.scene.collection.children.link(collection);collection.objects.link(sphere)
other=bpy.data.scenes.new('Unrelated user scene');other.world=bpy.context.scene.world
for s in bpy.data.scenes:
 if s.name.startswith('Calibrated camera'):s.render.engine='BLENDER_EEVEE'
'''+snapshot+'''bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath='''+repr(str(source))+''',check_existing=False)
open('''+repr(str(before))+''','w').write(json.dumps(snapshot(),sort_keys=True))
''',tmp_path)
    original_hash=hashlib.sha256(source.read_bytes()).hexdigest()
    _,current,pose=calibration_fixture([-.07,.008],width=2.5,depth=3.5,changed=True)
    recalibrate_blend(source,target,image,current,pose,dict(objects=[box]),size)
    assert hashlib.sha256(source.read_bytes()).hexdigest()==original_hash
    check='''import bpy,json,numpy as np
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
'''+snapshot+'''
workspace=bpy.data.scenes['Calibrated camera - undistorted workspace'];output=bpy.data.scenes['Calibrated camera - distorted sensor output']
assert 'Unrelated user scene' in bpy.data.scenes
assert sum(o.get('lens_cap_role')=='calibrated_camera' for o in bpy.data.objects)==1
assert sum(o.get('lens_cap_role')=='reference_plane' for o in bpy.data.objects)==1
assert workspace.world==output.world and workspace.world is not None
assert workspace.render.engine==output.render.engine=='BLENDER_EEVEE'
p=json.loads(output['lens_cap_plane']);assert p['width']==2.5 and p['depth']==3.5
assert json.loads(output['lens_cap_calibration'])['coefficients']==[-.07,.008]
k=np.array(p['cameraMatrix']);r=np.array(p['rotationMatrix']);t=np.array(p['tvec'])
for vertex in bpy.data.objects['Measured reference plane'].data.vertices:
 v=np.array(vertex.co);q=r@v+t;expected=(k@q)[:2]/q[2];uv=world_to_camera_view(workspace,workspace.camera,Vector(v));actual=np.array([uv.x*workspace.render.resolution_x-.5,(1-uv.y)*workspace.render.resolution_y-.5]);assert np.max(abs(expected-actual))<.001
assert any(n.type=='SCALE' and n.label=='Restore calibrated overscan raster' for n in output.compositing_node_group.nodes)
open('''+repr(str(after))+''','w').write(json.dumps(snapshot(),sort_keys=True))
output.render.filepath='''+repr(str(tmp_path/'render.png'))+'''
bpy.ops.render.render(write_still=True,scene=output.name)
'''
    blender_script(target,check,tmp_path)
    assert json.loads(before.read_text())==json.loads(after.read_text())
    assert cv2.imread(str(tmp_path/'render.png')).shape==image.shape
    recalibrate_blend(target,again,image,current,pose,dict(objects=[]),size)
    blender_script(again,check,tmp_path)
    assert json.loads(before.read_text())==json.loads(after.read_text())
    with pytest.raises(ValueError,match='separate copy'):
        recalibrate_blend(source,source,image,current,pose,dict(objects=[]),size)
    assert hashlib.sha256(source.read_bytes()).hexdigest()==original_hash


@pytest.mark.skipif(not shutil.which('blender'),reason='Blender not installed')
def test_generic_scene_and_non_metre_units_preserved(tmp_path):
    size,cal,plane=calibration_fixture([-.1,.01])
    source=tmp_path/'generic.blend';target=tmp_path/'calibrated.blend'
    script=tmp_path/'make.py';script.write_text('''import bpy
bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=.01
bpy.data.objects['Cube'].location=(100,200,300)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath='''+repr(str(source))+''',check_existing=False)
''')
    result=subprocess.run([shutil.which('blender'),'-b','--factory-startup','--python-exit-code','1','--python',str(script)],capture_output=True,text=True,timeout=90,env=dict(os.environ,ALSOFT_DRIVERS='null'))
    assert result.returncode==0,result.stdout+result.stderr
    before=hashlib.sha256(source.read_bytes()).hexdigest()
    recalibrate_blend(source,target,np.zeros((90,160,3),np.uint8),cal,plane,dict(objects=[]),size)
    blender_script(target,'''import bpy,json,numpy as np
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
w=bpy.data.scenes['Calibrated camera - undistorted workspace'];o=bpy.data.scenes['Calibrated camera - distorted sensor output']
assert 'Scene' in bpy.data.scenes and list(bpy.data.objects['Cube'].location)==[100,200,300]
assert bpy.data.objects['Camera'].type=='CAMERA'
assert w.camera!=bpy.data.objects['Camera'] and abs(w.unit_settings.scale_length-.01)<1e-8
p=json.loads(o['lens_cap_plane']);k=np.array(p['cameraMatrix']);r=np.array(p['rotationMatrix']);t=np.array(p['tvec'])
for v in bpy.data.objects['Measured reference plane'].data.vertices:
 metres=np.array(v.co)*.01;q=r@metres+t;expected=(k@q)[:2]/q[2];uv=world_to_camera_view(w,w.camera,v.co);actual=np.array([uv.x*w.render.resolution_x-.5,(1-uv.y)*w.render.resolution_y-.5]);assert np.max(abs(expected-actual))<.002
''',tmp_path)
    assert hashlib.sha256(source.read_bytes()).hexdigest()==before


def test_recalibration_failure_preserves_original_and_existing_target(tmp_path,monkeypatch):
    import types
    import blender_recalibrate as module
    source=tmp_path/'source.blend';target=tmp_path/'target.blend'
    source.write_bytes(b'original source');target.write_bytes(b'original target')
    monkeypatch.setattr(module,'export_blend',lambda template,*args:Path(template).write_bytes(b'template'))
    monkeypatch.setattr(module.shutil,'which',lambda name:'/test/blender')
    monkeypatch.setattr(module.subprocess,'run',lambda *args,**kwargs:types.SimpleNamespace(returncode=1,stderr='fixture failure',stdout=''))
    with pytest.raises(ValueError,match='fixture failure'):
        module.recalibrate_blend(source,target,None,{},dict(stale=False),{},(160,90))
    assert source.read_bytes()==b'original source' and target.read_bytes()==b'original target'
    assert not list(tmp_path.glob('.lens-cap-*'))
