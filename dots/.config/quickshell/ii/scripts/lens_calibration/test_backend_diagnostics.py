"""Worker failures retain actionable diagnostics and the last usable document state."""
import json
import numpy as np
import pytest
import backend


def test_error_response_keeps_structured_trace_diagnostics():
    exc = ValueError('Trace 3 has duplicate points.')
    exc.code = 'trace_geometry'
    exc.diagnostics = [dict(curve=2, status='error', code='duplicate', message=str(exc))]
    result = json.loads(json.dumps(backend.error_response(exc), allow_nan=False))
    assert result == dict(ok=False, error=str(exc), code=exc.code, diagnostics=exc.diagnostics)
    assert backend.error_response(ValueError('Cannot decode image.')) == dict(ok=False, error='Cannot decode image.')


def test_failed_preview_preserves_settings_and_annotation_state(tmp_path, monkeypatch):
    worker = backend.Worker(tmp_path)
    worker.image = np.zeros((108, 192, 3), dtype=np.uint8)
    worker.regions = [dict(label='bed')]
    worker.batch_regions = [dict(source='reference', regions=worker.regions)]
    worker.annotation_documents = {'reference': {'shapes': []}}
    worker.annotation_directory = tmp_path / 'existing'
    settings = dict(worker.project_settings)
    monkeypatch.setattr(backend, 'calibrate', lambda *args: dict(coefficients=[0, 0], hfov=90))
    def failed_preview(*args):
        raise OSError('Preview disk is full.')
    monkeypatch.setattr(worker, 'preview', failed_preview)
    with pytest.raises(OSError, match='disk is full'):
        worker.handle(dict(op='calibrate', order=2, projectSettings=dict(hfov=90)))
    assert worker.project_settings == settings
    assert worker.regions == [dict(label='bed')]
    assert worker.batch_regions
    assert worker.annotation_documents == {'reference': {'shapes': []}}
    assert worker.annotation_directory == tmp_path / 'existing'


def test_real_geometry_error_keeps_original_trace_index():
    from geometry import calibrate, CalibrationError
    with pytest.raises(CalibrationError) as caught:
        calibrate([[[2, 3], [5, float('nan')], [8, 9]]], (100, 100))
    response = backend.error_response(caught.value)
    assert response['code'] == 'invalid_trace'
    assert response['diagnostics'][0]['curve'] == 0
    assert response['diagnostics'][0]['point'] == 1
    assert response['diagnostics'][0]['code'] == 'non_finite_point'
    json.dumps(response, allow_nan=False)


def test_auto_preference_survives_project_and_profile_without_losing_chosen_model(tmp_path):
    import cv2
    worker = backend.Worker(tmp_path)
    source = tmp_path / 'source.png'
    assert cv2.imwrite(str(source), np.zeros((90, 160, 3), np.uint8))
    opened = worker.handle(dict(op='open', path=str(source)))
    assert opened['projectSettings']['order'] == 0
    calibration = dict(coefficients=[0., 0.], hfov=None, order=2, modelSelection='auto')
    project = tmp_path / 'auto.lenscap'
    profile = tmp_path / 'auto-profile.json'
    worker.handle(dict(op='save', path=str(project), calibration=calibration, curves=[]))
    worker.handle(dict(op='save_preset', path=str(profile), calibration=calibration))
    worker.handle(dict(op='set_settings', projectSettings=dict(order=1)))
    loaded = worker.handle(dict(op='load', path=str(project)))
    assert loaded['projectSettings']['order'] == 0
    assert loaded['calibration']['order'] == 2
    worker.handle(dict(op='set_settings', projectSettings=dict(order=1)))
    loaded = worker.handle(dict(op='load_preset', path=str(profile)))
    assert loaded['projectSettings']['order'] == 0
    assert loaded['calibration']['order'] == 2
