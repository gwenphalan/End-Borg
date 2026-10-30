.pragma library

// Centripetal Catmull–Rom interpolation expressed as cubic Bézier segments.
// Parameter intervals are sqrt(chord length), rather than uniform node spacing.
// https://www.cemyuksel.com/research/catmullrom_param/
function distanceSquared(a,b) {const x=a[0]-b[0],y=a[1]-b[1];return x*x+y*y;}
function reflected(a,b) {return [2*a[0]-b[0],2*a[1]-b[1]];}
// Display-only relaxation bounded to one image pixel from each original node.
// Endpoints and the source annotations are preserved.
function denoise(points,maxShift) {
    maxShift=maxShift===undefined ? 1 : maxShift;
    let output=points.map(p=>p.slice());
    for(let pass=0;pass<2;pass++) {
        const previous=output;
        output=previous.map((p,i)=> {
            if(i===0 || i===points.length-1) return p.slice();
            const a=previous[i-1],b=previous[i+1];
            const left=Math.sqrt(distanceSquared(a,p)),right=Math.sqrt(distanceSquared(p,b));
            if(left+right<1e-10) return p.slice();
            const fraction=left/(left+right);
            let x=p[0]+.5*(a[0]+fraction*(b[0]-a[0])-p[0]);
            let y=p[1]+.5*(a[1]+fraction*(b[1]-a[1])-p[1]);
            const dx=x-points[i][0],dy=y-points[i][1],shift=Math.hypot(dx,dy);
            if(shift>maxShift) {x=points[i][0]+dx*maxShift/shift;y=points[i][1]+dy*maxShift/shift;}
            return [x,y];
        });
    }
    return output;
}
function nearestPolyline(points,query,tolerance) {
    let best=null,bestDistance=tolerance*tolerance;
    for(let i=0;i+1<points.length;i++) {
        const a=points[i],b=points[i+1],length=distanceSquared(a,b);
        if(length<1e-20) continue;
        const t=Math.max(0,Math.min(1,((query[0]-a[0])*(b[0]-a[0])+(query[1]-a[1])*(b[1]-a[1]))/length));
        const p=[a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])],distance=distanceSquared(p,query);
        if(distance<bestDistance) {bestDistance=distance;best={index:i,t:t,point:p,distance:Math.sqrt(distance)};}
    }
    return best;
}
function segments(points) {
    const result=[];
    for(let i=0;i+1<points.length;i++) {
        const b=points[i],c=points[i+1];
        if(distanceSquared(b,c)<1e-20) {result.push({index:i,p0:b,c1:b,c2:c,p1:c});continue;}
        let a=i>0 ? points[i-1] : reflected(b,c);
        let d=i+2<points.length ? points[i+2] : reflected(c,b);
        if(distanceSquared(a,b)<1e-20) a=reflected(b,c);
        if(distanceSquared(c,d)<1e-20) d=reflected(c,b);
        const ab=Math.pow(distanceSquared(a,b),.25),bc=Math.pow(distanceSquared(b,c),.25),cd=Math.pow(distanceSquared(c,d),.25);
        const c1=[],c2=[];
        for(let axis=0;axis<2;axis++) {
            const m1=bc*((b[axis]-a[axis])/ab-(c[axis]-a[axis])/(ab+bc)+(c[axis]-b[axis])/bc);
            const m2=bc*((c[axis]-b[axis])/bc-(d[axis]-b[axis])/(bc+cd)+(d[axis]-c[axis])/cd);
            c1.push(b[axis]+m1/3);c2.push(c[axis]-m2/3);
        }
        result.push({index:i,p0:b,c1:c1,c2:c2,p1:c});
    }
    return result;
}
function evaluate(segment,t) {
    const u=1-t;
    return [0,1].map(axis=>u*u*u*segment.p0[axis]+3*u*u*t*segment.c1[axis]+3*u*t*t*segment.c2[axis]+t*t*t*segment.p1[axis]);
}
function nearestPoint(points,query,tolerance) {
    let best=null,bestDistance=tolerance*tolerance;
    for(const segment of segments(points)) {
        if(distanceSquared(segment.p0,segment.p1)<1e-20) continue;
        const samples=32;
        let sample=0,minimum=Infinity;
        for(let j=0;j<=samples;j++) {
            const distance=distanceSquared(evaluate(segment,j/samples),query);
            if(distance<minimum) {minimum=distance;sample=j;}
        }
        let low=Math.max(0,(sample-1)/samples),high=Math.min(1,(sample+1)/samples);
        for(let j=0;j<28;j++) {
            const a=low+(high-low)/3,b=high-(high-low)/3;
            if(distanceSquared(evaluate(segment,a),query)<distanceSquared(evaluate(segment,b),query)) high=b;else low=a;
        }
        const t=(low+high)/2,point=evaluate(segment,t),distance=distanceSquared(point,query);
        if(distance<bestDistance) {bestDistance=distance;best={index:segment.index,t:t,point:point,distance:Math.sqrt(distance)};}
    }
    return best;
}
