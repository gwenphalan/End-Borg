"""Integration-test only: simulate saving polygons after LabelMe opens PNGs.

Production hands LabelMe an image folder and never creates annotation JSON.
"""
import json
import os
from pathlib import Path
import sys

from PIL import Image
from labelme._label_file import read_label_file


fixture = json.loads(Path(sys.argv[1]).read_text())
target = Path(sys.argv[2])
images = sorted(target.glob('*.png')) if target.is_dir() else [target.with_suffix('.png')]
assert images
for image in images:
    destination = image.with_suffix('.json')
    assert not destination.exists(), 'Initial LabelMe handoff must contain images only'
    width, height = Image.open(image).size
    shapes = [dict(shape, flags=shape.get('flags', {}), group_id=shape.get('group_id'))
              for shape in fixture['shapes']]
    document = dict(version='7.9.1', flags={}, shapes=shapes,
                    imagePath=image.name, imageData=None,
                    imageWidth=width, imageHeight=height)
    temporary = destination.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(document))
    os.replace(temporary, destination)
    # Use the installed application's actual parser, rather than process liveness.
    read_label_file(filename=str(destination))
print(f'Validated {len(images)} simulated LabelMe saves')
