import json
import numpy as np
import cv2
import pytest
from geometry import (distort, undistort, calibrate, corrected_image,
                      labelme_regions, densify, matrix, validate_model, output_geometry,
                      original_to_output, output_to_original)
from backend import Worker

SIZE = (1920, 1080)


def polygon_document(size, coefficients, points, label='polygon'):
    geometry = output_geometry(size, coefficients)
    points = (np.array(points)-geometry['origin']).tolist()
    return dict(imageWidth=geometry['size'][0], imageHeight=geometry['size'][1],
                shapes=[dict(label=label, shape_type='polygon', points=points)])


def traces(coeff=(-.32, .0)):
    lines = []
    for y in [90, 230, 830, 980]:
        lines.append(np.column_stack([np.linspace(180, 1740, 25), np.full(25, y)]))
    for x in [190, 430, 1490, 1730]:
        lines.append(np.column_stack([np.full(25, x), np.linspace(100, 980, 25)]))
    return [distort(p, SIZE, coeff).tolist() for p in lines]


@pytest.mark.parametrize('coeff', [(-.32, 0), (.28, 0), (-.4, .15), (0, 0)])
def test_round_trip(coeff):
    p = np.random.default_rng(4).uniform([0, 0], [1919, 1079], (500, 2))
    np.testing.assert_allclose(distort(undistort(p, SIZE, coeff), SIZE, coeff), p, atol=1e-7)
    np.testing.assert_allclose(undistort(distort(p, SIZE, coeff), SIZE, coeff), p, atol=1e-7)


@pytest.mark.parametrize('coeff,order', [((-.32, 0), 1), ((.25, 0), 1), ((-.4, .15), 2)])
def test_recover_known_distortion(coeff, order):
    result = calibrate(traces(coeff), SIZE, order)
    np.testing.assert_allclose(result['coefficients'], coeff, atol=1e-5)
    assert result['rmsAfter'] < 1e-5
    assert result['rmsBefore'] > 1


def test_noisy_recovery():
    rng = np.random.default_rng(17)
    lines = [(np.array(c)+rng.normal(0, .15, np.array(c).shape)).tolist() for c in traces()]
    result = calibrate(lines, SIZE)
    assert abs(result['coefficients'][0]+.32) < .005
    assert result['rmsAfter'] < .3


def test_weak_constraints():
    with pytest.raises(ValueError):
        calibrate(traces()[:2], SIZE)
    lines = [np.column_stack([np.linspace(100, 1800, 10), np.full(10, 539.5)]).tolist()]*3
    with pytest.raises(ValueError):
        calibrate(lines, SIZE)
    with pytest.raises(ValueError):
        validate_model(SIZE, [-2, 0])


@pytest.mark.parametrize('order,coeff', [(1,(-.32,0)),(2,(-.4,.15))])
def test_short_traces_contribute_without_vetoing_valid_constraints(order, coeff):
    lines=traces(coeff)
    short=distort(np.column_stack([np.full(5,180.),np.linspace(120,240,5)]),SIZE,coeff)
    assert np.linalg.norm(np.ptp(short,axis=0)) < .15*max(SIZE)
    result=calibrate(lines+[short.tolist()],SIZE,order)
    np.testing.assert_allclose(result['coefficients'],coeff,atol=1e-5)
    assert result['usedCurves']==len(lines)+1
    assert result['ignoredCurves']==0


def test_short_trace_actually_influences_the_estimated_correction():
    short=distort(np.column_stack([np.full(5,180.),np.linspace(120,240,5)]),SIZE,[-.32,0])
    short[2,0]+=2
    result=calibrate(traces()+[short.tolist()],SIZE)
    assert abs(result['coefficients'][0]+.32)>1e-7
    assert result['usedCurves']==9


def test_three_point_traces_and_incomplete_traces():
    lines=[np.asarray(curve)[[0,12,24]].tolist() for curve in traces()]
    result=calibrate(lines+[[[1,1],[2,2]],[],[[5,5],[5,5],[5,5]]],SIZE)
    np.testing.assert_allclose(result['coefficients'],[-.32,0],atol=1e-5)
    assert result['usedCurves']==len(lines)
    assert result['ignoredCurves']==3
    with pytest.raises(ValueError,match='three distinct'):
        calibrate([[[1,1],[2,2]]]*8,SIZE)


def test_short_low_information_traces_still_reject_unstable_calibration():
    lines=[np.column_stack([np.linspace(100,105,5),np.full(5,y)]).tolist() for y in [100,500,900]]
    with pytest.raises(ValueError):calibrate(lines,SIZE)


def test_raster_and_opencv_match_mapping():
    size = (320, 180)
    yy, xx = np.mgrid[:180, :320].astype(np.float32)
    grid = np.dstack([xx, yy, xx*0])
    image = corrected_image(grid, [-.32, 0])
    pts = np.array([[40, 30], [200, 120], [280, 150]])
    expected = output_to_original(pts, size, [-.32, 0])
    actual = image[pts[:, 1], pts[:, 0], :2]
    np.testing.assert_allclose(actual, expected, atol=.017)
    k = matrix(size)
    cv = cv2.undistortPoints(expected.reshape(-1,1,2), k, np.array([-.32,0,0,0,0]), R=None,P=k,criteria=
                               (cv2.TERM_CRITERIA_COUNT | cv2.TERM_CRITERIA_EPS,100,1e-12))
    np.testing.assert_allclose(cv.reshape(-1,2)-output_geometry(size,[-.32,0])["origin"], pts, atol=1e-8)


def test_labelme_densification_and_normalization():
    polygon = [[200, 160], [1700, 160], [1700, 900], [200, 900]]
    doc = polygon_document(SIZE, [-.32,0], polygon, 'floor')
    result = labelme_regions(doc, SIZE, [-.32, 0])[0]
    assert len(result['points']) > 2000
    np.testing.assert_allclose(original_to_output(result['points'], SIZE, [-.32, 0]), densify(doc["shapes"][0]["points"]), atol=1e-7)
    np.testing.assert_allclose(np.array(result['normalized'])*SIZE, result['points'])
    with pytest.raises(ValueError, match='dimensions'):
        labelme_regions(dict(doc, imageWidth=1280), SIZE, [-.32, 0])
    geometry=output_geometry(SIZE,[-.32,0]);w,h=geometry['size']
    clipped=labelme_regions(dict(imageWidth=w,imageHeight=h,shapes=[dict(points=[[0,0],[w-1,0],[w-1,h-1],[0,h-1]])]), SIZE, [-.32,0])
    assert len(clipped)==1
    np.testing.assert_allclose(np.array(clipped[0]['points']).min(axis=0),[0,0])
    np.testing.assert_allclose(np.array(clipped[0]['points']).max(axis=0),np.array(SIZE)-1)


def test_session_and_exports(tmp_path):
    original = tmp_path/'camera.png'
    cv2.imwrite(str(original), np.zeros((1080,1920,3), np.uint8))
    cache = tmp_path/'cache'
    cache.mkdir()
    worker = Worker(cache)
    opened = worker.handle(dict(op='open', path=str(original)))
    assert opened['size'] == [1920,1080]
    fit = worker.handle(dict(op='calibrate', curves=traces(), order=1))
    calibration = fit['calibration']
    session = tmp_path/'session.json'
    worker.handle(dict(op='save',path=str(session), curves=traces(),calibration=calibration))
    loaded = worker.handle(dict(op='load',path=str(session)))
    assert loaded['curves'] == traces()
    assert loaded['calibration'] == calibration
    output = tmp_path/'corrected.png'
    worker.handle(dict(op='image', path=str(output), calibration=calibration))
    assert cv2.imread(str(output)).shape == tuple(output_geometry(SIZE,calibration["coefficients"])["size"][::-1])+(3,)
    with pytest.raises(ValueError, match='original'):
        worker.handle(dict(op='image', path=str(original), calibration=calibration))
    labelme = tmp_path/'labelme.json'
    labelme.write_text(json.dumps(polygon_document(SIZE,calibration['coefficients'],[[200,200],[1700,200],[900,900]],'floor')))
    worker.handle(dict(op='labelme',path=str(labelme),calibration=calibration))
    frigate = tmp_path/'frigate.json'
    worker.handle(dict(op='regions',path=str(frigate),calibration=calibration))
    assert 'coordinates' in json.loads(frigate.read_text())['zones']['floor']
    cv2.imwrite(str(original),np.ones((1080,1920,3),np.uint8))
    with pytest.raises(ValueError, match='changed'):
        worker.handle(dict(op='load',path=str(session)))


@pytest.fixture
def small_worker(tmp_path):
    source = tmp_path/'original.png'
    cv2.imwrite(str(source), np.zeros((180, 320, 3), np.uint8))
    cache = tmp_path/'cache'
    cache.mkdir()
    worker = Worker(cache)
    worker.handle(dict(op='open', path=str(source)))
    return worker


def test_regions_bound_to_calibration_and_session_recomputed(small_worker, tmp_path):
    worker = small_worker
    calibration = dict(coefficients=[-.32, 0.])
    document = polygon_document((320,180),calibration['coefficients'],[[60,50],[240,50],[240,130],[60,130]],'room')
    labelme = tmp_path/'labelme.json'
    labelme.write_text(json.dumps(document))
    worker.handle(dict(op='labelme', path=str(labelme), calibration=calibration))
    with pytest.raises(ValueError, match='Calibration changed'):
        worker.handle(dict(op='regions', path=str(tmp_path/'zones.json'), calibration=dict(coefficients=[0., 0.])))
    session = tmp_path/'session.json'
    worker.handle(dict(op='save', path=str(session), calibration=calibration, curves=[]))
    saved = json.loads(session.read_text())
    saved['regions'][0]['coordinates'] = '0,0,1,0,1,1'
    saved['regions'][0]['normalized'] = [[0, 0]]
    session.write_text(json.dumps(saved))
    restored = worker.handle(dict(op='load', path=str(session)))
    assert restored['regions'][0]['coordinates'] != '0,0,1,0,1,1'
    np.testing.assert_allclose(np.array(restored['regions'][0]['normalized'])*(320, 180),
                               restored['regions'][0]['points'])


def test_failed_load_keeps_current_document(small_worker, tmp_path, monkeypatch):
    worker = small_worker
    original_source = worker.source
    other = tmp_path/'other.png'
    cv2.imwrite(str(other), np.ones((90, 160, 3), np.uint8))
    session = tmp_path/'session.json'
    source, image, digest = worker.load(other)
    session.write_text(json.dumps(dict(version=1, source=str(source), sha256=digest,
        size=[160, 90], curves=[], calibration=dict(coefficients=[0., 0.]), regions=[])))
    def fail_preview(*args):
        raise ValueError('Preview write failed')
    monkeypatch.setattr(worker, 'preview', fail_preview)
    with pytest.raises(ValueError, match='Preview write failed'):
        worker.handle(dict(op='load', path=str(session)))
    assert worker.source == original_source
    assert worker.image.shape == (180, 320, 3)
    session.write_text('{}')
    with pytest.raises(ValueError, match='session version'):
        worker.handle(dict(op='load', path=str(session)))


@pytest.mark.parametrize('points', [[[1, 1], [1, 1], [2, 2]], [[0, 0], [1, 1], [2, 2]]])
def test_degenerate_polygons_rejected(points):
    with pytest.raises(ValueError, match='non-collinear'):
        densify(points)


def test_invalid_sampling_step():
    with pytest.raises(ValueError, match='sampling step'):
        densify([[0, 0], [10, 0], [10, 10]], step=0)


def test_automated_labelme_handoff(small_worker, tmp_path, monkeypatch):
    worker = small_worker
    monkeypatch.setenv('XDG_STATE_HOME', str(tmp_path/'state'))
    calibration = dict(coefficients=[-.32, 0.])
    source_bytes = worker.source.read_bytes()
    prepared = worker.handle(dict(op='prepare_labelme', calibration=calibration))
    from pathlib import Path
    image_path = Path(prepared['labelmeImage'])
    json_path = Path(prepared['labelmeJson'])
    assert image_path.parent == Path(prepared['labelmeOutputDir']) == json_path.parent
    assert image_path.parent.is_relative_to(worker.cache)
    assert prepared['labelmeFolder']==prepared['labelmeOutputDir']
    assert cv2.imread(str(image_path)).shape == tuple(output_geometry((320,180),calibration['coefficients'])['size'][::-1])+(3,)
    assert not json_path.exists()
    response = worker.handle(dict(op='finish_labelme', path=str(json_path), calibration=calibration))
    assert response == dict(message='No saved LabelMe polygons')
    document = polygon_document((320,180),calibration['coefficients'],[[60,50],[240,50],[240,130],[60,130]],'room')
    json_path.write_text(json.dumps(document))
    saved_annotation = json_path.read_bytes()
    response = worker.handle(dict(op='finish_labelme', path=str(json_path), calibration=calibration))
    assert len(response['regions']) == 1
    assert len(response['regions'][0]['points']) > 200
    np.testing.assert_allclose(np.array(response['regions'][0]['normalized'])*(320,180), response['regions'][0]['points'])
    again = worker.handle(dict(op='prepare_labelme', calibration=calibration))
    assert again == prepared
    assert json_path.read_bytes() == saved_annotation
    # Metadata and equivalent numeric representations do not change the mapping.
    same = worker.handle(dict(op='prepare_labelme', calibration=dict(coefficients=[-.32, 0], manual=True)))
    assert same == prepared
    json_path.write_text(json.dumps(dict(document, shapes=[])))
    response = worker.handle(dict(op='finish_labelme', path=str(json_path), calibration=calibration))
    assert response['regions'] == []
    assert worker.regions == []
    changed = dict(coefficients=[-.31, 0.])
    with pytest.raises(ValueError, match='changed during annotation'):
        worker.handle(dict(op='finish_labelme', path=str(json_path), calibration=changed))
    other = worker.handle(dict(op='prepare_labelme', calibration=changed))
    assert other['labelmeOutputDir'] != prepared['labelmeOutputDir']
    assert not Path(other['labelmeJson']).exists()
    assert worker.source.read_bytes() == source_bytes


def test_labelme_handoff_requires_calibration(small_worker):
    with pytest.raises(ValueError, match='Calculate a calibration first'):
        small_worker.handle(dict(op='prepare_labelme'))
    with pytest.raises(ValueError, match='changed during annotation'):
        small_worker.handle(dict(op='finish_labelme', path='/tmp/nonexistent.json', calibration=dict(coefficients=[0.,0.])))


def source_perimeter(size, step=.1):
    w,h=size
    x=np.linspace(0,w-1,int(np.ceil((w-1)/step))+1)
    y=np.linspace(0,h-1,int(np.ceil((h-1)/step))+1)
    return np.concatenate([np.column_stack((x,np.zeros_like(x))),
        np.column_stack((np.full_like(y,w-1),y)),
        np.column_stack((x[::-1],np.full_like(x,h-1))),
        np.column_stack((np.zeros_like(y),y[::-1]))])


@pytest.mark.parametrize('coefficients',[[-.32,0.],[.28,0.],[-.8303007867433208,1.3371628077915936]])
def test_full_canvas_covers_dense_source_boundary_and_interior(coefficients):
    geometry=output_geometry(SIZE,coefficients)
    points=np.concatenate((source_perimeter(SIZE),np.random.default_rng(41).uniform([0,0],[1919,1079],(10000,2))))
    corrected=original_to_output(points,SIZE,coefficients)
    assert np.all(corrected>=0)
    assert np.all(corrected<=np.array(geometry['size'])-1)
    np.testing.assert_allclose(output_to_original(corrected,SIZE,coefficients),points,atol=1e-8)
    raw_k=matrix(SIZE);output_k=np.array(geometry['cameraMatrix'])
    np.testing.assert_allclose(output_k[:2,:2],raw_k[:2,:2])
    np.testing.assert_allclose(output_k[:2,2]+geometry['origin'],raw_k[:2,2])


def test_identity_canvas_and_raster():
    geometry=output_geometry((320,180),[0.,0.])
    assert geometry['size']==[320,180] and geometry['origin']==[0,0]
    image=np.random.default_rng(8).integers(0,256,(180,320,3),dtype=np.uint8)
    np.testing.assert_array_equal(corrected_image(image,[0.,0.]),image)


@pytest.mark.parametrize('coefficients',[[-.32,0.],[-.8303007867433208,1.3371628077915936]])
def test_full_stream_polygon_survives_expanded_labelme_mapping(coefficients):
    size=(320,180)
    source=source_perimeter(size,step=.25)
    output=original_to_output(source,size,coefficients)
    geometry=output_geometry(size,coefficients)
    document=dict(imageWidth=geometry['size'][0],imageHeight=geometry['size'][1],
        shapes=[dict(label='whole_stream',points=output.tolist())])
    region=labelme_regions(document,size,coefficients)[0]
    mapped=np.array(region['points'])
    np.testing.assert_allclose(mapped.min(axis=0),[0,0],atol=1e-7)
    np.testing.assert_allclose(mapped.max(axis=0),[319,179],atol=1e-7)
    np.testing.assert_allclose(np.array(region['normalized'])*size,mapped,atol=1e-10)
    assert np.max(np.minimum.reduce([mapped[:,0],319-mapped[:,0],mapped[:,1],179-mapped[:,1]]))<.01


def test_excessive_canvas_rejected():
    with pytest.raises(ValueError,match='safe image dimensions'):
        output_geometry((40000,1000),[0.,0.])


def test_v1_region_session_migrates_without_original_coordinate_shift(small_worker,tmp_path):
    worker=small_worker;size=(320,180);coefficients=[-.32,0.]
    old_corrected=np.array([[60.,50.],[240.,50.],[240.,130.],[60.,130.]])
    expected_original=distort(old_corrected,size,coefficients)
    session=tmp_path/'legacy.json'
    session.write_text(json.dumps(dict(version=1,source=str(worker.source),sha256=worker.digest,
        size=list(size),curves=[],calibration=dict(coefficients=coefficients),
        regions=[dict(label='legacy_room',correctedPoints=old_corrected.tolist(),
                      coordinates='untrusted',points=[],normalized=[])])))
    loaded=worker.handle(dict(op='load',path=str(session)))
    geometry=output_geometry(size,coefficients);region=loaded['regions'][0]
    assert loaded['outputGeometry']==geometry
    corrected=np.array(region['correctedPoints']);mapped=np.array(region['points'])
    np.testing.assert_allclose(output_to_original(corrected,size,coefficients),mapped,atol=1e-10)
    for vertex,original in zip(old_corrected,expected_original):
        matches=np.flatnonzero(np.linalg.norm(corrected-(vertex-geometry['origin']),axis=1)<1e-9)
        assert len(matches)==1
        np.testing.assert_allclose(mapped[matches[0]],original,atol=1e-10)
    saved=tmp_path/'migrated.json'
    worker.handle(dict(op='save',path=str(saved),curves=[],calibration=dict(coefficients=coefficients)))
    assert json.loads(saved.read_text())['version']==3
    loaded_again=worker.handle(dict(op='load',path=str(saved)))
    np.testing.assert_allclose(loaded_again['regions'][0]['points'][0],expected_original[0],atol=1e-10)


def test_preset_reuse_on_different_reference(small_worker,tmp_path,monkeypatch):
    worker=small_worker;calibration=dict(coefficients=[-.32,0.],order=1)
    preset=tmp_path/'camera-preset.json'
    worker.handle(dict(op='save_preset',path=str(preset),calibration=calibration))
    document=json.loads(preset.read_text())
    assert document['type']=='lens-calibration-preset'
    assert not {'source','sha256','curves','regions','extraImages'} & document.keys()
    other=tmp_path/'another-source.png';cv2.imwrite(str(other),np.full((180,320,3),70,np.uint8))
    worker.handle(dict(op='open',path=str(other)))
    import backend
    def forbidden(*args,**kwargs):raise AssertionError('Preset must never recalibrate')
    monkeypatch.setattr(backend,'calibrate',forbidden)
    loaded=worker.handle(dict(op='load_preset',path=str(preset),curves=[]))
    assert loaded['calibration']==calibration
    assert worker.source==other and loaded['outputGeometry']==output_geometry((320,180),calibration['coefficients'])
    assert loaded['regions']==[] and loaded['batchRegions']==[]
    mismatch=tmp_path/'different-size.png';cv2.imwrite(str(mismatch),np.zeros((90,160,3),np.uint8))
    worker.handle(dict(op='open',path=str(mismatch)))
    with pytest.raises(ValueError,match='Preset dimensions'):
        worker.handle(dict(op='load_preset',path=str(preset)))
    document['outputGeometry']['origin'][0]+=1;preset.write_text(json.dumps(document))
    worker.handle(dict(op='open',path=str(other)))
    with pytest.raises(ValueError,match='Preset output geometry'):
        worker.handle(dict(op='load_preset',path=str(preset)))


def test_batch_add_is_transactional(small_worker,tmp_path):
    worker=small_worker
    good=tmp_path/'additional.png';cv2.imwrite(str(good),np.ones((180,320,3),np.uint8))
    bad=tmp_path/'wrong-size.png';cv2.imwrite(str(bad),np.ones((90,160,3),np.uint8))
    with pytest.raises(ValueError,match='reference image dimensions'):
        worker.handle(dict(op='add_images',paths=[str(good),str(bad)]))
    assert worker.extra_images==[]
    result=worker.handle(dict(op='add_images',paths=[good.as_uri(),str(good),str(worker.source)]))
    assert result['extraImages']==[str(good)]


def test_batch_handoff_same_calibration_and_session(small_worker,tmp_path):
    from pathlib import Path
    worker=small_worker;reference=worker.source
    extra=tmp_path/'extra snapshot.png'
    yy,xx=np.mgrid[:180,:320];second=np.dstack((xx%256,yy,xx*0+117)).astype(np.uint8)
    cv2.imwrite(str(extra),second)
    original_bytes={reference:reference.read_bytes(),extra:extra.read_bytes()}
    added=worker.handle(dict(op='add_images',paths=[str(extra)]));assert added['extraImages']==[str(extra)]
    calibration=dict(coefficients=[-.32,0.],order=1)
    prepared=worker.handle(dict(op='prepare_labelme',calibration=calibration))
    folder=Path(prepared['labelmeFolder']);assert folder.is_relative_to(worker.cache)
    images=sorted(folder.glob('*.png'));assert [p.name for p in images]==['000-reference.png','001-extra_snapshot.png']
    for output,original in zip(images,[worker.image,second]):
        np.testing.assert_array_equal(cv2.imread(str(output)),corrected_image(original,calibration['coefficients']))
    docs=[]
    for output,label in zip(images,['reference_zone','extra_zone']):
        doc=polygon_document((320,180),calibration['coefficients'],[[60,50],[240,50],[240,130],[60,130]],label)
        output.with_suffix('.json').write_text(json.dumps(doc));docs.append(doc)
    # Reopening same map and input order keeps the temporary annotation folder.
    again=worker.handle(dict(op='prepare_labelme',calibration=calibration));assert again==prepared
    assert images[1].with_suffix('.json').is_file()
    result=worker.handle(dict(op='finish_labelme',path=prepared['labelmeJson'],calibration=calibration))
    assert [item['source'] for item in result['batchRegions']]==[str(reference),str(extra)]
    assert result['regions'][0]['label']=='reference_zone'
    np.testing.assert_allclose(result['batchRegions'][0]['regions'][0]['points'],result['batchRegions'][1]['regions'][0]['points'])
    zones=tmp_path/'batch-zones.json';worker.handle(dict(op='regions',path=str(zones),calibration=calibration))
    exported=json.loads(zones.read_text());assert len(exported['images'])==2
    assert 'extra_zone' in exported['images'][1]['zones']
    session=tmp_path/'batch-session.json';worker.handle(dict(op='save',path=str(session),curves=[],calibration=calibration))
    worker.handle(dict(op='open',path=str(reference)))
    loaded=worker.handle(dict(op='load',path=str(session)))
    assert loaded['extraImages']==[str(extra)] and len(loaded['batchRegions'])==2
    for source,raw in original_bytes.items():assert source.read_bytes()==raw
    cv2.imwrite(str(extra),np.zeros_like(second))
    with pytest.raises(ValueError,match='Additional image changed'):
        worker.handle(dict(op='load',path=str(session)))
    assert worker.source==reference


def test_adding_images_preserves_prior_regions(small_worker,tmp_path):
    worker=small_worker;calibration=dict(coefficients=[-.32,0.])
    worker.regions=[dict(label='old')];worker.batch_regions=[dict(source=str(worker.source),regions=worker.regions)]
    worker.region_coefficients=calibration['coefficients']
    additional=tmp_path/'new.png';cv2.imwrite(str(additional),np.ones_like(worker.image))
    result=worker.handle(dict(op='add_images',paths=[str(additional)]))
    assert result['regions']==[dict(label='old')]
    assert result['batchRegions']==[dict(source=str(worker.source),regions=worker.regions)]


def mapped_polygon_document(size,coefficients,original_points,label='region'):
    geometry=output_geometry(size,coefficients)
    output=original_to_output(original_points,size,coefficients)
    assert np.all(output>=0) and np.all(output<=np.array(geometry['size'])-1)
    return dict(imageWidth=geometry['size'][0],imageHeight=geometry['size'][1],
                shapes=[dict(label=label,points=output.tolist())])


def test_polygon_boundary_intersections_not_vertex_clamping():
    from shapely.geometry import Polygon,box
    size=(320,180);coefficients=[-.32,0.]
    document=mapped_polygon_document(size,coefficients,[[-5,60],[60,-5],[80,70]])
    mapped=output_to_original(densify(document['shapes'][0]['points']),size,coefficients)
    expected=Polygon(mapped).intersection(box(0,0,319,179))
    region=labelme_regions(document,size,coefficients)[0]
    actual=Polygon(region['points'])
    assert actual.symmetric_difference(expected).area<1e-9
    assert actual.hausdorff_distance(expected)<1e-9
    # Point clamping introduces different intersections and changes polygon area.
    clamped=Polygon(np.clip(mapped,[0,0],[319,179]))
    assert actual.symmetric_difference(clamped).area>.1
    points=np.array(region['points'])
    assert np.count_nonzero(np.isclose(points[:,0],0))>=2
    assert np.count_nonzero(np.isclose(points[:,1],0))>=2
    np.testing.assert_allclose(output_to_original(region['correctedPoints'],size,coefficients),points,atol=1e-8)


def test_polygon_fully_outside_original_is_empty():
    size=(320,180);coefficients=[-.32,0.]
    document=mapped_polygon_document(size,coefficients,[[130,-8],[190,-8],[190,-4],[130,-4]])
    assert labelme_regions(document,size,coefficients)==[]


def test_concave_clipping_splits_with_collision_free_labels():
    from shapely.geometry import Polygon,box
    size=(320,180);coefficients=[-.32,0.]
    document=mapped_polygon_document(size,coefficients,
        [[80,-4],[240,-4],[240,60],[210,60],[210,-2],[110,-2],[110,60],[80,60]],'room')
    other=mapped_polygon_document(size,coefficients,[[140,80],[180,80],[180,120],[140,120]],'room_2')
    document['shapes'].extend(other['shapes'])
    regions=labelme_regions(document,size,coefficients)
    assert [r['label'] for r in regions]==['room','room_3','room_2']
    assert [r['sourceLabel'] for r in regions]==['room','room','room_2']
    assert all(Polygon(r['points']).is_valid for r in regions)
    mapped=output_to_original(densify(document['shapes'][0]['points']),size,coefficients)
    expected=Polygon(mapped).intersection(box(0,0,319,179))
    actual=Polygon(regions[0]['points']).union(Polygon(regions[1]['points']))
    assert expected.geom_type=='MultiPolygon'
    assert expected.symmetric_difference(actual).area<1e-9


def test_actual_camera_oversize_labelme_polygon_crops_to_whole_stream():
    size=SIZE;coefficients=[-.8303007867433208,1.3371628077915936]
    geometry=output_geometry(size,coefficients);w,h=geometry['size']
    document=dict(imageWidth=w,imageHeight=h,shapes=[dict(label='all',points=[[0,0],[w-1,0],[w-1,h-1],[0,h-1]])])
    regions=labelme_regions(document,size,coefficients)
    assert len(regions)==1
    from shapely.geometry import Polygon
    assert Polygon(regions[0]['points']).area==pytest.approx(1919*1079,abs=1e-7)
    np.testing.assert_allclose(np.array(regions[0]['points']).min(axis=0),[0,0])
    np.testing.assert_allclose(np.array(regions[0]['points']).max(axis=0),[1919,1079])
    np.testing.assert_allclose(np.array(regions[0]['normalized'])*size,regions[0]['points'],atol=1e-10)


def test_self_intersecting_labelme_polygon_rejected():
    document=polygon_document((320,180),[-.32,0.],[[80,50],[240,130],[80,130],[240,50]])
    with pytest.raises(ValueError,match='self-intersecting'):
        labelme_regions(document,(320,180),[-.32,0.])


def test_lensproject_reopens_saved_labelme_after_temporary_assets_deleted(small_worker,tmp_path):
    from pathlib import Path
    worker=small_worker;calibration=dict(coefficients=[-.32,0.])
    original=worker.source;original_bytes=original.read_bytes()
    prepared=worker.handle(dict(op='prepare_labelme',calibration=calibration))
    document=polygon_document((320,180),calibration['coefficients'],[[60,50],[240,50],[240,130],[60,130]],'room')
    document.update(version='7.9.1',flags={'reviewed':True},imagePath='000-reference.png',imageData=None,
                    description='retain all annotation metadata')
    document['shapes'][0].update(group_id=7,flags={'occluded':True},description='human annotation')
    Path(prepared['labelmeJson']).write_text(json.dumps(document))
    imported=worker.handle(dict(op='finish_labelme',path=prepared['labelmeJson'],calibration=calibration))
    saved_coordinates=imported['regions'][0]['coordinates']
    project=tmp_path/'room.lensproject'
    saved=worker.handle(dict(op='save',path=str(project),calibration=calibration,curves=[]))
    assert saved['projectPath']==str(project)
    project_document=json.loads(project.read_text())
    assert project_document['type']=='lens-calibration-project'
    assert project_document['labelmeDocuments'][str(original)]==document
    assert project_document['annotationDirectory']==prepared['labelmeFolder']
    # Temporary assets can disappear normally at app shutdown.
    worker.annotation_temp.cleanup()
    assert not Path(prepared['labelmeFolder']).exists()
    cache=tmp_path/'new-app-cache';cache.mkdir();reopened=Worker(cache)
    loaded=reopened.handle(dict(op='load',path=str(project)))
    assert loaded['projectPath']==str(project)
    assert loaded['regions'][0]['coordinates']==saved_coordinates
    regenerated=reopened.handle(dict(op='prepare_labelme',calibration=calibration))
    assert regenerated['labelmeFolder']!=prepared['labelmeFolder']
    assert Path(regenerated['labelmeFolder']).is_relative_to(cache)
    assert cv2.imread(regenerated['labelmeImage']).shape==tuple(output_geometry((320,180),calibration['coefficients'])['size'][::-1])+(3,)
    restored=json.loads(Path(regenerated['labelmeJson']).read_text())
    assert restored==document
    assert original.read_bytes()==original_bytes


def test_lensproject_without_polygons_never_creates_blank_labelme_json(small_worker,tmp_path):
    from pathlib import Path
    worker=small_worker;calibration=dict(coefficients=[-.32,0.])
    project=tmp_path/'empty.lensproject'
    worker.handle(dict(op='save',path=str(project),curves=[],calibration=calibration))
    document=json.loads(project.read_text())
    assert document['labelmeDocuments']=={}
    # Untrusted historical temp-directory references are never read or reused.
    document['annotationDirectory']=str(tmp_path/'outside-assets')
    project.write_text(json.dumps(document))
    worker.handle(dict(op='load',path=str(project)))
    prepared=worker.handle(dict(op='prepare_labelme',calibration=calibration))
    assert not Path(prepared['labelmeJson']).exists()
    assert Path(prepared['labelmeFolder']).is_relative_to(worker.cache)


def test_legacy_project_reconstructs_saved_polygons_for_labelme(small_worker,tmp_path):
    from pathlib import Path
    worker=small_worker;coefficients=[-.32,0.];calibration=dict(coefficients=coefficients)
    old_points=[[60,50],[240,50],[240,130],[60,130]]
    legacy=tmp_path/'legacy.json'
    legacy.write_text(json.dumps(dict(version=1,source=str(worker.source),sha256=worker.digest,
        size=[320,180],curves=[],calibration=calibration,
        regions=[dict(label='legacy',correctedPoints=old_points)])))
    loaded=worker.handle(dict(op='load',path=str(legacy)))
    prepared=worker.handle(dict(op='prepare_labelme',calibration=calibration))
    restored=json.loads(Path(prepared['labelmeJson']).read_text())
    assert restored['shapes'] and restored['shapes'][0]['label']=='legacy'
    regions=labelme_regions(restored,(320,180),coefficients)
    np.testing.assert_allclose(regions[0]['points'][0],loaded['regions'][0]['points'][0],atol=1e-8)


@pytest.mark.parametrize('hfov',[60.,90.,110.])
def test_hfov_intrinsics_precision_and_full_coverage(hfov):
    size=(320,180);coefficients=[-.025,.002]
    expected=320/(2*np.tan(np.deg2rad(hfov)/2))
    assert matrix(size,hfov)[0,0]==pytest.approx(expected)
    assert matrix((640,360),hfov)[0,0]==pytest.approx(2*expected)
    points=np.random.default_rng(9).uniform([0,0],[319,179],(1000,2))
    corrected=original_to_output(points,size,coefficients,hfov)
    geometry=output_geometry(size,coefficients,hfov)
    assert np.all(corrected>=0) and np.all(corrected<=np.array(geometry['size'])-1)
    np.testing.assert_allclose(output_to_original(corrected,size,coefficients,hfov),points,atol=1e-9)
    grid=np.dstack(np.mgrid[:180,:320][::-1]).astype(np.float32)
    raster=corrected_image(grid,coefficients,hfov)
    output_points=np.rint(corrected[100:110]).astype(int)
    expected_raw=output_to_original(output_points,size,coefficients,hfov)
    np.testing.assert_allclose(raster[output_points[:,1],output_points[:,0]],expected_raw,atol=.017)


@pytest.mark.parametrize('hfov',[0,180,float('nan'),float('inf')])
def test_invalid_hfov_rejected(hfov):
    with pytest.raises(ValueError,match='field of view'):
        output_geometry((320,180),[0.,0.],hfov)


def test_hfov_calibration_recovers_known_model():
    hfov=90.;coefficients=[-.08,0.]
    lines=[]
    for y in [90,230,830,980]:
        points=np.column_stack([np.linspace(180,1740,25),np.full(25,y)])
        lines.append(distort(points,SIZE,coefficients,hfov).tolist())
    for x in [190,430,1490,1730]:
        points=np.column_stack([np.full(25,x),np.linspace(100,980,25)])
        lines.append(distort(points,SIZE,coefficients,hfov).tolist())
    result=calibrate(lines,SIZE,1,hfov)
    assert result['hfov']==90.
    np.testing.assert_allclose(result['coefficients'],coefficients,atol=1e-6)
    assert result['rmsAfter']<1e-6 and result['rmsBefore']>1


def test_project_hfov_settings_preset_session_and_invalidation(small_worker,tmp_path):
    worker=small_worker;settings=dict(hfov=90.,order=2,snapping=False)
    configured=worker.handle(dict(op='set_settings',projectSettings=settings))
    assert configured['projectSettings']==settings and configured['calibration'] is None
    calibration=dict(coefficients=[-.025,.002],hfov=90.,order=2)
    # Explicit model HFOV controls preview even if worker settings later differ.
    preview=worker.handle(dict(op='preview',calibration=calibration))
    assert preview['outputGeometry']==output_geometry((320,180),calibration['coefficients'],90.)
    preset=tmp_path/'hfov-preset.json';project=tmp_path/'hfov.lensproject'
    worker.handle(dict(op='save_preset',path=str(preset),calibration=calibration))
    worker.handle(dict(op='save',path=str(project),calibration=calibration,curves=[]))
    assert json.loads(project.read_text())['projectSettings']==settings
    worker.handle(dict(op='set_settings',projectSettings=dict(hfov=None,order=1,snapping=True)))
    loaded=worker.handle(dict(op='load',path=str(project)))
    assert loaded['projectSettings']==settings
    assert loaded['outputGeometry']==preview['outputGeometry']
    worker.handle(dict(op='set_settings',projectSettings=dict(hfov=100.,order=1,snapping=True)))
    loaded_preset=worker.handle(dict(op='load_preset',path=str(preset)))
    assert loaded_preset['projectSettings']==settings
    assert loaded_preset['outputGeometry']==preview['outputGeometry']
    prepared=worker.handle(dict(op='prepare_labelme',calibration=calibration))
    assert worker.labelme_handoff['hfov']==90.
    geometry=output_geometry((320,180),calibration['coefficients'],90.)
    points=(np.array([[80,60],[220,60],[220,120],[80,120]])-geometry['origin']).tolist()
    doc=dict(imageWidth=geometry['size'][0],imageHeight=geometry['size'][1],shapes=[dict(label='hfov',points=points)])
    from pathlib import Path
    Path(prepared['labelmeJson']).write_text(json.dumps(doc))
    result=worker.handle(dict(op='finish_labelme',path=prepared['labelmeJson'],calibration=calibration))
    assert result['regions'] and worker.region_hfov==90.
    changed=worker.handle(dict(op='set_settings',projectSettings=dict(hfov=100.,order=2,snapping=False)))
    assert changed['calibration'] is None and worker.regions==[] and worker.annotation_documents=={}
    assert worker.labelme_handoff is None
    with pytest.raises(ValueError,match='field of view'):
        worker.handle(dict(op='set_settings',projectSettings=dict(hfov=180)))
    assert worker.project_settings['hfov']==100.


def test_legacy_model_ignores_unrelated_current_hfov_settings(small_worker):
    worker=small_worker
    worker.handle(dict(op='set_settings',projectSettings=dict(hfov=110.)))
    result=worker.handle(dict(op='preview',calibration=dict(coefficients=[-.32,0.])))
    assert result['outputGeometry']==output_geometry((320,180),[-.32,0.])
    assert matrix((320,180))[0,0]==320


def legacy_conversion_fixture(worker,tmp_path):
    legacy=tmp_path/'legacy-camera.lensproject'
    worker.handle(dict(op='save',path=str(legacy),curves=[],calibration=dict(coefficients=[-.32,0.])))
    # Conversion must retain the bytes, not rewrite or normalize JSON formatting.
    legacy.write_bytes(b' \n'+legacy.read_bytes()+b'\n  ')
    return legacy


def test_convert_legacy_preserves_bytes_and_returns_loaded_lenscap(small_worker,tmp_path):
    worker=small_worker;legacy=legacy_conversion_fixture(worker,tmp_path);raw=legacy.read_bytes()
    result=worker.handle(dict(op='convert_legacy',path=str(legacy)))
    target=legacy.with_suffix('.lenscap')
    assert not legacy.exists() and target.read_bytes()==raw
    assert result['projectPath']==str(target)
    assert result['source']==str(worker.source) and result['calibration']['coefficients']==[-.32,0.]
    assert 'converted' in result['message']


def test_convert_legacy_existing_target_never_overwritten(small_worker,tmp_path):
    worker=small_worker;legacy=legacy_conversion_fixture(worker,tmp_path);raw=legacy.read_bytes()
    target=legacy.with_suffix('.lenscap');target.write_bytes(b'existing project')
    state=worker.__dict__.copy()
    with pytest.raises(ValueError,match='already exists'):
        worker.handle(dict(op='convert_legacy',path=str(legacy)))
    assert legacy.read_bytes()==raw and target.read_bytes()==b'existing project'
    assert worker.source==state['source'] and worker.image is state['image']
    assert worker.serial==state['serial'] and worker.annotation_documents is state['annotation_documents']


def test_convert_legacy_invalid_content_or_extension_keeps_state(small_worker,tmp_path):
    worker=small_worker;state=worker.__dict__.copy()
    legacy=tmp_path/'invalid.lensproject';legacy.write_text('{}')
    with pytest.raises(ValueError,match='session version'):
        worker.handle(dict(op='convert_legacy',path=str(legacy)))
    assert legacy.exists() and not legacy.with_suffix('.lenscap').exists()
    assert worker.image is state['image'] and worker.serial==state['serial']
    with pytest.raises(ValueError,match='legacy .lensproject'):
        worker.handle(dict(op='convert_legacy',path=str(tmp_path/'other.json')))


def test_convert_legacy_rename_failure_keeps_project_and_state(small_worker,tmp_path,monkeypatch):
    import backend
    worker=small_worker;legacy=legacy_conversion_fixture(worker,tmp_path);raw=legacy.read_bytes()
    state=worker.__dict__.copy()
    def fail(*args):raise PermissionError('rename denied')
    monkeypatch.setattr(backend,'rename_no_replace',fail)
    with pytest.raises(PermissionError,match='rename denied'):
        worker.handle(dict(op='convert_legacy',path=str(legacy)))
    assert legacy.read_bytes()==raw and not legacy.with_suffix('.lenscap').exists()
    assert worker.image is state['image'] and worker.serial==state['serial']


def test_convert_legacy_postrename_failure_restores_filename_and_preview_state(small_worker,tmp_path,monkeypatch):
    worker=small_worker;legacy=legacy_conversion_fixture(worker,tmp_path);raw=legacy.read_bytes()
    worker.handle(dict(op='preview',calibration=dict(coefficients=[-.1,0.])))
    state=worker.__dict__.copy()
    cached={p.name:p.read_bytes() for p in worker.cache.iterdir() if p.is_file()}
    def fail(*args):raise OSError('preview storage failed')
    monkeypatch.setattr(worker,'preview',fail)
    with pytest.raises(OSError,match='preview storage failed'):
        worker.handle(dict(op='convert_legacy',path=str(legacy)))
    assert legacy.read_bytes()==raw and not legacy.with_suffix('.lenscap').exists()
    assert worker.image is state['image'] and worker.serial==state['serial']
    assert worker.annotation_documents is state['annotation_documents']
    assert {p.name:p.read_bytes() for p in worker.cache.iterdir() if p.is_file()}==cached


def test_conversion_history_records_new_lenscap_not_removed_legacy(small_worker,tmp_path):
    import os,subprocess,sys
    from pathlib import Path
    legacy=legacy_conversion_fixture(small_worker,tmp_path)
    target=legacy.with_suffix('.lenscap')
    environment=dict(os.environ,XDG_STATE_HOME=str(tmp_path/'history-state'))
    completed=subprocess.run([sys.executable,str(Path(__file__).with_name('backend.py'))],
        input=json.dumps(dict(op='convert_legacy',path=str(legacy)))+'\n',text=True,capture_output=True,env=environment,check=True)
    responses=[json.loads(line) for line in completed.stdout.splitlines()]
    assert responses[-1]['ok'] and responses[-1]['projectPath']==str(target)
    assert responses[-1]['recentProjects']==[str(target)]
    history=json.loads((tmp_path/'history-state/lens-calibration/recent.json').read_text())
    assert history['projects']==[str(target)] and history['folders']['project']==str(tmp_path)


def test_labelme_polygon_outside_corrected_image_is_cropped_before_mapping():
    from shapely.geometry import Polygon, box
    size=(320,180);coefficients=[-.32,0.]
    w,h=output_geometry(size,coefficients)['size']
    points=[[-100,40],[w/2,20],[w/2,h/2],[-100,h/2]]
    document=dict(imageWidth=w,imageHeight=h,shapes=[dict(label='edge',points=points)])
    corrected=Polygon(points).intersection(box(0,0,w-1,h-1))
    expected=Polygon(output_to_original(densify(corrected.exterior.coords[:-1]),size,coefficients)).intersection(box(0,0,319,179))
    regions=labelme_regions(document,size,coefficients)
    assert len(regions)==1
    assert Polygon(regions[0]['points']).symmetric_difference(expected).area<1e-9
    assert np.all(np.array(regions[0]['points'])>=0)
    assert np.all(np.array(regions[0]['points'])<=np.array(size)-1)


def test_labelme_corrected_boundary_clipping_splits_and_skips_empty_regions():
    from shapely.geometry import Polygon, box
    size=(320,180);coefficients=[0.,0.]
    points=[[20,-20],[260,-20],[260,60],[220,60],[220,-10],[60,-10],[60,60],[20,60]]
    document=dict(imageWidth=320,imageHeight=180,shapes=[dict(label='room',points=points),dict(label='outside',points=[[-100,-100],[-50,-100],[-50,-50]])])
    regions=labelme_regions(document,size,coefficients)
    assert [region['label'] for region in regions]==['room','room_2']
    actual=Polygon(regions[0]['points']).union(Polygon(regions[1]['points']))
    assert actual.symmetric_difference(Polygon(points).intersection(box(0,0,319,179))).area<1e-9


def test_clipped_sensor_sides_follow_curved_corrected_image_boundary():
    size=(320,180);coefficients=[-.32,0.]
    width,height=output_geometry(size,coefficients)['size']
    # A surrounding polygon clips against every sensor edge, introducing new
    # straight sensor segments that must become curves in the corrected view.
    document=dict(imageWidth=width,imageHeight=height,shapes=[dict(label='whole',
        points=[[-10,-10],[width+10,-10],[width+10,height+10],[-10,height+10]])])
    region=labelme_regions(document,size,coefficients)[0]
    original=np.array(region['points']);corrected=np.array(region['correctedPoints'])
    np.testing.assert_allclose(output_to_original(corrected,size,coefficients),original,atol=1e-7)
    for x in (0.,319.):
        side=np.isclose(original[:,0],x)
        assert side.sum()>50
        side_points=corrected[side]
        # At the side midpoint the boundary bows away from its corner chord.
        assert np.ptp(side_points[:,0])>5
        assert np.max(np.linalg.norm(np.diff(side_points,axis=0),axis=1))<5
