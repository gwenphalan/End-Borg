"""Distorted LabelMe export is independent of Frigate zone-name constraints."""
import copy
import json
from pathlib import Path
import subprocess

import cv2
import numpy as np
import pytest

from backend import Worker, distorted_labelme_shapes
from geometry import original_to_output, output_geometry


def worker_for(tmp_path):
    source=tmp_path/'source.png'
    cv2.imwrite(str(source),np.zeros((180,320,3),np.uint8))
    cache=tmp_path/'cache';cache.mkdir()
    worker=Worker(cache);worker.handle(dict(op='open',path=str(source)))
    return worker,dict(coefficients=[-.08,.005],hfov=None)


def test_duplicate_labels_metadata_and_real_labelme_parser(tmp_path):
    worker,cal=worker_for(tmp_path)
    regions=[]
    for index,x in enumerate((70,170)):
        points=original_to_output([[x,45],[x+55,45],[x+55,100],[x,100]],(320,180),cal['coefficients']).tolist()
        regions.append(dict(id=f'r{index}',label='same label',points=points,flags={'reviewed':bool(index)},group_id=index,labelmeShape={'description':f'annotation {index}','custom':index}))
    worker.commit_native(str(worker.source),regions,cal)
    document=worker.annotation_documents[str(worker.source)]
    document.update(version='7.9.1',flags={'complete':True},description='document metadata',custom={'hello':'world'})
    before=copy.deepcopy((worker.native_scene,worker.annotation_documents,worker.regions))
    output=tmp_path/'exports'/'distorted.json';output.parent.mkdir()
    result=worker.handle(dict(op='export_labelme',path=str(output),calibration=cal))
    doc=json.loads(output.read_text())
    assert result['shapeCount']==2
    assert doc['imagePath']=='../source.png' and doc['imageData'] is None
    assert (doc['imageWidth'],doc['imageHeight'])==(320,180)
    assert doc['flags']=={'complete':True} and doc['custom']=={'hello':'world'}
    assert [s['label'] for s in doc['shapes']]==['same label','same label']
    for index,shape in enumerate(doc['shapes']):
        assert shape['description']==f'annotation {index}' and shape['custom']==index
        assert shape['group_id']==index and shape['flags']=={'reviewed':bool(index)}
        assert len(shape['points'])>4
        assert np.allclose(shape['points'][0],[70+100*index,45],atol=1e-4)
    assert (worker.native_scene,worker.annotation_documents,worker.regions)==before
    parser=Path.home()/'.local/share/uv/tools/labelme/bin/python'
    if parser.is_file():
        run=subprocess.run([str(parser),'-c','from labelme._label_file import read_label_file;import sys;read_label_file(filename=sys.argv[1])',str(output)],capture_output=True,text=True)
        assert run.returncode==0,run.stdout+run.stderr


def test_active_extra_and_nonpolygon_shapes(tmp_path):
    worker,cal=worker_for(tmp_path)
    extra=tmp_path/'extra.png';cv2.imwrite(str(extra),np.ones((180,320,3),np.uint8))
    worker.handle(dict(op='add_images',paths=[str(extra)]));worker.annotation_image=str(extra)
    size=output_geometry((320,180),cal['coefficients'])['size']
    shapes=[dict(label='',shape_type=kind,points=points,flags={},group_id=5,description=kind) for kind,points in [('rectangle',[[60,50],[100,100]]),('circle',[[180,90],[200,90]]),('line',[[60,50],[250,50]]),('point',[[150,80]])]]
    worker.annotation_documents[str(extra)]=dict(imageWidth=size[0],imageHeight=size[1],shapes=shapes)
    output=tmp_path/'extra-distorted.json'
    worker.handle(dict(op='export_labelme',path=str(output),calibration=cal))
    doc=json.loads(output.read_text())
    assert doc['imagePath']=='extra.png'
    assert [s['shape_type'] for s in doc['shapes']]==['polygon','polygon','linestrip','point']
    assert all(s['label']=='' and s['group_id']==5 for s in doc['shapes'])


def test_clipping_keeps_duplicate_labels_and_metadata():
    shapes=[dict(label='same',shape_type='polygon',points=[[-10,10],[30,10],[30,40],[-10,40]],flags={'a':True},group_id=8)]
    output=distorted_labelme_shapes(shapes,(100,100),[0,0])
    assert output[0]['label']=='same' and output[0]['flags']=={'a':True}
    assert np.asarray(output[0]['points'])[:,0].min()==0


def test_unsupported_shape_does_not_overwrite_target(tmp_path):
    worker,cal=worker_for(tmp_path)
    size=output_geometry((320,180),cal['coefficients'])['size']
    worker.annotation_documents[str(worker.source)]=dict(imageWidth=size[0],imageHeight=size[1],shapes=[dict(label='mask',shape_type='mask',points=[[20,20],[40,40]],mask='payload')])
    output=tmp_path/'existing.json';output.write_text('untouched')
    with pytest.raises(ValueError,match='mask'):
        worker.handle(dict(op='export_labelme',path=str(output),calibration=cal))
    assert output.read_text()=='untouched'


def test_stale_mapping_requires_review_without_writing(tmp_path):
    worker,cal=worker_for(tmp_path)
    worker.commit_native(str(worker.source),[],cal)
    output=tmp_path/'stale.json'
    with pytest.raises(ValueError,match='older lens correction'):
        worker.handle(dict(op='export_labelme',path=str(output),calibration=dict(coefficients=[-.04,0],hfov=None)))
    assert not output.exists()
