"""Read Blender meshes without running embedded scripts; recognize real cuboids."""
import itertools
import json
import math
from pathlib import Path
import sys

import numpy as np


def cuboid_geometry(vertices, faces):
    """Return a rigid box frame only when the evaluated closed mesh is a cuboid."""
    p=np.asarray(vertices,dtype=float)
    if p.shape!=(8,3) or not np.isfinite(p).all():
        raise ValueError('not an eight-corner box')
    scale=float(np.linalg.norm(np.ptp(p,axis=0)))
    if scale<=1e-9: raise ValueError('degenerate box')
    tolerance=max(1e-8,scale*2e-5)
    if min(np.linalg.norm(p[i]-p[j]) for i in range(8) for j in range(i))<=tolerance:
        raise ValueError('duplicate box corners')
    origin=p[np.lexsort((p[:,2],p[:,1],p[:,0]))[0]].copy()
    vectors=p-origin
    chosen=None
    for indexes in itertools.combinations([i for i,v in enumerate(vectors) if np.linalg.norm(v)>tolerance],3):
        edges=vectors[list(indexes)]; lengths=np.linalg.norm(edges,axis=1)
        basis=(edges/lengths[:,None]).T
        if not np.allclose(basis.T@basis,np.eye(3),atol=2e-5,rtol=0):continue
        local=(p-origin)@basis
        distances=np.minimum(abs(local),abs(local-lengths))
        if np.max(distances)>tolerance:continue
        if len(set(map(tuple,np.rint(local/lengths).astype(int))))!=8:continue
        chosen=(basis,lengths);break
    if chosen is None:raise ValueError('mesh is not a rectangular box')
    basis,lengths=chosen
    if np.linalg.det(basis)<0:
        basis=basis[:,[1,0,2]]; lengths=lengths[[1,0,2]]
    local=(p-origin)@basis
    edge_count={}; areas=np.zeros((3,2))
    if not isinstance(faces,(list,tuple)) or not 6<=len(faces)<=12:raise ValueError('box must have a closed surface')
    for face in faces:
        if len(face) not in (3,4) or len(set(face))!=len(face) or any(not isinstance(i,(int,np.integer)) or i<0 or i>=8 for i in face):
            raise ValueError('invalid box surface')
        f=local[face]; side=None
        for axis in range(3):
            for end in range(2):
                if np.max(abs(f[:,axis]-end*lengths[axis]))<=tolerance:side=(axis,end);break
            if side is not None:break
        if side is None:raise ValueError('box has a nonplanar or internal face')
        turns=np.array([np.cross(f[(i+1)%len(f)]-f[i],f[(i+2)%len(f)]-f[(i+1)%len(f)])[side[0]] for i in range(len(f))])
        if not (np.all(turns>tolerance*tolerance) or np.all(turns<-tolerance*tolerance)):
            raise ValueError('box face is crossed or nonconvex')
        area=sum(np.linalg.norm(np.cross(f[i]-f[0],f[i+1]-f[0]))*.5 for i in range(1,len(f)-1))
        if area<=tolerance*tolerance:raise ValueError('degenerate box face')
        areas[side]+=area
        for i in range(len(face)):
            edge=tuple(sorted((int(face[i]),int(face[(i+1)%len(face)]))))
            edge_count[edge]=edge_count.get(edge,0)+1
    if any(count!=2 for count in edge_count.values()):raise ValueError('box surface is not watertight')
    expected=np.array([lengths[1]*lengths[2],lengths[0]*lengths[2],lengths[0]*lengths[1]])[:,None]
    if not np.allclose(areas,expected,rtol=1e-4,atol=tolerance*tolerance):raise ValueError('box surface is incomplete or overlapping')
    return dict(position=origin.tolist(),size=lengths.tolist(),rotationMatrix=basis.tolist())


def object_identity(source, name, preferred, used):
    import hashlib
    namespace=str(Path(source).resolve())+'\0'+name
    identity=preferred if isinstance(preferred,str) and preferred and len(preferred)<=256 else 'blender-'+hashlib.sha256(namespace.encode()).hexdigest()[:20]
    if identity in used:identity='blender-'+hashlib.sha256((namespace+'\0'+identity).encode()).hexdigest()[:20]
    used.add(identity)
    return identity


def read_blend(source, destination):
    import bpy
    bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
    objects=[];details=[];seen=set();ids=set()
    scenes=[bpy.context.scene]+[s for s in bpy.data.scenes if s!=bpy.context.scene]
    for scene in scenes:
        bpy.context.window.scene=scene
        scale=float(scene.unit_settings.scale_length)
        if not math.isfinite(scale) or scale<=0:raise ValueError('Invalid Blender scene unit scale.')
        graph=bpy.context.evaluated_depsgraph_get()
        for obj in scene.objects:
            key=obj.as_pointer()
            if key in seen:continue
            seen.add(key)
            if obj.get('lens_cap_role')=='reference_plane':
                details.append(dict(name=obj.name,reason='reference plane'));continue
            if obj.type!='MESH':
                details.append(dict(name=obj.name,reason='not a box mesh'));continue
            evaluated=None
            try:
                evaluated=obj.evaluated_get(graph);mesh=evaluated.to_mesh()
                vertices=[list((evaluated.matrix_world@vertex.co)*scale) for vertex in mesh.vertices]
                frame=cuboid_geometry(vertices,[list(poly.vertices) for poly in mesh.polygons])
                identity=object_identity(source,obj.name,obj.get('lens_cap_id'),ids)
                color=obj.active_material.diffuse_color if obj.active_material else obj.color
                hexcolor='#'+''.join(f'{max(0,min(255,round(float(v)*255))):02x}' for v in color[:3])
                objects.append(dict(id=identity,kind='cuboid',label=obj.name,color=hexcolor,yaw=0,**frame))
            except (ValueError,RuntimeError) as error:
                details.append(dict(name=obj.name,reason=str(error)))
            finally:
                if evaluated is not None:evaluated.to_mesh_clear()
    Path(destination).write_text(json.dumps(dict(objects=objects,skipped=len(details),details=details)))


if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:]
    read_blend(Path(args[0]),Path(args[1]))
