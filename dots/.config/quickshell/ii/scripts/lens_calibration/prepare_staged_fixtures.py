"""Create isolated native/spatial UI test data; optionally use a read-only camera image."""
import argparse
import json
from pathlib import Path
import cv2
import numpy as np
from backend import Worker


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image',type=Path)
    args=parser.parse_args()
    folder=Path('/tmp/lens-cap-stage-ui');folder.mkdir(exist_ok=True)
    fixture=json.loads(Path(__file__).with_name('fixtures').joinpath('bed_vision_traces.json').read_text())
    image=cv2.imread(str(args.image)) if args.image else np.full((1080,1920,3),35,np.uint8)
    if image is None or list(image.shape[1::-1])!=fixture['size']:
        raise ValueError('Test image must decode to 1920 × 1080.')
    if not args.image:
        for curve in fixture['curves']:
            cv2.polylines(image,[np.asarray(curve,dtype=np.int32)],False,(160,160,160),2)
    assert cv2.imwrite(str(folder/'reference.png'),image)
    assert cv2.imwrite(str(folder/'extra.jpeg'),image)
    worker=Worker(folder)
    worker.handle(dict(op='open',path=str(folder/'reference.png')))
    worker.handle(dict(op='set_settings',projectSettings=dict(fixture['settings'],order=0)))
    worker.handle(dict(op='save',path=str(folder/'reference.lenscap'),curves=fixture['curves'],calibration=None))
    print(folder)


if __name__=='__main__':main()
