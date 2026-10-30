pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id:root
    property string title:Translation.tr("Choose a color")
    property bool showHexInput:true
    property real spectrumHeight:260
    property real hue:0
    property real saturation:1
    property real level:1
    property bool invalid:false
    property bool syncing:false
    property bool editingHex:false
    readonly property bool interacting:wheelPointer.pressed || brightness.pressed
    readonly property color selectedColor:Qt.hsva(hue/360,saturation,level,1)
    readonly property var selectedRgb:[Math.round(selectedColor.r*255),Math.round(selectedColor.g*255),Math.round(selectedColor.b*255)]
    readonly property string hex:"#"+selectedRgb.map(v => v.toString(16).padStart(2,"0")).join("")
    signal chosen(var rgb)
    signal cancelled()
    function reset(color) { syncing=true; hue=Math.max(0,color.hsvHue)*360; saturation=color.hsvSaturation; level=color.hsvValue; invalid=false; editingHex=false; syncing=false; }
    spacing:16
    StyledText { Layout.fillWidth:true; visible:text.length > 0; text:root.title; font.pixelSize:Appearance.font.pixelSize.large; font.weight:Font.Medium }
    Item {
        id:wheel
        objectName:"lightColorWheel"
        Layout.alignment:Qt.AlignHCenter
        Layout.preferredWidth:Math.min(root.width,Math.max(200,Math.min(320,root.spectrumHeight)))
        Layout.preferredHeight:width
        readonly property real radius:width/2-12
        activeFocusOnTab:true
        Accessible.name:Translation.tr("Color wheel")
        Accessible.description:Translation.tr("Left and right change hue. Up and down change saturation.")
        Keys.onPressed:event => {
            if (![Qt.Key_Left,Qt.Key_Right,Qt.Key_Up,Qt.Key_Down].includes(event.key)) return;
            const step=event.modifiers & Qt.ShiftModifier ? 10 : 1;
            if (event.key===Qt.Key_Left || event.key===Qt.Key_Right) root.hue=(root.hue+(event.key===Qt.Key_Right ? step : -step)+360)%360;
            else root.saturation=Math.max(0,Math.min(1,root.saturation+(event.key===Qt.Key_Up ? step : -step)/100));
            root.invalid=false;event.accepted=true;
        }
        Canvas {
            anchors.fill:parent
            onWidthChanged:requestPaint()
            onHeightChanged:requestPaint()
            onPaint: {
                const ctx=getContext("2d"), cx=width/2, cy=height/2, r=wheel.radius;
                ctx.clearRect(0,0,width,height);
                for (let degree=0;degree<360;degree++) {
                    const a=(degree-90)*Math.PI/180,b=(degree-88.5)*Math.PI/180;
                    const gradient=ctx.createLinearGradient(cx,cy,cx+Math.cos(a)*r,cy+Math.sin(a)*r);
                    gradient.addColorStop(0,"white");gradient.addColorStop(1,Qt.hsva(degree/360,1,1,1));
                    ctx.beginPath();ctx.moveTo(cx,cy);ctx.arc(cx,cy,r,a,b);ctx.closePath();ctx.fillStyle=gradient;ctx.fill();
                }
            }
        }
        Rectangle { anchors.centerIn:parent; width:wheel.radius*2; height:width; radius:width/2; color:"black"; opacity:1-root.level }
        Rectangle { anchors.fill:parent; radius:width/2; color:"transparent"; border.width:wheel.activeFocus ? 2 : 0; border.color:Appearance.colors.colPrimary }
        Rectangle {
            width:28;height:28;radius:14
            x:wheel.width/2+Math.cos((root.hue-90)*Math.PI/180)*wheel.radius*root.saturation-width/2
            y:wheel.height/2+Math.sin((root.hue-90)*Math.PI/180)*wheel.radius*root.saturation-height/2
            color:root.selectedColor;border.width:3;border.color:"white"
            Rectangle { anchors.fill:parent; anchors.margins:-1; radius:width/2; color:"transparent"; border.width:1; border.color:"#60000000" }
        }
        MouseArea {
            id:wheelPointer
            anchors.fill:parent; preventStealing:true; cursorShape:Qt.CrossCursor
            function update(mouse) {
                const dx=mouse.x-width/2,dy=mouse.y-height/2;
                root.hue=(Math.atan2(dy,dx)*180/Math.PI+450)%360;
                root.saturation=Math.min(1,Math.sqrt(dx*dx+dy*dy)/wheel.radius);root.invalid=false;
            }
            onPressed:mouse => { wheel.forceActiveFocus();update(mouse); }
            onPositionChanged:mouse => { if (pressed) update(mouse); }
        }
    }
    RowLayout {
        Layout.fillWidth:true
        MaterialSymbol { text:"brightness_6"; iconSize:20; color:Appearance.colors.colSubtext }
        StyledText { Layout.fillWidth:true; text:Translation.tr("Brightness"); color:Appearance.colors.colSubtext }
        StyledText { text:Math.round(root.level*100)+"%"; font.weight:Font.Medium }
    }
    StyledSlider {
        id:brightness; Layout.fillWidth:true
        from:0;to:1;value:root.level
        stopIndicatorValues:[]
        configuration:StyledSlider.Configuration.L
        highlightColor:Qt.hsva(root.hue/360,root.saturation,1,1)
        Accessible.name:Translation.tr("Color brightness")
        onMoved:{root.level=value;root.invalid=false;}
    }
    RowLayout {
        Layout.fillWidth:true;spacing:12;visible:root.showHexInput
        Rectangle { implicitWidth:40;implicitHeight:40;radius:20;color:root.selectedColor;border.width:1;border.color:Appearance.colors.colSubtext }
        StyledText { Layout.fillWidth:true;text:root.hex.toUpperCase();font.weight:Font.Medium }
        IconToolbarButton {
            id:hexToggle
            text:"edit";toggled:root.editingHex;implicitWidth:40;implicitHeight:40
            Accessible.name:Translation.tr("Enter hex color")
            onClicked:{root.editingHex=!root.editingHex;if(root.editingHex)hexInput.forceActiveFocus();}
            StyledToolTip { text:Translation.tr("Enter hex color");extraVisibleCondition:false;alternativeVisibleCondition:hexToggle.isHovered || hexToggle.activeFocus }
        }
    }
    MaterialTextArea {
        id:hexInput;Layout.fillWidth:true;visible:root.showHexInput && root.editingHex
        placeholderText:Translation.tr("Hex color");text:root.hex;wrapMode:TextEdit.NoWrap
        Accessible.name:Translation.tr("Hex color")
        onTextChanged:if(activeFocus && !root.syncing) {
            root.invalid=!/^#[a-f0-9]{6}$/i.test(text);
            if(!root.invalid) {const c=text.slice(1);root.syncing=true;const color=Qt.rgba(parseInt(c.slice(0,2),16)/255,parseInt(c.slice(2,4),16)/255,parseInt(c.slice(4,6),16)/255,1);root.hue=Math.max(0,color.hsvHue)*360;root.saturation=color.hsvSaturation;root.level=color.hsvValue;root.syncing=false;}
        }
    }
    StyledText { visible:root.invalid;Layout.fillWidth:true;text:Translation.tr("Use six hex digits, for example #4F8C79.");wrapMode:Text.Wrap;color:Appearance.colors.colError }
    RowLayout {
        Layout.fillWidth:true
        DialogButton { buttonText:Translation.tr("Cancel");onClicked:root.cancelled() }
        Item { Layout.fillWidth:true }
        RippleButtonWithIcon { materialIcon:"check";mainText:Translation.tr("Apply color");enabled:!root.invalid;onClicked:root.chosen(root.selectedRgb) }
    }
}
