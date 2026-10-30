"""Physical-model regression and original-index evidence-based trace diagnostics."""
import json
from pathlib import Path
import numpy as np
import pytest
from geometry import (CalibrationError,calibrate,distort,undistort,validate_model,
                      matrix,output_geometry,original_to_output,_physical_margin)

SIZE=(1920,1080)


def observed_edges(coefficients=(-.32,0.)):
    curves=[]
    for y in [90,230,830,980]:
        curves.append(np.column_stack((np.linspace(180,1740,25),np.full(25,y))))
    for x in [190,430,1490,1730]:
        curves.append(np.column_stack((np.full(25,x),np.linspace(100,980,25))))
    return [distort(points,SIZE,coefficients).tolist() for points in curves]


def real_fixture():
    return json.loads(Path(__file__).with_name('fixtures').joinpath('bed_vision_traces.json').read_text())


def test_real_project_k1_is_physically_bounded_and_recommends_explicit_k2():
    document=real_fixture();settings=document['settings']
    before=json.dumps(document,sort_keys=True)
    result=calibrate(document['curves'],document['size'],1,settings['hfov'])
    assert result['order']==1 and result['hfov']==98.8
    assert result['coefficients'][0]==pytest.approx(-.08130956,abs=1e-7)
    validate_model(document['size'],result['coefficients'],settings['hfov'])
    assert _physical_margin(result['coefficients'],document['size'],settings['hfov'])>=0
    assert 2.1<result['rmsAfter']<2.3 and result['rmsBefore']>4.4
    assert result['limitedByModel'] and result['diagnostics']==[]
    recommendation=result['recommendation']
    assert recommendation['order']==2 and recommendation['rmsAfter']<.61
    assert recommendation['reason'] in result['warnings']
    assert len(recommendation['validation']['curves'])>=2
    assert recommendation['validation']['rms']<recommendation['validation']['baselineRms']*.8
    geometry=output_geometry(document['size'],result['coefficients'],settings['hfov'])
    original=np.random.default_rng(21).uniform([0,0],[1919,1079],(3000,2))
    corrected=original_to_output(original,document['size'],result['coefficients'],settings['hfov'])
    assert np.all(corrected>=0) and np.all(corrected<=np.array(geometry['size'])-1)
    assert json.dumps(document,sort_keys=True)==before


def test_real_project_explicit_k2_resolves_curvature_without_false_trace_blame():
    document=real_fixture()
    result=calibrate(document['curves'],document['size'],2,document['settings']['hfov'])
    assert result['rmsAfter']==pytest.approx(.59558,abs=1e-4)
    assert result['diagnostics']==[] and result['warnings']==[]
    assert not result['limitedByModel'] and 'recommendation' not in result
    validate_model(document['size'],result['coefficients'],document['settings']['hfov'])


def test_exact_derivative_vertex_rejects_narrow_noninvertible_valley():
    coefficients=[-1.,9/(20*(.85+1e-9))]
    corners=np.array([[0,0],[1919,0],[0,1079],[1919,1079]])
    corrected=undistort(corners,SIZE,coefficients)
    k=matrix(SIZE);radius=np.linalg.norm((corrected-k[:2,2])/k[0,0],axis=1).max()
    old_samples=np.linspace(0,radius,1024)
    assert np.min(1+3*coefficients[0]*old_samples**2+5*coefficients[1]*old_samples**4)>.15
    with pytest.raises(ValueError,match='non-invertible'):validate_model(SIZE,coefficients)
    assert _physical_margin(coefficients,SIZE,None)<0


def test_physical_k2_solver_recovers_known_monotone_models():
    for coefficients in [(-.4,.15),(.25,-.05)]:
        result=calibrate(observed_edges(coefficients),SIZE,2)
        np.testing.assert_allclose(result['coefficients'],coefficients,atol=1e-5)
        validate_model(SIZE,result['coefficients'])
        assert result['rmsAfter']<1e-4


def test_ignored_curves_keep_original_indices_and_three_points_contribute():
    source=observed_edges()
    curves=[[],source[0],[[1,1],[2,2]],*source[1:]]
    result=calibrate(curves,SIZE)
    assert result['usedCurves']==8 and result['ignoredCurves']==2
    assert [(item['curve'],item['status']) for item in result['diagnostics']]==[(0,'ignored'),(2,'ignored')]
    assert result['diagnostics'][1]['code']=='incomplete_trace'
    three=[np.asarray(curve)[[0,12,24]].tolist() for curve in source]
    fit=calibrate(three,SIZE)
    assert fit['usedCurves']==8 and fit['ignoredCurves']==0


def test_malformed_and_outside_traces_are_attributed_to_actual_original_indices():
    curves=[[],*observed_edges(),[[1,1],[float('nan'),2],[3,3]],[[0,0],[1920,50],[100,100]],['bad']]
    with pytest.raises(CalibrationError) as caught:calibrate(curves,SIZE)
    error=caught.value
    assert isinstance(error,ValueError) and error.code=='invalid_trace'
    flagged=[item for item in error.diagnostics if item['status']=='error']
    assert [item['curve'] for item in flagged]==[9,10,11]
    assert flagged[0]['point']==1 and flagged[1]['point']==1
    assert error.message==str(error) and 'No correction was applied' in error.message
    json.dumps(error.diagnostics,allow_nan=False)


def test_global_weakness_never_marks_all_curves_as_bad():
    curves=[np.column_stack((np.linspace(100,1800,10),np.full(10,539.5))).tolist()]*3
    with pytest.raises(CalibrationError) as caught:calibrate(curves,SIZE)
    assert caught.value.code=='weak_coverage'
    assert caught.value.diagnostics==[]
    with pytest.raises(CalibrationError) as caught:calibrate([[[1,1],[2,2]]]*5,SIZE)
    assert caught.value.code=='insufficient_traces'
    assert all(item['status']=='ignored' for item in caught.value.diagnostics)


def test_conflicting_trace_is_identified_only_against_stable_held_out_fit():
    curves=observed_edges()
    rogue=np.column_stack((np.linspace(350,1550,25),500+80*np.sin(np.linspace(0,2*np.pi,25)))).tolist()
    with pytest.raises(CalibrationError) as caught:calibrate([[],rogue,*curves],SIZE)
    conflicts=[item for item in caught.value.diagnostics if item['code']=='conflicting_trace']
    assert [item['curve'] for item in conflicts]==[1]
    assert conflicts[0]['rms']>3 and conflicts[0]['othersRms']<1e-4
    assert all(item['status']!='error' or item['curve']==1 for item in caught.value.diagnostics)


def test_unstable_fit_can_still_isolate_one_corrupted_real_trace():
    document=real_fixture();curves=document['curves']
    curves[5][2][0]+=90
    with pytest.raises(CalibrationError) as caught:calibrate(curves,document['size'],2,document['settings']['hfov'])
    conflicts=[item for item in caught.value.diagnostics if item['code']=='conflicting_trace']
    assert [item['curve'] for item in conflicts]==[5]
    assert conflicts[0]['othersRms']<1 and conflicts[0]['rms']>3


def test_auto_selects_validated_k2_for_real_project_without_an_action():
    document=real_fixture()
    result=calibrate(document['curves'],document['size'],0,document['settings']['hfov'])
    assert result['modelSelection']=='auto' and result['order']==2
    assert result['rmsAfter']==pytest.approx(.59558,abs=1e-4)
    assert 'recommendation' not in result and result['diagnostics']==[]
    assert 'Selected k1 + k2' in result['selectionReason']
    assert len(result['modelValidation']['curves'])>=2
    assert result['modelValidation']['rms']<result['modelValidation']['baselineRms']*.8
    validate_model(document['size'],result['coefficients'],document['settings']['hfov'])


@pytest.mark.parametrize('noise',[0.,.2])
def test_auto_preserves_simple_model_for_clean_and_noisy_k1_traces(noise):
    random=np.random.default_rng(177)
    curves=[(np.asarray(points)+random.normal(0,noise,np.asarray(points).shape)).tolist() for points in observed_edges()]
    result=calibrate(curves,SIZE,0)
    assert result['modelSelection']=='auto' and result['order']==1
    assert 'recommendation' not in result
    assert abs(result['coefficients'][0]+.32)<.005
    assert result['rmsAfter']<max(.001,noise*2)
    assert 'additional radial term' in result['selectionReason']


def test_auto_uses_safe_k1_when_too_few_traces_support_k2():
    result=calibrate(observed_edges()[:4],SIZE,0)
    assert result['modelSelection']=='auto' and result['order']==1
    assert result['usedCurves']==4
    assert 'fewer than five' in result['selectionReason']
    validate_model(SIZE,result['coefficients'])


def test_auto_propagates_original_trace_failure_diagnostics_without_blind_k2(monkeypatch):
    import geometry
    calls=[]
    original=geometry._fit_lines
    def recorded(lines,size,order,hfov,max_iterations=350):
        calls.append(order)
        return original(lines,size,order,hfov,max_iterations)
    monkeypatch.setattr(geometry,'_fit_lines',recorded)
    malformed=[*observed_edges(),[[1,2],[float('nan'),4],[3,4]]]
    with pytest.raises(CalibrationError) as caught:calibrate(malformed,SIZE,0)
    assert caught.value.code=='invalid_trace'
    assert [item['curve'] for item in caught.value.diagnostics if item['status']=='error']==[8]
    assert calls==[]
    weak=[np.column_stack((np.linspace(100,1800,10),np.full(10,539.5))).tolist()]*3
    with pytest.raises(CalibrationError) as caught:calibrate(weak,SIZE,0)
    assert caught.value.code=='weak_coverage' and caught.value.diagnostics==[]
    assert calls==[]


def test_auto_can_use_validated_recommendation_from_failed_k1(monkeypatch):
    import geometry
    original=geometry.calibrate
    recommendation=dict(order=2,rmsAfter=.5,reason='Independent traces validate the second radial term.',
                        validation=dict(curves=[0,1],rms=.5,baselineRms=2.))
    def manual(curves,size,order=1,hfov=None):
        if order==1:
            raise CalibrationError('k1 leaves too much curvature.','poor_model_fit',[],recommendation)
        return original(curves,size,order,hfov)
    # The auto dispatcher calls the same public fitter for the selected manual order.
    monkeypatch.setattr(geometry,'calibrate',manual)
    result=original(observed_edges((-.4,.15)),SIZE,0)
    assert result['order']==2 and result['modelSelection']=='auto'
    assert result['modelValidation']==recommendation['validation']
    assert 'recommendation' not in result


@pytest.mark.parametrize('order',[False,True,1.,'0',None])
def test_model_order_is_an_explicit_integer_not_a_truth_value(order):
    with pytest.raises(CalibrationError) as caught:
        calibrate(observed_edges(),SIZE,order)
    assert caught.value.code=='invalid_model'
