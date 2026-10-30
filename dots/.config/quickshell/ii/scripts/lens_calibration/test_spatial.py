import json
import cv2
import numpy as np
import pytest
from spatial import calibrate_plane,project_scene,obj_text,validate_scene
from geometry import matrix


def reference():
    k=matrix((1920,1080)); c=np.array([2.,-3.,4.]); f=np.array([0.,1.,-1.]);f/=np.linalg.norm(f)
    r=np.array([[1.,0.,0.],np.cross(f,[1.,0.,0.]),f]); rv=cv2.Rodrigues(r)[0];t=-r@c
    world=np.array([[0.,0.,0.],[4.,0.,0.],[4.,3.,0.],[0.,3.,0.]])
    corners=cv2.projectPoints(world,rv,t,k,None)[0].reshape(-1,2)
    return calibrate_plane(dict(corners=corners.tolist(),width=4,depth=3),k,(1920,1080),'mapping'),c


def test_measured_pose_and_projection():
    plane,c=reference()
    assert plane['intrinsicsAssumed']
    assert np.allclose(plane['cameraPosition'],c,atol=1e-5)
    scene=dict(objects=[dict(id='bed',kind='cuboid',position=[1,1,0],size=[2,1,.5],yaw=0,color='#abcdef')])
    result=project_scene(scene,plane,'mapping')[0]
    assert len(result['vertices'])==8 and len(result['faces'])==6 and len(result['edges'])==12
    assert min(result['depths'])>0
    with pytest.raises(ValueError,match='current lens'): project_scene(scene,plane,'different')


@pytest.mark.parametrize('corners', [[[1,1],[10,10],[1,10],[10,1]],[[1,1],[2,2],[3,3],[4,4]],[[1,1]]*4])
def test_bad_reference(corners):
    with pytest.raises(ValueError): calibrate_plane(dict(corners=corners,width=2,depth=3),matrix((100,100)),(100,100),'x')


def test_obj_and_vertical_plane():
    scene=dict(objects=[dict(id='wall',kind='plane',orientation='xz',position=[0,2,0],size=[3,2],yaw=0,color='#ff0000')])
    obj,mtl=obj_text(scene,'scene.mtl')
    assert 'v 3 2 2' in obj and 'Kd 1 0 0' in mtl and 'Z up' in obj
    with pytest.raises(ValueError): validate_scene(dict(objects=scene['objects']*2))


def test_worker_native_regions_and_project_v3(tmp_path):
    from backend import Worker
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((1080,1920,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir(); w=Worker(cache);w.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[0,0],order=1,hfov=None)
    plane,_=reference()
    w.handle(dict(op='set_spatial_calibration',calibration=cal,plane=plane))
    scene=dict(objects=[dict(id='box',kind='cuboid',position=[1,1,0],size=[1,1,1],yaw=0)])
    w.handle(dict(op='project_spatial',calibration=cal,nativeScene=scene))
    result=w.handle(dict(op='native_regions',calibration=cal,regions=[dict(id='r',label='floor',color='#ffffff',points=[[100,100],[200,100],[200,200]])]))
    assert len(result['nativeScene']['objects'])==1 and len(result['regions'])==1
    project=tmp_path/'test.lenscap';w.handle(dict(op='save',path=str(project),calibration=cal,curves=[]))
    assert json.loads(project.read_text())['version']==3
    cache2=tmp_path/'cache2';cache2.mkdir(); other=Worker(cache2)
    loaded=other.handle(dict(op='load',path=str(project)))
    assert len(loaded['nativeRegions'])==1 and len(loaded['projectedScene'])==1
    assert not loaded['planeCalibration']['stale']
    assert other.spatial_state(dict(coefficients=[.01,0],hfov=None))['planeCalibration']['stale']
    for fmt in ('json','obj'):
        target=tmp_path/f'scene.{fmt}';other.handle(dict(op='export_spatial',path=str(target),format=fmt,calibration=cal));assert target.exists()
        if fmt=='json':
            exported=json.loads(target.read_text());assert exported['axes']==dict(x='right',y='back',z='up',units='metres')
            assert exported['nativeScene']['objects'][0]['id']=='box'
        else: assert target.with_suffix('.mtl').exists()


def test_homography_and_reversed_reference():
    plane,_=reference()
    world=np.array([[0,0,1],[4,0,1],[4,3,1],[0,3,1]],dtype=float)
    p=world@np.array(plane['homography']).T;p=p[:,:2]/p[:,2:]
    np.testing.assert_allclose(p,plane['corners'],atol=1e-4)
    back=np.c_[p,np.ones(4)]@np.array(plane['inverseHomography']).T
    np.testing.assert_allclose(back[:,:2]/back[:,2:],world[:,:2],atol=1e-10)
    with pytest.raises(ValueError,match='above'):
        calibrate_plane(dict(plane,corners=list(reversed(plane['corners']))),plane['cameraMatrix'],plane['outputSize'],'x')


def test_behind_camera_has_no_invalid_projection():
    plane,_=reference()
    result=project_scene(dict(objects=[dict(id='behind',kind='cuboid',position=[0,-100,0],size=[1,1,1])]),plane,'mapping')[0]
    assert result['visible'] is False and result['vertices']==[]


def test_invalid_native_region_is_transactional(tmp_path):
    from backend import Worker
    image=tmp_path/'a.png'; cv2.imwrite(str(image),np.zeros((100,100,3),np.uint8));cache=tmp_path/'cache';cache.mkdir()
    worker=Worker(cache);worker.handle(dict(op='open',path=str(image)))
    with pytest.raises(ValueError):
        worker.handle(dict(op='native_regions',calibration=dict(coefficients=[0,0]),regions=[dict(id='bad',label='x',points=[[1,1]])]))
    assert worker.native_scene['regions']==[] and worker.regions==[]


def test_extra_image_regions_and_legacy_import_reopen(tmp_path):
    from backend import Worker
    image=tmp_path/'reference.png';extra=tmp_path/'other.png'
    cv2.imwrite(str(image),np.zeros((100,160,3),np.uint8));cv2.imwrite(str(extra),np.full((100,160,3),80,np.uint8))
    originals=[p.read_bytes() for p in (image,extra)]
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache)
    worker.handle(dict(op='open',path=str(image)));worker.handle(dict(op='add_images',paths=[str(extra)]))
    cal=dict(coefficients=[0,0],order=1)
    first=[dict(id='a',label='a',points=[[10,10],[40,10],[40,40]])]
    worker.handle(dict(op='native_regions',calibration=cal,regions=first))
    selected=worker.handle(dict(op='select_image',source=str(extra),calibration=cal))
    assert selected['nativeRegions']==[] and selected['activeImage']==str(extra)
    assert str(worker.source)==str(image)
    legacy=tmp_path/'legacy.json';legacy.write_text(json.dumps(dict(imageWidth=160,imageHeight=100,imagePath='unidentified-export.png',flags={'reviewed':True},shapes=[dict(label='extra',shape_type='polygon',points=[[50,50],[70,50],[70,70]],flags={'hidden':True})])))
    imported=worker.handle(dict(op='labelme',path=str(legacy),calibration=cal))
    assert imported['nativeRegions'][0]['label']=='extra' and len(imported['batchRegions'])==2
    assert worker.handle(dict(op='select_image',source=str(image),calibration=cal))['nativeRegions']==first
    project=tmp_path/'batch.lenscap';worker.handle(dict(op='save',path=str(project),calibration=cal,curves=[]))
    cache2=tmp_path/'cache2';cache2.mkdir();other=Worker(cache2)
    loaded=other.handle(dict(op='load',path=str(project)))
    assert len(loaded['nativeScene']['images'])==2
    selected=other.handle(dict(op='select_image',source=str(extra),calibration=cal))
    assert selected['nativeRegions'][0]['flags']=={'hidden':True}
    zones=tmp_path/'zones.json';other.handle(dict(op='regions',path=str(zones),calibration=cal))
    assert len(json.loads(zones.read_text())['images'])==2
    assert originals==[p.read_bytes() for p in (image,extra)]
    with pytest.raises(ValueError,match='Unknown annotation'): other.handle(dict(op='select_image',source=str(tmp_path/'unknown.png'),calibration=cal))


def test_active_extra_preview_refreshes_on_lens_change(tmp_path):
    from backend import Worker
    from geometry import corrected_image,output_geometry
    from urllib.parse import urlparse,unquote
    original=tmp_path/'reference.png';extra=tmp_path/'extra.png'
    pixels=np.zeros((90,160,3),np.uint8);pixels[10:70,20:50]=255
    cv2.imwrite(str(original),pixels);cv2.imwrite(str(extra),255-pixels)
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache)
    worker.handle(dict(op='open',path=str(original)));worker.handle(dict(op='add_images',paths=[str(extra)]))
    identity=dict(coefficients=[0,0],order=1)
    worker.handle(dict(op='select_image',source=str(extra),calibration=identity))
    native=[dict(id='r',label='region',points=[[20,20],[40,20],[40,40]])]
    worker.handle(dict(op='native_regions',regions=native,calibration=identity))
    changed=dict(coefficients=[-.2,0],order=1)
    result=worker.handle(dict(op='preview',calibration=changed))
    assert result['activeImage']==str(extra) and result['nativeScene']['mappingStale']
    assert result['nativeRegions']==native
    actual=cv2.imread(unquote(urlparse(result['annotationPreview']).path))
    expected=corrected_image(cv2.imread(str(extra)),changed['coefficients'])
    np.testing.assert_array_equal(actual,expected)
    assert actual.shape[1::-1]==tuple(output_geometry((160,90),changed['coefficients'])['size'])
    preset=tmp_path/'profile.json';worker.handle(dict(op='save_preset',path=str(preset),calibration=identity))
    result=worker.handle(dict(op='load_preset',path=str(preset)))
    assert result['activeImage']==str(extra)
    np.testing.assert_array_equal(cv2.imread(unquote(urlparse(result['annotationPreview']).path)),cv2.imread(str(extra)))


def test_loading_another_project_resets_active_image_transactionally(tmp_path,monkeypatch):
    from backend import Worker,region_color
    cal=dict(coefficients=[0,0],order=1)
    reference=tmp_path/'first.png';extra=tmp_path/'extra.png';second=tmp_path/'second.png'
    for i,p in enumerate((reference,extra,second)): cv2.imwrite(str(p),np.full((50,80,3),i*70,np.uint8))
    cache=tmp_path/'cache';cache.mkdir();w=Worker(cache)
    w.handle(dict(op='open',path=str(second)));project=tmp_path/'second.lenscap';w.handle(dict(op='save',path=str(project),calibration=cal,curves=[]))
    w.handle(dict(op='open',path=str(reference)));w.handle(dict(op='add_images',paths=[str(extra)]));w.handle(dict(op='select_image',source=str(extra),calibration=cal))
    previous_source=w.source;previous_active=w.annotation_image
    original_preview=w.preview
    def fail_preview(*args,**kwargs): raise ValueError('Simulated preview failure')
    monkeypatch.setattr(w,'preview',fail_preview)
    with pytest.raises(ValueError,match='Simulated'): w.handle(dict(op='load',path=str(project)))
    assert w.source==previous_source and w.annotation_image==previous_active
    monkeypatch.setattr(w,'preview',original_preview)
    loaded=w.handle(dict(op='load',path=str(project)))
    assert loaded['activeImage']==str(second) and w.annotation_image==str(second)
    assert region_color('room')==region_color('room')
    assert len({region_color(s) for s in ('room','bed','desk','door')})>1
    assert region_color('room')!='#cba6f7'


def test_reference_plane_can_extend_beyond_image():
    k=matrix((1920,1080))
    camera=np.array([2.,-3.,4.])
    forward=np.array([0.,1.,-1.]);forward/=np.linalg.norm(forward)
    rotation=np.array([[1.,0.,0.],np.cross(forward,[1.,0.,0.]),forward])
    world=np.array([[-5.,0.,0.],[9.,0.,0.],[9.,3.,0.],[-5.,3.,0.]])
    corners=cv2.projectPoints(world,cv2.Rodrigues(rotation)[0],-rotation@camera,k,None)[0].reshape(-1,2)
    assert np.any(corners[:,0]<0) and np.any(corners[:,0]>1919)
    plane=calibrate_plane(dict(corners=corners.tolist(),width=14,depth=3),k,(1920,1080),'outside')
    np.testing.assert_allclose(plane['corners'],corners,atol=1e-9)
    assert plane['reprojectionRms']<1e-4


def test_saved_reference_survives_failed_pose_and_project_reopen(tmp_path,monkeypatch):
    import backend
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((100,160,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();worker=backend.Worker(cache)
    worker.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[0,0],order=1,hfov=None)
    # Tape-measured dimensions remain exact internally, regardless of display units.
    plane=dict(corners=[[-20,-10],[130,5],[180,80],[0,100]],width=55*.0254,depth=78*.0254)
    def rejected(*args,**kwargs): raise ValueError('Measured rectangle is inconsistent with assumed camera intrinsics')
    monkeypatch.setattr(backend,'calibrate_plane',rejected)
    saved=worker.handle(dict(op='save_reference_plane',calibration=cal,plane=plane))
    assert saved['referencePlane']['corners']==plane['corners']
    assert saved['planeCalibration'] is None
    with pytest.raises(ValueError,match='inconsistent'):
        worker.handle(dict(op='calculate_spatial_calibration',calibration=cal))
    assert worker.reference_plane['width']==pytest.approx(1.397) and worker.reference_plane['depth']==pytest.approx(1.9812)
    project=tmp_path/'measured.lenscap'
    worker.handle(dict(op='save',path=str(project),calibration=cal,curves=[]))
    cache2=tmp_path/'cache2';cache2.mkdir();other=backend.Worker(cache2)
    loaded=other.handle(dict(op='load',path=str(project)))
    assert loaded['referencePlane']==saved['referencePlane']
    assert loaded['planeCalibration'] is None


def test_reference_save_invalidates_pose_without_deleting_scene(tmp_path):
    from backend import Worker
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((1080,1920,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache);worker.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[0,0],order=1,hfov=None);plane,_=reference()
    worker.handle(dict(op='set_spatial_calibration',calibration=cal,plane=plane))
    worker.native_scene['objects']=[dict(id='box',kind='cuboid',position=[1,1,0],size=[1,1,1])]
    updated=dict(plane,width=4.1)
    result=worker.handle(dict(op='save_reference_plane',calibration=cal,plane=updated))
    assert result['planeCalibration'] is None and len(result['nativeScene']['objects'])==1
    with pytest.raises(ValueError):
        worker.handle(dict(op='save_reference_plane',calibration=cal,plane=dict(updated,width=-1)))
    assert worker.reference_plane['width']==4.1


def test_legacy_solved_plane_restores_reference(tmp_path):
    from backend import Worker
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((1080,1920,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache);worker.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[0,0],order=1,hfov=None);plane,_=reference()
    worker.handle(dict(op='set_spatial_calibration',calibration=cal,plane=plane))
    project=tmp_path/'legacy.lenscap';worker.handle(dict(op='save',path=str(project),calibration=cal,curves=[]))
    document=json.loads(project.read_text());document.pop('referencePlane');project.write_text(json.dumps(document))
    result=worker.handle(dict(op='load',path=str(project)))
    assert result['referencePlane']['corners']==plane['corners']
    assert result['referencePlane']['width']==4


def test_calculate_3d_uses_saved_reference_without_resaving(tmp_path):
    from backend import Worker
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((1080,1920,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache);worker.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[0,0],order=1,hfov=None);plane,_=reference()
    saved=worker.handle(dict(op='save_reference_plane',calibration=cal,plane=dict(corners=plane['corners'],width=4,depth=3)))
    result=worker.handle(dict(op='calculate_spatial_calibration',calibration=cal))
    assert result['planeCalibration']['reprojectionRms']<1e-4
    assert result['referencePlane']==saved['referencePlane']
    changed=dict(coefficients=[.01,0],order=1,hfov=None)
    with pytest.raises(ValueError,match='different lens'):
        worker.handle(dict(op='calculate_spatial_calibration',calibration=changed))
    assert worker.reference_plane['corners']==plane['corners']


@pytest.mark.parametrize('axes',[['y','-x'],['x','z'],['-z','y']])
def test_reference_axis_assignments_preserve_metric_pose(axes):
    from spatial import reference_basis
    original,camera=reference()
    solved=calibrate_plane(dict(corners=original['corners'],width=4,depth=3,axes=axes),original['cameraMatrix'],original['outputSize'],'axes')
    assert solved['referenceAxes']==axes
    np.testing.assert_allclose(solved['cameraPosition'],reference_basis(axes)@camera,atol=1e-5)
    assert solved['reprojectionRms']<1e-4


def test_project_save_uses_current_editor_plane_snapshot(tmp_path):
    from backend import Worker
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((100,160,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache)
    worker.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[0,0],order=1,hfov=None)
    plane=dict(corners=[[-20,-10],[130,5],[180,80],[0,100]],width=.3048,depth=.1524,axes=['x','y'])
    worker.handle(dict(op='save_reference_plane',calibration=cal,plane=plane))
    current=dict(plane,width=55*.0254,depth=78*.0254,axes=['y','-x'])
    project=tmp_path/'current.lenscap'
    result=worker.handle(dict(op='save',path=str(project),calibration=cal,curves=[],referencePlane=current))
    saved=json.loads(project.read_text())['referencePlane']
    assert saved['width']==pytest.approx(1.397)
    assert saved['depth']==pytest.approx(1.9812)
    assert saved['axes']==['y','-x']
    assert result['referencePlane']==worker.reference_plane==saved
    cache2=tmp_path/'cache2';cache2.mkdir();other=Worker(cache2)
    assert other.handle(dict(op='load',path=str(project)))['referencePlane']==dict(saved,stale=False)


def test_manufacturer_hfov_uses_distorted_source_edges_for_pose():
    from geometry import spatial_camera_matrix,output_geometry
    size=(1920,1080);coefficients=[-.14754856915960193,.01690970923143725];hfov=98.8
    geometry=output_geometry(size,coefficients,hfov)
    camera=spatial_camera_matrix(size,coefficients,hfov)
    assert camera[0][0]>geometry['cameraMatrix'][0][0]
    assert camera[0][2]==geometry['cameraMatrix'][0][2]
    assert np.allclose(spatial_camera_matrix(size,[0,0],hfov),matrix(size,hfov))
    plane=dict(corners=[[2105.1831133433207,1040.9057718203687],[1829.4854674327948,472.0111529433068],[1127.6312740918438,-.21199644415362687],[1413.2107817348362,1192.97827148811]],width=55*.0254,depth=78*.0254)
    result=calibrate_plane(plane,camera,geometry['size'],'measured')
    assert result['reprojectionRms']<7


def test_blender_export_requires_current_pose_and_passes_calibrated_data(tmp_path,monkeypatch):
    import sys,types
    from backend import Worker
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((1080,1920,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache)
    worker.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[0,0],order=1,hfov=None)
    exported=[]
    def capture(*args): exported.append(args)
    monkeypatch.setitem(sys.modules,'blender_export',types.SimpleNamespace(export_blend=capture))
    request=dict(op='export_spatial',path=str(tmp_path/'scene.blend'),format='blend',calibration=cal)
    with pytest.raises(ValueError,match='reference plane'):worker.handle(request)
    plane,_=reference();worker.handle(dict(op='set_spatial_calibration',calibration=cal,plane=plane))
    worker.handle(request)
    assert len(exported)==1
    target,pixels,lens,pose,scene,size=exported[0]
    assert target.suffix=='.blend' and pixels.shape==(1080,1920,3)
    assert lens==cal and pose==worker.plane_calibration and size==(1920,1080)
    assert scene==worker.native_scene
    with pytest.raises(ValueError,match='reference plane'):
        worker.handle(dict(request,calibration=dict(cal,coefficients=[.01,0])))
