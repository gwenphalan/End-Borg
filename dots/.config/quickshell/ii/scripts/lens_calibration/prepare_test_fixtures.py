"""Rebuild the synthetic fixtures for lensCalibrationTest.qml; no camera files."""
import json
from pathlib import Path
import cv2
import numpy as np
from backend import Worker
from geometry import distort, output_geometry, original_to_output


def main():
    folder = Path('/tmp/lens-verification')
    folder.mkdir(exist_ok=True)
    size = (1920, 1080)
    image = np.full((1080, 1920, 3), 35, np.uint8)
    curves = []
    for y in [90, 230, 830, 980]:
        points = np.column_stack([np.linspace(180, 1740, 25), np.full(25, y)])
        curve = distort(points, size, [-.32, 0])
        curves.append(curve.tolist())
        cv2.polylines(image, [curve.astype(np.int32)], False, (160, 160, 160), 2)
    for x in [190, 430, 1490, 1730]:
        points = np.column_stack([np.full(25, x), np.linspace(100, 980, 25)])
        curve = distort(points, size, [-.32, 0])
        curves.append(curve.tolist())
        cv2.polylines(image, [curve.astype(np.int32)], False, (160, 160, 160), 2)
    cv2.imwrite(str(folder/'grid.png'), image)
    worker = Worker(folder)
    worker.handle(dict(op='open', path=str(folder/'grid.png')))
    worker.handle(dict(op='save', path=str(folder/'session.json'), curves=curves, calibration=None))
    geometry=output_geometry(size,[-.32,0])
    (folder/'labelme.json').write_text(json.dumps(dict(imageWidth=geometry['size'][0], imageHeight=geometry['size'][1],
        shapes=[dict(label='floor', shape_type='polygon', points=original_to_output([[200, 200], [1700, 200], [900, 900]],size,[-.32,0]).tolist())])))


if __name__ == '__main__':
    main()
