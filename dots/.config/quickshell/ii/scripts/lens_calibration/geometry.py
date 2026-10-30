"""Pixel-preserving Brown radial model: corrected pixels -> original pixels.

K uses max(width,height) as a fixed scale, principal point at image center.
No crop, resizing, EXIF rotation, tangential terms or guessed C101 intrinsics.
"""
from functools import lru_cache
import cv2
import numpy as np
from scipy.optimize import least_squares, minimize
from shapely.geometry import Polygon, box


def matrix(size, hfov=None):
    w, h = size
    if not np.isfinite([w, h]).all() or w < 2 or h < 2:
        raise ValueError('Image dimensions must be at least two pixels.')
    if hfov is not None and (not np.isfinite(hfov) or not 1 <= hfov <= 179):
        raise ValueError('Horizontal field of view must be between 1 and 179 degrees.')
    f = max(w, h) if hfov is None else w/(2*np.tan(np.deg2rad(hfov)/2))
    return np.array([[f, 0, (w-1)/2], [0, f, (h-1)/2], [0, 0, 1.]], dtype=float)


def distort(points, size, coefficients, hfov=None):
    k = matrix(size, hfov)
    p = (np.asarray(points, dtype=float).reshape(-1, 2) - k[:2, 2])/k[0, 0]
    r2 = np.sum(p*p, axis=1)
    a, b = coefficients
    return p*(1+a*r2+b*r2*r2)[:, None]*k[0, 0]+k[:2, 2]


def undistort(points, size, coefficients, hfov=None):
    # Newton inversion with an explicit convergence check (OpenCV's default five
    # iterations are insufficient for subpixel round trips near image corners).
    k = matrix(size, hfov)
    target = (np.asarray(points, dtype=float).reshape(-1, 2)-k[:2, 2])/k[0, 0]
    rd = np.linalg.norm(target, axis=1)
    r = rd.copy()
    a, b = coefficients
    for _ in range(60):
        derivative = 1+3*a*r*r+5*b*r**4
        if np.any(derivative <= 0):
            raise ValueError('Distortion folds within the image; reduce correction.')
        step = (r*(1+a*r*r+b*r**4)-rd)/derivative
        r -= step
        if np.max(np.abs(step), initial=0) < 1e-13:
            break
    if np.any(r < 0) or np.max(np.abs(r*(1+a*r*r+b*r**4)-rd), initial=0) > 1e-9:
        raise ValueError('Distortion inversion did not converge.')
    ratio = np.divide(r, rd, out=np.ones_like(r), where=rd > 0)
    return target*ratio[:, None]*k[0, 0]+k[:2, 2]


def validate_model(size, coefficients, hfov=None):
    c = np.asarray(coefficients, dtype=float)
    if c.shape != (2,) or not np.isfinite(c).all() or np.any(np.abs(c) > 3):
        raise ValueError('Invalid radial coefficients.')
    w, h = size
    corners = np.array([[0, 0], [w-1, 0], [0, h-1], [w-1, h-1]])
    u = undistort(corners, size, c, hfov)
    k = matrix(size, hfov)
    radius = max(np.linalg.norm((u-k[:2, 2])/k[0, 0], axis=1).max(),
                 np.linalg.norm((corners-k[:2, 2])/k[0, 0], axis=1).max())
    squared=[0.,radius*radius]
    if c[1]>0:
        vertex=-3*c[0]/(10*c[1])
        if 0<vertex<squared[-1]:squared.append(vertex)
    if min(1+3*c[0]*t+5*c[1]*t*t for t in squared) < .15:
        raise ValueError('Correction is too close to a non-invertible model.')


def line_residual(points):
    p = points-points.mean(axis=0)
    _, _, v = np.linalg.svd(p, full_matrices=False)
    normal = v[-1]
    if (points[-1, 0]-points[0, 0])*normal[1]-(points[-1, 1]-points[0, 1])*normal[0] < 0:
        normal = -normal
    return p @ normal


class CalibrationError(ValueError):
    """Actionable global failure plus evidence-based, original-index trace details."""
    def __init__(self,message,code='calibration_failed',diagnostics=None,recommendation=None):
        super().__init__(message)
        self.message=message
        self.code=code
        self.diagnostics=list(diagnostics or [])
        self.recommendation=recommendation


def _physical_margin(coefficients,size,hfov):
    """Cover the full source before the radial derivative first falls below .15.

    The first positive root of 1+3*k1*t+5*k2*t²=.15 bounds the monotone branch.
    It must cover both the raw corner radius and its inverse; positive quadratics
    with no crossing remain admissible. This tests the entire interval exactly.
    """
    k=matrix(size,hfov)
    rd=float(np.linalg.norm((np.array(size)-1-k[:2,2])/k[0,0]))
    a,b=coefficients
    roots=[]
    if abs(b)<1e-15:
        if a<0:roots=[-.85/(3*a)]
    else:
        discriminant=9*a*a-20*b*.85
        if discriminant>0:
            root=np.sqrt(discriminant)
            q=-.5*(3*a+np.copysign(root,3*a))
            if q:
                roots=[q/(5*b),.85/q]
    roots=[t for t in roots if t>0]
    if not roots:return 1.
    r=float(np.sqrt(min(roots)))
    distorted=r*(1+a*r*r+b*r**4)
    return min(1.,r/rd-1,distorted/rd-1)


def _fit_lines(lines,size,order,hfov,max_iterations=350):
    count=sum(map(len,lines))
    def residual(parameters):
        coefficients=[parameters[0],parameters[1] if order==2 else 0.]
        try:
            result=np.concatenate([line_residual(undistort(p,size,coefficients,hfov)) for p in lines])
            if np.isfinite(result).all():return result
        except (ValueError,FloatingPointError,np.linalg.LinAlgError):pass
        return np.full(count,1e5+np.linalg.norm(parameters)*1e3)
    if order==1:
        k=matrix(size,hfov)
        radius=float(np.linalg.norm((np.array(size)-1-k[:2,2])/k[0,0]))
        # Exact k1-only full-frame limit at derivative=.15, with a small guard.
        lower=max(-2.,-.85*2.15**2/(27*radius*radius)*(1-1e-5))
        fit=least_squares(residual,np.zeros(1),bounds=([lower],[2.]),loss='soft_l1',
            f_scale=.75,jac='3-point',max_nfev=max_iterations,
            ftol=1e-11,xtol=1e-11,gtol=1e-9)
        parameters=fit.x
        jacobian=fit.jac
        success=fit.success
    else:
        def objective(parameters):
            values=residual(parameters)/.75
            return float(np.sum(2*.75**2*(np.sqrt(1+values*values)-1))/count)
        fit=minimize(objective,np.zeros(2),method='SLSQP',bounds=[(-2.,2.)]*2,
            constraints=[dict(type='ineq',fun=lambda c:_physical_margin(c,size,hfov)-1e-5)],
            options=dict(maxiter=max_iterations,ftol=1e-13))
        parameters=fit.x
        success=fit.success
        columns=[]
        for axis in range(2):
            step=1e-6*max(1.,abs(parameters[axis]))
            delta=np.zeros(2);delta[axis]=step
            columns.append((residual(parameters+delta)-residual(parameters-delta))/(2*step))
        jacobian=np.column_stack(columns)*(1+(residual(parameters)/.75)**2)[:,None]**(-.75)
    coefficients=[float(parameters[0]),float(parameters[1]) if order==2 else 0.]
    validate_model(size,coefficients,hfov)
    if _physical_margin(coefficients,size,hfov)<0:
        raise ValueError('The fitted model does not cover the whole image monotonically.')
    singular=np.linalg.svd(jacobian,compute_uv=False)
    stable=(bool(success) and singular[-1]>=1 and singular[0]/singular[-1]<=1000
            and not np.any(np.abs(parameters)>1.98))
    per_curve=[float(np.sqrt(np.mean(line_residual(undistort(p,size,coefficients,hfov))**2))) for p in lines]
    before=float(np.sqrt(np.mean(residual(np.zeros(order))**2)))
    after=float(np.sqrt(np.mean(residual(parameters)**2)))
    return dict(coefficients=coefficients,stable=stable,rmsBefore=before,rmsAfter=after,
        perCurve=per_curve,limited=_physical_margin(coefficients,size,hfov)<1e-3)


def _recommend_second_order(lines,indices,size,hfov,baseline):
    if len(lines)<5:return None
    try:candidate=_fit_lines(lines,size,2,hfov,180)
    except (ValueError,np.linalg.LinAlgError):return None
    if (not candidate['stable'] or candidate['rmsAfter']>.7*baseline['rmsAfter']
            or baseline['rmsAfter']-candidate['rmsAfter']<.5):return None
    recommendation=dict(order=2,rmsAfter=candidate['rmsAfter'],
        reason='A physically valid k1 + k2 model straightens these traces better than k1 alone.')
    if len(lines)>=6:
        held_out=[];reference=[];checked=[]
        for index in np.unique(np.linspace(0,len(lines)-1,min(4,len(lines)),dtype=int)):
            remaining=lines[:index]+lines[index+1:]
            try:fit=_fit_lines(remaining,size,2,hfov,100)
            except (ValueError,np.linalg.LinAlgError):continue
            if not fit['stable']:continue
            error=line_residual(undistort(lines[index],size,fit['coefficients'],hfov))
            held_out.append(float(np.mean(error*error)))
            reference.append(baseline['perCurve'][index]**2)
            checked.append(indices[index])
        if len(held_out)<2 or np.mean(held_out)>=.8**2*np.mean(reference):return None
        recommendation['validation']=dict(curves=checked,rms=float(np.sqrt(np.mean(held_out))),
            baselineRms=float(np.sqrt(np.mean(reference))))
    return recommendation


def _trace_conflicts(lines,indices,size,order,hfov,fit):
    """Only attribute errors if a stable valid held-out model isolates a conflict."""
    if len(lines)<(4 if order==1 else 6):return []
    rms=np.asarray(fit['perCurve'])
    median=float(np.median(rms));mad=float(np.median(np.abs(rms-median)))*1.4826
    threshold=max(2.,4*median,median+4*mad)
    suspects=[int(i) for i in np.argsort(rms)[::-1] if rms[i]>threshold][:6]
    diagnostics=[]
    for index in suspects:
        try:other=_fit_lines(lines[:index]+lines[index+1:],size,order,hfov,100)
        except (ValueError,np.linalg.LinAlgError):continue
        if not other['stable'] or other['rmsAfter']>2.:continue
        points=undistort(lines[index],size,other['coefficients'],hfov)
        held_out=float(np.sqrt(np.mean(line_residual(points)**2)))
        if held_out>max(3.,4*other['rmsAfter']):
            diagnostics.append(dict(curve=indices[index],status='error',code='conflicting_trace',rms=held_out,
                othersRms=other['rmsAfter'],message='This trace conflicts with the other traces. Check its points and whether the edge is straight in the real world.'))
    return diagnostics


def calibrate(curves,size,order=1,hfov=None):
    if type(order) is not int or order not in (0,1,2):
        raise CalibrationError('Choose Auto, k1 or k1 + k2.','invalid_model')
    if order==0:
        baseline=None
        try:
            baseline=calibrate(curves,size,1,hfov)
            recommendation=baseline.get('recommendation')
        except CalibrationError as error:
            if not error.recommendation:
                raise
            recommendation=error.recommendation
        if recommendation:
            result=calibrate(curves,size,2,hfov)
            result['selectionReason']='Selected k1 + k2: '+recommendation['reason']
            if recommendation.get('validation'):
                result['modelValidation']=recommendation['validation']
        else:
            result=baseline
            result['selectionReason']=('Selected k1: fewer than five usable traces support the simpler model.'
                if result['usedCurves']<5 else
                'Selected k1: the additional radial term has no validated, meaningful improvement.')
        result.pop('recommendation',None)
        result['modelSelection']='auto'
        return result
    diagnostics=[]
    if order not in (1,2):raise CalibrationError('Choose k1 or k1 + k2.','invalid_model')
    try:matrix(size,hfov)
    except (ValueError,TypeError) as error:raise CalibrationError(str(error),'invalid_settings') from error
    lines=[];indices=[]
    if not isinstance(curves,(list,tuple,np.ndarray)):
        raise CalibrationError('Trace data must be a list of curves.','invalid_traces')
    w,h=size
    for index,curve in enumerate(curves):
        try:p=np.asarray(curve,dtype=float)
        except (ValueError,TypeError):
            diagnostics.append(dict(curve=index,status='error',code='invalid_trace',message='Trace points must be finite x/y coordinates.'));continue
        if p.size==0:
            diagnostics.append(dict(curve=index,status='ignored',code='empty_trace',message='Empty trace ignored.'));continue
        if p.ndim!=2 or p.shape[1]!=2:
            diagnostics.append(dict(curve=index,status='error',code='invalid_trace',message='Trace points must be x/y coordinate pairs.'));continue
        invalid=~np.isfinite(p).all(axis=1)
        outside=np.any((p<0)|(p>[w-1,h-1]),axis=1)
        if np.any(invalid) or np.any(outside):
            bad=int(np.flatnonzero(invalid|outside)[0])
            diagnostics.append(dict(curve=index,point=bad,status='error',code='non_finite_point' if invalid[bad] else 'point_outside_image',
                message='Trace contains a non-finite point.' if invalid[bad] else 'Trace point lies outside the original image.'));continue
        _,unique=np.unique(p,axis=0,return_index=True)
        p=p[np.sort(unique)]
        if len(p)<3:
            diagnostics.append(dict(curve=index,status='ignored',code='incomplete_trace',distinctPoints=len(p),
                message='At least three distinct points are needed to measure curvature.'));continue
        lines.append(p);indices.append(index)
    if any(item['status']=='error' for item in diagnostics):
        raise CalibrationError('Fix the invalid trace points highlighted in the canvas. No correction was applied.','invalid_trace',diagnostics)
    if len(lines)<(3 if order==1 else 5):
        raise CalibrationError('Use at least three traces (five for k1 + k2) with three distinct points each. Two-point traces cannot measure curvature.','insufficient_traces',diagnostics)
    if np.any(np.ptp(np.concatenate(lines),axis=0)<.25*np.array(size)):
        raise CalibrationError('The traces do not span both image axes. Add independent edges farther apart; no correction was applied.','weak_coverage',diagnostics)
    try:fit=_fit_lines(lines,size,order,hfov)
    except (ValueError,np.linalg.LinAlgError) as error:
        raise CalibrationError('No physically invertible correction could be fitted over the whole image. Check the model and HFOV settings, then add independent edges. No correction was applied.','non_invertible_model',diagnostics) from error
    check_second=fit['limited'] or fit['rmsAfter']>1. or max(fit['perCurve'])>2.
    recommendation=_recommend_second_order(lines,indices,size,hfov,fit) if order==1 and check_second else None
    if not fit['stable']:
        conflicts=[] if recommendation else _trace_conflicts(lines,indices,size,order,hfov,fit)
        message=('The highlighted trace conflicts with otherwise stable constraints. Check its points; no correction was applied.' if conflicts else
                 'The traces provide weak or unstable constraints. Add long off-center edges, or use k1 only. No correction was applied.')
        raise CalibrationError(message,'weak_constraints',diagnostics+conflicts,recommendation)
    if fit['rmsAfter']>max(2.,.7*fit['rmsBefore']) and fit['rmsBefore']>.5:
        conflicts=[] if recommendation or fit['limited'] else _trace_conflicts(lines,indices,size,order,hfov,fit)
        message=('The selected model leaves systematic curvature. Try k1 + k2; no correction was applied.' if recommendation else
                 'These traces do not fit the selected radial model well enough. Check the highlighted traces, or add independent edges. No correction was applied.' if conflicts else
                 'These traces do not fit the selected radial model well enough. Check the model, HFOV and edge placement; no individual trace was identified as the cause. No correction was applied.')
        raise CalibrationError(message,'poor_model_fit',diagnostics+conflicts,recommendation)
    warnings=[]
    if fit['limited']:
        warnings.append('The k1 correction reached its full-image invertibility limit; remaining curvature may need k1 + k2.' if order==1 else 'The fit reached its full-image invertibility limit; check edge placement and model assumptions.')
    elif not recommendation and len(lines)>=4:
        values=np.asarray(fit['perCurve']);median=float(np.median(values));mad=float(np.median(np.abs(values-median)))*1.4826
        for local,value in enumerate(values):
            if value>max(2.,4*median,median+4*mad):
                diagnostics.append(dict(curve=indices[local],status='warning',code='high_residual',rms=float(value),
                    message='This trace retains more curvature than the others. Check point placement.'))
    if recommendation:warnings.append(recommendation['reason'])
    result=dict(coefficients=fit['coefficients'],rmsBefore=fit['rmsBefore'],rmsAfter=fit['rmsAfter'],
        model='brown-radial',order=order,fixedCenter=True,cameraMatrix=matrix(size,hfov).tolist(),hfov=hfov,
        usedCurves=len(lines),ignoredCurves=sum(item['status']=='ignored' for item in diagnostics),
        diagnostics=diagnostics,warnings=warnings,limitedByModel=fit['limited'])
    if recommendation:result['recommendation']=recommendation
    return result


@lru_cache(maxsize=32)
def _output_geometry_cached(size, coefficients, hfov=None):
    validate_model(size, coefficients, hfov)
    w, h = size
    if max(size) >= 32767 or w*h > 100_000_000:
        raise ValueError('Expanded canvas exceeds safe image dimensions.')
    if coefficients == (0., 0.):
        return (0, 0), size
    # Dense perimeter sampling catches extrema along sides, not only corners.
    xs = np.linspace(0, w-1, int(np.ceil((w-1)/.25))+1)
    ys = np.linspace(0, h-1, int(np.ceil((h-1)/.25))+1)
    perimeter = np.concatenate((np.column_stack((xs, np.zeros_like(xs))),
        np.column_stack((np.full_like(ys, w-1), ys)),
        np.column_stack((xs, np.full_like(xs, h-1))),
        np.column_stack((np.zeros_like(ys), ys))))
    boundary = undistort(perimeter, size, coefficients, hfov)
    lower = np.floor(boundary.min(axis=0)).astype(np.int64)-1
    upper = np.ceil(boundary.max(axis=0)).astype(np.int64)+1
    output_size = upper-lower+1
    if np.any(output_size < 2) or np.any(output_size >= 32767) or np.prod(output_size) > 100_000_000:
        raise ValueError('Expanded canvas exceeds safe image dimensions.')
    return tuple(int(v) for v in lower), tuple(int(v) for v in output_size)


def output_geometry(size, coefficients, hfov=None):
    """Full source coverage at original pixel scale; origin is in K's pixel plane."""
    size = tuple(int(v) for v in size)
    matrix(size, hfov)
    coefficients = tuple(float(v) for v in coefficients)
    origin, output_size = _output_geometry_cached(size, coefficients, hfov)
    kout = matrix(size, hfov)
    kout[:2, 2] -= origin
    return dict(origin=list(origin), size=list(output_size), cameraMatrix=kout.tolist())


def original_to_output(points, size, coefficients, hfov=None):
    return undistort(points, size, coefficients, hfov)-output_geometry(size, coefficients, hfov)['origin']


def output_to_original(points, size, coefficients, hfov=None):
    return distort(np.asarray(points, dtype=float)+output_geometry(size, coefficients, hfov)['origin'], size, coefficients, hfov)


def corrected_image(image, coefficients, hfov=None):
    h, w = image.shape[:2]
    geometry = output_geometry((w, h), coefficients, hfov)
    k = matrix((w, h), hfov)
    kout = np.array(geometry['cameraMatrix'], dtype=float)
    d = np.array([*coefficients, 0., 0., 0.])
    x, y = cv2.initUndistortRectifyMap(k, d, None, kout, tuple(geometry['size']), cv2.CV_32FC1)
    return cv2.remap(image, x, y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)


def densify(points, step=2.):
    points = np.asarray(points, dtype=float)
    if points.ndim != 2 or points.shape[1] != 2 or len(points) < 3 or not np.isfinite(points).all():
        raise ValueError('Invalid LabelMe polygon.')
    if not np.isfinite(step) or step <= 0:
        raise ValueError('Polygon sampling step must be positive.')
    if len(np.unique(points, axis=0)) < 3 or np.linalg.matrix_rank(points-points[0]) < 2:
        raise ValueError('Polygon needs at least three distinct, non-collinear vertices.')
    result = []
    for a, b in zip(points, np.roll(points, -1, axis=0)):
        n = max(1, int(np.ceil(np.linalg.norm(b-a)/step)))
        result.extend(a+(b-a)*t for t in np.arange(n)/n)
    return np.array(result)


def labelme_regions(document, size, coefficients, hfov=None):
    geometry = output_geometry(size, coefficients, hfov)
    if [document.get('imageWidth'), document.get('imageHeight')] != geometry['size']:
        raise ValueError('LabelMe dimensions differ from the corrected image.')
    validate_model(size, coefficients, hfov)
    regions = []
    boundary = box(0., 0., float(size[0]-1), float(size[1]-1))
    reserved = {shape.get('label', '') for shape in document.get('shapes', [])}
    used = set()
    for shape in document.get('shapes', []):
        if shape.get('shape_type', 'polygon') != 'polygon':
            raise ValueError('Only LabelMe polygons are supported.')
        source_points = np.asarray(shape['points'], dtype=float)
        if (source_points.ndim != 2 or source_points.shape[1] != 2 or
                len(source_points) < 3 or not np.isfinite(source_points).all()):
            raise ValueError('Invalid LabelMe polygon.')
        source_polygon = Polygon(source_points)
        if not source_polygon.is_valid:
            raise ValueError('LabelMe polygon is self-intersecting.')
        if source_polygon.is_empty or source_polygon.area <= 1e-12:
            continue
        # LabelMe permits nodes beyond the image. Intersect edges with the
        # corrected viewport before sampling/mapping; clamping vertices changes
        # the region and mapping arbitrarily distant nodes can fold the model.
        corrected_boundary = box(0., 0., *(np.array(geometry['size'], dtype=float)-1))
        source_clipped = source_polygon.intersection(corrected_boundary)
        source_components = ([source_clipped] if source_clipped.geom_type == 'Polygon' else
            [part for part in getattr(source_clipped, 'geoms', []) if part.geom_type == 'Polygon'])
        components = []
        retain_order = len(source_components) == 1 and corrected_boundary.covers(source_polygon)
        for source_component in source_components:
            if source_component.area <= 1e-12:
                continue
            p = densify(source_points if retain_order else source_component.exterior.coords[:-1])
            mapped = output_to_original(p, size, coefficients, hfov)
            polygon = Polygon(mapped)
            if not polygon.is_valid:
                raise ValueError('LabelMe polygon is self-intersecting after mapping.')
            if polygon.is_empty or polygon.area <= 1e-12:
                continue
            clipped = polygon.intersection(boundary)
            components.extend([clipped] if clipped.geom_type == 'Polygon' else
                [part for part in getattr(clipped, 'geoms', []) if part.geom_type == 'Polygon'])
        components = sorted((part for part in components if part.area > 1e-12),
                            key=lambda part: (-part.area, part.bounds))
        label = shape.get('label', '')
        suffix = 2
        for index, component in enumerate(components):
            if len(component.interiors):
                raise ValueError('Frigate regions cannot contain polygon holes.')
            output_label = label
            if index:
                output_label = f'{label}_{suffix}'
                while output_label in reserved or output_label in used:
                    suffix += 1
                    output_label = f'{label}_{suffix}'
                suffix += 1
            used.add(output_label)
            if retain_order and len(components)==1 and boundary.covers(polygon):
                # Retain point order and precision for an entirely inside polygon.
                original_points, corrected_points = mapped, p
            else:
                # Intersection introduces straight sensor-border edges with
                # only their endpoints. Sample those edges before undistorting:
                # the corrected image boundary is curved, not an endpoint chord.
                original_points = densify(component.exterior.coords[:-1])
                corrected_points = original_to_output(original_points, size, coefficients, hfov)
            normalized = original_points/np.array(size)
            regions.append(dict(label=output_label, sourceLabel=label,
                points=original_points.tolist(), correctedPoints=corrected_points.tolist(),
                normalized=normalized.tolist(),
                coordinates=','.join(f'{v:.8f}' for v in normalized.ravel())))
    return regions


def spatial_camera_matrix(size, coefficients, hfov=None):
    """Pose intrinsics: manufacturer HFOV spans the distorted source, not its corrected raster.

    Lens K remains the radial model's normalization. The physical focal length
    uses undistorted mid-edge rays and leaves corrected pixel coordinates intact.
    """
    k=np.asarray(output_geometry(size,coefficients,hfov)['cameraMatrix'],dtype=float)
    if hfov is not None:
        w,h=size
        edges=undistort([[0,(h-1)/2],[w-1,(h-1)/2]],size,coefficients,hfov)
        # Pixel-centre rays span w-1; the specified FOV spans w pixel widths.
        span=(edges[1,0]-edges[0,0])*w/(w-1)
        focal=span/(2*np.tan(np.deg2rad(hfov)/2))
        k[0,0]=k[1,1]=focal
    return k.tolist()
