import QtQuick
import QtQuick.Layouts

// Put in ToolApp.status or ToolConfiguredApp.status. Domain-specific fields are
// supplied in toolInputs to the right of left-aligned inline shortcuts. No status spam here.
Item {
    id:root
    objectName:"toolCanvasFooter"
    default property alias toolInputs:toolFields.data
    property alias leadingControls:leadingFields.data
    property alias prefixControls:prefixFields.data
    property real zoomPercent:100
    property bool atReset:true
    property bool zoomEnabled:true
    property bool showZoom:true
    property bool showCursorCoordinates:true
    property bool cursorActive:false
    property real cursorX:0
    property real cursorY:0
    property var hints:[]
    property bool toolInputsEnabled:true
    readonly property bool zoomFocused:showZoom && zoom.inputFocused
    signal zoomEdited(real percent)
    signal resetRequested()
    Layout.fillWidth:true
    implicitWidth:row.implicitWidth
    implicitHeight:row.implicitHeight
    property Item content:RowLayout {
        id:row
        parent:root
        anchors.fill:parent
        spacing:0
        RowLayout {
            id:prefixFields
            spacing:6
            visible:children.length>0
            Layout.fillWidth:false
            Layout.preferredWidth:implicitWidth
            Layout.maximumWidth:implicitWidth
            Layout.rightMargin:implicitWidth>0 ? 12 : 0
        }
        ToolShortcutHints {Layout.fillWidth:true;Layout.minimumWidth:0;horizontalAlignment:Qt.AlignLeft;hints:root.hints}
        // Only hints may consume spare width. In particular an empty trailing
        // slot must never become a flex item after the coordinate readout.
        RowLayout {
            id:rightFields
            objectName:"footerRightControls"
            spacing:0
            Layout.fillWidth:false
            Layout.minimumWidth:implicitWidth
            Layout.preferredWidth:implicitWidth
            Layout.maximumWidth:implicitWidth
            Layout.alignment:Qt.AlignRight
            Layout.leftMargin:implicitWidth>0 ? 12 : 0
            RowLayout {
                id:toolFields
                spacing:6
                visible:children.length>0
                enabled:root.toolInputsEnabled
                Layout.fillWidth:false
                Layout.preferredWidth:implicitWidth
                Layout.maximumWidth:implicitWidth
            }
            ToolCursorCoordinates {
                visible:root.showCursorCoordinates
                objectName:"cursorCoordinates"
                reservedWidth:0
                active:root.cursorActive;pixelX:root.cursorX;pixelY:root.cursorY
                Layout.leftMargin:toolFields.implicitWidth>0 ? 12 : 0
            }
            ToolZoomControl {
                id:zoom
                objectName:"zoomControl"
                visible:root.showZoom
                resetBeforeInput:true
                percent:root.zoomPercent;atReset:root.atReset;enabled:root.zoomEnabled
                Layout.fillWidth:false
                Layout.preferredWidth:implicitWidth
                Layout.maximumWidth:implicitWidth
                Layout.leftMargin:toolFields.implicitWidth>0 || root.showCursorCoordinates ? 12 : 0
                onZoomEdited:percent=>root.zoomEdited(percent)
                onResetRequested:root.resetRequested()
            }
            RowLayout {
                id:leadingFields
                spacing:6
                visible:children.length>0
                Layout.fillWidth:false
                Layout.preferredWidth:implicitWidth
                Layout.maximumWidth:implicitWidth
                Layout.leftMargin:implicitWidth>0 && (toolFields.implicitWidth>0 || root.showCursorCoordinates || root.showZoom) ? 12 : 0
            }
        }
    }
}
