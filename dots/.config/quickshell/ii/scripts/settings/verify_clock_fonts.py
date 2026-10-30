"""Verify the curated bundled fonts and the controls they actually support.

Maintenance dependency: fontTools. The picker must not claim a native axis that
is absent or fails to change clock glyphs.
"""
from pathlib import Path
from hashlib import sha256
from itertools import product
import json
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import DecomposingRecordingPen

assets = Path(__file__).resolve().parents[2] / 'assets/fonts/clock'
sources = json.loads((assets / 'sources.json').read_text())
calibration = json.loads((assets / 'calibration.json').read_text())
assert len(sources) == 6, 'The curated picker must contain six faces'
assert len({(s['family'], s['italic']) for s in sources}) == 6

supported = {
    'Google Sans Flex': ('wght', 'wdth', 'ROND'),
    'Kode Mono': ('wght', 'wdth', 'ROND'),
    'Fraunces': ('wght', 'SOFT'),
    'Mona Sans': ('wght', 'wdth'),
    'Roboto Serif': ('wght', 'wdth'),
    'Science Gothic': ('wght', 'wdth'),
}


def outline(font, glyph, location):
    glyphs = font.getGlyphSet(location=location)
    pen = DecomposingRecordingPen(glyphs)
    glyphs[glyph].draw(pen)
    return pen.value, glyphs[glyph].width


for source in sources:
    folder = assets / source['slug']
    path = folder / source['filename']
    assert sha256(path.read_bytes()).hexdigest() == source['sha256'], path
    assert 'SIL OPEN FONT LICENSE' in (folder / 'OFL.txt').read_text().upper()
    font = TTFont(path)
    family = font['name'].getDebugName(16) or font['name'].getDebugName(1)
    assert family == source['family'], (family, source['family'])
    assert bool(font['head'].macStyle & 2) == source['italic'], source['slug']
    axes = {axis.axisTag: axis for axis in font['fvar'].axes} if 'fvar' in font else {}
    profile = calibration[family]
    for tag, field in (('wght', 'weight'), ('wdth', 'width')):
        if tag not in axes:
            continue
        axis = axes[tag]
        assert profile[field + 'Min'] == axis.minValue
        assert profile[field + 'Max'] == axis.maxValue
        assert axis.minValue < profile[field] < axis.maxValue, (
            family, tag, 'the grid center must be inside the native range')
    tags = supported[family]
    assert set(tags) <= axes.keys(), (family, tags, list(axes))
    cmap = font.getBestCmap()
    digits = {char: cmap[ord(char)] for char in '0123456789:'}
    for tag in tags:
        axis = axes[tag]
        changed = [char for char, glyph in digits.items()
                   if outline(font, glyph, {tag: axis.minValue})
                   != outline(font, glyph, {tag: axis.maxValue})]
        assert changed, (source['slug'], tag, 'axis does not change clock glyphs')
    for values in product(*((axes[tag].minValue, axes[tag].maxValue) for tag in tags)):
        location = dict(zip(tags, values))
        for char, glyph in digits.items():
            drawing, advance = outline(font, glyph, location)
            assert drawing and advance > 0, (source['slug'], char, location)
    print(f"{source['name']}: native {', '.join(tags) if tags else 'none (static face)'} and {2 ** len(tags)} control extremes verified")
