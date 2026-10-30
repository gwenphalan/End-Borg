.pragma library
.import "ToolPointSelection.js" as PointSelection

function endpointError(polylines,nodes,tolerance) {
    if (!Number.isFinite(tolerance) || tolerance<0) return "Endpoint tolerance must be finite and nonnegative.";
    try {PointSelection.copyPolylines(polylines);} catch(error) {return error.message;}
    const selected=PointSelection.normalizeNodes(polylines,nodes);
    if (!Array.isArray(nodes) || nodes.length!==2 || selected.length!==2) return "Select exactly two endpoints.";
    if (selected[0][0]===selected[1][0]) return "Select endpoints from different polylines.";
    for (const node of selected) {
        const line=polylines[node[0]];
        if (line.length<2) return "Each open polyline needs at least two points.";
        if (node[1]!==0 && node[1]!==line.length-1) return "Only polyline endpoints can be joined.";
        if (Math.hypot(line[0][0]-line[line.length-1][0],line[0][1]-line[line.length-1][1])<=tolerance) return "Only open polylines can be joined.";
    }
    return "";
}

function canJoinSelectedEndpoints(polylines,nodes,tolerance) {
    return endpointError(polylines,nodes,tolerance===undefined ? 1e-9 : tolerance)==="";
}

function joinSelectedEndpoints(polylines,nodes,tolerance) {
    tolerance=tolerance===undefined ? 1e-9 : tolerance;
    const error=endpointError(polylines,nodes,tolerance);
    if (error) return {ok:false,error:error};
    const selected=PointSelection.normalizeNodes(polylines,nodes), first=selected[0], second=selected[1];
    const copies=PointSelection.copyPolylines(polylines);
    let a=copies[first[0]], b=copies[second[0]];
    if (first[1]===0) a.reverse();
    if (second[1]!==0) b.reverse();
    const joinPointIndex=a.length-1;
    const deduplicated=Math.hypot(a[joinPointIndex][0]-b[0][0],a[joinPointIndex][1]-b[0][1])<=tolerance;
    if (deduplicated) b=b.slice(1);
    const merged=a.concat(b), joinedIndex=Math.min(first[0],second[0]), result=[];
    const indexMap=polylines.map(()=>-1);
    for (let i=0;i<copies.length;i++) {
        if (i===joinedIndex) {result.push(merged);indexMap[first[0]]=indexMap[second[0]]=result.length-1;}
        if (i===first[0] || i===second[0]) continue;
        indexMap[i]=result.length;result.push(copies[i]);
    }
    const nextNodes=deduplicated ? [[joinedIndex,joinPointIndex]] : [[joinedIndex,joinPointIndex],[joinedIndex,joinPointIndex+1]];
    const selection=PointSelection.selectionResult(result,nextNodes,nextNodes[nextNodes.length-1],[]);
    return {ok:true,polylines:result,selection:selection,nodes:selection.nodes,
        joinedIndex:joinedIndex,joinPointIndex:joinPointIndex,sourceIndices:[first[0],second[0]],
        indexMap:indexMap,deduplicated:deduplicated};
}
