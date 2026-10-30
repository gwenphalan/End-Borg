"""Blender import changes only box regions and updates stable exported IDs."""
import json
import sys
import types

import cv2
import numpy as np
import pytest

from backend import Worker
from test_spatial import reference


def test_import_merges_boxes_preserves_calibration_and_round_trips(tmp_path,monkeypatch):
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((1080,1920,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();w=Worker(cache);w.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[0,0],order=1,hfov=None)
    plane,_=reference();w.handle(dict(op='set_spatial_calibration',calibration=cal,plane=plane))
    region=dict(id='r',label='2D',points=[[100,100],[200,100],[200,200]])
    box=dict(id='original',kind='cuboid',position=[1,1,0],size=[1,1,1],yaw=0)
    w.handle(dict(op='project_spatial',calibration=cal,nativeScene=dict(regions=[],objects=[box])))
    w.handle(dict(op='native_regions',calibration=cal,regions=[region]))
    saved_pose=json.loads(json.dumps(w.plane_calibration));saved_reference=json.loads(json.dumps(w.reference_plane))
    imported=[dict(box,position=[2,1,0]),dict(box,id='new',label='Blender box',position=[0,0,0])]
    monkeypatch.setitem(sys.modules,'blender_import',types.SimpleNamespace(import_blend=lambda p:dict(objects=imported,skipped=4)))
    request=dict(op='import_blend',path=str(tmp_path/'scene.blend'),calibration=cal)
    result=w.handle(request)
    assert result['importedCount']==2 and result['skippedCount']==4
    assert len(result['nativeScene']['objects'])==2
    assert result['nativeScene']['objects'][0]['position']==[2,1,0]
    assert result['nativeScene']['regions']==[region]
    assert len(result['projectedScene'])==2
    assert w.plane_calibration==saved_pose and w.reference_plane==saved_reference
    assert len(w.handle(request)['nativeScene']['objects'])==2
    project=tmp_path/'imported.lenscap';w.handle(dict(op='save',path=str(project),calibration=cal))
    cache2=tmp_path/'cache2';cache2.mkdir();loaded=Worker(cache2).handle(dict(op='load',path=str(project)))
    assert len(loaded['nativeScene']['objects'])==2 and loaded['nativeRegions']==[region]
    before=json.loads(json.dumps(w.native_scene))
    monkeypatch.setitem(sys.modules,'blender_import',types.SimpleNamespace(import_blend=lambda p:dict(objects=[dict(box,kind='plane',size=[1,1])],skipped=0)))
    with pytest.raises(ValueError,match='non-box'):w.handle(request)
    assert w.native_scene==before
    with pytest.raises(ValueError,match='reference plane'):
        w.handle(dict(request,calibration=dict(cal,coefficients=[.01,0])))


def test_recalibrate_blender_uses_current_calibration_without_project_mutation(tmp_path,monkeypatch):
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((1080,1920,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();w=Worker(cache);w.handle(dict(op='open',path=str(image)))
    cal=dict(coefficients=[0,0],order=1,hfov=None)
    plane,_=reference();w.handle(dict(op='set_spatial_calibration',calibration=cal,plane=plane))
    captured=[]
    monkeypatch.setitem(sys.modules,'blender_recalibrate',types.SimpleNamespace(recalibrate_blend=lambda *args:captured.append(args)))
    source=tmp_path/'edited.blend';target=tmp_path/'edited-recalibrated.blend'
    before=json.loads(json.dumps(w.native_scene))
    request=dict(op='recalibrate_blend',sourcePath=str(source),path=str(target),calibration=cal)
    result=w.handle(request)
    assert result['blenderPath']==str(target)
    assert len(captured)==1
    assert captured[0][0]==source and captured[0][1]==target
    assert captured[0][3]==cal and captured[0][4]==w.plane_calibration
    assert w.native_scene==before
    with pytest.raises(ValueError,match='new file'):w.handle(dict(request,path=str(source)))
    with pytest.raises(ValueError,match='reference plane'):
        w.handle(dict(request,calibration=dict(cal,coefficients=[.01,0])))
