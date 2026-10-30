"""Line-delimited JSON worker. All OpenCV, optimization and disk I/O stay off QML."""
import hashlib
import copy
import itertools
import uuid
import json
import os
import re
from pathlib import Path
import sys
import tempfile
import cv2
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tool_app.files import local_path as path, atomic_json, rename_no_replace
from history import History, purpose_group
from profiles import manage_profile
import numpy as np
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import nearest_points
from spatial import validate_reference_plane, calibrate_plane, validate_scene, project_scene, obj_text, AXES
from geometry import calibrate, corrected_image, labelme_regions as geometry_labelme_regions, undistort, validate_model, matrix, output_geometry, original_to_output, output_to_original, densify, spatial_camera_matrix


def labelme_regions(document,size,coefficients,hfov=None):
    # LabelMe owns its full shape vocabulary; polygon-only downstream formats
    # must not prevent preserving rectangles, points, circles or lines.
    shapes=document.get('shapes')
    if not isinstance(shapes,list) or any(not isinstance(shape,dict) for shape in shapes):raise ValueError('Invalid LabelMe shapes.')
    return geometry_labelme_regions(dict(document,shapes=[shape for shape in shapes if shape.get('shape_type','polygon')=='polygon']),size,coefficients,hfov)


def distorted_labelme_shapes(shapes,size,coefficients,hfov=None):
    """Map corrected annotations back to sensor pixels without zone-name rules."""
    boundary=box(0.,0.,float(size[0]-1),float(size[1]-1))
    result=[]
    for index,shape in enumerate(shapes):
        if not isinstance(shape,dict):raise ValueError('Invalid LabelMe shape.')
        if shape.get('mask') is not None:raise ValueError('Distorted LabelMe export does not yet support mask shapes.')
        kind=shape.get('shape_type','polygon')
        points=np.asarray(shape.get('points',[]),dtype=float)
        if points.ndim!=2 or points.shape[1:]!=(2,) or not np.isfinite(points).all():raise ValueError(f'Invalid points in LabelMe shape {index+1}.')
        polygon=kind in ('polygon','rectangle','circle','oriented_rectangle')
        if kind=='rectangle':
            if len(points)!=2:raise ValueError('A LabelMe rectangle needs two corners.')
            left,top=points.min(axis=0);right,bottom=points.max(axis=0)
            points=np.array([[left,top],[right,top],[right,bottom],[left,bottom]])
        elif kind=='circle':
            if len(points)!=2:raise ValueError('A LabelMe circle needs a centre and edge point.')
            radius=float(np.linalg.norm(points[1]-points[0]))
            if radius<=0:raise ValueError('A LabelMe circle needs a positive radius.')
            angles=np.linspace(0,2*np.pi,max(64,min(65536,int(np.ceil(2*np.pi*radius/2)))),endpoint=False)
            points=points[0]+radius*np.column_stack((np.cos(angles),np.sin(angles)))
        elif kind not in ('polygon','oriented_rectangle','line','linestrip','point'):
            raise ValueError(f'Distorted LabelMe export does not support shape type {kind!r}.')
        if polygon:
            mapped=output_to_original(densify(points),size,coefficients,hfov)
            geometry=Polygon(mapped)
            if not geometry.is_valid:raise ValueError(f'LabelMe shape {index+1} is self-intersecting after distortion.')
            clipped=geometry.intersection(boundary)
            parts=[clipped] if clipped.geom_type=='Polygon' else [part for part in getattr(clipped,'geoms',[]) if part.geom_type=='Polygon']
            parts=sorted((part for part in parts if not part.is_empty and part.area>1e-12),key=lambda part:(-part.area,part.bounds))
            for part in parts:
                if part.interiors:raise ValueError('A distorted LabelMe polygon contains holes that LabelMe cannot represent.')
                output=copy.deepcopy(shape)
                output.update(shape_type='polygon',points=mapped.tolist() if len(parts)==1 and boundary.covers(geometry) else np.asarray(part.exterior.coords[:-1]).tolist())
                result.append(output)
        elif kind=='point':
            if len(points)!=1:raise ValueError('A LabelMe point shape needs one point.')
            mapped=output_to_original(points,size,coefficients,hfov)
            if boundary.covers(Point(mapped[0])):
                output=copy.deepcopy(shape);output.update(points=mapped.tolist());result.append(output)
        else:
            if len(points)<2 or (kind=='line' and len(points)!=2):raise ValueError('A LabelMe line needs two or more points.')
            samples=[]
            for a,b in zip(points[:-1],points[1:]):
                count=max(1,int(np.ceil(np.linalg.norm(b-a)/2)))
                samples.extend(a+(b-a)*t for t in np.arange(count)/count)
            samples.append(points[-1]);mapped=output_to_original(samples,size,coefficients,hfov)
            clipped=LineString(mapped).intersection(boundary)
            parts=[clipped] if clipped.geom_type=='LineString' else [part for part in getattr(clipped,'geoms',[]) if part.geom_type=='LineString']
            for part in parts:
                if part.is_empty or part.length<=1e-12:continue
                p=np.asarray(part.coords);output=copy.deepcopy(shape)
                # A radially warped line is a polyline; straight lines stay lines.
                vector=p[-1]-p[0];length=np.linalg.norm(vector)
                straight=length>0 and np.max(np.abs((p[:,0]-p[0,0])*vector[1]-(p[:,1]-p[0,1])*vector[0]))/length<1e-8
                output.update(shape_type='line' if kind=='line' and straight else 'linestrip',points=p[[0,-1]].tolist() if kind=='line' and straight else p.tolist())
                result.append(output)
    return result


def cleanup_vertex_indices(shape):
    """Generated smooth crop-boundary samples are geometry, not authored nodes."""
    marker=shape.get('lenscap_cleanup')
    if not isinstance(marker,dict) or marker.get('points')!=shape.get('points'):
        return range(len(shape.get('points',[])))
    return marker.get('vertices',range(len(shape.get('points',[]))))


def cleanup_region_identity(shape,index):
    marker=shape.get('lenscap_cleanup')
    return marker.get('source',index) if isinstance(marker,dict) and marker.get('points')==shape.get('points') else index


def clipped_cleanup_shapes(shapes,size,coefficients,hfov=None):
    """Expose real crop intersections without treating smooth samples as nodes."""
    sensor=np.array([[0.,0.],[size[0]-1.,0.],[size[0]-1.,size[1]-1.],[0.,size[1]-1.]])
    # Keep curved image sides to subpixel accuracy, without thousands of
    # collinear sampling nodes in the editable LabelMe polygon.
    footprint=Polygon(original_to_output(densify(sensor),size,coefficients,hfov)).simplify(.01,preserve_topology=True)
    geometry=output_geometry(size,coefficients,hfov)
    footprint=footprint.intersection(box(0.,0.,geometry['size'][0]-1.,geometry['size'][1]-1.))
    boundary=footprint.boundary;result=[];polygon_index=-1
    for si,shape in enumerate(shapes):
        if shape.get('shape_type','polygon')!='polygon':result.append(copy.deepcopy(shape));continue
        polygon_index+=1
        points=np.asarray(shape['points'],dtype=float);polygon=Polygon(points)
        # Keep already materialized geometry and its verified node mask.
        marker=shape.get('lenscap_cleanup')
        if isinstance(marker,dict) and marker.get('points')==shape.get('points'):
            result.append(copy.deepcopy(shape));continue
        if footprint.covers(polygon):result.append(copy.deepcopy(shape));continue
        clipped=polygon.intersection(footprint)
        parts=[clipped] if clipped.geom_type=='Polygon' else [part for part in getattr(clipped,'geoms',[]) if part.geom_type=='Polygon']
        if not parts:
            # A completely outside annotation is kept for future LabelMe edits;
            # it has no visible cleanup candidates.
            output=copy.deepcopy(shape);output['lenscap_cleanup']=dict(points=copy.deepcopy(shape['points']),vertices=[],boundary=[],source=uuid.uuid4().hex,origin=polygon_index)
            result.append(output);continue
        lineage=uuid.uuid4().hex
        for part in sorted(parts,key=lambda part:(-part.area,part.bounds)):
            if part.interiors:raise ValueError('Cropped region contains unsupported holes.')
            outline=np.asarray(part.exterior.coords[:-1]);vertices=[]
            for vi,point in enumerate(outline):
                if np.min(np.linalg.norm(points-point,axis=1))<1e-7:
                    vertices.append(vi);continue
                previous=outline[(vi-1)%len(outline)];following=outline[(vi+1)%len(outline)]
                # A crop entry/exit joins an authored edge to the curved image
                # border. Interior samples along that border stay ineligible.
                on_previous=boundary.distance(Point((previous+point)/2))<1e-7
                on_following=boundary.distance(Point((following+point)/2))<1e-7
                if on_previous!=on_following:vertices.append(vi)
            output=copy.deepcopy(shape);output['points']=outline.tolist()
            output['lenscap_cleanup']=dict(points=copy.deepcopy(output['points']),vertices=vertices,boundary=[vi for vi in vertices if boundary.distance(Point(outline[vi]))<1e-7],source=lineage,origin=polygon_index)
            result.append(output)
    return result


def refresh_cleanup_markers(shapes):
    for shape in shapes:
        marker=shape.get('lenscap_cleanup')
        if isinstance(marker,dict):marker['points']=copy.deepcopy(shape['points'])


def region_move_guard(shapes, validator=None):
    """Validate each proposed group against original shape and cumulative edits."""
    originals={}
    for si,shape in enumerate(shapes):
        if shape.get('shape_type','polygon')!='polygon':continue
        points=np.asarray(shape.get('points',[]),dtype=float)
        if points.ndim!=2 or points.shape[1:]!=(2,) or len(points)<3 or not np.isfinite(points).all():
            raise ValueError('Invalid region vertices.')
        polygon=Polygon(points)
        if not polygon.is_valid or polygon.area<=1e-12:
            raise ValueError('Invalid region polygon.')
        originals[si]=polygon
    def safe(result,members,target):
        targets=[target for _ in members] if not isinstance(target,dict) else [target[(si,vi)] for si,vi in members]
        old=[copy.deepcopy(result[si]['points'][vi]) for si,vi in members]
        for (si,vi),point in zip(members,targets):result[si]['points'][vi]=list(point)
        accepted=True
        try:
            for si in {si for si,_ in members}:
                points=np.asarray(result[si]['points']);polygon=Polygon(points);original=originals[si]
                # Keep winding and at least 80% of the original shape. A close
                # snap on a thin region can otherwise remove most of its area.
                if (len(np.unique(points,axis=0))!=len(points) or not polygon.is_valid or polygon.area<=1e-12 or
                        polygon.exterior.is_ccw!=original.exterior.is_ccw or
                        polygon.symmetric_difference(original).area>original.area*.2+1e-12):
                    accepted=False;break
                if validator is not None:validator(result[si])
        except Exception:
            accepted=False
        if not accepted:
            for (si,vi),point in zip(members,old):result[si]['points'][vi]=point
        return accepted
    return safe


def normalize_region_vertices(shapes, tolerance=2., stats=None, validator=None, crop_boundary=None, to_distance=None, from_distance=None):
    """Snap authored polygon vertices; complete-link groups prevent tolerance chains."""
    if isinstance(tolerance, bool):
        raise ValueError('Vertex tolerance must be a positive pixel distance.')
    try:
        tolerance=float(tolerance)
    except (TypeError, ValueError):
        raise ValueError('Vertex tolerance must be a positive pixel distance.')
    if not np.isfinite(tolerance) or tolerance<=0:
        raise ValueError('Vertex tolerance must be a positive pixel distance.')
    result=copy.deepcopy(shapes);vertices=[]
    for shape in result:
        marker=shape.get('lenscap_cleanup')
        if isinstance(marker,dict) and marker.get('points')!=shape.get('points'):
            shape.pop('lenscap_cleanup',None)
    safe=region_move_guard(result,validator);skipped=0
    for si,shape in enumerate(result):
        if shape.get('shape_type','polygon')!='polygon':continue
        points=np.asarray(shape.get('points',[]),dtype=float)
        if points.ndim!=2 or points.shape[1:]!=(2,) or len(points)<3 or not np.isfinite(points).all():
            raise ValueError('Invalid region vertices.')
        for vi in cleanup_vertex_indices(shape):vertices.append((si,vi,points[vi]))
    metric_points=np.asarray([v[2] for v in vertices],dtype=float)
    if len(vertices) and to_distance is not None:metric_points=np.asarray(to_distance(metric_points),dtype=float)
    distances={(si,vi):point for (si,vi,_),point in zip(vertices,metric_points)}
    groups=[]
    for vertex in sorted(vertices,key=lambda v:(v[2][0],v[2][1],v[0],v[1])):
        # Every pair in a group stays within tolerance, so a chain of nearby
        # nodes cannot pull distant corners into the same position.
        group=next((g for g in groups if all(cleanup_region_identity(result[vertex[0]],vertex[0])!=cleanup_region_identity(result[v[0]],v[0]) and np.linalg.norm(distances[vertex[:2]]-distances[v[:2]])<=tolerance for v in g)),None)
        if group is None:groups.append([vertex])
        else:group.append(vertex)
    moved=0;merged=0
    for group in groups:
        if len(group)<2:continue
        location=np.mean([distances[v[:2]] for v in group],axis=0)
        if from_distance is not None:location=np.asarray(from_distance([location]),dtype=float)[0]
        location=location.tolist()
        if crop_boundary is not None and any(vi in result[si].get('lenscap_cleanup',{}).get('boundary',[]) for si,vi,_ in group):
            location=list(nearest_points(crop_boundary,Point(location))[0].coords[0])
        metric_location=np.asarray(to_distance([location]),dtype=float)[0] if to_distance is not None else np.asarray(location)
        if any(np.linalg.norm(distances[v[:2]]-metric_location)>tolerance+1e-8 for v in group):
            skipped+=len(group);continue
        changed=any(np.linalg.norm(v[2]-location)>1e-8 for v in group)
        if not changed:continue
        members=[(si,vi) for si,vi,_ in group]
        if not safe(result,members,location):
            skipped+=sum(bool(np.linalg.norm(point-location)>1e-8) for _,_,point in group)
            continue
        merged+=1
        moved+=sum(bool(np.linalg.norm(point-location)>1e-8) for _,_,point in group)
    if stats is not None:stats['skippedVertices']=skipped
    refresh_cleanup_markers(result)
    return result,moved,merged



def snap_region_vertices_to_edges(shapes, tolerance=2., stats=None, validator=None):
    """Project shared vertices onto stable edges of other regions, longest first.

    An edge becomes an anchor when used: its endpoints cannot subsequently
    move. Existing vertex/edge incidences are anchors too, so repeating the
    operation cannot drift a boundary that already has sections attached.
    """
    if isinstance(tolerance,bool):
        raise ValueError('Edge tolerance must be a positive pixel distance.')
    try:tolerance=float(tolerance)
    except (TypeError,ValueError):raise ValueError('Edge tolerance must be a positive pixel distance.')
    if not np.isfinite(tolerance) or tolerance<=0:
        raise ValueError('Edge tolerance must be a positive pixel distance.')
    result=copy.deepcopy(shapes);groups={};edges=[]
    safe=region_move_guard(result,validator);skipped=set()
    for si,shape in enumerate(result):
        if shape.get('shape_type','polygon')!='polygon':continue
        points=np.asarray(shape.get('points',[]),dtype=float)
        if points.ndim!=2 or points.shape[1:]!=(2,) or len(points)<3 or not np.isfinite(points).all():
            raise ValueError('Invalid region vertices.')
        for vi,point in enumerate(points):groups.setdefault(tuple(point),[]).append((si,vi))
        for vi,(a,b) in enumerate(zip(points,np.roll(points,-1,axis=0))):
            length=float(np.linalg.norm(b-a))
            if length>0:edges.append((length,si,vi,tuple(a),tuple(b)))
    locations={key:np.array(key,dtype=float) for key in groups}
    owners={key:{si for si,_ in members} for key,members in groups.items()}
    frozen=set();settled=set();moved=set();epsilon=1e-8;constraints=[]
    def projection(point,a,b):
        vector=b-a;length2=float(vector@vector)
        if length2<=1e-20:return None
        t=float((point-a)@vector/length2)
        # Segment endpoints are valid edge targets too. Never use the infinite
        # line extension: clamp to the actual corner and test its distance.
        t=min(1.,max(0.,t))
        target=a+t*vector;distance=float(np.linalg.norm(point-target))
        return target,distance
    # Preserve already attached boundaries, including constraints from a prior
    # invocation, before considering any new movement.
    for _,si,_,ak,bk in edges:
        for key,point in locations.items():
            if si in owners[key]:continue
            hit=projection(point,locations[ak],locations[bk])
            if hit is not None and hit[1]<=epsilon:
                settled.add(key);frozen.update((ak,bk))
                vector=locations[bk]-locations[ak]
                constraints.append((key,ak,bk,float((point-locations[ak])@vector/(vector@vector))))
    def propagated(key,target,anchor_a,anchor_b):
        # Existing attachments form a linear constraint network. Solve the
        # smallest coordinated movement rather than freezing every endpoint.
        # Heavily weight the selected target edge so surrounding boundaries
        # remain stationary unless preserving attachments requires movement.
        keys=list(locations);indices={k:i for i,k in enumerate(keys)}
        vector=locations[anchor_b]-locations[anchor_a]
        t=float((target-locations[anchor_a])@vector/(vector@vector))
        equations=[*constraints,(key,anchor_a,anchor_b,t)]
        rows=[];rhs=[]
        for attached,ak,bk,fraction in equations:
            row=np.zeros(len(keys));row[indices[attached]]+=1
            row[indices[ak]]-=1-fraction;row[indices[bk]]-=fraction
            if np.max(np.abs(row))<=1e-12:continue
            rows.append(row)
            rhs.append(-(locations[attached]-(locations[ak]+fraction*(locations[bk]-locations[ak]))))
        matrix=np.asarray(rows);rhs=np.asarray(rhs)
        weights=np.ones(len(keys));weights[indices[anchor_a]]=weights[indices[anchor_b]]=0.
        delta=np.linalg.lstsq(matrix*weights,rhs,rcond=None)[0]*weights[:,None]
        if np.max(np.abs(matrix@delta-rhs))>epsilon:
            weights[indices[anchor_a]]=weights[indices[anchor_b]]=.001
            delta=np.linalg.lstsq(matrix*weights,rhs,rcond=None)[0]*weights[:,None]
            if np.max(np.abs(matrix@delta-rhs))>epsilon:return None
        proposed={k:locations[k]+delta[i] for i,k in enumerate(keys)}
        if any(np.linalg.norm(proposed[k]-np.asarray(k))>tolerance+epsilon for k in proposed):return None
        return {k:p for k,p in proposed.items() if np.linalg.norm(p-locations[k])>epsilon}
    for _,si,_,ak,bk in sorted(edges,key=lambda e:(-e[0],min(e[3],e[4]),max(e[3],e[4]),e[1],e[2])):
        a,b=locations[ak],locations[bk]
        candidates=[]
        for key,point in locations.items():
            if key in settled or si in owners[key]:continue
            hit=projection(point,a,b)
            if hit is not None and epsilon<hit[1]<=tolerance:
                candidates.append((hit[1],key,hit[0]))
        for _,key,target in sorted(candidates,key=lambda item:(item[0],item[1])):
            changes=propagated(key,target,ak,bk)
            if changes is None:
                skipped.add(key);continue
            final_a=changes.get(ak,locations[ak]);final_b=changes.get(bk,locations[bk])
            final_hit=projection(changes.get(key,locations[key]),final_a,final_b)
            if final_hit is None or final_hit[1]>epsilon:
                skipped.add(key);continue
            members=[member for changed in changes for member in groups[changed]]
            targets={member:changes[changed] for changed in changes for member in groups[changed]}
            if not safe(result,members,targets):
                skipped.add(key);continue
            locations.update(changes);settled.add(key);moved.update(changes)
            skipped.discard(key);frozen.update((ak,bk))
            vector=locations[bk]-locations[ak]
            constraints.append((key,ak,bk,float((locations[key]-locations[ak])@vector/(vector@vector))))
    for key,members in groups.items():
        for si,vi in members:result[si]['points'][vi]=locations[key].tolist()
    if stats is not None:stats['skippedVertices']=sum(len(groups[key]) for key in skipped if key not in moved)
    return result,sum(len(groups[key]) for key in moved)


def region_color(label):
    palette=('#ffb454','#63c7ff','#d49aff','#70db9b','#ff829b','#e7d665','#6edbd3','#b2b2ff')
    digest=0
    encoded=str(label).encode('utf-16-le',errors='surrogatepass')
    for i in range(0,len(encoded),2):
        digest=(digest*31+int.from_bytes(encoded[i:i+2],'little')) & 0xffffffff
    return palette[digest%len(palette)]


class Worker:
    def __init__(self, cache):
        self.cache = Path(cache)
        self.image = None
        self.source = None
        self.digest = None
        self.regions = []
        self.serial = 0
        self.region_coefficients = None
        self.region_hfov = None
        self.labelme_handoff = None
        self.extra_images = []
        self.batch_regions = []
        self.annotation_temp = tempfile.TemporaryDirectory(prefix='annotations-', dir=self.cache)
        self.annotation_directory = None
        self.annotation_documents = {}
        self.project_settings = dict(hfov=None,snapping=True,order=0)
        self.native_scene = dict(version=1,objects=[],regions=[])
        self.plane_calibration = None
        self.reference_plane = None
        self.annotation_image = None

    def image_entries(self):
        return [dict(source=str(self.source),sha256=self.digest),*self.extra_images]

    def native_document(self, regions, calibration):
        geometry=output_geometry(self.image.shape[1::-1],calibration['coefficients'],calibration.get('hfov'))
        return dict(imageWidth=geometry['size'][0],imageHeight=geometry['size'][1],imageData=None,shapes=[dict(r.get('labelmeShape',{}),label=r['label'],points=r['points'],shape_type='polygon',flags=r.get('flags',{}),group_id=r.get('group_id')) for r in regions])

    def commit_native(self, source, regions, calibration):
        scene=validate_scene(dict(self.native_scene,regions=regions))
        entries={e['source']:e for e in self.image_entries()}
        if source not in entries: raise ValueError('Unknown annotation image.')
        images={e['source']:dict(e) for e in scene.get('images',[])}
        images[source]=dict(entries[source],regions=regions,mappingSignature=self.spatial_signature(calibration))
        scene.update(images=list(images.values()),regions=regions,mappingSignature=self.spatial_signature(calibration),mappingStale=False)
        self.native_scene=scene
        self.annotation_documents[source]=dict(self.annotation_documents.get(source,{}),**self.native_document(regions,calibration))
        self.refresh_native_mappings(calibration)

    def refresh_native_mappings(self, calibration):
        signature=self.spatial_signature(calibration); batch=[]
        for entry in self.native_scene.get('images',[]):
            if entry.get('mappingSignature')!=signature: continue
            mapped=labelme_regions(self.native_document(entry['regions'],calibration),self.image.shape[1::-1],calibration['coefficients'],calibration.get('hfov'))
            batch.append(dict(source=entry['source'],regions=mapped))
        self.batch_regions=batch
        self.regions=next((e['regions'] for e in batch if e['source']==str(self.source)),[])
        self.region_coefficients=list(calibration['coefficients']);self.region_hfov=calibration.get('hfov')

    def select_annotation(self, source, calibration):
        source=str(path(source));entry=next((e for e in self.image_entries() if e['source']==source),None)
        if not entry: raise ValueError('Unknown annotation image.')
        _,image,digest=self.load(source)
        if digest!=entry['sha256'] or image.shape!=self.image.shape: raise ValueError('Annotation image changed or has incompatible dimensions.')
        self.serial+=1;target=self.cache/f'annotation-{self.serial}.png'
        if not cv2.imwrite(str(target),corrected_image(image,calibration['coefficients'],calibration.get('hfov'))): raise ValueError('Cannot prepare annotation image.')
        previous=self.cache.glob('annotation-*.png')
        for old in previous:
            if old!=target: old.unlink(missing_ok=True)
        self.annotation_image=source
        item=next((e for e in self.native_scene.get('images',[]) if e['source']==source),None)
        self.native_scene=dict(self.native_scene,regions=item['regions'] if item else [],mappingSignature=item.get('mappingSignature') if item else self.spatial_signature(calibration))
        return dict(activeImage=source,annotationPreview=target.as_uri(),**self.spatial_state(calibration),regions=self.regions,batchRegions=self.batch_regions)

    def spatial_signature(self, calibration):
        if not calibration: return None
        value=dict(size=list(self.image.shape[1::-1]),coefficients=calibration['coefficients'],hfov=calibration.get('hfov'))
        return hashlib.sha256(json.dumps(value,sort_keys=True,allow_nan=False).encode()).hexdigest()

    def equivalent_mapping(self, signature, calibration):
        # Older project signatures used JSON's int/float spelling. Geometry is
        # unchanged when e.g. a manual editor returns 0 instead of 0.0.
        def variants(value):
            if value is None:return [None]
            number=float(value);result=[value,number]
            if number.is_integer():result.append(int(number))
            if number==0:result.append(0.0)
            return result
        coefficients=calibration['coefficients']
        for first,second,hfov in itertools.product(variants(coefficients[0]),variants(coefficients[1]),variants(calibration.get('hfov'))):
            if signature==self.spatial_signature(dict(calibration,coefficients=[first,second],hfov=hfov)):return True
        return False

    def spatial_state(self, calibration):
        signature=self.spatial_signature(calibration)
        plane=dict(self.plane_calibration) if self.plane_calibration else None
        if plane: plane['stale']=plane.get('mappingSignature')!=signature
        scene=dict(self.native_scene)
        scene['mappingStale']=bool(scene.get('regions')) and scene.get('mappingSignature')!=signature
        projected=[]
        if plane and not plane['stale']:
            projected=project_scene(scene,plane,signature)
        reference=dict(self.reference_plane) if self.reference_plane else None
        if reference: reference['stale']=reference.get('mappingSignature')!=signature
        return dict(nativeScene=scene,nativeRegions=scene.get('regions',[]),referencePlane=reference,planeCalibration=plane,projectedScene=projected)

    def settings(self, value=None):
        settings=dict(self.project_settings)
        settings.update(value or {})
        hfov=settings.get('hfov')
        if hfov is not None:
            if isinstance(hfov,bool):
                raise ValueError('Horizontal field of view must be between 1 and 179 degrees.')
            try:
                hfov=float(hfov)
            except (TypeError,ValueError):
                raise ValueError('Horizontal field of view must be between 1 and 179 degrees.')
            matrix((2,2),hfov)
        if type(settings.get('snapping')) is not bool or type(settings.get('order')) is not int or settings.get('order') not in (0,1,2):
            raise ValueError('Invalid project settings.')
        return dict(hfov=hfov,snapping=settings['snapping'],order=settings['order'])

    def load(self, filename):
        filename = path(filename)
        raw = filename.read_bytes()
        image = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR | cv2.IMREAD_IGNORE_ORIENTATION)
        if image is None:
            raise ValueError('Cannot decode image.')
        return filename, image, hashlib.sha256(raw).hexdigest()

    def preview(self, coefficients, curves, hfov=None):
        size = self.image.shape[1::-1]
        validate_model(size, coefficients, hfov)
        result = corrected_image(self.image, coefficients, hfov)
        self.serial += 1
        filename = self.cache / f'corrected-{self.serial}.png'
        if not cv2.imwrite(str(filename), result):
            raise ValueError('Cannot write preview.')
        # Keep the current and previous frames so Qt can finish image loading.
        for old in self.cache.glob('corrected-*.png'):
            if old.name not in (filename.name, f'corrected-{self.serial-1}.png'):
                old.unlink(missing_ok=True)
        calibration=dict(coefficients=list(coefficients),hfov=hfov)
        active=self.annotation_image if self.annotation_image in {e['source'] for e in self.image_entries()} else str(self.source)
        annotation=self.select_annotation(active,calibration)
        return dict(**self.spatial_state(calibration),activeImage=annotation['activeImage'],annotationPreview=annotation['annotationPreview'],preview=filename.as_uri(),
                    outputGeometry=output_geometry(size, coefficients, hfov),
                    correctedCurves=[original_to_output(c, size, coefficients, hfov).tolist() if c else [] for c in curves])

    def clear_regions(self):
        # Keep authored LabelMe data with its per-image mapping snapshot while
        # derived source-space polygons are invalidated by a lens change.
        if self.annotation_documents:
            images={entry['source']:dict(entry) for entry in self.native_scene.get('images',[])}
            known={entry['source']:entry for entry in self.image_entries()} if self.image is not None else {}
            for source,document in self.annotation_documents.items():
                if source in known:
                    entry=images.setdefault(source,dict(known[source],regions=[]))
                    entry['labelmeDocument']=document
            self.native_scene=dict(self.native_scene,images=list(images.values()))
        self.regions = []
        self.batch_regions = []
        self.region_coefficients = None
        self.region_hfov = None
        self.labelme_handoff = None
        self.annotation_directory = None
        self.annotation_documents = {}

    def annotation_folder(self, size, coefficients, inputs, hfov=None):
        mapping = dict(version=3,size=list(size),hfov=hfov,coefficients=[float(v) for v in coefficients],
            outputGeometry=output_geometry(size,coefficients,hfov),inputs=inputs)
        digest=hashlib.sha256(json.dumps(mapping,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
        return Path(self.annotation_temp.name)/digest

    def restore_regions(self, regions, size, calibration, legacy=False):
        if not regions:
            return []
        if not calibration:
            raise ValueError('Session regions require a calibration.')
        geometry = output_geometry(size, calibration['coefficients'], calibration.get('hfov'))
        origin = np.array(geometry['origin'])
        shapes = [dict(label=r['label'], points=(np.asarray(r['correctedPoints'])-origin).tolist()
                  if legacy else r['correctedPoints']) for r in regions]
        return labelme_regions(dict(imageWidth=geometry['size'][0], imageHeight=geometry['size'][1],
            shapes=shapes), size, calibration['coefficients'], calibration.get('hfov'))

    def protected_target(self, target):
        if path(target) in [self.source, *[path(e['source']) for e in self.extra_images]]:
            raise ValueError('Cannot overwrite an original snapshot.')

    def handle(self, request):
        op = request['op']
        if op == 'convert_legacy':
            source=path(request['path'])
            if source.suffix.lower()!='.lensproject':
                raise ValueError('Choose a legacy .lensproject file to convert.')
            target=source.with_suffix('.lenscap')
            if os.path.lexists(target):
                raise ValueError('A .lenscap project already exists beside this legacy file.')
            # Validate without touching the currently open worker or its previews.
            with tempfile.TemporaryDirectory(prefix='legacy-validation-',dir=self.cache) as cache:
                validator=Worker(cache)
                try:
                    validator.handle(dict(op='load',path=str(source)))
                finally:
                    validator.annotation_temp.cleanup()
            snapshot=self.__dict__.copy()
            cached={filename.name:filename.read_bytes() for filename in self.cache.iterdir()
                    if filename.is_file() and (filename.name=='original.png' or filename.name.startswith('corrected-'))}
            rename_no_replace(source,target)
            try:
                result=self.handle(dict(op='load',path=str(target)))
            except Exception:
                rename_no_replace(target,source)
                self.__dict__.clear()
                self.__dict__.update(snapshot)
                for filename in self.cache.iterdir():
                    if filename.is_file() and (filename.name=='original.png' or filename.name.startswith('corrected-')):
                        filename.unlink()
                for name,data in cached.items():
                    (self.cache/name).write_bytes(data)
                raise
            result.update(projectPath=str(target),message='Legacy project converted to .lenscap')
            return result
        if op in ('open', 'load'):
            session = json.loads(path(request['path']).read_text()) if op == 'load' else None
            if op == 'load' and (not isinstance(session, dict) or session.get('version') not in (1, 2, 3)):
                raise ValueError('Unsupported calibration session version.')
            source, image, digest = self.load(session['source'] if session else request['path'])
            if session and (session['sha256'] != digest or session['size'] != list(image.shape[1::-1])):
                raise ValueError('Original image changed since this session was saved.')
            curves = session['curves'] if session else []
            for curve in curves:
                p = np.asarray(curve, dtype=float)
                if p.ndim != 2 or p.shape[1] != 2 or not np.isfinite(p).all() or np.any(p < 0) or np.any(p > np.array(image.shape[1::-1])-1):
                    raise ValueError('Session contains invalid trace points.')
            if session and session.get('calibration'):
                validate_model(image.shape[1::-1], session['calibration']['coefficients'],session['calibration'].get('hfov'))
            # Validate stored mappings by rebuilding them from corrected pixels.
            # Never trust serialized normalized coordinates for stream exports.
            regions = session.get('regions', []) if session else []
            calibration = session.get('calibration') if session else None
            regions = self.restore_regions(regions, image.shape[1::-1], calibration,
                                           session['version']==1 if session else False)
            extras = session.get('extraImages', []) if session else []
            seen = {source}
            for extra in extras:
                extra_source, extra_image, extra_digest = self.load(extra['source'])
                if extra_source in seen or extra_image.shape != image.shape or extra_digest != extra['sha256']:
                    raise ValueError('Additional image changed or has incompatible dimensions.')
                seen.add(extra_source)
            batch = []
            for item in session.get('batchRegions', []) if session else []:
                item_source = str(path(item['source']))
                if path(item_source) not in seen:
                    raise ValueError('Session batch contains an unknown source.')
                batch.append(dict(source=item_source, regions=self.restore_regions(item['regions'], image.shape[1::-1], calibration)))
            if calibration and session and session.get('outputGeometry') not in (None, output_geometry(image.shape[1::-1],calibration['coefficients'],calibration.get('hfov'))):
                raise ValueError('Session output geometry differs from its calibration.')
            documents = session.get('labelmeDocuments', {}) if session else {}
            if not isinstance(documents, dict):
                raise ValueError('Invalid saved LabelMe documents.')
            documents = dict(documents)
            for document_source, document in documents.items():
                if path(document_source) not in seen or not calibration:
                    raise ValueError('Saved LabelMe document has an unknown source or calibration.')
                labelme_regions(document,image.shape[1::-1],calibration['coefficients'],calibration.get('hfov'))
            # Older projects retain mapped corrected points but not raw LabelMe JSON.
            # Reconstruct only actual saved polygons, never an initial blank file.
            old_items = batch or ([dict(source=str(source),regions=regions)] if regions else [])
            if calibration:
                geometry=output_geometry(image.shape[1::-1],calibration['coefficients'],calibration.get('hfov'))
                for item in old_items:
                    if item['regions'] and item['source'] not in documents:
                        documents[item['source']]=dict(version='5.0.1',flags={},
                            imageWidth=geometry['size'][0],imageHeight=geometry['size'][1],
                            imageData=None,shapes=[dict(label=r['label'],points=r['correctedPoints'],
                            shape_type='polygon',flags={},group_id=None) for r in item['regions']])
            # The stored directory is an informational temporary reference. Never
            # read an arbitrary path from a project; regenerate inside our own temp.
            annotation_directory = None
            settings=self.settings((dict(hfov=calibration.get('hfov') if calibration else None,order=(0 if calibration.get('modelSelection')=='auto' else calibration.get('order',1)) if calibration else 0) | (session.get('projectSettings',{}) if session else {})))
            if calibration and settings['hfov']!=calibration.get('hfov'):
                raise ValueError('Project HFOV differs from its saved calibration.')
            native_scene=validate_scene(session.get("nativeScene",dict(objects=[],regions=[]))) if session else dict(version=1,objects=[],regions=[])
            known_entries={str(source):digest,**{e['source']:e['sha256'] for e in extras}}
            native_sources=set()
            for item in native_scene.get('images',[]):
                if item.get('source') not in known_entries or item.get('sha256')!=known_entries[item['source']] or item['source'] in native_sources:
                    raise ValueError('Native annotations reference an unknown or changed image.')
                native_sources.add(item['source']);validate_scene(dict(objects=[],regions=item['regions']))
            plane_calibration=session.get("planeCalibration") if session else None
            if plane_calibration:
                plane_calibration=calibrate_plane(plane_calibration,plane_calibration["cameraMatrix"],plane_calibration.get("outputSize",image.shape[1::-1]),plane_calibration["mappingSignature"])
            reference_plane=session.get("referencePlane",plane_calibration) if session else None
            if reference_plane:
                reference_plane=dict(validate_reference_plane(reference_plane),mappingSignature=reference_plane.get('mappingSignature'),outputSize=reference_plane.get('outputSize',list(image.shape[1::-1])))
            candidate_active=str(path(session.get("activeImage") or source)) if session else str(source)
            if candidate_active not in known_entries: raise ValueError("Unknown saved annotation image.")
            old_spatial=self.native_scene,self.plane_calibration,self.annotation_image,self.reference_plane
            old_state = self.source, self.image, self.digest, self.regions, self.region_coefficients, self.extra_images, self.batch_regions, self.labelme_handoff, self.annotation_directory, self.annotation_documents, self.region_hfov, self.project_settings
            self.source, self.image, self.digest = source, image, digest
            self.regions, self.extra_images, self.batch_regions = regions, extras, batch
            self.region_coefficients = list(calibration['coefficients']) if regions or batch else None
            self.labelme_handoff = None
            self.annotation_directory = annotation_directory
            self.annotation_documents = documents
            self.region_hfov = calibration.get("hfov") if calibration and (regions or batch) else None
            self.project_settings = settings
            self.annotation_image=candidate_active
            self.native_scene = native_scene
            self.plane_calibration = plane_calibration
            self.reference_plane = reference_plane
            original = self.cache / 'original.png'

            out = dict(original=original.as_uri(), size=list(image.shape[1::-1]), source=str(source),
                       curves=curves, calibration=session.get('calibration') if session else None,
                       regions=self.regions, extraImages=[e["source"] for e in self.extra_images], batchRegions=self.batch_regions,
                       annotationDirectory=self.annotation_directory, projectSettings=self.project_settings, projectPath=str(path(request["path"])) if op=="load" else "")
            try:
                if out['calibration']:
                    out.update(self.preview(out['calibration']['coefficients'], curves,out['calibration'].get('hfov')))
                if not cv2.imwrite(str(original), self.image):
                    raise ValueError('Cannot write original preview.')
            except Exception:
                self.native_scene,self.plane_calibration,self.annotation_image,self.reference_plane=old_spatial
                self.source, self.image, self.digest, self.regions, self.region_coefficients, self.extra_images, self.batch_regions, self.labelme_handoff, self.annotation_directory, self.annotation_documents, self.region_hfov, self.project_settings = old_state
                raise
            self.annotation_image=candidate_active
            if calibration:
                if not self.native_scene.get('images'):
                    legacy_scene=dict(self.native_scene);legacy_regions=legacy_scene.get('regions',[])
                    for original,document in list(documents.items()):
                        native=[dict(id='legacy-'+str(i),label=shape.get('label','region'),color=region_color(shape.get('label','region')),labelmeShape=shape,points=shape['points'],flags=shape.get('flags',{}),group_id=shape.get('group_id')) for i,shape in enumerate(document.get('shapes',[])) if shape.get('shape_type','polygon')=='polygon']
                        if native:
                            self.commit_native(original,native,calibration)
                            self.annotation_documents[original]=document
                    if not self.native_scene.get('images') and legacy_regions: self.commit_native(str(source),legacy_regions,calibration)
                if self.native_scene.get('images'): self.refresh_native_mappings(calibration)
                out.update(self.select_annotation(session.get('activeImage') or str(source) if session else str(source),calibration))
            out.update(self.spatial_state(calibration))
            return out
        if op == 'set_settings':
            settings=self.settings(request.get('projectSettings'))
            changed=settings['hfov']!=self.project_settings['hfov']
            self.project_settings=settings
            if changed:
                self.clear_regions()
                return dict(**self.spatial_state(None),projectSettings=settings,calibration=None,regions=[],batchRegions=[],outputGeometry=None,
                            message='HFOV changed; calculate calibration again')
            return dict(projectSettings=settings,message='Project settings saved')
        if self.image is None:
            raise ValueError('Open an image first.')
        size = self.image.shape[1::-1]
        curves = request.get('curves', [])
        calibration = request.get('calibration')
        if op=='select_image':
            if not calibration: raise ValueError('Calculate lens correction first.')
            return self.select_annotation(request['source'],calibration)
        if op in ('save_reference_plane','calculate_spatial_calibration','set_spatial_calibration','project_spatial','native_regions','export_scene','export_spatial','import_blend','recalibrate_blend'):
            if not calibration:
                raise ValueError('Calculate lens correction first.')
            signature=self.spatial_signature(calibration)
            geometry=output_geometry(size,calibration['coefficients'],calibration.get('hfov'))
            if op=='save_reference_plane':
                reference=dict(validate_reference_plane(request['plane']),mappingSignature=signature,outputSize=geometry['size'])
                if reference != self.reference_plane:
                    self.plane_calibration=None
                self.reference_plane=reference
                return dict(**self.spatial_state(calibration),message='Reference plane saved')
            if op in ('calculate_spatial_calibration','set_spatial_calibration'):
                reference=request.get('plane') or self.reference_plane
                if not reference:
                    raise ValueError('Save a reference plane first.')
                if 'plane' not in request and reference.get('mappingSignature')!=signature:
                    raise ValueError('Reference plane belongs to a different lens correction; save it again first.')
                result=calibrate_plane(reference,spatial_camera_matrix(size,calibration['coefficients'],calibration.get('hfov')),geometry['size'],signature)
                projected=project_scene(self.native_scene,result,signature)
                self.plane_calibration=result
                if op=='set_spatial_calibration':
                    self.reference_plane=dict(validate_reference_plane(reference),mappingSignature=signature,outputSize=geometry['size'])
                return dict(**self.spatial_state(calibration),message='3D space calculated')
            if op=='native_regions':
                native=request['regions']
                if not isinstance(native,list): raise ValueError('Invalid native polygons.')
                ids=set()
                for region in native:
                    if not isinstance(region,dict) or not isinstance(region.get('id'),str) or not region['id'] or region['id'] in ids:
                        raise ValueError('Native polygons require unique IDs.')
                    ids.add(region['id'])
                validate_scene(dict(self.native_scene,regions=native))
                document=dict(imageWidth=geometry['size'][0],imageHeight=geometry['size'][1],shapes=[dict(label=r['label'],points=r['points'],shape_type='polygon') for r in native])
                mapped=labelme_regions(document,size,calibration['coefficients'],calibration.get('hfov'))
                self.commit_native(self.annotation_image or str(self.source),native,calibration)
                return dict(nativeRegions=native,nativeScene=self.native_scene,regions=self.regions,batchRegions=self.batch_regions,message='Regions updated')
            if op=='recalibrate_blend':
                project_scene(self.native_scene,self.plane_calibration,signature)
                source=path(request['sourcePath']);target=path(request['path'])
                if source.suffix.lower()!='.blend' or target.suffix.lower()!='.blend': raise ValueError('Choose Blender .blend files.')
                if source.resolve()==target.resolve(): raise ValueError('Save the recalibrated Blender scene as a new file.')
                self.protected_target(target)
                from blender_recalibrate import recalibrate_blend
                recalibrate_blend(source,target,self.image,calibration,self.plane_calibration,self.native_scene,size)
                return dict(message='Recalibrated Blender scene saved',blenderPath=str(target))
            if op=='import_blend':
                project_scene(self.native_scene,self.plane_calibration,signature)
                source=path(request['path'])
                if source.suffix.lower()!='.blend': raise ValueError('Choose a .blend file to import 3D regions.')
                from blender_import import import_blend
                imported=import_blend(source)
                boxes=validate_scene(dict(objects=imported.get('objects',[])))['objects']
                if any(obj['kind']!='cuboid' for obj in boxes): raise ValueError('Blender import returned a non-box region.')
                merged=validate_scene(self.native_scene)
                slots={obj['id']:i for i,obj in enumerate(merged['objects'])}
                for obj in boxes:
                    if obj['id'] in slots: merged['objects'][slots[obj['id']]]=obj
                    else: slots[obj['id']]=len(merged['objects']);merged['objects'].append(obj)
                projected=project_scene(merged,self.plane_calibration,signature)
                self.native_scene=merged
                skipped=imported.get('skipped',0)
                return dict(nativeScene=merged,projectedScene=projected,importedCount=len(boxes),skippedCount=skipped,message=f'Imported {len(boxes)} 3D regions; skipped {skipped} non-box objects.')
            scene=validate_scene(request.get('nativeScene',self.native_scene))
            if op=='project_spatial':
                projected=project_scene(scene,self.plane_calibration,signature)
                self.native_scene=scene
                return dict(nativeScene=scene,projectedScene=projected)
            self.protected_target(request['path'])
            target=path(request['path']); fmt=request.get('format','json')
            if fmt=='json':
                atomic_json(target,dict(version=1,axes=AXES,nativeScene=scene,planeCalibration=self.plane_calibration))
            elif fmt=='blend':
                project_scene(scene,self.plane_calibration,signature)
                if target.suffix.lower()!='.blend': raise ValueError('Choose a .blend filename for the Blender scene.')
                from blender_export import export_blend
                export_blend(target,self.image,calibration,self.plane_calibration,scene,size)
            elif fmt=='obj':
                material=target.with_suffix('.mtl'); self.protected_target(material)
                if '\n' in material.name or '\r' in material.name: raise ValueError('Invalid material filename.')
                obj,mtl=obj_text(scene,material.name)
                material.write_text(mtl); target.write_text(obj)
            else: raise ValueError('Unknown scene export format.')
            self.native_scene=scene
            return dict(nativeScene=scene,message='Scene exported')
        if op == 'add_images':
            extras = list(self.extra_images)
            seen = {self.source, *[path(e['source']) for e in extras]}
            for filename in request['paths']:
                source, image, digest = self.load(filename)
                if source in seen:
                    continue
                if image.shape != self.image.shape:
                    raise ValueError('Additional images must match the reference image dimensions.')
                extras.append(dict(source=str(source), sha256=digest))
                seen.add(source)
            if extras != self.extra_images:
                self.extra_images = extras
                # New source images change the LabelMe batch, not existing
                # images' pixel mapping or authored regions.
                self.labelme_handoff = None
                self.annotation_directory = None
            return dict(extraImages=[e['source'] for e in extras], regions=self.regions,
                        batchRegions=self.batch_regions, message=f'{len(extras)} additional images')
        if op == 'clear_profile':
            self.clear_regions()
            return dict(calibration=None,regions=[],batchRegions=[],message='Lens profile cleared')
        if op == 'load_preset':
            document = json.loads(path(request['path']).read_text())
            if document.get('type') != 'lens-calibration-preset' or document.get('version') != 1:
                raise ValueError('Unsupported calibration preset.')
            if document.get('size') != list(size):
                raise ValueError('Preset dimensions differ from the reference image.')
            calibration = document['calibration']
            geometry = output_geometry(size, calibration['coefficients'], calibration.get('hfov'))
            if document.get('outputGeometry') != geometry:
                raise ValueError('Preset output geometry differs from its calibration.')
            settings=self.settings(dict(hfov=calibration.get('hfov'),order=0 if calibration.get('modelSelection')=='auto' else calibration.get('order',1)) | document.get('projectSettings',{}))
            if settings['hfov']!=calibration.get('hfov'):
                raise ValueError('Preset HFOV differs from its calibration.')
            preview = self.preview(calibration['coefficients'], curves,calibration.get('hfov'))
            self.project_settings=settings
            self.clear_regions()
            return dict(calibration=calibration, projectSettings=self.project_settings,regions=[], batchRegions=[],
                        message='Calibration preset loaded', **preview)
        if op == 'calibrate':
            settings=self.settings(request.get('projectSettings'))
            settings['order']=request.get('order',settings['order'])
            calibration = calibrate(curves, size, settings['order'],settings['hfov'])
            preview = self.preview(calibration['coefficients'], curves, calibration.get('hfov'))
            self.project_settings=settings
            self.clear_regions()
            return dict(calibration=calibration,projectSettings=self.project_settings, **preview)
        if op in ('preview', 'image', 'labelme', 'regions', 'parameters', 'prepare_labelme', 'finish_labelme', 'save_preset', 'export_labelme', 'normalize_vertices', 'snap_vertices_to_edges'):
            if not calibration:
                raise ValueError('Calculate a calibration first.')
            validate_model(size, calibration['coefficients'], calibration.get('hfov'))
        if op in ('normalize_vertices','snap_vertices_to_edges'):
            source=self.annotation_image or str(self.source)
            snapshot=next((entry for entry in self.native_scene.get('images',[]) if entry['source']==source),None)
            if snapshot and not self.equivalent_mapping(snapshot.get('mappingSignature'),calibration):
                raise ValueError('Annotations use an older lens correction. Review and save them in LabelMe before normalizing vertices.')
            document=copy.deepcopy(self.annotation_documents.get(source) or {})
            native=copy.deepcopy((snapshot or {}).get('regions',self.native_scene.get('regions',[])))
            canonical=iter(self.native_document(native,calibration)['shapes'])
            shapes=[]
            for shape in document.get('shapes',[]):
                if shape.get('shape_type','polygon')!='polygon':shapes.append(shape)
                else:
                    current=next(canonical,None)
                    if current is not None:shapes.append(current)
            shapes.extend(canonical)
            stats={}
            def validate_shape(shape):
                geometry=output_geometry(size,calibration['coefficients'],calibration.get('hfov'))
                labelme_regions(dict(imageWidth=geometry['size'][0],imageHeight=geometry['size'][1],shapes=[shape]),size,calibration['coefficients'],calibration.get('hfov'))
            view_space=request.get('viewSpace','corrected')
            if op=='normalize_vertices' and view_space not in ('original','corrected'):
                raise ValueError('Unsupported normalization view space.')
            if op=='normalize_vertices':
                shapes=clipped_cleanup_shapes(shapes,size,calibration['coefficients'],calibration.get('hfov'))
                sensor=np.array([[0.,0.],[size[0]-1.,0.],[size[0]-1.,size[1]-1.],[0.,size[1]-1.]])
                crop_boundary=Polygon(original_to_output(densify(sensor),size,calibration['coefficients'],calibration.get('hfov'))).simplify(.01,preserve_topology=True).boundary
                to_distance=(lambda points:output_to_original(points,size,calibration['coefficients'],calibration.get('hfov'))) if view_space=='original' else None
                from_distance=(lambda points:original_to_output(points,size,calibration['coefficients'],calibration.get('hfov'))) if view_space=='original' else None
                shapes,moved,groups=normalize_region_vertices(shapes,request.get('tolerance',2.),stats,validate_shape,crop_boundary,to_distance,from_distance)
            else:
                shapes,moved=snap_region_vertices_to_edges(shapes,request.get('tolerance',2.),stats,validate_shape);groups=0
            polygon_shapes=[shape for shape in shapes if shape.get('shape_type','polygon')=='polygon']
            if not polygon_shapes:raise ValueError('Import regions from LabelMe first.')
            updated_native=[]
            for index,shape in enumerate(polygon_shapes):
                marker=shape.get('lenscap_cleanup',{})
                origin=marker.get('origin',index)
                original=next((region for region in native if marker.get('nativeId') and region.get('id')==marker['nativeId']),None)
                if original is None:original=native[origin] if origin<len(native) else {}
                region=copy.deepcopy(original)
                region.update(id=str(original.get('id','labelme-'+str(origin)))+('-crop-'+str(index) if len(polygon_shapes)!=len(native) else ''),
                    label=shape.get('label',''),points=copy.deepcopy(shape['points']),labelmeShape=copy.deepcopy(shape),
                    flags=copy.deepcopy(shape.get('flags',{})),group_id=shape.get('group_id'))
                if marker:marker['nativeId']=region['id'];region['labelmeShape']=copy.deepcopy(shape)
                updated_native.append(region)
            native=updated_native
            geometry=output_geometry(size,calibration['coefficients'],calibration.get('hfov'))
            document.update(imageWidth=geometry['size'][0],imageHeight=geometry['size'][1],shapes=shapes)
            # Validate all projected geometry before changing any project state.
            labelme_regions(document,size,calibration['coefficients'],calibration.get('hfov'))
            fields=('native_scene','annotation_documents','batch_regions','regions','region_coefficients','region_hfov')
            previous={field:copy.deepcopy(getattr(self,field)) for field in fields}
            try:
                if moved:
                    self.commit_native(source,native,calibration)
                    self.annotation_documents[source]=document
                # The existing LabelMe workspace is reused on its next launch.
                # Keep its JSON in sync so it cannot restore pre-snap vertices.
                handoff_entry=next((entry for entry in (self.labelme_handoff or {}).get('entries',[]) if entry['source']==source),None)
                if moved and handoff_entry and path(handoff_entry['json']).is_file():
                    atomic_json(path(handoff_entry['json']),document)
            except Exception:
                for field,value in previous.items():setattr(self,field,value)
                raise
            result=dict(**self.spatial_state(calibration),regions=self.regions,batchRegions=self.batch_regions,
                        normalizedVertices=moved if op=='normalize_vertices' else 0,normalizedGroups=groups,
                        snappedVertices=moved if op=='snap_vertices_to_edges' else 0,skippedVertices=stats.get('skippedVertices',0),
                        message=(f'{moved} region vertices snapped to nearby edges' if moved else 'No vertex-to-edge moves within tolerance') if op=='snap_vertices_to_edges' else
                            (f'{moved} region vertices normalized across {groups} shared positions' if moved else 'No vertex pairs within tolerance'))
            if op=='normalize_vertices':result['viewSpace']=view_space
            if stats.get('skippedVertices'):result['message']+=f"; {stats['skippedVertices']} unsafe vertices left unchanged"
            return result
        if op == 'preview':
            if self.region_coefficients is not None and (self.region_coefficients != list(calibration['coefficients']) or self.region_hfov != calibration.get('hfov')):
                self.clear_regions()
            return dict(**self.preview(calibration['coefficients'], curves,calibration.get('hfov')),
                        regions=self.regions,batchRegions=self.batch_regions)
        if op == 'image':
            target = path(request['path'])
            self.protected_target(target)
            if target.suffix.lower() != '.png':
                raise ValueError('Export the corrected image as PNG for LabelMe.')
            if not cv2.imwrite(str(target), corrected_image(self.image, calibration['coefficients'],calibration.get('hfov'))):
                raise ValueError('Image export failed.')
            return dict(message='Corrected PNG saved')
        if op == 'save_preset':
            self.protected_target(request['path'])
            atomic_json(request['path'], dict(type='lens-calibration-preset',version=1,
                size=list(size),calibration=calibration,projectSettings=self.settings(dict(hfov=calibration.get('hfov'),order=self.project_settings['order'])),outputGeometry=output_geometry(size,calibration['coefficients'],calibration.get('hfov'))))
            return dict(message='Calibration preset saved',projectSettings=self.settings(dict(hfov=calibration.get('hfov'),order=self.project_settings['order'])))
        if op == 'prepare_labelme':
            coefficients = [float(v) for v in calibration['coefficients']]
            if self.region_coefficients is not None and (self.region_coefficients != coefficients or self.region_hfov!=calibration.get('hfov')):
                self.clear_regions()
            inputs = [dict(source=str(self.source),sha256=self.digest), *self.extra_images]
            images = []
            for entry in inputs:
                source, image, digest = self.load(entry['source'])
                if digest != entry['sha256'] or image.shape != self.image.shape:
                    raise ValueError('An original image changed. Reopen or add it again.')
                images.append(image)
            folder = self.annotation_folder(size,coefficients,inputs,calibration.get('hfov'))
            if folder.resolve().parent != Path(self.annotation_temp.name).resolve():
                raise ValueError('Annotation directory is outside temporary assets.')
            folder.mkdir(parents=True,exist_ok=True)
            entries=[]
            snapshots={entry['source']:entry for entry in self.native_scene.get('images',[])}
            geometry=output_geometry(size,coefficients,calibration.get('hfov'))
            notice=False
            for index,(entry,image) in enumerate(zip(inputs,images)):
                stem = 'reference' if index==0 else re.sub(r'[^A-Za-z0-9_-]+','_',Path(entry['source']).stem)[:70] or 'image'
                image_path = folder/f'{index:03d}-{stem}.png'
                json_path = image_path.with_suffix('.json')
                self.protected_target(image_path)
                ok,encoded=cv2.imencode('.png',corrected_image(image,coefficients,calibration.get('hfov')))
                if not ok:
                    raise ValueError('Cannot prepare corrected image for LabelMe.')
                fd,temporary=tempfile.mkstemp(dir=folder,prefix='.corrected-',suffix='.png')
                try:
                    with os.fdopen(fd,'wb') as stream:stream.write(encoded.tobytes())
                    os.replace(temporary,image_path)
                finally:
                    if os.path.exists(temporary):os.unlink(temporary)
                snapshot=snapshots.get(entry['source'])
                document=dict(self.annotation_documents.get(entry['source']) or (snapshot or {}).get('labelmeDocument') or {})
                current_mapping=bool(snapshot and self.equivalent_mapping(snapshot.get('mappingSignature'),calibration))
                if current_mapping:
                    original_shapes=document.get('shapes',[])
                    document.update(self.native_document(snapshot.get('regions',[]),calibration))
                    polygons=iter(document['shapes']);ordered=[]
                    for shape in original_shapes:
                        if shape.get('shape_type','polygon')!='polygon':ordered.append(shape)
                        else:
                            current=next(polygons,None)
                            if current is not None:ordered.append(current)
                    document['shapes']=ordered+list(polygons)
                elif snapshot and snapshot.get('regions') and not document.get('shapes'):
                    document.update(self.native_document(snapshot['regions'],calibration))
                if snapshot and not current_mapping and document.get('shapes'):
                    notice=True
                if not json_path.exists() and document.get('shapes'):
                    document.update(imagePath=image_path.name,imageData=None,imageWidth=geometry['size'][0],imageHeight=geometry['size'][1])
                    document.setdefault('version','7.9.1');document.setdefault('flags',{})
                    atomic_json(json_path,document)
                entries.append(dict(source=entry['source'],json=str(json_path),image=str(image_path)))
            self.annotation_directory = str(folder.resolve())
            self.labelme_handoff = dict(reference=entries[0]['json'],digest=self.digest,
                coefficients=coefficients,hfov=calibration.get('hfov'),inputs=inputs,entries=entries)
            active=next((entry for entry in entries if entry['source']==self.annotation_image),entries[0])
            result=dict(labelmeImage=active['image'],labelmeJson=entries[0]['json'],labelmeFolder=str(folder),labelmeOutputDir=str(folder))
            if notice:result['labelmeNotice']='Existing annotations were drawn under an older lens correction. Review them in LabelMe.'
            return result
        if op == 'finish_labelme':
            handoff=self.labelme_handoff
            inputs=[dict(source=str(self.source),sha256=self.digest),*self.extra_images]
            if (not handoff or path(request['path'])!=path(handoff['reference']) or
                handoff['digest']!=self.digest or handoff.get('hfov')!=calibration.get('hfov') or handoff['coefficients']!=list(calibration['coefficients']) or handoff['inputs']!=inputs):
                raise ValueError('Image or calibration changed during annotation. Open LabelMe again.')
            imported=[]
            documents=dict(self.annotation_documents)
            for entry in handoff['entries']:
                filename=path(entry['json'])
                if not filename.is_file():continue
                document=json.loads(filename.read_text())
                imported.append(dict(source=entry['source'],regions=labelme_regions(document,size,calibration['coefficients'],calibration.get('hfov'))))
                documents[entry['source']]=document
            if not imported:
                return dict(message='No saved LabelMe polygons')
            for entry in imported:
                document=documents[entry['source']]
                native=[dict(id='labelme-'+str(i),label=shape.get('label','region'),color=region_color(shape.get('label','region')),labelmeShape=shape,points=shape['points'],flags=shape.get('flags',{}),group_id=shape.get('group_id')) for i,shape in enumerate(document.get('shapes',[])) if shape.get('shape_type','polygon')=='polygon']
                self.commit_native(entry['source'],native,calibration)
            self.annotation_documents=documents
            merged={item['source']:item for item in self.batch_regions}
            merged.update({item['source']:item for item in imported})
            self.batch_regions=[merged[e['source']] for e in inputs if e['source'] in merged]
            self.regions=next((item['regions'] for item in self.batch_regions if item['source']==str(self.source)),[])
            self.region_coefficients=list(calibration['coefficients'])
            self.region_hfov=calibration.get('hfov')
            count=sum(len(item['regions']) for item in imported)
            return dict(**self.select_annotation(self.annotation_image or str(self.source),calibration),message=f'{count} polygons imported')
        if op == 'labelme':
            filename=path(request['path']);document=json.loads(filename.read_text())
            labelme_regions(document,size,calibration['coefficients'],calibration.get('hfov'))
            source=self.annotation_image or str(self.source)
            image_path=document.get('imagePath')
            if isinstance(image_path,str):
                candidate=str(path(filename.parent/image_path))
                known={e['source'] for e in self.image_entries()}
                if candidate in known: source=candidate
                for entry in (self.labelme_handoff or {}).get('entries',[]):
                    if candidate==entry['image']: source=entry['source']
            native=[dict(id='labelme-'+str(i),label=shape.get('label','region'),color=region_color(shape.get('label','region')),labelmeShape=shape,points=shape['points'],flags=shape.get('flags',{}),group_id=shape.get('group_id')) for i,shape in enumerate(document.get('shapes',[])) if shape.get('shape_type','polygon')=='polygon']
            self.commit_native(source,native,calibration)
            self.annotation_documents[source]=document
            result=self.select_annotation(source,calibration)
            result['message']=f'{len(native)} polygons imported'
            return result
        if op in ('save', 'parameters'):
            if calibration:
                validate_model(size, calibration['coefficients'], calibration.get('hfov'))
            if (self.regions or self.batch_regions) and calibration and (self.region_coefficients != list(calibration['coefficients']) or self.region_hfov!=calibration.get('hfov')):
                raise ValueError('Calibration changed. Import LabelMe polygons again before saving regions.')
            if not calibration:
                self.clear_regions()
            reference=self.reference_plane
            solved=self.plane_calibration
            if op=='save' and 'referencePlane' in request:
                if not calibration: raise ValueError('Calculate lens correction before saving a reference plane.')
                reference=dict(validate_reference_plane(request['referencePlane']),mappingSignature=self.spatial_signature(calibration),outputSize=output_geometry(size,calibration['coefficients'],calibration.get('hfov'))['size'])
                if reference != self.reference_plane: solved=None
            doc = dict(type='lens-calibration-project',version=3, nativeScene=self.native_scene,referencePlane=reference,planeCalibration=solved,activeImage=self.annotation_image, source=str(self.source), sha256=self.digest, size=list(size),
                       curves=curves, calibration=calibration, projectSettings=self.settings(dict(hfov=calibration.get('hfov') if calibration else self.project_settings['hfov'])),regions=self.regions,
                       extraImages=self.extra_images,batchRegions=self.batch_regions,annotationDirectory=self.annotation_directory,
                       labelmeDocuments=self.annotation_documents,
                       mapping='Brown radial; expanded full-source output; translated output K; no crop or rotation',
                       outputGeometry=output_geometry(size,calibration['coefficients'],calibration.get('hfov')) if calibration else None,
                       cameraMatrix=matrix(size,calibration.get('hfov') if calibration else self.project_settings['hfov']).tolist())
            self.protected_target(request['path'])
            atomic_json(request['path'], doc)
            self.reference_plane=reference;self.plane_calibration=solved
            return dict(referencePlane=reference,planeCalibration=solved,message='Project saved',projectPath=str(path(request['path'])),projectSettings=doc['projectSettings']) if op=='save' else dict(message='Calibration saved',projectSettings=doc['projectSettings'])
        if op == 'export_labelme':
            target=path(request['path']);self.protected_target(target)
            source=self.annotation_image or str(self.source)
            if source not in {entry['source'] for entry in self.image_entries()}:raise ValueError('Unknown annotation image.')
            snapshot=next((entry for entry in self.native_scene.get('images',[]) if entry['source']==source),None)
            document=copy.deepcopy(self.annotation_documents.get(source) or (snapshot or {}).get('labelmeDocument') or {})
            if snapshot:
                if not self.equivalent_mapping(snapshot.get('mappingSignature'),calibration):raise ValueError('Annotations use an older lens correction. Review and save them in LabelMe before exporting distorted JSON.')
                original_shapes=document.get('shapes',[])
                canonical=self.native_document(snapshot.get('regions',[]),calibration)
                polygons=iter(canonical['shapes']);ordered=[]
                for shape in original_shapes:
                    if shape.get('shape_type','polygon')!='polygon':ordered.append(shape)
                    else:
                        current=next(polygons,None)
                        if current is not None:ordered.append(current)
                document.update(canonical);document['shapes']=ordered+list(polygons)
            geometry=output_geometry(size,calibration['coefficients'],calibration.get('hfov'))
            if document.get('shapes') and [document.get('imageWidth'),document.get('imageHeight')]!=geometry['size']:raise ValueError('LabelMe dimensions differ from the corrected image.')
            shapes=document.get('shapes',[])
            if not isinstance(shapes,list):raise ValueError('Invalid LabelMe shapes.')
            document.update(version=document.get('version','7.9.1'),flags=document.get('flags',{}),shapes=distorted_labelme_shapes(shapes,size,calibration['coefficients'],calibration.get('hfov')),imagePath=os.path.relpath(source,target.parent),imageData=None,imageWidth=int(size[0]),imageHeight=int(size[1]))
            atomic_json(target,document)
            return dict(message='Distorted LabelMe JSON saved',annotationPath=str(target),shapeCount=len(document['shapes']))
        if op == 'regions':
            if not self.regions and not self.batch_regions:
                raise ValueError('Import LabelMe polygons first.')
            self.protected_target(request['path'])
            if (self.region_coefficients != list(calibration['coefficients']) or self.region_hfov!=calibration.get('hfov')):
                raise ValueError('Calibration changed. Import LabelMe polygons again.')
            def zones(regions):
                result={}
                for region in regions:
                    name=region['label']
                    if not name or name in result:
                        raise ValueError(f'Frigate zone export needs unique nonempty zone names; duplicate or empty name: {name!r}. Use Distorted LabelMe JSON to preserve repeated labels.')
                    result[name]=dict(coordinates=region['coordinates'])
                return result
            if self.extra_images:
                document=dict(images=[dict(source=item['source'],zones=zones(item['regions'])) for item in self.batch_regions])
            else:
                document=dict(zones=zones(self.regions))
            atomic_json(request['path'],document)
            return dict(message='Frigate zones saved')
        raise ValueError('Unknown operation.')


def error_response(exc):
    """Keep structured calibration diagnostics across the JSON worker boundary."""
    result = dict(ok=False, error=str(exc))
    if isinstance(getattr(exc, "code", None), str):
        result["code"] = exc.code
    if isinstance(getattr(exc, "diagnostics", None), list):
        result["diagnostics"] = exc.diagnostics
    if isinstance(getattr(exc, "recommendation", None), dict):
        result["recommendation"] = exc.recommendation
    return result


def main():
    with tempfile.TemporaryDirectory(prefix='lens-calibration-') as cache:
        worker = Worker(cache)
        history = History()
        print(json.dumps(dict(ready=True, recentProjects=history.projects(),lensProfiles=history.profiles())), flush=True)
        for line in sys.stdin:
            try:
                request = json.loads(line)
                result = manage_profile(request,worker,history) if request["op"] in ("save_profile","update_profile","rename_profile","delete_profile") else worker.handle(request)
                if request.get("path") and request.get("op") in ("open", "load", "save", "convert_legacy", "load_preset", "save_preset", "labelme", "image", "regions", "parameters", "export_labelme"):
                    try:
                        history_path=result["projectPath"] if request["op"]=="convert_legacy" else request["path"]
                        history.update(purpose_group("load" if request["op"]=="convert_legacy" else request["op"]), [history_path], project=request["op"] in ("load", "save", "convert_legacy") and str(history_path).lower().endswith((".lenscap", ".lensproject")))
                    except OSError:
                        pass
                if request.get("op") in ("save_preset","load_preset"):
                    history.remember_profile(request["path"])
                    result["profilePath"]=str(path(request["path"]))
                result["lensProfiles"]=history.profiles()
                result["recentProjects"] = history.projects()
                print(json.dumps(dict(ok=True, **result), allow_nan=False), flush=True)
            except Exception as exc:
                print(json.dumps(error_response(exc), allow_nan=False), flush=True)


if __name__ == '__main__':
    main()
