import QtQuick

// Exponent-4 superellipse, matching the adaptive app icon mask.
Canvas {
    id:root
    property color color:"transparent"
    property color borderColor:"transparent"
    property real borderWidth:0
    antialiasing:true
    onWidthChanged:requestPaint()
    onHeightChanged:requestPaint()
    onColorChanged:requestPaint()
    onBorderColorChanged:requestPaint()
    onBorderWidthChanged:requestPaint()
    onPaint: {
        const context=getContext("2d");
        context.reset();
        if (width<=0 || height<=0) return;
        const inset=Math.max(0,borderWidth)/2;
        const rx=Math.max(0,width/2-inset),ry=Math.max(0,height/2-inset);
        context.beginPath();
        for (let index=0;index<=192;index++) {
            const angle=index*Math.PI*2/192;
            const cosine=Math.cos(angle),sine=Math.sin(angle);
            const x=width/2+rx*Math.sign(cosine)*Math.sqrt(Math.abs(cosine));
            const y=height/2+ry*Math.sign(sine)*Math.sqrt(Math.abs(sine));
            if (!index) context.moveTo(x,y);else context.lineTo(x,y);
        }
        context.closePath();
        context.fillStyle=color;context.fill();
        if (borderWidth>0) { context.lineWidth=borderWidth;context.strokeStyle=borderColor;context.stroke(); }
    }
}
