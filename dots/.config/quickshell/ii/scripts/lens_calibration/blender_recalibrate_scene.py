"""Executed in a script-disabled Blender process; only managed calibration is replaced."""
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix

WORKSPACE='Calibrated camera - undistorted workspace'
OUTPUT='Calibrated camera - distorted sensor output'
source,template,target=sys.argv[sys.argv.index('--')+1:]
bpy.ops.wm.open_mainfile(filepath=source,load_ui=False,use_scripts=False)
source_scene=bpy.context.scene
old_workspace=next((s for s in bpy.data.scenes if s.get('lens_cap_role')=='workspace'),None) or bpy.data.scenes.get(WORKSPACE)
old_output=next((s for s in bpy.data.scenes if s.get('lens_cap_role')=='sensor_output'),None) or bpy.data.scenes.get(OUTPUT)
managed=[s for s in (old_workspace,old_output) if s is not None]
origin_scenes=managed or [source_scene]
old_camera=next((o for s in managed for o in s.objects if o.get('lens_cap_role')=='calibrated_camera'),None)
if old_camera is None and old_workspace and old_workspace.camera and old_workspace.camera.name=='Calibrated camera':old_camera=old_workspace.camera
old_guide=next((o for s in managed for o in s.objects if o.get('lens_cap_role')=='reference_plane'),None)
if old_guide is None and managed:old_guide=next((o for s in managed for o in s.objects if o.name=='Measured reference plane'),None)
old_camera_data=old_camera.data if old_camera else None
old_guide_data=old_guide.data if old_guide and old_guide.type=='MESH' else None
old_group=getattr(old_output,'compositing_node_group',None) if old_output else None
old_images=set(bg.image for bg in old_camera_data.background_images if bg.image) if old_camera_data else set()
if old_group:old_images.update(node.image for node in old_group.nodes if node.type=='IMAGE' and node.image)
world=(old_workspace or old_output or source_scene).world
unit_source=old_workspace or old_output or source_scene
unit_scale=float(unit_source.unit_settings.scale_length)
if not math.isfinite(unit_scale) or unit_scale<=0:raise ValueError('Invalid Blender scene unit scale.')
# Remember original collections and root-linked objects before appending assets.
collections=set(c for s in origin_scenes for c in s.collection.children)
root_objects=set(o for s in origin_scenes for o in s.collection.objects)
with bpy.data.libraries.load(template,link=False) as (available,loaded):loaded.scenes=[WORKSPACE,OUTPUT]
fresh_workspace,fresh_output=loaded.scenes
bpy.context.window.scene=fresh_workspace;bpy.context.view_layer.update()
fresh_camera=fresh_workspace.camera
fresh_guide=next(o for o in fresh_workspace.objects if o.get('lens_cap_role')=='reference_plane')
workspace=old_workspace or fresh_workspace
output=old_output or fresh_output
camera=old_camera or fresh_camera
guide=old_guide or fresh_guide
if old_camera:
    old_camera.data=fresh_camera.data
    old_camera.parent=None
    old_camera.animation_data_clear()
    for constraint in list(old_camera.constraints):old_camera.constraints.remove(constraint)
    old_camera.matrix_world=fresh_camera.matrix_world.copy()
else:camera.matrix_world=fresh_camera.matrix_world.copy()
# Calibrated geometry is in metres; existing authored Blender-unit coordinates stay fixed.
transform=camera.matrix_world.copy();transform.translation/=unit_scale;camera.matrix_world=transform
camera['lens_cap_role']='calibrated_camera'
if old_guide:
    old_guide.data=fresh_guide.data.copy()
    old_guide.parent=None;old_guide.matrix_world=Matrix.Identity(4)
    for modifier in list(old_guide.modifiers):old_guide.modifiers.remove(modifier)
    for constraint in list(old_guide.constraints):old_guide.constraints.remove(constraint)
    old_guide.animation_data_clear()
for vertex in guide.data.vertices:vertex.co/=unit_scale
guide.hide_render=True;guide.display_type='WIRE';guide['lens_cap_role']='reference_plane'
# Copy only render calibration, leaving engines, worlds and authored scene settings intact.
for destination,fresh,role in ((workspace,fresh_workspace,'workspace'),(output,fresh_output,'sensor_output')):
    if destination!=fresh:
        destination.render.resolution_x=fresh.render.resolution_x;destination.render.resolution_y=fresh.render.resolution_y
        destination.render.resolution_percentage=100
        destination.render.pixel_aspect_x=fresh.render.pixel_aspect_x;destination.render.pixel_aspect_y=fresh.render.pixel_aspect_y
        destination.render.film_transparent=True
    else:
        destination.render.engine=unit_source.render.engine
        destination.unit_settings.system=unit_source.unit_settings.system
        destination.unit_settings.scale_length=unit_scale
    destination.camera=camera;destination.world=world;destination.use_fake_user=True;destination['lens_cap_role']=role
    for collection in collections:
        if collection!=destination.collection and collection.name not in destination.collection.children:destination.collection.children.link(collection)
    for obj in root_objects | {camera,guide}:
        if obj not in (fresh_camera,fresh_guide) or obj in (camera,guide):
            if obj.name not in destination.objects:destination.collection.objects.link(obj)
    for key in ('lens_cap_calibration','lens_cap_plane','lens_cap_original_resolution'):
        if key in fresh_output:destination[key]=fresh_output[key]
# Swap the generated distortion pipeline as a private group, preserving unrelated groups/scenes.
output.use_nodes=True
if hasattr(output,'compositing_node_group'):
    output.compositing_node_group=fresh_output.compositing_node_group.copy()
    for node in output.compositing_node_group.nodes:
        if node.type=='R_LAYERS':node.scene=workspace
else:
    # Blender 4.x has embedded scene compositor trees; swapping the fresh scene
    # preserves the old scene as an authored scene instead of deleting its data.
    if output!=fresh_output:
        output.name=OUTPUT+' - previous calibration';output=fresh_output
        for collection in collections:
            if collection.name not in output.collection.children:output.collection.children.link(collection)
        for obj in root_objects | {camera,guide}:
            if obj.name not in output.objects:output.collection.objects.link(obj)
        output.camera=camera;output.world=world
    for node in output.node_tree.nodes:
        if node.type=='R_LAYERS':node.scene=workspace
# Discard template helper objects only after all camera/mesh data have been transferred.
for fresh,chosen in ((fresh_camera,camera),(fresh_guide,guide)):
    if fresh!=chosen:bpy.data.objects.remove(fresh,do_unlink=True)
for fresh,chosen in ((fresh_workspace,workspace),(fresh_output,output)):
    if fresh!=chosen:bpy.data.scenes.remove(fresh)
workspace.name=WORKSPACE;output.name=OUTPUT
# Retire only superseded generated assets, never arbitrary unused user data.
if old_camera_data and old_camera_data!=camera.data and old_camera_data.users==0:bpy.data.cameras.remove(old_camera_data)
if old_guide_data and old_guide_data!=guide.data and old_guide_data.users==0:bpy.data.meshes.remove(old_guide_data)
if old_group and old_group.users==0:bpy.data.node_groups.remove(old_group)
for image in old_images:
    if image.users==0:bpy.data.images.remove(image)
# Ensure loaded packed assets remain self contained, including authored textures.
for image in bpy.data.images:
    if image.source=='FILE' and not image.packed_file:
        try:image.pack()
        except RuntimeError:pass  # Preserve an existing missing-texture reference unchanged.
bpy.context.window.scene=output
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=target,check_existing=False)
print('LENS_CAP_RECALIBRATED',target)
