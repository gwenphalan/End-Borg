"""Box recognition and actual safe Blender file round-trip."""
import json
import os
from pathlib import Path
import shutil
import subprocess

import cv2
import numpy as np
import pytest

from blender_import import import_blend
from blender_read import cuboid_geometry,object_identity
from spatial import object_geometry,validate_scene

BOX=dict(kind='cuboid',position=[-.5,.2,1],size=[2,3,4],yaw=0)


def test_box_recognition_preserves_arbitrary_rigid_orientation():
    rotation=cv2.Rodrigues(np.array([.4,.6,-.2]))[0]
    vertices,faces,_=object_geometry(dict(BOX,rotationMatrix=rotation.tolist()))
    frame=cuboid_geometry(vertices,faces)
    recovered,_,_=object_geometry(dict(BOX,**frame))
    assert np.max(np.min(np.linalg.norm(vertices[:,None,:]-recovered[None,:,:],axis=2),axis=1))<1e-6
    validated=validate_scene(dict(objects=[dict(id='box',**BOX,rotationMatrix=rotation.tolist())]))
    assert np.allclose(validated['objects'][0]['rotationMatrix'],rotation)
    with pytest.raises(ValueError,match='orthonormal'):
        validate_scene(dict(objects=[dict(id='box',**BOX,rotationMatrix=[[1,0,0],[0,2,0],[0,0,1]])]))


def test_box_recognition_rejects_nonboxes_and_open_surfaces():
    vertices,faces,_=object_geometry(BOX)
    deformed=vertices.copy();deformed[6]+=[.1,.2,0]
    for points,surface in [(deformed,faces),(vertices,faces[:-1]),(vertices[:4],faces[:1]),(vertices,faces+faces[:1])]:
        with pytest.raises(ValueError):cuboid_geometry(points,surface)
    triangles=[]
    for face in faces:triangles.extend([[face[0],face[1],face[2]],[face[0],face[2],face[3]]])
    assert cuboid_geometry(vertices,triangles)['size']==pytest.approx([2,3,4])


@pytest.mark.skipif(not shutil.which('blender'),reason='Blender not installed')
def test_actual_blender_import_only_boxes_preserves_transforms_and_ids(tmp_path):
    source=tmp_path/'scene.blend';fixture=tmp_path/'fixture.py';expected=tmp_path/'expected.json'
    fixture.write_text('''import bpy,json
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
s=bpy.context.scene;s.unit_settings.system='METRIC';s.unit_settings.scale_length=.5
bpy.ops.mesh.primitive_cube_add(location=(1,2,3));box=bpy.context.object;box.name='Rotated region';box.rotation_euler=(.4,.6,.2);box.scale=(1,2,3);box['lens_cap_id']='saved-region';box['lens_cap_role']='region'
bpy.context.view_layer.update()
vertices=[list((box.matrix_world@v.co)*.5) for v in box.data.vertices]
box.modifiers.new('Triangulate','TRIANGULATE')
shared=s.copy();shared.use_fake_user=True
bpy.ops.mesh.primitive_uv_sphere_add();bpy.context.object.name='Sphere ignored'
bpy.ops.mesh.primitive_plane_add();bpy.context.object.name='Reference ignored';bpy.context.object['lens_cap_role']='reference_plane'
bpy.ops.mesh.primitive_cube_add(location=(5,0,0));deformed=bpy.context.object;deformed.name='Deformed ignored';deformed.data.vertices[0].co.x+=.3
bpy.ops.object.camera_add();bpy.context.object.name='Camera ignored'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath='''+repr(str(source))+''',check_existing=False)
open('''+repr(str(expected))+''','w').write(json.dumps(vertices))
''')
    marker=tmp_path/'embedded-script-ran'
    embedded="open("+repr(str(marker))+",'w').write('unexpected')"
    fixture.write_text(fixture.read_text().replace('bpy.context.preferences.filepaths.save_version=0',"autorun=bpy.data.texts.new('not-executed.py');autorun.use_module=True;autorun.write("+repr(embedded)+")\nbpy.context.preferences.filepaths.save_version=0",1))
    result=subprocess.run([shutil.which('blender'),'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',str(fixture)],capture_output=True,text=True,timeout=90,env=dict(os.environ,ALSOFT_DRIVERS='null'))
    assert result.returncode==0,result.stdout+result.stderr
    before=source.read_bytes()
    imported=import_blend(source)
    assert source.read_bytes()==before
    assert not marker.exists(),'Embedded Blender scripts must not run during import'
    assert len(imported['objects'])==1,imported
    box=imported['objects'][0];assert box['id']=='saved-region' and box['label']=='Rotated region'
    points=np.array(json.loads(expected.read_text()));actual,_,_=object_geometry(box)
    assert np.max(np.min(np.linalg.norm(points[:,None,:]-actual[None,:,:],axis=2),axis=1))<1e-5
    assert imported['skipped']==4
    assert {detail['name'] for detail in imported['details']}=={'Sphere ignored','Reference ignored','Deformed ignored','Camera ignored'}
    second=import_blend(source)
    assert second==imported


@pytest.mark.skipif(not shutil.which('blender'),reason='Blender not installed')
def test_exported_scene_round_trips_boxes_without_camera_or_reference(tmp_path):
    from blender_export import export_blend
    from geometry import spatial_camera_matrix,output_geometry
    from spatial import calibrate_plane
    size=(160,90);calibration=dict(coefficients=[-.1,.01],hfov=98.8)
    camera=np.asarray(spatial_camera_matrix(size,calibration['coefficients'],calibration['hfov']))
    world=np.array([[0,0,0],[2,0,0],[2,3,0],[0,3,0]],float)
    points=cv2.projectPoints(world,np.array([2.6,0,0]),np.array([-1.,1,6]),camera,None)[0].reshape(4,2)
    plane=calibrate_plane(dict(corners=points.tolist(),width=2,depth=3),camera,output_geometry(size,calibration['coefficients'],calibration['hfov'])['size'],'test')
    source=dict(id='native-box',label='Measured box',color='#123456',**BOX,rotationMatrix=cv2.Rodrigues(np.array([.3,-.1,.5]))[0].tolist())
    target=tmp_path/'roundtrip.blend'
    export_blend(target,np.zeros((90,160,3),np.uint8),calibration,plane,dict(objects=[source]),size)
    edited_expected=tmp_path/'edited.json';edit=tmp_path/'edit.py'
    edit.write_text("""import bpy,json
box=bpy.data.objects['Measured box'];box.location=(2,-1,.5);box.rotation_euler=(.2,-.4,.7);box.scale=(1.5,.8,2)
bpy.context.view_layer.update()
points=[list(box.matrix_world@vertex.co) for vertex in box.data.vertices]
bpy.ops.mesh.primitive_uv_sphere_add();bpy.context.object.name='Ignore me'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath="""+repr(str(target))+""",check_existing=False)
open("""+repr(str(edited_expected))+""",'w').write(json.dumps(points))
""")
    edited=subprocess.run([shutil.which('blender'),'--background','--factory-startup','--disable-autoexec',str(target),'--python-exit-code','1','--python',str(edit)],capture_output=True,text=True,timeout=90,env=dict(os.environ,ALSOFT_DRIVERS='null'))
    assert edited.returncode==0,edited.stdout+edited.stderr
    imported=import_blend(target)
    assert len(imported['objects'])==1
    result=imported['objects'][0]
    assert result['id']==source['id'] and result['label']==source['label'] and result['color']==source['color']
    expected=np.asarray(json.loads(edited_expected.read_text()));actual,_,_=object_geometry(result)
    assert np.max(np.min(np.linalg.norm(expected[:,None,:]-actual[None,:,:],axis=2),axis=1))<1e-5


def test_external_box_ids_are_namespaced_by_file(tmp_path):
    first=object_identity(tmp_path/'first.blend','Cube',None,set())
    assert first==object_identity(tmp_path/'first.blend','Cube',None,set())
    assert first!=object_identity(tmp_path/'second.blend','Cube',None,set())
    assert object_identity(tmp_path/'first.blend','Cube','saved-id',set())=='saved-id'
