"""Normalization changes authored vertices without altering region identity or metadata."""
import copy
import json
from pathlib import Path

import cv2
import numpy as np
import pytest
from backend import Worker, normalize_region_vertices


def shapes():
    return [dict(label='same',shape_type='polygon',points=[[20,20],[80,20],[80,80],[20,80]],flags={'a':True},group_id=3,description='keep'),
            dict(label='same',shape_type='polygon',points=[[81,21],[140,20],[140,80],[81,81]],flags={},group_id=4),
            dict(label='point',shape_type='point',points=[[80.5,20.5]],flags={})]


def worker_with_shapes(tmp_path):
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((180,320,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache);cal=dict(coefficients=[0.,0.],hfov=None)
    worker.handle(dict(op='open',path=str(image)))
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    doc=dict(imageWidth=320,imageHeight=180,imagePath='000-reference.png',imageData=None,flags={'review':True},shapes=shapes())
    Path(prepared['labelmeJson']).write_text(json.dumps(doc))
    worker.handle(dict(op='finish_labelme',path=prepared['labelmeJson'],calibration=cal))
    return worker,cal


def test_snap_preserves_labels_metadata_and_nonpolygons():
    original=shapes();result,moved,groups=normalize_region_vertices(original)
    assert moved==4 and groups==2
    assert result[0]['points'][1]==result[1]['points'][0]==[80.5,20.5]
    assert result[0]['points'][2]==result[1]['points'][3]==[80.5,80.5]
    assert result[0]['description']=='keep' and result[0]['flags']=={'a':True}
    assert result[2]==original[2] and original==shapes()
    assert normalize_region_vertices(result)[1:]==(0,0)


def test_tolerance_does_not_chain_distant_vertices():
    source=[dict(shape_type='polygon',points=[[x,0],[x+10,20],[x-10,20]]) for x in (0.,1.5,3.)]
    result,_,_=normalize_region_vertices(source,2)
    assert result[0]['points'][0]==result[1]['points'][0]
    assert result[2]['points'][0]!=result[0]['points'][0]


@pytest.mark.parametrize('tolerance',[0,-1,float('nan'),True,'bad'])
def test_invalid_tolerance(tolerance):
    with pytest.raises(ValueError,match='tolerance'):normalize_region_vertices(shapes(),tolerance)


def test_worker_updates_labelme_and_distorted_export(tmp_path):
    worker,cal=worker_with_shapes(tmp_path)
    result=worker.handle(dict(op='normalize_vertices',calibration=cal,tolerance=2))
    assert result['normalizedVertices']==4
    source=str(worker.source);doc=worker.annotation_documents[source]
    assert doc['flags']=={'review':True} and len(doc['shapes'])==3
    assert [s['label'] for s in doc['shapes']]==['same','same','point']
    assert worker.native_scene['regions'][0]['points'][1]==[80.5,20.5]
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    saved=json.loads(Path(prepared['labelmeJson']).read_text())
    assert saved['shapes'][0]['points'][1]==[80.5,20.5]
    target=tmp_path/'distorted.json';worker.handle(dict(op='export_labelme',path=str(target),calibration=cal))
    exported=json.loads(target.read_text())
    assert len(exported['shapes'])==3 and exported['shapes'][0]['description']=='keep'
    assert any(np.allclose(point,[80.5,20.5]) for point in exported['shapes'][0]['points'])


def test_invalid_snap_is_atomic(tmp_path):
    worker,cal=worker_with_shapes(tmp_path)
    before=copy.deepcopy((worker.native_scene,worker.annotation_documents,worker.batch_regions,worker.regions))
    result=worker.handle(dict(op='normalize_vertices',calibration=cal,tolerance=500))
    assert result['normalizedVertices']==0 and result['skippedVertices']>0
    assert before==(worker.native_scene,worker.annotation_documents,worker.batch_regions,worker.regions)


def test_active_extra_only_and_stale_mapping(tmp_path):
    worker,cal=worker_with_shapes(tmp_path)
    source=str(worker.source)
    reference_native=copy.deepcopy(worker.native_scene['regions'])
    extra=tmp_path/'extra.png';cv2.imwrite(str(extra),np.ones((180,320,3),np.uint8))
    worker.handle(dict(op='add_images',paths=[str(extra)]))
    worker.commit_native(source,copy.deepcopy(reference_native),cal)
    worker.commit_native(str(extra),copy.deepcopy(reference_native),cal)
    reference=copy.deepcopy(worker.annotation_documents[source]);worker.annotation_image=str(extra)
    worker.handle(dict(op='normalize_vertices',calibration=cal))
    assert worker.annotation_documents[source]==reference
    assert worker.annotation_documents[str(extra)]['shapes'][0]['points'][1]==[80.5,20.5]
    with pytest.raises(ValueError,match='older lens correction'):
        worker.handle(dict(op='normalize_vertices',calibration=dict(coefficients=[-.05,0.],hfov=None)))


def edge_shapes():
    return [dict(label='whole',shape_type='polygon',points=[[20,20],[180,20],[180,150],[20,150]],flags={'a':True}),
            dict(label='section',shape_type='polygon',points=[[60,21],[100,19],[100,60],[60,60]],description='keep')]


def test_edge_snap_keeps_long_boundary_fixed_and_is_idempotent():
    from backend import snap_region_vertices_to_edges
    source=edge_shapes();result,moved=snap_region_vertices_to_edges(source,2)
    assert moved==2
    assert result[0]==source[0]
    assert result[1]['points'][:2]==[[60.,20.],[100.,20.]]
    assert result[1]['description']=='keep'
    assert source==edge_shapes()
    assert snap_region_vertices_to_edges(result,2)==(result,0)


def test_edge_snap_shared_vertices_move_together_but_distant_ones_stay():
    from backend import snap_region_vertices_to_edges
    source=edge_shapes()+[dict(label='other',shape_type='polygon',points=[[60,21],[45,65],[30,60]])]
    result,moved=snap_region_vertices_to_edges(source,2)
    assert moved==3
    assert result[1]['points'][0]==result[2]['points'][0]==[60.,20.]
    assert result[1]['points'][2:]==source[1]['points'][2:]
    assert snap_region_vertices_to_edges(result,2)==(result,0)


def test_edge_snap_does_not_use_own_edges_or_segment_extensions():
    from backend import snap_region_vertices_to_edges
    source=[dict(shape_type='polygon',points=[[0,0],[10,0],[5,1]])]
    assert snap_region_vertices_to_edges(source,2)==(source,0)
    source+=[dict(shape_type='polygon',points=[[11,1],[30,20],[30,30]])]
    result,_=snap_region_vertices_to_edges(source,1.1)
    assert result[1]['points'][0]==[11.,1.]


@pytest.mark.parametrize('tolerance',[0,-1,float('nan'),True,'bad'])
def test_invalid_edge_tolerance(tolerance):
    from backend import snap_region_vertices_to_edges
    with pytest.raises(ValueError,match='tolerance'):snap_region_vertices_to_edges(edge_shapes(),tolerance)


def test_edge_snap_worker_updates_labelme_project_and_export(tmp_path):
    worker,cal=worker_with_shapes(tmp_path)
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    document=json.loads(Path(prepared['labelmeJson']).read_text());document['shapes']=edge_shapes()
    Path(prepared['labelmeJson']).write_text(json.dumps(document))
    worker.handle(dict(op='finish_labelme',path=prepared['labelmeJson'],calibration=cal))
    result=worker.handle(dict(op='snap_vertices_to_edges',tolerance=2,calibration=cal))
    assert result['snappedVertices']==2
    assert worker.native_scene['regions'][1]['points'][0]==[60.,20.]
    saved=json.loads(Path(prepared['labelmeJson']).read_text())
    assert saved['shapes'][1]['points'][0]==[60.,20.]
    target=tmp_path/'distorted.json';worker.handle(dict(op='export_labelme',path=str(target),calibration=cal))
    exported=json.loads(target.read_text());assert exported['shapes'][1]['points'][0]==[60.,20.]
    assert worker.handle(dict(op='snap_vertices_to_edges',tolerance=2,calibration=cal))['snappedVertices']==0


def test_invalid_edge_snap_is_atomic(tmp_path):
    worker,cal=worker_with_shapes(tmp_path)
    # A narrow triangle would flatten onto the enclosing rectangle's edge.
    native=[dict(id='whole',label='whole',points=[[20,20],[180,20],[180,150],[20,150]]),
            dict(id='section',label='section',points=[[60,21],[100,21],[80,22]])]
    worker.commit_native(str(worker.source),native,cal)
    before=copy.deepcopy((worker.native_scene,worker.annotation_documents,worker.batch_regions,worker.regions))
    result=worker.handle(dict(op='snap_vertices_to_edges',calibration=cal,tolerance=2))
    assert result['snappedVertices']==0 and result['skippedVertices']>0
    assert 'left unchanged' in result['message']
    assert before==(worker.native_scene,worker.annotation_documents,worker.batch_regions,worker.regions)


def test_normalization_preserves_small_region_and_merges_cross_region_groups():
    source=shapes()[:2]+[dict(label='tiny',shape_type='polygon',points=[[200,20],[201,20],[200,21]])]
    stats={};result,moved,groups=normalize_region_vertices(source,2,stats)
    assert moved==4 and groups==2 and stats['skippedVertices']==0
    assert result[2]==source[2]
    assert result[0]['points'][1]==result[1]['points'][0]


def test_edge_snap_skips_unsafe_vertices_and_keeps_safe_ones():
    from backend import snap_region_vertices_to_edges
    source=edge_shapes()+[dict(label='thin',shape_type='polygon',points=[[120,21],[160,21],[140,22]])]
    stats={};result,moved=snap_region_vertices_to_edges(source,2,stats)
    assert moved==2 and stats['skippedVertices']==3
    assert result[1]['points'][:2]==[[60.,20.],[100.,20.]]
    assert result[2]==source[2]


def test_edge_snap_includes_near_corners_not_infinite_extension():
    from backend import snap_region_vertices_to_edges
    source=edge_shapes()[:1]+[dict(label='corner section',shape_type='polygon',points=[[19,19],[60,40],[40,60]])]
    result,moved=snap_region_vertices_to_edges(source,2)
    assert moved==1 and result[1]['points'][0]==[20.,20.]
    assert snap_region_vertices_to_edges(result,2)==(result,0)


def test_already_attached_vertices_follow_moving_boundary_endpoint():
    from backend import snap_region_vertices_to_edges
    source=[dict(label='target',shape_type='polygon',points=[[0,0],[100,0],[100,-50],[0,-50]]),
            dict(label='moving',shape_type='polygon',points=[[20,1],[80,20],[20,20]]),
            dict(label='attached',shape_type='polygon',points=[[50,10.5],[80,40],[20,40]])]
    result,moved=snap_region_vertices_to_edges(source,2)
    assert moved==3
    np.testing.assert_allclose(result[1]['points'][0],[20.,0.],atol=1e-8)
    np.testing.assert_allclose(result[2]['points'][0],np.mean(result[1]['points'][:2],axis=0))
    assert snap_region_vertices_to_edges(result,2)==(result,0)


def test_large_shape_change_skips_without_topology_failure():
    from backend import snap_region_vertices_to_edges
    source=[dict(label='whole',shape_type='polygon',points=[[0,0],[100,0],[100,50],[0,50]]),
            dict(label='thin',shape_type='polygon',points=[[20,1],[80,1],[80,2],[20,2]])]
    stats={};result,moved=snap_region_vertices_to_edges(source,2,stats)
    assert moved==0 and stats['skippedVertices']==4 and result==source


def test_mapping_validator_skips_only_affected_candidate():
    source=shapes()[:2];stats={}
    def validator(shape):
        if shape['points'][1]==[80.5,20.5]:raise ValueError('Invalid mapped geometry')
    result,moved,groups=normalize_region_vertices(source,2,stats,validator)
    assert moved==2 and groups==1 and stats['skippedVertices']==2
    assert result[0]['points'][1]==source[0]['points'][1]
    assert result[0]['points'][2]==result[1]['points'][3]


def test_normalization_never_merges_vertices_from_same_region():
    source=[dict(shape_type='polygon',points=[[0,0],[1,0],[20,10],[0,20]])]
    result,moved,groups=normalize_region_vertices(source,2)
    assert result==source and moved==0 and groups==0


def test_cross_region_cluster_contains_only_one_vertex_per_region():
    source=[dict(shape_type='polygon',points=[[0,0],[1,0],[20,10],[0,20]]),
            dict(shape_type='polygon',points=[[.5,-.5],[20,-20],[-20,-20]])]
    result,moved,groups=normalize_region_vertices(source,2)
    assert moved==2 and groups==1
    assert result[0]['points'][0]==result[1]['points'][0]
    assert result[0]['points'][1]==source[0]['points'][1]


def cropped_shapes():
    return [dict(label='same',shape_type='polygon',points=[[-20,20],[40,20],[40,80],[-20,80]],description='keep',flags={'crop':True}),
            dict(label='same',shape_type='polygon',points=[[-200,21],[80,21],[80,100],[-200,100]],group_id=7)]


def test_generated_crop_intersections_are_cleanup_vertices():
    from backend import clipped_cleanup_shapes,cleanup_vertex_indices
    source=cropped_shapes()
    assert normalize_region_vertices(source,2)[1]==0
    effective=clipped_cleanup_shapes(source,(320,180),[0.,0.])
    result,moved,groups=normalize_region_vertices(effective,2)
    assert moved==2 and groups==1
    assert [0.,20.5] in result[0]['points'] and [0.,20.5] in result[1]['points']
    assert result[0]['description']=='keep' and result[1]['group_id']==7
    assert normalize_region_vertices(result,2)[1]==0
    assert all(len(cleanup_vertex_indices(shape))==4 for shape in result)


def test_curved_crop_samples_are_not_normalization_candidates():
    from backend import clipped_cleanup_shapes,cleanup_vertex_indices
    from geometry import output_geometry,original_to_output
    size=(320,180);coefficients=[-.32,0.];width,height=output_geometry(size,coefficients)['size']
    source=[dict(shape_type='polygon',points=[[-100,10],[width+100,10],[width+100,height-10],[-100,height-10]])]
    effective=clipped_cleanup_shapes(source,size,coefficients)
    assert len(effective[0]['points'])>20
    assert len(cleanup_vertex_indices(effective[0]))<=8
    result,moved,groups=normalize_region_vertices(effective,2)
    assert result==effective and moved==0 and groups==0
    # If LabelMe later edits/reorders nodes, the old sampling mask is discarded.
    edited=copy.deepcopy(effective[0]);edited['points'][0][0]+=.5
    assert len(cleanup_vertex_indices(edited))==len(edited['points'])


def test_crop_cleanup_worker_save_reload_and_export(tmp_path):
    worker,cal=worker_with_shapes(tmp_path)
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    doc=json.loads(Path(prepared['labelmeJson']).read_text());doc['shapes']=cropped_shapes()
    Path(prepared['labelmeJson']).write_text(json.dumps(doc))
    worker.handle(dict(op='finish_labelme',path=prepared['labelmeJson'],calibration=cal))
    result=worker.handle(dict(op='normalize_vertices',tolerance=2,calibration=cal))
    assert result['normalizedVertices']==2
    assert len(worker.native_scene['regions'])==2
    for shape in worker.annotation_documents[str(worker.source)]['shapes']:
        assert [0.,20.5] in shape['points']
    saved=tmp_path/'crop.lenscap';worker.handle(dict(op='save',path=str(saved),calibration=cal,curves=[]))
    worker.handle(dict(op='load',path=str(saved)))
    assert worker.handle(dict(op='normalize_vertices',tolerance=2,calibration=cal))['normalizedVertices']==0
    exported=tmp_path/'crop-distorted.json';worker.handle(dict(op='export_labelme',path=str(exported),calibration=cal))
    shapes_out=json.loads(exported.read_text())['shapes']
    assert len(shapes_out)==2
    assert all(any(np.allclose(point,[0.,20.5]) for point in shape['points']) for shape in shapes_out)


def test_crop_normalization_noop_preserves_authored_data(tmp_path):
    worker,cal=worker_with_shapes(tmp_path)
    worker.commit_native(str(worker.source),[dict(id='cropped',label='cropped',points=cropped_shapes()[0]['points'])],cal)
    before=copy.deepcopy((worker.native_scene,worker.annotation_documents))
    result=worker.handle(dict(op='normalize_vertices',tolerance=2,calibration=cal))
    assert result['normalizedVertices']==0
    assert (worker.native_scene,worker.annotation_documents)==before


def test_normalization_response_is_json_serializable_at_four_pixels(tmp_path):
    worker,cal=worker_with_shapes(tmp_path)
    result=worker.handle(dict(op='normalize_vertices',tolerance=4,calibration=cal))
    assert result['normalizedVertices']>0
    decoded=json.loads(json.dumps(result))
    assert type(decoded['normalizedVertices']) is int
    # Unsafe candidates also return native JSON integers.
    source=shapes()[:2];stats={}
    def reject(shape):raise ValueError('skip this candidate')
    normalize_region_vertices(source,4,stats,reject)
    assert stats['skippedVertices']>0
    json.dumps(stats)


def test_original_view_tolerance_merges_real_top_crop_gap(tmp_path):
    from geometry import original_to_output
    image=tmp_path/'wide.png';cv2.imwrite(str(image),np.zeros((1080,1920,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache)
    worker.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[-.1492020004011568,.01781275173127814],hfov=98.8)
    # Actual RED ZONE / Loft Foot Bounds crop corners: 3.8267 source pixels
    # apart, but 4.74 corrected pixels apart. Original-view 4px must include them.
    sensor_shapes=[[[573.6014044789566,0],[550,100],[450,100]],
                   [[577.4281223897068,0],[680,100],[610,100]]]
    native=[dict(id=str(i),label=str(i),points=original_to_output(points,(1920,1080),cal['coefficients'],cal['hfov']).tolist())
            for i,points in enumerate(sensor_shapes)]
    worker.commit_native(str(worker.source),native,cal)
    unchanged=worker.handle(dict(op='normalize_vertices',tolerance=4,calibration=cal))
    assert unchanged['normalizedVertices']==0 and unchanged['viewSpace']=='corrected'
    assert unchanged['message']=='No vertex pairs within tolerance'
    result=worker.handle(dict(op='normalize_vertices',tolerance=4,viewSpace='original',calibration=cal))
    assert result['normalizedVertices']==2 and result['viewSpace']=='original'
    top=[]
    for region in worker.regions:
        points=np.asarray(region['points']);top.append(points[np.argmin(points[:,1])])
    np.testing.assert_allclose(top[0],top[1],atol=.02)
    assert worker.handle(dict(op='normalize_vertices',tolerance=4,viewSpace='original',calibration=cal))['normalizedVertices']==0
    json.dumps(result)


def test_invalid_normalization_view_space_preserves_project(tmp_path):
    worker,cal=worker_with_shapes(tmp_path)
    before=copy.deepcopy((worker.native_scene,worker.annotation_documents))
    with pytest.raises(ValueError,match='view space'):
        worker.handle(dict(op='normalize_vertices',viewSpace='screen',calibration=cal))
    assert (worker.native_scene,worker.annotation_documents)==before
