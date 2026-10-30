// Exercise the exact QML drawing helper without a compositor or dependencies.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const filename = new URL('../../modules/lensCalibration/CurveGeometry.js', import.meta.url);
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(filename, 'utf8').replace(/^\.pragma library\s*/, ''), context);

const points = [[0, 0], [10, .7], [20, -.6], [30, .5], [40, 0]];
const original = JSON.stringify(points);
const smooth = context.denoise(points, 1);
assert.equal(JSON.stringify(points), original, 'Smoothing must not modify annotations');
assert.equal(JSON.stringify(smooth[0]), JSON.stringify(points[0]));
assert.equal(JSON.stringify(smooth.at(-1)), JSON.stringify(points.at(-1)));
assert(smooth.reduce((sum, p) => sum + Math.abs(p[1]), 0) < points.reduce((sum, p) => sum + Math.abs(p[1]), 0));
smooth.forEach((p, i) => assert(Math.hypot(p[0]-points[i][0], p[1]-points[i][1]) <= 1+1e-12));
for (const input of [[], [[0, 0]], [[0, 0], [1, 1]], [[0, 0], [0, 0], [10, 0]]])
    for (const p of context.denoise(input)) assert(p.every(Number.isFinite));
const hit = context.nearestPolyline([[0, 0], [10, 0], [10, 10]], [10.2, 4], 1);
assert.equal(hit.index, 1);
assert(Math.hypot(hit.point[0]-10, hit.point[1]-4) < 1e-12);
assert.equal(context.nearestPolyline(points, [500, 500], 1), null);
console.log('Curve display smoothing and edit-segment geometry passed');
