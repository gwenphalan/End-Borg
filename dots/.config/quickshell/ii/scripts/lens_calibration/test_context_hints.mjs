import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

function method(file,name){
    const text=fs.readFileSync(new URL('../../modules/lensCalibration/'+file,import.meta.url),'utf8');
    const start=text.indexOf('function '+name+'(');assert.ok(start>=0);
    const brace=text.indexOf('{',start);let depth=1,end=brace+1;
    while(depth && end<text.length){if(text[end]==='{')depth++;if(text[end]==='}')depth--;end++;}
    assert.equal(depth,0);return text.slice(start,end);
}
function run(source,name,state){return vm.runInNewContext(source+';'+name+'()',state);}
function keys(hints,key){return hints.some(hint=>hint.keys.includes(key));}

const lens=method('CalibrationWorkspace.qml','buildLensHints');
const ls={stage:'lens',canvasShortcuts:true,hasImage:true,corrected:false,preview:'',viewAtReset:true,drawing:true,activeCurve:-1,selected:-1,selectedNodes:[],curves:[[[0,0],[1,2],[3,4]]],canConnectEndpoints:false,mouse:{containsMouse:false},CurveGeometry:{nearestPolyline:()=>null}};
let hints=run(lens,'buildLensHints',{...ls});
assert.ok(!keys(hints,'Enter') && !keys(hints,'Esc') && !keys(hints,'Del'));
hints=run(lens,'buildLensHints',{...ls,activeCurve:0});assert.ok(keys(hints,'Enter') && keys(hints,'Esc'));
hints=run(lens,'buildLensHints',{...ls,drawing:false,selected:0,selectedNodes:[[0,0]]});assert.ok(keys(hints,'Del') && keys(hints,'← ↑ ↓ →') && !keys(hints,'Enter') && !keys(hints,'M'));
hints=run(lens,'buildLensHints',{...ls,drawing:false,selected:0,selectedNodes:[[0,0]],canConnectEndpoints:true});assert.ok(keys(hints,'M'));
assert.equal(run(lens,'buildLensHints',{...ls,canvasShortcuts:false}).length,0);

const native=method('NativeRegionEditor.qml','buildContextHints');
const ns={keyboardEnabled:true,imageSource:'image.png',imageSize:[100,100],creating:true,draft:[],canFinish:false,workingRegions:[{points:[[0,0],[50,0],[50,50]]}],selectedNodes:[],selectedRegion:-1,hasSnapTargets:false};
hints=run(native,'buildContextHints',{...ns});assert.ok(!keys(hints,'Enter') && !keys(hints,'Del') && !keys(hints,'S'));
hints=run(native,'buildContextHints',{...ns,draft:[[0,0],[50,0],[50,50]],canFinish:true});assert.ok(keys(hints,'Enter') && keys(hints,'Esc'));
hints=run(native,'buildContextHints',{...ns,creating:false,selectedNodes:[[0,0]],selectedRegion:0,hasSnapTargets:true});assert.ok(keys(hints,'Del') && keys(hints,'← ↑ ↓ →') && keys(hints,'S') && !keys(hints,'Enter') && !keys(hints,'F2'));
hints=run(native,'buildContextHints',{...ns,creating:false,selectedRegion:0});assert.ok(keys(hints,'F2') && keys(hints,'Del') && !keys(hints,'← ↑ ↓ →'));
assert.equal(run(native,'buildContextHints',{...ns,keyboardEnabled:false}).length,0);

const spatial=method('SpatialEditor.qml','buildContextHints');
const ss={keyboardEnabled:true,mode:'calibration',corners:[],selectedCorner:-1,placingObject:false,calibrated:false,objects:[],hasSelectedObject:false};
hints=run(spatial,'buildContextHints',{...ss});assert.ok(!keys(hints,'Enter') && !keys(hints,'Del'));
hints=run(spatial,'buildContextHints',{...ss,corners:[[0,0],[1,0],[1,1],[0,1]],selectedCorner:0});assert.ok(keys(hints,'Enter') && keys(hints,'Esc'));
hints=run(spatial,'buildContextHints',{...ss,mode:'boxes',calibrated:true});assert.ok(!keys(hints,'LMB') && !keys(hints,'Enter') && !keys(hints,'Del'));
hints=run(spatial,'buildContextHints',{...ss,mode:'boxes',calibrated:true,objects:[{id:'box'}],hasSelectedObject:true});assert.ok(keys(hints,'LMB') && keys(hints,'Enter') && keys(hints,'Del'));
assert.equal(run(spatial,'buildContextHints',{...ss,keyboardEnabled:false}).length,0);
console.log('Context hints PASS: empty/draft/selected nodes, valid finishing, endpoint joining, rename, snapping, plane/box selection, inactive/modal states');
