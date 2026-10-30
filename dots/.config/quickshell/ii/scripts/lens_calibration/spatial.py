"""Measured planar reference and metre-based scene geometry. OpenCV camera axes x/y/z are right/down/forward."""
import copy
import json
import math
import re
import cv2
import numpy as np

AXES = dict(x='right', y='back', z='up', units='metres')


def numbers(value, count, name):
    try:
        a = np.asarray(value, dtype=np.float64)
    except (TypeError, ValueError):
        raise ValueError(f'Invalid {name}.') from None
    if a.shape != (count,) or not np.isfinite(a).all():
        raise ValueError(f'Invalid {name}.')
    return a


def validate_reference_plane(plane):
    """Validate measured geometry for persistence, without assuming a camera pose."""
    p = np.asarray(plane.get('corners', plane.get('points', [])), dtype=np.float64)
    if p.shape != (4, 2) or not np.isfinite(p).all():
        raise ValueError('Place four finite plane corners in perimeter order.')
    a=np.roll(p,-1,axis=0)-p; b=np.roll(p,-2,axis=0)-np.roll(p,-1,axis=0)
    cross=a[:,0]*b[:,1]-a[:,1]*b[:,0]
    if not (np.all(cross > 1) or np.all(cross < -1)) or abs(cv2.contourArea(p.astype(np.float32))) < 25:
        raise ValueError('Plane corners must form a convex, nondegenerate perimeter.')
    dimensions=numbers([plane.get('width'),plane.get('depth')],2,'plane dimensions')
    if np.any(dimensions<=0):
        raise ValueError('Plane width and depth must be positive.')
    axes=plane.get('referenceAxes',plane.get('axes',['x','y']))
    if isinstance(axes,dict): axes=['x','y']  # Existing solved-pose global axis labels.
    if not isinstance(axes,(list,tuple)) or len(axes)!=2 or any(axis not in ('x','-x','y','-y','z','-z') for axis in axes) or axes[0].lstrip('-')==axes[1].lstrip('-'):
        raise ValueError('Choose two different reference axes.')
    return dict(corners=p.tolist(),width=float(dimensions[0]),depth=float(dimensions[1]),axes=list(axes))


def reference_basis(axes):
    def vector(axis):
        result=np.zeros(3);result['xyz'.index(axis.lstrip('-'))]=-1 if axis.startswith('-') else 1
        return result
    first,second=map(vector,axes)
    return np.column_stack((first,second,np.cross(first,second)))


def calibrate_plane(plane, camera_matrix, output_size, signature):
    measured=validate_reference_plane(plane)
    p=np.asarray(measured['corners'],dtype=np.float64)
    w,d=measured['width'],measured['depth']
    local_world=np.array([[0,0,0],[w,0,0],[w,d,0],[0,d,0]],dtype=np.float64)
    basis=reference_basis(measured['axes'])
    world=local_world@basis.T
    k = np.asarray(camera_matrix,dtype=np.float64)
    candidates = cv2.solvePnPGeneric(world,p,k,None,flags=cv2.SOLVEPNP_IPPE)
    valid=[]
    for rv,tv in zip(candidates[1],candidates[2]):
        rv,tv=cv2.solvePnPRefineLM(world,p,k,None,rv.copy(),tv.copy())
        r=cv2.Rodrigues(rv)[0]; center=(-r.T@tv).ravel()
        depths=(world@r.T+tv.ravel())[:,2]
        if np.dot(center,basis[:,2]) <= 1e-6 or np.min(depths) <= 1e-6:
            continue
        projected=cv2.projectPoints(world,rv,tv,k,None)[0].reshape(-1,2)
        rms=float(np.sqrt(np.mean(np.sum((projected-p)**2,axis=1))))
        valid.append((rms,rv,tv,r,center))
    if not valid:
        raise ValueError('Corner order does not describe a plane viewed from above. Use near-left, near-right, far-right, far-left.')
    rms,rv,tv,r,center=min(valid,key=lambda x:x[0])
    if rms > max(3, np.linalg.norm(np.ptp(p,axis=0))*.02):
        raise ValueError(f'The assumed camera model cannot fit this measured plane ({rms:.2f} px RMS). The saved plane is independent of 3D calculation.')
    h,_=cv2.findHomography(local_world[:,:2],p,0)
    return dict(outputSize=list(output_size),corners=p.tolist(),width=float(w),depth=float(d),homography=h.tolist(),inverseHomography=np.linalg.inv(h).tolist(),cameraMatrix=k.tolist(),rvec=rv.ravel().tolist(),tvec=tv.ravel().tolist(),rotationMatrix=r.tolist(),cameraPosition=center.tolist(),reprojectionRms=rms,intrinsicsAssumed=True,axes=AXES,referenceAxes=measured['axes'],referenceBasis=basis.tolist(),mappingSignature=signature,stale=False)


def validate_scene(scene):
    if not isinstance(scene,dict) or not isinstance(scene.get('objects',[]),list) or not isinstance(scene.get('regions',[]),list):
        raise ValueError('Invalid native scene.')
    result=copy.deepcopy(scene); result.update(version=1,objects=[],regions=copy.deepcopy(scene.get('regions',[])))
    region_ids=set()
    for region in result['regions']:
        if not isinstance(region,dict) or not isinstance(region.get('id'),str) or not region['id'] or region['id'] in region_ids:
            raise ValueError('Native polygons require unique IDs.')
        region_ids.add(region['id'])
        points=np.asarray(region.get('points',[]),dtype=np.float64)
        if points.ndim!=2 or points.shape[1]!=2 or len(points)<3 or not np.isfinite(points).all() or not isinstance(region.get('label'),str) or not region['label']:
            raise ValueError('Native polygons require a label and at least three finite points.')
    ids=set()
    for obj in scene.get('objects',[]):
        if not isinstance(obj,dict) or not isinstance(obj.get('id'),str) or not obj['id'] or obj['id'] in ids:
            raise ValueError('Scene objects require unique nonempty IDs.')
        ids.add(obj['id']); kind=obj.get('kind')
        if kind not in ('plane','cuboid'):
            raise ValueError('Unknown scene object kind.')
        position=numbers(obj.get('position'),3,'object position')
        size=numbers(obj.get('size'),2 if kind=='plane' else 3,'object size')
        yaw=numbers([obj.get('yaw',0)],1,'object rotation')[0]
        if np.any(size <= 0): raise ValueError('Object dimensions must be positive.')
        color=obj.get('color','#cba6f7')
        if not isinstance(color,str) or not re.fullmatch(r'#[0-9a-fA-F]{6}',color): raise ValueError('Use a six-digit object color.')
        label=obj.get('label',obj['id'])
        if not isinstance(label,str): raise ValueError('Object label must be text.')
        orientation=obj.get('orientation','xy')
        if orientation not in ('xy','xz','yz'): raise ValueError('Unknown plane orientation.')
        normalized=dict(orientation=orientation,id=obj['id'],kind=kind,label=label,color=color,position=position.tolist(),size=size.tolist(),yaw=float(yaw))
        if 'rotationMatrix' in obj:
            rotation=np.asarray(obj['rotationMatrix'],dtype=float)
            if rotation.shape!=(3,3) or not np.isfinite(rotation).all() or not np.allclose(rotation.T@rotation,np.eye(3),atol=1e-5,rtol=0) or not np.isclose(np.linalg.det(rotation),1,atol=1e-5):
                raise ValueError('Object rotation matrix must be a proper orthonormal rotation.')
            normalized['rotationMatrix']=rotation.tolist()
        result['objects'].append(normalized)
    return result


def object_geometry(obj):
    w,d=obj['size'][:2]
    vertices=[[0,0,0],[w,0,0],[w,d,0],[0,d,0]]
    if obj['kind']=='plane' and obj.get('orientation')=='xz': vertices=[[x,0,y] for x,y,z in vertices]
    if obj['kind']=='plane' and obj.get('orientation')=='yz': vertices=[[0,x,y] for x,y,z in vertices]
    faces=[[0,3,2,1]]
    if obj['kind']=='cuboid':
        h=obj['size'][2]; vertices += [[0,0,h],[w,0,h],[w,d,h],[0,d,h]]
        faces += [[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]
    a=math.radians(obj['yaw']); c,s=math.cos(a),math.sin(a)
    rotation=np.array([[c,-s,0],[s,c,0],[0,0,1]])
    if 'rotationMatrix' in obj: rotation=rotation@np.asarray(obj['rotationMatrix'],dtype=float)
    vertices=np.asarray(vertices)@rotation.T+obj['position']
    edges=sorted({tuple(sorted((face[i],face[(i+1)%len(face)]))) for face in faces for i in range(len(face))})
    return vertices,faces,edges


def project_scene(scene, calibration, signature):
    scene=validate_scene(scene)
    if not calibration or calibration.get('mappingSignature')!=signature or calibration.get('stale'):
        raise ValueError('Set the measured reference plane for the current lens correction first.')
    k=np.asarray(calibration['cameraMatrix']); rv=np.asarray(calibration['rvec']); tv=np.asarray(calibration['tvec']); r=cv2.Rodrigues(rv)[0]
    objects=[]
    for obj in scene['objects']:
        world,faces,edges=object_geometry(obj); depths=(world@r.T+tv)[:,2]
        visible=bool(np.all(depths>1e-6))
        points=cv2.projectPoints(world,rv,tv,k,None)[0].reshape(-1,2).tolist() if visible else []
        objects.append(dict(**obj,worldVertices=world.tolist(),vertices=points,faces=faces,edges=edges,depths=depths.tolist(),visible=visible))
    return objects


def obj_text(scene, material_name):
    scene=validate_scene(scene); lines=['# Lens Cap; metres; X right; Y back; Z up',f'mtllib {material_name}']; materials=[]; offset=1
    for i,obj in enumerate(scene['objects']):
        world,faces,_=object_geometry(obj); name=f'object_{i}'
        lines += [f'o {name}',f'usemtl material_{i}']
        lines += ['v '+' '.join(format(float(v),'.17g') for v in p) for p in world]
        lines += ['f '+' '.join(str(offset+j) for j in f) for f in faces]; offset+=len(world)
        rgb=[int(obj['color'][j:j+2],16)/255 for j in (1,3,5)]
        materials += [f'newmtl material_{i}','Kd '+' '.join(format(v,'.9g') for v in rgb),'d 1']
    return '\n'.join(lines)+'\n','\n'.join(materials)+'\n'
