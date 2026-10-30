import QtQuick
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    required property var app
    required property var controller
    property string label
    FontMetrics { id:labelMetrics; font.family:"Noto Sans"; font.pixelSize:12; font.weight:Font.Bold }
    // Lay out against the bold face once, so hover changes weight without moving words.
    function stableLabel(availableWidth) {
        const words=label.trim().split(/\s+/);
        let first="";
        while (words.length && labelMetrics.advanceWidth(first ? first+" "+words[0] : words[0])<=availableWidth) first+=(first ? " " : "")+words.shift();
        if (!first && words.length) first=words.shift();
        if (!words.length) return labelMetrics.elidedText(first,Qt.ElideRight,availableWidth);
        return labelMetrics.elidedText(first,Qt.ElideRight,availableWidth)+"\n"+labelMetrics.elidedText(words.join(" "),Qt.ElideRight,availableWidth);
    }
    property bool labelAlwaysBold:false
    property bool labelBoldOnSelection:true
    property int labelRestWeight:Font.Medium
    property bool chosen:false
    property bool selected: false
    property real iconLift: down ? 2 : selected || hovered ? -5 : 0
    Behavior on iconLift {
        NumberAnimation {
            duration: root.controller.reducedMotion ? 0 : Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
        }
    }
    signal launch()
    signal contextRequested()
    Component.onCompleted: controller.createdAppTiles++
    Component.onDestruction: if (controller) controller.createdAppTiles--
    Accessible.name: app.name
    buttonRadius: Appearance.rounding.normal
    colBackground: "transparent"
    colBackgroundHover: "transparent"
    rippleEnabled: false
    Keys.forwardTo: [controller.keyRouter]
    onClicked: launch()
    altAction: () => contextRequested()
    contentItem: Column {
        spacing: 4
        Item {
            width: parent.width
            height: 56
            AdaptiveAppIcon {
                transform: Translate { y: root.iconLift }
                anchors.centerIn: parent
                implicitSize: 48
                appId: root.app.id
                appName: root.app.name
                iconName: root.app.icon
                hovered: root.hovered
                pressed: root.down
                selected: root.selected || root.chosen
                selectionOutline:root.chosen
                contextMenuOpen: Boolean(root.controller?.menuOpen && root.controller?.menuApp?.id === root.app?.id)
            }
        }
        Item {
            width:parent.width
            height:34
            Rectangle {
                anchors.centerIn:parent
                width:Math.min(parent.width,labelText.paintedWidth+12)
                height:Math.min(parent.height,labelText.paintedHeight+6)
                radius:Appearance.rounding.small
                visible:root.chosen
                color:Appearance.colors.colSecondaryContainer
            }
            StyledText {
                id:labelText
                anchors.fill:parent
                text:root.stableLabel(width-12)
                horizontalAlignment:Text.AlignHCenter
                wrapMode:Text.NoWrap
                maximumLineCount:2
                elide:Text.ElideRight
                font.family:"Noto Sans"
                font.variableAxes:({})
                font.weight:root.labelAlwaysBold || root.labelBoldOnSelection && root.selected || root.isHovered ? Font.Bold : root.labelRestWeight
                font.pixelSize:12
                color:root.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
            }
        }
    }
}
