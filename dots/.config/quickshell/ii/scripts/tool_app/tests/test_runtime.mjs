import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../../modules/common/tool_app');
function load(name) {
    let source=fs.readFileSync(path.join(root,name),'utf8').replace(/^\.pragma library\s*/,'');
    const ctx=vm.createContext({});
    source=source.replace(/^\.import "([^"]+)" as (\w+)\s*$/gm,(_,file,alias)=>{ctx[alias]=load(file);return '';});
    vm.runInContext(source,ctx);return ctx;
}
const definition=load('ToolDefinition.js');
assert.equal(definition.evaluate({all:['open',{not:'busy'}]},{open:true,busy:false}),true);
assert.equal(definition.evaluate('missing',{}),false);
assert.equal(definition.evaluate({eq:['mode','edit']},{mode:'draw'}),false);
assert.equal(definition.evaluate({any:['ready','selected']},{selected:true}),true);
assert.equal(definition.validateSetting({type:'real',min:0,max:10},Infinity),'Expected a finite real');
assert.equal(definition.validateSetting({type:'int'},1.5),'Expected a finite int');
assert.equal(definition.validateSetting({type:'bool'},'false'),'Expected a boolean');
assert.equal(definition.validateSetting({type:'string',choices:[{value:'a'}]},'b'),'Choose an available value');
assert.equal(JSON.stringify(definition.flattenToolbar([{actions:['a']},{actions:['b']},{stretch:true},{actions:['c']}])),'[{"action":"a"},{"separator":true},{"action":"b"},{"stretch":true},{"action":"c"}]');
const selection=load('ToolPointSelection.js');
const points=[[10,10],[20,20],[30,30]],before=JSON.stringify(points);
assert.equal(JSON.stringify(selection.centroid(points,[0,1,2])),'[20,20]');
assert.equal(JSON.stringify(selection.translate(points,[0,1,2],100,100,[100,100])),'[[79,79],[89,89],[99,99]]');
assert.equal(JSON.stringify(selection.translate(points,[0,1,2],-100,0,[100,100])),'[[0,10],[10,20],[20,30]]');
assert.equal(JSON.stringify(selection.translate(points,[1],5,0,[100,100])),'[[10,10],[25,20],[30,30]]');
assert.equal(JSON.stringify(points),before);
console.log('Declarative state, validation, toolbar grouping, centroid and bounded group movement passed');

// Reusable multi-polyline selection: stale nodes, modifier semantics, precision
// and bounded group movement share no application-specific state.
const plain=value=>JSON.parse(JSON.stringify(value));
const lines=[[[10,10],[20,20],[30,30]],[[40,40],[50,50]],[[5,70],[15,80]]];
const originalLines=JSON.stringify(lines);
assert.deepEqual(plain(selection.normalizeNodes(lines,[[0,1],[0,1],[1,0],[-1,0],[0,99],null,[1.5,0],[0,NaN]])),[[0,1],[1,0]]);
let selected=selection.selectNode(lines,[],[0,1]);
assert.deepEqual(plain(selected.nodes),[[0,1]]);
assert.deepEqual(plain(selected.primary),[0,1]);
selected=selection.selectNode(lines,selected.nodes,[1,0],{toggle:true});
assert.deepEqual(plain(selected.nodes),[[0,1],[1,0]]);
assert.deepEqual(plain(selected.primary),[1,0]);
selected=selection.toggleNode(lines,selected.nodes,[1,0]);
assert.deepEqual(plain(selected.nodes),[[0,1]]);
assert.deepEqual(plain(selected.primary),[0,1]);
selected=selection.selectNode(lines,selected.nodes,[1,1],{wholePolyline:true});
assert.deepEqual(plain(selected.nodes),[[1,0],[1,1]]);
assert.equal(selected.wholePolyline,true);
assert.deepEqual(plain(selection.selectNode(lines,selected.nodes,[1,0]).nodes),[[1,0],[1,1]]);
assert.deepEqual(plain(selection.selectNode(lines,selected.nodes,[1,0]).primary),[1,0]);
assert.deepEqual(plain(selection.selectNode(lines,selected.nodes,[1,0],{preserveGroup:false}).nodes),[[1,0]]);
assert.deepEqual(plain(selection.selectNode(lines,selected.nodes,[0,0],{toggle:true,wholePolyline:true}).nodes),[[1,0],[1,1],[0,0]]);
assert.deepEqual(plain(selection.selectNode(lines,selected.nodes,[-1,-1],{toggle:true}).nodes),[[1,0],[1,1]]);
assert.deepEqual(plain(selection.selectNode(lines,selected.nodes,[-1,-1]).nodes),[]);
assert.deepEqual(plain(selection.centroidNodes(lines,[[0,0],[0,0],[1,1]])),[30,30]);
assert.deepEqual(plain(selection.centroidNodes(lines,[])),[0,0]);
let moved=selection.translateNodes(lines,[[0,0],[1,1],[0,0]],100,100,[100,100]);
assert.deepEqual(plain(moved.delta),[49,49]);
assert.deepEqual(plain(moved.polylines[0][0]),[59,59]);
assert.deepEqual(plain(moved.polylines[1][1]),[99,99]);
assert.deepEqual(plain(moved.polylines[0][1]),[20,20]);
assert.deepEqual(plain(moved.polylines[2]),lines[2]);
assert.deepEqual(plain(moved.centroid),[79,79]);
assert.equal(moved.changed,true);
moved=selection.translateNodes(lines,[[0,0],[1,1]],-100,-100,[100,100]);
assert.deepEqual(plain(moved.delta),[-10,-10]);
assert.deepEqual(plain(moved.polylines[1][1]),[40,40]);
assert.equal(selection.translateNodes(lines,[],5,5,[100,100]).changed,false);
assert.equal(selection.translateNodes(lines,[[0,0]],0,0,[100,100]).changed,false);
assert.throws(()=>selection.translateNodes(lines,[[0,0],[1,1]],1,1,[20,20]),/do not fit/);
assert.throws(()=>selection.translateNodes(lines,[[0,0]],NaN,0,[100,100]),/finite/);
assert.throws(()=>selection.translateNodes(lines,[[0,0]],1,1,[0,100]),/positive/);
assert.equal(JSON.stringify(lines),originalLines);

const polyline=load('ToolPolyline.js');
const a=[[0,0],[1,0],[2,0]], b=[[10,0],[11,0],[12,0]];
for (const first of [0,2]) for (const second of [0,2]) {
    const input=[a,b], before=JSON.stringify(input);
    const joined=polyline.joinSelectedEndpoints(input,[[0,first],[1,second]]);
    const expectedA=first===0 ? a.slice().reverse() : a;
    const expectedB=second===0 ? b : b.slice().reverse();
    assert.equal(joined.ok,true);
    assert.equal(polyline.canJoinSelectedEndpoints(input,[[0,first],[1,second]]),true);
    assert.deepEqual(plain(joined.polylines),[expectedA.concat(expectedB)]);
    assert.deepEqual(plain(joined.nodes),[[0,2],[0,3]]);
    assert.deepEqual(plain(joined.selection.primary),[0,3]);
    assert.equal(joined.joinedIndex,0);
    assert.equal(joined.joinPointIndex,2);
    assert.equal(joined.deduplicated,false);
    assert.equal(JSON.stringify(input),before);
}
const ordered=[[[90,0],[91,0]],a,[[92,0],[93,0]],b,[[94,0],[95,0]]];
const orderedBefore=JSON.stringify(ordered);
const joined=polyline.joinSelectedEndpoints(ordered,[[3,2],[1,0]]);
assert.equal(joined.joinedIndex,1);
assert.deepEqual(plain(joined.sourceIndices),[3,1]);
assert.deepEqual(plain(joined.indexMap),[0,1,2,1,3]);
assert.deepEqual(plain(joined.polylines),[ordered[0],b.concat(a),ordered[2],ordered[4]]);
assert.equal(JSON.stringify(ordered),orderedBefore);
assert.notEqual(joined.polylines[0],ordered[0]);
assert.notEqual(joined.polylines[0][0],ordered[0][0]);
const coincident=[a,[[2,0],[3,0],[4,0]]];
const dedup=polyline.joinSelectedEndpoints(coincident,[[0,2],[1,0]]);
assert.equal(dedup.deduplicated,true);
assert.deepEqual(plain(dedup.polylines),[[[0,0],[1,0],[2,0],[3,0],[4,0]]]);
assert.deepEqual(plain(dedup.nodes),[[0,2]]);
const near=[a,[[2+5e-10,0],[3,0]]];
assert.equal(polyline.joinSelectedEndpoints(near,[[0,2],[1,0]]).deduplicated,true);
assert.equal(polyline.joinSelectedEndpoints(near,[[0,2],[1,0]],0).deduplicated,false);
for (const [input,nodes] of [
    [[a,b],[[0,0],[0,2]]],
    [[a,b],[[0,1],[1,0]]],
    [[a,b],[[0,0],[0,0]]],
    [[a,b],[[0,0],[2,0]]],
    [[a,b],[[0,0]]],
    [[[[0,0]],b],[[0,0],[1,0]]],
    [[[[0,0],[1,0],[0,0]],b],[[0,0],[1,0]]],
    [[[[NaN,0],[1,0]],b],[[0,0],[1,0]]],
]) {
    const before=JSON.stringify(input);
    const result=polyline.joinSelectedEndpoints(input,nodes);
    assert.equal(result.ok,false);
    assert.equal(typeof result.error,'string');
    assert.equal(polyline.canJoinSelectedEndpoints(input,nodes),false);
    assert.equal(JSON.stringify(input),before);
}
assert.equal(polyline.joinSelectedEndpoints([a,b],[[0,2],[1,0]],-1).ok,false);
assert.equal(polyline.joinSelectedEndpoints([a,b],[[0,2],[1,0]],Infinity).ok,false);
console.log('Node-pair selection, modifier behavior, cross-polyline centroid/translation and all endpoint-join orientations passed');

// Exercise actual shared field methods without constructing a QtQuick item.
const pointSource=fs.readFileSync(path.join(root,'ToolPointCoordinates.qml'),'utf8');
const field={position:[12.123456,20],decimals:3,bounds:[100,100],edits:[],errors:[]};
field.coordinateEdited=(axis,value)=>field.edits.push([axis,value]);
field.invalid=message=>field.errors.push(message);
const fieldContext=vm.createContext(field);
for(const name of ['formatted','commit']) {
    const start=pointSource.indexOf('    function '+name+'(');
    let end=pointSource.indexOf('{',start),depth=1;
    while(depth && ++end<pointSource.length) {if(pointSource[end]==='{')depth++;if(pointSource[end]==='}')depth--;}
    vm.runInContext(pointSource.slice(start,end+1),fieldContext);
}
assert.equal(fieldContext.formatted(12.123456),'12.123');
assert.equal(fieldContext.commit(0,'12.123'),false);
assert.equal(field.edits.length,0,'focusing a rounded value must not quantize model coordinates');
assert.equal(fieldContext.commit(0,'12.5'),true);
assert.deepEqual(field.edits,[[0,12.5]]);
assert.equal(fieldContext.commit(1,'100'),false);
assert.equal(fieldContext.commit(1,''),false);
assert.equal(fieldContext.commit(1,'Infinity'),false);
assert.equal(field.errors.length,3);
console.log('Shared coordinate field precision, unchanged-draft handling, finite input and bounds passed');
