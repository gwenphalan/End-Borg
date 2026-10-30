import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.tool_app
import qs.modules.settings.desktop as SettingsControls

RowLayout {
    id:root
    objectName:"modeOperations"
    readonly property bool compact:workspace.width<1500
    required property var workspace
    readonly property var spatial:workspace.spatialTools
    readonly property bool isReference:workspace.stage==="calibration"
    readonly property bool inputFocused:referenceWidth.inputFocused || referenceDepth.inputFocused
    spacing:16
    implicitHeight:96
    component Caption:StyledText {font.pixelSize:13;color:Appearance.colors.colSubtext}
    component Divider:Rectangle {Layout.preferredWidth:1;Layout.fillHeight:true;Layout.topMargin:6;Layout.bottomMargin:6;color:Appearance.colors.colOutlineVariant}
    component Action:ToolIconButton {property string description:"";Accessible.name:description;StyledToolTip {text:parent.description}}
    component Length:RowLayout {
        id:length
        property string symbol:"straighten"
        property string description:""
        property real value:1
        property bool signedValue:false
        readonly property bool inputFocused:control.inputFocused
        readonly property bool invalid:control.invalid
        signal edited(real value)
        spacing:6
        MaterialSymbol {visible:length.symbol.length>0;text:length.symbol;iconSize:18;color:Appearance.colors.colSubtext;HoverHandler{id:hover}StyledToolTip{text:length.description;extraVisibleCondition:hover.hovered}}
        ToolLengthInput {id:control;metres:length.value;signedValue:length.signedValue;description:length.description;onEdited:value=>length.edited(value)}
    }
    component AxisControl:RowLayout {
        id:axisControl
        required property int axisIndex
        readonly property string axisLabel:axisIndex===0 ? "Width axis" : "Depth axis"
        spacing:4
                Action {
                    text:axisControl.axisIndex===0 ? "swap_horiz" : "swap_vert";description:"Reverse axis direction";enabled:!root.workspace.busy
                    onClicked:{const axes=root.spatial.referenceAxes.slice(),axis=axes[axisControl.axisIndex];axes[axisControl.axisIndex]=axis.startsWith("-") ? axis.slice(1) : "-"+axis;root.spatial.referenceAxes=axes;}
                }
                ToolIconButton {
                    id:axisButton
                    text:{const axis=root.spatial.referenceAxes[axisControl.axisIndex];return (axis.startsWith("-") ? "−" : "+")+axis.replace("-","").toUpperCase();}
                    toggled:false;implicitWidth:35;implicitHeight:35
                    Layout.preferredWidth:35;Layout.preferredHeight:35
                    Layout.minimumWidth:35;Layout.maximumWidth:35
                    Layout.minimumHeight:35;Layout.maximumHeight:35
                    contentItem:StyledText {anchors.centerIn:parent;text:axisButton.text;font.pixelSize:13;color:axisButton.colText;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter}
                    enabled:!root.workspace.busy
                    Accessible.name:axisControl.axisLabel+"; click to change axis"
                    StyledToolTip{text:"Change "+axisControl.axisLabel.toLowerCase()}
                    onClicked:{const axes=root.spatial.referenceAxes.slice(),axis=axes[axisControl.axisIndex],other=axes[1-axisControl.axisIndex].replace("-",""),available=["x","y","z"].filter(value=>value!==other);axes[axisControl.axisIndex]=(axis.startsWith("-") ? "-" : "")+available[(available.indexOf(axis.replace("-",""))+1)%available.length];root.spatial.referenceAxes=axes;}
                }
    }
    ColumnLayout {
        visible:root.isReference;spacing:5
        RowLayout {Caption{text:"Reference plane"}Action{text:"crop_free";implicitWidth:18;implicitHeight:18;iconSize:16;description:"Redraw reference plane";enabled:!root.workspace.busy;onClicked:root.spatial.redrawReferencePlane()}Caption{text:"Normal "+root.spatial.normalAxis}}
        RowLayout {spacing:4;Length{id:referenceWidth;symbol:"";description:"Reference width";value:root.spatial.referenceWidth;onEdited:value=>root.spatial.referenceWidth=value} AxisControl{axisIndex:0}}
        RowLayout {spacing:4;Length{id:referenceDepth;symbol:"";description:"Reference depth";value:root.spatial.referenceDepth;onEdited:value=>root.spatial.referenceDepth=value} AxisControl{axisIndex:1}}
    }
    ColumnLayout {
        visible:root.isReference;spacing:8
        RowLayout {
            spacing:6
            ToolBarButton {text:"Save plane";materialSymbol:"done";enabled:root.spatial.referenceDirty && root.spatial.corners.length===4 && !referenceWidth.invalid && !referenceDepth.invalid && !root.workspace.busy;onClicked:root.spatial.saveReferencePlane()}
            ToolBarButton {objectName:"recalibrateReferenceBlender";text:"Recalibrate Blender file";materialSymbol:"sync";enabled:root.workspace.canExportBlender;onClicked:root.workspace.file("recalibrate_blend_source")}
        }
        RowLayout {
            spacing:6
            ToolBarButton {text:"Calculate 3D";materialSymbol:"calculate";current:true;enabled:!!root.workspace.referencePlane && !root.workspace.referencePlane.stale && !root.spatial.referenceDirty && !root.workspace.busy;onClicked:root.spatial.calculateSpace()}
            ToolBarButton {objectName:"exportReferenceBlender";text:"Export to Blender";materialSymbol:"deployed_code";enabled:root.workspace.canExportBlender;onClicked:root.workspace.file("scene_blend")}
        }
    }
}
