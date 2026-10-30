"""Audit bundled axes and regenerate mappings for the shared clock controls.

Requires fontTools for maintenance only. Run --write to update the registry and
calibration JSON. The renderer matches visible height with a uniform scale and
keeps each face's native proportions.
"""
from pathlib import Path
import argparse
import json
from fontTools.ttLib import TTFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--write', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
assets = repo / 'assets/fonts/clock'
profiles = {}
previous_profiles = json.loads((assets / 'calibration.json').read_text())
for source in json.loads((assets / 'sources.json').read_text()):
    font = TTFont(assets / source['slug'] / source['filename'])
    axes = {axis.axisTag: axis for axis in font['fvar'].axes} if 'fvar' in font else {}
    family = font['name'].getDebugName(16) or font['name'].getDebugName(1)
    weight = axes.get('wght')
    width = axes.get('wdth')
    # Kode Mono starts at 400. An interior neutral avoids an inactive lower
    # half of the weight grid while retaining the complete native range.
    neutral_weight = (400 if weight.minValue < 400 < weight.maxValue else (
        weight.minValue + weight.maxValue) / 2) if weight else 400
    # Some families put the default width at an endpoint. Centering that
    # endpoint in a two-sided grid makes one half of the drag do nothing.
    neutral_width = 100
    if width:
        neutral_width = width.defaultValue
        if not width.minValue < neutral_width < width.maxValue:
            neutral_width = (width.minValue + width.maxValue) / 2
    profiles[family] = dict(
        weight=neutral_weight, width=neutral_width,
        weightMin=weight.minValue if weight else 400,
        weightMax=weight.maxValue if weight else 400,
        widthMin=width.minValue if width else 100,
        widthMax=width.maxValue if width else 100,
    )
# Saved clocks may still use former picker families. Keep their native mapping.
profiles.update({family: profile for family, profile in previous_profiles.items()
                 if family not in profiles})
print(json.dumps(profiles, indent=2))
if args.write:
    (assets / 'calibration.json').write_text(json.dumps(profiles, indent=2) + '\n')
    registry = repo / 'modules/common/ClockFonts.qml'
    content = registry.read_text()
    start = content.index('    readonly property var calibration:')
    end = content.index('\n    function profile(', start)
    registry.write_text(content[:start] + '    readonly property var calibration: ('
                        + json.dumps(profiles, indent=8) + ')' + content[end:])
