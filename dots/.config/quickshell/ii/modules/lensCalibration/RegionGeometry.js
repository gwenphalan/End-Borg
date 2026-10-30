.pragma library

const palette=["#ffb454","#63c7ff","#d49aff","#70db9b","#ff829b","#e7d665","#6edbd3","#b2b2ff"];
function color(id) {let hash=0;for(const c of String(id)) hash=(hash*31+c.charCodeAt(0))>>>0;return palette[hash%palette.length];}
function nearest(points,query,tolerance) {
    let best=null;
    for(let i=0;i<points.length;i++) {
        const a=points[i],b=points[(i+1)%points.length],dx=b[0]-a[0],dy=b[1]-a[1],length=dx*dx+dy*dy;
        if(!length) continue;
        const t=Math.max(0,Math.min(1,((query[0]-a[0])*dx+(query[1]-a[1])*dy)/length));
        const point=[a[0]+t*dx,a[1]+t*dy],distance=Math.hypot(point[0]-query[0],point[1]-query[1]);
        if(distance<=tolerance && (!best || distance<best.distance)) best={index:i,point:point,distance:distance};
    }
    return best;
}
function contains(points,p) {
    let inside=false;
    for(let i=0,j=points.length-1;i<points.length;j=i++) {const a=points[i],b=points[j];if((a[1]>p[1])!==(b[1]>p[1]) && p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]) inside=!inside;}
    return inside;
}
function valid(points) {
    if(points.length<3 || points.some(p=>!Array.isArray(p)||p.length!==2||!p.every(Number.isFinite))) return false;
    let area=0;for(let i=0;i<points.length;i++) {const a=points[i],b=points[(i+1)%points.length];area+=a[0]*b[1]-b[0]*a[1];}
    return Math.abs(area)>1e-6;
}
function snap(objects,p,tolerance) {
    let best={point:p,distance:tolerance},vertexFound=false;
    for(const object of objects || []) for(const vertex of object.vertices || []) {
        const distance=Math.hypot(vertex[0]-p[0],vertex[1]-p[1]);
        if(distance<best.distance) {best={point:vertex.slice(0,2),distance:distance};vertexFound=true;}
    }
    if(vertexFound)return best.point;
    for(const object of objects || []) {
        const vertices=object.vertices || [];
        for(const edge of object.edges || []) {if(!vertices[edge[0]]||!vertices[edge[1]]) continue;const hit=nearest([vertices[edge[0]],vertices[edge[1]]],p,best.distance);if(hit)best=hit;}
    }
    return best.point;
}
