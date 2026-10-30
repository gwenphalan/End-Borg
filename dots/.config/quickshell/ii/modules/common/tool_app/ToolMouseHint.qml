import QtQuick
import qs.modules.common

// A mouse silhouette with the relevant physical button highlighted.
Canvas {
    id: root
    property string button: "LMB"
    property color color: Appearance.colors.colOnSurfaceVariant
    readonly property string token: button.toUpperCase().replace(/[ _-]/g, "")
    readonly property bool scrolling: token.includes("SCROLL") || token === "WHEEL"
    implicitWidth: scrolling ? 28 : 22
    implicitHeight: 26
    Accessible.name: scrolling ? (token.includes("UP") ? "Scroll up" : token.includes("DOWN") ? "Scroll down" : "Scroll wheel") : token === "LMB" ? "Left mouse button" : token === "RMB" ? "Right mouse button" : "Middle mouse button"
    onButtonChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c=getContext("2d");
        c.reset();
        c.scale(width/implicitWidth,height/26);
        c.strokeStyle=color; c.fillStyle=color; c.lineWidth=1.5;
        c.lineCap="round"; c.lineJoin="round";
        if(token==="LMB" || token==="RMB") {
            c.beginPath();
            if(token==="LMB") {
                c.moveTo(4,12);c.lineTo(4,9);c.quadraticCurveTo(4,3,10,3);c.lineTo(10,12);
            } else {
                c.moveTo(12,3);c.quadraticCurveTo(18,3,18,9);c.lineTo(18,12);c.lineTo(12,12);
            }
            c.closePath();c.fill();
        }
        c.beginPath();c.moveTo(11,2);c.bezierCurveTo(5,2,3,5,3,10);
        c.lineTo(3,16);c.bezierCurveTo(3,21,6,24,11,24);
        c.bezierCurveTo(16,24,19,21,19,16);c.lineTo(19,10);
        c.bezierCurveTo(19,5,17,2,11,2);c.closePath();c.stroke();
        c.beginPath();c.moveTo(3,13);c.lineTo(19,13);c.moveTo(11,2);c.lineTo(11,5);c.moveTo(11,10);c.lineTo(11,13);c.stroke();
        c.beginPath();c.roundedRect(9.5,5,3,5,1,1);
        if(token==="MMB" || scrolling)c.fill();else c.stroke();
        if(scrolling) {
            c.beginPath();c.moveTo(25,5);c.lineTo(25,21);
            if(!token.includes("DOWN")){c.moveTo(22,8);c.lineTo(25,5);c.lineTo(27,8);}
            if(!token.includes("UP")){c.moveTo(22,18);c.lineTo(25,21);c.lineTo(27,18);}
            c.stroke();
        }
    }
}
