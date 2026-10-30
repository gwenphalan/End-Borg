import json
import cv2
import numpy as np
import pytest
from backend import Worker
from history import History
from profiles import manage_profile


def test_named_profile_lifecycle_and_validation(tmp_path):
    cache=tmp_path/'cache';cache.mkdir()
    image=tmp_path/'image.png';cv2.imwrite(str(image),np.zeros((64,96,3),np.uint8))
    worker=Worker(cache);worker.handle(dict(op='open',path=str(image)))
    history=History(tmp_path/'state/recent.json')
    calibration=dict(coefficients=[.01,0],hfov=None,order=1)
    request=dict(op='save_profile',name='Camera',calibration=calibration,curves=[])
    saved=manage_profile(request,worker,history);filename=saved['profilePath']
    assert History(history.filename).profiles()[0]['name']=='Camera'
    with pytest.raises(ValueError,match='already exists'):manage_profile(request,worker,history)
    with pytest.raises(ValueError,match='Enter a profile'):manage_profile(dict(request,name=' '),worker,history)
    manage_profile(dict(op='rename_profile',path=filename,name='Bedroom'),worker,history)
    assert history.profiles()[0]['name']=='Bedroom'
    manage_profile(dict(request,op='update_profile',path=filename,calibration=dict(calibration,coefficients=[.02,0])),worker,history)
    document=json.loads(open(filename).read());assert document['name']=='Bedroom';assert document['calibration']['coefficients']==[.02,0]
    worker.handle(dict(op='load_preset',path=filename,curves=[]))
    result=worker.handle(dict(op='clear_profile'));assert result['calibration'] is None
    with pytest.raises(ValueError,match='no longer available'):manage_profile(dict(op='delete_profile',path=str(image)),worker,history)
    manage_profile(dict(op='delete_profile',path=filename),worker,history)
    assert history.profiles()==[]
    assert not __import__('pathlib').Path(filename).exists()
