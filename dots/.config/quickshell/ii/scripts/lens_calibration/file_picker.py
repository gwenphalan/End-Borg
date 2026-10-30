"""Lens Cap chooser policy; the native chooser lives in scripts/tool_app."""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tool_app.native_picker import PickerSpec,FileFilter,choose as native_choose,choose_with_history
from history import History,purpose_group


FILTERS={
    'image':FileFilter('Images',('*.png','*.jpg','*.jpeg','*.bmp','*.webp','*.PNG','*.JPG','*.JPEG')),
    'png':FileFilter('PNG image',('*.png',)),
    'json':FileFilter('JSON',('*.json',)),
    'project':FileFilter('Lens Cap project',('*.lenscap','*.lensproject')),
}
DEFAULT_NAMES={'png':'corrected.png','project':'Untitled.lenscap','json':'calibration.json'}


def spec(kind):
    return PickerSpec('org.quickshell.LensCalibration','Lens Cap',(FILTERS[kind],),DEFAULT_NAMES.get(kind))


def choose(mode,kind,folder,multiple=False,name=None):
    return native_choose(spec(kind),mode,folder,multiple,name)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('mode',choices=['open','save'])
    parser.add_argument('kind',choices=list(FILTERS))
    parser.add_argument('folder')
    parser.add_argument('--multiple',action='store_true')
    parser.add_argument('--name')
    parser.add_argument('--purpose')
    args=parser.parse_args()
    try:
        result=choose_with_history(spec(args.kind),args.mode,args.folder,History(),purpose_group(args.purpose or args.kind),args.multiple,args.name)
    except Exception as exc:result=dict(ok=False,error=str(exc))
    print(json.dumps(result),flush=True)


if __name__=='__main__':main()
