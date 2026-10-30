"""Executed inside Blender; all export assets are packed before saving."""
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Matrix

work=Path(sys.argv[sys.argv.index('--')+1]); target=sys.argv[-1]
data=json.loads((work/'scene.json').read_text()); plane=data['plane']
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
ow,oh=data['outputSize']; sw,sh=data['sourceSize']
scene.render.resolution_x=ow; scene.render.resolution_y=oh; scene.render.resolution_percentage=100
scene.render.film_transparent=True
engines={item.identifier for item in scene.render.bl_rna.properties['engine'].enum_items}
scene.render.engine='BLENDER_EEVEE' if 'BLENDER_EEVEE' in engines else 'BLENDER_EEVEE_NEXT'
scene.cycles.samples=32; scene.cycles.device='CPU'
scene.view_settings.view_transform='Standard'
scene.view_settings.look='None'; scene.view_settings.exposure=0; scene.view_settings.gamma=1
k=np.asarray(plane['cameraMatrix'],float)
camera=bpy.data.cameras.new('Calibrated camera'); obj=bpy.data.objects.new('Calibrated camera',camera); scene.collection.objects.link(obj); scene.camera=obj
camera.type='PERSP'; camera.sensor_fit='HORIZONTAL'; camera.sensor_width=36
camera.lens=k[0,0]*36/ow
scene.render.pixel_aspect_x=1; scene.render.pixel_aspect_y=k[0,0]/k[1,1]
camera.shift_x=(ow/2-(k[0,2]+.5))/ow
camera.shift_y=((k[1,2]+.5)-oh/2)/ow*(k[0,0]/k[1,1])
r=np.asarray(plane['rotationMatrix']); t=np.asarray(plane['tvec'])
transform=np.eye(4); transform[:3,:3]=r.T@np.diag([1,-1,-1]); transform[:3,3]=-r.T@t
obj.matrix_world=Matrix(transform.tolist());obj['lens_cap_role']='calibrated_camera'; camera.clip_start=.001; camera.clip_end=10000
reference=bpy.data.images.load(str(work/'reference.png')); reference.name='Undistorted reference (packed)'; reference.pack()
camera.show_background_images=True
bg=camera.background_images.new(); bg.image=reference; bg.alpha=1; bg.display_depth='BACK'; bg.frame_method='FIT'

def mesh(name,vertices,faces,color,reference=False):
    m=bpy.data.meshes.new(name); m.from_pydata(vertices,[],faces); m.update()
    ob=bpy.data.objects.new(name,m); scene.collection.objects.link(ob)
    ob.color=tuple(int(color[i:i+2],16)/255 for i in (1,3,5))+(1,)
    material=bpy.data.materials.new(name); material.diffuse_color=ob.color; ob.data.materials.append(material)
    if reference:
        ob.display_type='WIRE'; ob.hide_render=True
    return ob
guide=mesh('Measured reference plane',data['referenceVertices'],[[0,1,2,3]],'#d5afea',True)
guide['lens_cap_role']='reference_plane'
for item in data['objects']:
    region=mesh(item['name'],item['vertices'],item['faces'],item['color'])
    region.matrix_world=Matrix(item['matrixWorld'])
    region['lens_cap_role']='region';region['lens_cap_id']=item['id']
uv=np.load(work/'distortion.npy')
stmap=bpy.data.images.new('Exact Brown radial redistortion STMap',width=ow,height=oh,alpha=True,float_buffer=True)
stmap.colorspace_settings.name='Non-Color'; stmap.pixels.foreach_set(uv.ravel()); stmap.pack()
scene.name='Calibrated camera - undistorted workspace'
overscan=scene;overscan['lens_cap_role']='workspace'
scene=scene.copy(); scene.use_fake_user=True; scene.name='Calibrated camera - distorted sensor output'
scene.render.resolution_x=sw; scene.render.resolution_y=sh;scene['lens_cap_role']='sensor_output'
# Keep the overscan pinhole render independent from the final sensor raster.
scene.use_nodes=True
if hasattr(scene,'compositing_node_group'):
    tree=bpy.data.node_groups.new('Lens Cap calibrated distortion','CompositorNodeTree'); scene.compositing_node_group=tree
else: tree=scene.node_tree
tree.nodes.clear()
render=tree.nodes.new('CompositorNodeRLayers'); render.scene=overscan; render.location=(-600,120)
background=tree.nodes.new('CompositorNodeImage'); background.image=reference; background.location=(-600,-100)
over=tree.nodes.new('CompositorNodeAlphaOver'); over.location=(-350,100); over.inputs.get('Factor',over.inputs[0]).default_value=1
# Referenced Render Layers use the output scene's dimensions in F12 renders.
# Restore their overscan pixel domain before mixing with the reference image.
resize=tree.nodes.new('CompositorNodeScale');resize.label='Restore calibrated overscan raster';resize.location=(-500,150)
if 'Type' in resize.inputs:resize.inputs['Type'].default_value='Absolute'
else:resize.space='ABSOLUTE'
resize.inputs['X'].default_value=ow;resize.inputs['Y'].default_value=oh
if hasattr(resize,'interpolation'):resize.interpolation='BILINEAR'
tree.links.new(render.outputs['Image'],resize.inputs['Image'])
tree.links.new(background.outputs['Image'],over.inputs.get('Background',over.inputs[1])); tree.links.new(resize.outputs['Image'],over.inputs.get('Foreground',over.inputs[2]))
map_image=tree.nodes.new('CompositorNodeImage'); map_image.image=stmap; map_image.location=(-350,-180)
warp=tree.nodes.new('CompositorNodeMapUV'); warp.location=(-80,100); warp.label='Exact calibrated k1 + k2; original sensor framing'
tree.links.new(over.outputs['Image'],warp.inputs['Image']); tree.links.new(map_image.outputs['Image'],warp.inputs['UV'])
if hasattr(scene,'compositing_node_group'):
    tree.interface.new_socket(name='Image',in_out='OUTPUT',socket_type='NodeSocketColor')
    output=tree.nodes.new('NodeGroupOutput')
else: output=tree.nodes.new('CompositorNodeComposite')
crop=tree.nodes.new('CompositorNodeCrop'); crop.location=(140,100)
if 'Width' in crop.inputs:
    crop.inputs['X'].default_value=(ow-sw)//2; crop.inputs['Y'].default_value=oh-sh-(oh-sh)//2
    crop.inputs['Width'].default_value=sw; crop.inputs['Height'].default_value=sh
else:
    crop.use_crop_size=True; crop.min_x=(ow-sw)//2; crop.max_x=crop.min_x+sw; crop.min_y=oh-sh-(oh-sh)//2; crop.max_y=crop.min_y+sh
tree.links.new(warp.outputs['Image'],crop.inputs['Image'])
output.location=(380,100); tree.links.new(crop.outputs['Image'],output.inputs['Image'])
scene['lens_cap_calibration']=json.dumps(data['calibration']); scene['lens_cap_plane']=json.dumps(plane)
scene['lens_cap_original_resolution']=data['sourceSize']
text=bpy.data.texts.new('Lens Cap - Read me')
text.write('Lens Cap calibrated scene\n\nUse the undistorted workspace scene for camera-aligned 3D editing. The distorted sensor output scene is active by default for F12 rendering at original resolution. Both scenes share the same geometry.\n\nThe workspace camera is an exact pinhole projection of the solved corrected camera. Blender viewport cameras cannot display radial distortion. The packed compositor STMap applies the calibrated Brown k1+k2 distortion to renders, returning original sensor framing. The undistorted reference is packed as camera background and render background. The measured reference mesh is wireframe and excluded from renders. Scene coordinates are metres, with saved signed axis assignments. Camera calibration accuracy remains limited by the original image, corner placement, and lens fit.\n')
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D': area.spaces.active.region_3d.view_perspective='CAMERA'
bpy.context.window.scene=scene
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=target,check_existing=False)
