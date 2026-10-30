.pragma library

function centroid(points, indices) {
    if (!indices.length) return [0,0];
    return indices.reduce((sum,i) => [sum[0]+points[i][0]/indices.length,sum[1]+points[i][1]/indices.length],[0,0]);
}
// Preserve relative spacing when a group reaches a boundary; clamp the group delta.
function translate(points, indices, dx, dy, size) {
    const result=points.map(point=>point.slice());
    if (!indices.length) return result;
    const chosen=indices.map(i=>points[i]);
    dx=Math.max(-Math.min.apply(null,chosen.map(p=>p[0])),Math.min(size[0]-1-Math.max.apply(null,chosen.map(p=>p[0])),dx));
    dy=Math.max(-Math.min.apply(null,chosen.map(p=>p[1])),Math.min(size[1]-1-Math.max.apply(null,chosen.map(p=>p[1])),dy));
    for (const i of indices) {result[i][0]+=dx;result[i][1]+=dy;}
    return result;
}

// Node selections are [polylineIndex, pointIndex] pairs. Stale/duplicate nodes
// are ignored so a selection remains safe after document edits.
function normalizeNodes(polylines, nodes) {
    if (!Array.isArray(polylines) || !Array.isArray(nodes)) return [];
    const result=[], seen={};
    for (const node of nodes) {
        if (!Array.isArray(node) || node.length!==2 || !Number.isInteger(node[0]) || !Number.isInteger(node[1])) continue;
        const line=polylines[node[0]];
        if (node[0]<0 || !Array.isArray(line) || node[1]<0 || node[1]>=line.length) continue;
        const point=line[node[1]];
        if (!Array.isArray(point) || point.length<2 || !Number.isFinite(point[0]) || !Number.isFinite(point[1])) continue;
        const key=node[0]+":"+node[1];
        if (!seen[key]) {seen[key]=true;result.push(node.slice());}
    }
    return result;
}

function wholePolylineNodes(polylines, index) {
    if (!Array.isArray(polylines) || !Number.isInteger(index) || index<0 || !Array.isArray(polylines[index])) return [];
    return normalizeNodes(polylines,polylines[index].map((point,i)=>[index,i]));
}

function sameNodes(a,b) {
    return a.length===b.length && a.every((node,i)=>node[0]===b[i][0] && node[1]===b[i][1]);
}

function selectionResult(polylines, nodes, primary, previous) {
    nodes=normalizeNodes(polylines,nodes);
    const chosen=normalizeNodes(polylines,[primary]);
    primary=chosen.length && nodes.some(node=>sameNodes([node],chosen)) ? chosen[0] : nodes.length ? nodes[nodes.length-1].slice() : [-1,-1];
    const whole=nodes.length>0 && nodes.every(node=>node[0]===nodes[0][0]) && nodes.length===polylines[nodes[0][0]].length;
    return {nodes:nodes,primary:primary,wholePolyline:whole,changed:!sameNodes(nodes,normalizeNodes(polylines,previous || []))};
}

function toggleNode(polylines, nodes, node) {
    const previous=normalizeNodes(polylines,nodes), hit=normalizeNodes(polylines,[node]);
    if (!hit.length) return selectionResult(polylines,previous,null,previous);
    const exists=previous.some(item=>sameNodes([item],hit));
    const next=exists ? previous.filter(item=>!sameNodes([item],hit)) : previous.concat(hit);
    return selectionResult(polylines,next,null,previous);
}

// The host supplies modifier semantics rather than Qt-specific key constants.
// Toggle takes precedence; Shift-style wholePolyline replaces the selection;
// ordinary clicks on a selected node preserve the current group by default.
function selectNode(polylines, nodes, node, options) {
    options=options || {};
    const previous=normalizeNodes(polylines,nodes), hit=normalizeNodes(polylines,[node]);
    if (options.toggle) return toggleNode(polylines,previous,node);
    if (!hit.length) return selectionResult(polylines,[],null,previous);
    const keep=options.preserveGroup!==false && previous.some(item=>sameNodes([item],hit));
    const next=options.wholePolyline ? wholePolylineNodes(polylines,hit[0][0]) : keep ? previous : hit;
    return selectionResult(polylines,next,hit[0],previous);
}

function centroidNodes(polylines, nodes) {
    const chosen=normalizeNodes(polylines,nodes).map(node=>polylines[node[0]][node[1]]);
    return centroid(chosen,chosen.map((point,i)=>i));
}

function copyPolylines(polylines) {
    if (!Array.isArray(polylines)) throw new TypeError("Expected an array of polylines.");
    return polylines.map(line=> {
        if (!Array.isArray(line)) throw new TypeError("Expected an array of points.");
        return line.map(point=> {
            if (!Array.isArray(point) || point.length<2 || !Number.isFinite(point[0]) || !Number.isFinite(point[1])) throw new TypeError("Expected finite 2D points.");
            return point.slice();
        });
    });
}

function translateNodes(polylines, nodes, dx, dy, size) {
    if (!Number.isFinite(dx) || !Number.isFinite(dy)) throw new TypeError("Translation must be finite.");
    if (!Array.isArray(size) || size.length!==2 || !size.every(value=>Number.isFinite(value) && value>=1)) throw new RangeError("Bounds must contain two positive dimensions.");
    const result=copyPolylines(polylines), chosen=normalizeNodes(polylines,nodes);
    const points=chosen.map(node=>polylines[node[0]][node[1]]);
    for (let axis=0;axis<2;axis++) {
        if (points.length && Math.max.apply(null,points.map(point=>point[axis]))-Math.min.apply(null,points.map(point=>point[axis]))>size[axis]-1) throw new RangeError("Selected points do not fit within bounds.");
    }
    const moved=translate(points,points.map((point,i)=>i),dx,dy,size);
    for (let i=0;i<chosen.length;i++) result[chosen[i][0]][chosen[i][1]]=moved[i];
    const delta=points.length ? [moved[0][0]-points[0][0],moved[0][1]-points[0][1]] : [0,0];
    return {polylines:result,nodes:chosen,centroid:centroidNodes(result,chosen),delta:delta,changed:delta[0]!==0 || delta[1]!==0};
}
