"""LabelMe receives current annotations, valid images, and per-image deletion semantics."""
import json
from pathlib import Path
import subprocess

import cv2
import numpy as np
import pytest

from backend import Worker


def setup_worker(tmp_path):
    image=tmp_path/'source.png';cv2.imwrite(str(image),np.zeros((180,320,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir();worker=Worker(cache);worker.handle(dict(op='open',path=str(image)))
    return worker,dict(coefficients=[0.,0.],hfov=None)


def polygon(label='region'):
    return dict(id='region-id',label=label,points=[[40,40],[120,40],[120,100],[40,100]],flags={'occluded':True},group_id=7,labelmeShape=dict(description='preserve shape metadata'))


def test_current_native_annotations_seed_valid_labelme_json_and_active_extra(tmp_path):
    worker,cal=setup_worker(tmp_path);original=worker.source.read_bytes()
    extra=tmp_path/'extra.png';cv2.imwrite(str(extra),np.ones((180,320,3),np.uint8))
    worker.handle(dict(op='add_images',paths=[str(extra)]))
    worker.commit_native(str(worker.source),[polygon('reference')],cal)
    worker.commit_native(str(extra),[polygon('extra current')],cal)
    worker.annotation_documents[str(extra)]=dict(flags={'reviewed':True},shapes=[dict(shape_type='polygon',label='outdated',points=[[1,1],[2,1],[2,2]])])
    worker.annotation_image=str(extra)
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    assert prepared['labelmeImage'].endswith('001-extra.png')
    assert Path(prepared['labelmeJson']).name=='000-reference.json'
    document=json.loads(Path(prepared['labelmeImage']).with_suffix('.json').read_text())
    assert document['imagePath']=='001-extra.png' and document['imageData'] is None
    assert [document['imageWidth'],document['imageHeight']]==[320,180]
    assert document['flags']=={'reviewed':True}
    shape=document['shapes'][0]
    assert shape['label']=='extra current' and shape['group_id']==7 and shape['flags']=={'occluded':True}
    assert shape['description']=='preserve shape metadata'
    assert worker.source.read_bytes()==original
    parser=Path.home()/'.local/share/uv/tools/labelme/bin/python'
    if parser.is_file():
        result=subprocess.run([str(parser),'-c','from labelme._label_file import read_label_file;import sys;read_label_file(filename=sys.argv[1])',str(Path(prepared['labelmeImage']).with_suffix('.json'))],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr


def test_brand_new_image_has_no_fake_annotation_json(tmp_path):
    worker,cal=setup_worker(tmp_path)
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    assert Path(prepared['labelmeImage']).is_file()
    assert not Path(prepared['labelmeJson']).exists()


def test_deleting_all_shapes_clears_only_that_image(tmp_path):
    worker,cal=setup_worker(tmp_path)
    extra=tmp_path/'extra.png';cv2.imwrite(str(extra),np.ones((180,320,3),np.uint8))
    worker.handle(dict(op='add_images',paths=[str(extra)]))
    worker.commit_native(str(worker.source),[polygon('reference')],cal)
    worker.commit_native(str(extra),[polygon('untouched extra')],cal)
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    reference=Path(prepared['labelmeJson']);doc=json.loads(reference.read_text());doc['shapes']=[];reference.write_text(json.dumps(doc))
    Path(prepared['labelmeFolder'],'001-extra.json').unlink()
    worker.handle(dict(op='finish_labelme',path=str(reference),calibration=cal))
    scenes={item['source']:item['regions'] for item in worker.native_scene['images']}
    assert scenes[str(worker.source)]==[]
    assert scenes[str(extra)][0]['label']=='untouched extra'
    assert worker.annotation_documents[str(worker.source)]['shapes']==[]


def test_labelme_non_polygons_survive_save_and_reopen(tmp_path):
    worker,cal=setup_worker(tmp_path)
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    doc=dict(version='7.9.1',flags={'reviewed':True},imagePath=Path(prepared['labelmeImage']).name,imageData=None,imageWidth=320,imageHeight=180,shapes=[dict(label='circle',shape_type='circle',points=[[100,80],[120,80]],flags={},group_id=None),dict(label='polygon',shape_type='polygon',points=polygon()['points'],flags={},group_id=3)])
    Path(prepared['labelmeJson']).write_text(json.dumps(doc))
    worker.handle(dict(op='finish_labelme',path=prepared['labelmeJson'],calibration=cal))
    assert len(worker.regions)==1
    assert worker.annotation_documents[str(worker.source)]==doc
    project=tmp_path/'regions.lenscap';worker.handle(dict(op='save',path=str(project),calibration=cal))
    cache=tmp_path/'reopened-cache';cache.mkdir();other=Worker(cache);other.handle(dict(op='load',path=str(project)))
    again=other.handle(dict(op='prepare_labelme',calibration=cal))
    restored=json.loads(Path(again['labelmeJson']).read_text())
    assert {shape['shape_type'] for shape in restored['shapes']}=={'circle','polygon'}
    assert restored['flags']=={'reviewed':True}


def test_lens_change_preserves_raw_annotations_and_requests_review(tmp_path):
    worker,cal=setup_worker(tmp_path)
    worker.commit_native(str(worker.source),[polygon()],cal)
    document=worker.annotation_documents[str(worker.source)]
    document['shapes'].append(dict(label='point',shape_type='point',points=[[70,70]],flags={}))
    changed=dict(coefficients=[-.05,0],hfov=None)
    worker.handle(dict(op='preview',calibration=changed))
    prepared=worker.handle(dict(op='prepare_labelme',calibration=changed))
    restored=json.loads(Path(prepared['labelmeJson']).read_text())
    assert {shape['label'] for shape in restored['shapes']}=={'region','point'}
    assert 'older lens correction' in prepared['labelmeNotice']
    assert restored['shapes'][0]['points']==polygon()['points']


def test_finish_labelme_imports_overhanging_polygon_and_preserves_raw_document(tmp_path):
    from shapely.geometry import Polygon
    worker,cal=setup_worker(tmp_path)
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    points=[[-25,40],[120,40],[120,100],[-25,100]]
    doc=dict(version='7.9.1',flags={'reviewed':True},imagePath=Path(prepared['labelmeImage']).name,imageData=None,imageWidth=320,imageHeight=180,
             shapes=[dict(label='overhang',shape_type='polygon',points=points,flags={'occluded':True},group_id=3)])
    Path(prepared['labelmeJson']).write_text(json.dumps(doc))
    worker.handle(dict(op='finish_labelme',path=prepared['labelmeJson'],calibration=cal))
    assert len(worker.regions)==1
    assert Polygon(worker.regions[0]['points']).bounds==(0.,40.,120.,100.)
    assert worker.annotation_documents[str(worker.source)]==doc
    assert worker.native_scene['images'][0]['regions'][0]['points']==points


def test_same_calibration_preview_preserves_regions_and_labelme_documents(tmp_path):
    worker,cal=setup_worker(tmp_path)
    worker.commit_native(str(worker.source),[polygon()],cal)
    document=worker.annotation_documents[str(worker.source)]
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    result=worker.handle(dict(op='preview',calibration=cal))
    assert len(result['regions'])==1 and len(result['batchRegions'])==1
    assert worker.annotation_documents[str(worker.source)]==document
    assert worker.labelme_handoff is not None
    worker.handle(dict(op='finish_labelme',path=prepared['labelmeJson'],calibration=cal))
    assert len(worker.regions)==1


def test_adding_image_preserves_existing_authored_annotations(tmp_path):
    worker,cal=setup_worker(tmp_path)
    worker.commit_native(str(worker.source),[polygon()],cal)
    document=worker.annotation_documents[str(worker.source)]
    worker.handle(dict(op='prepare_labelme',calibration=cal))
    extra=tmp_path/'extra.png';cv2.imwrite(str(extra),np.ones((180,320,3),np.uint8))
    result=worker.handle(dict(op='add_images',paths=[str(extra)]))
    assert len(result['regions'])==1 and len(result['batchRegions'])==1
    assert worker.annotation_documents[str(worker.source)]==document
    assert worker.labelme_handoff is None
    prepared=worker.handle(dict(op='prepare_labelme',calibration=cal))
    restored=json.loads(Path(prepared['labelmeJson']).read_text())
    assert restored['shapes'][0]['label']=='region'
