import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property var sections: []
    property real scrollY: 0
    property real contentHeight: 0
    property real viewportHeight: 0
    property int motionDuration: 140
    property var keyRouter: null
    property bool reducedMotion: false
    readonly property int activeIndex: {
        let selected = 0;
        for (let i = 0; i < sections.length; ++i)
            if (sections[i].y <= scrollY + 2) selected = i;
        return selected;
    }
    readonly property string activeSection: sections[activeIndex]?.section ?? ""
    readonly property var visibleEntries: sections
    readonly property int iconCount: visibleEntries.filter(section => !section.letter).length
    readonly property int letterCount: visibleEntries.length - iconCount
    readonly property real entrySpacing: 2
    readonly property real iconHeight: Math.min(36, Math.max(0, height / Math.max(1, iconCount)))
    readonly property real letterHeight: Math.max(0, Math.min(25,
        (height - iconCount * iconHeight - Math.max(0, visibleEntries.length - 1) * entrySpacing) / Math.max(1, letterCount)))
    signal jump(real position)
    implicitWidth: 46
    clip: true
    function inspect() {
        return {activeSection, letters: letterCount, icons: iconCount,
            height, contentHeight: railColumn.height, letterHeight,
            centerX: width / 2};
    }
    Column {
        id: railColumn
        width: parent.width
        spacing: root.entrySpacing
        Repeater {
            model: root.visibleEntries
            delegate: Button {
                id: entry
                required property var modelData
                readonly property bool isLetter: !!modelData.letter
                readonly property bool selected: isLetter
                    ? root.sections[root.activeIndex]?.letter === modelData.letter
                    : root.activeSection === modelData.section
                width: railColumn.width
                height: isLetter ? root.letterHeight : root.iconHeight
                padding: 0
                hoverEnabled: true
                Accessible.name: modelData.label
                Accessible.role: Accessible.Button
                Keys.forwardTo: root.keyRouter ? [root.keyRouter] : []
                onClicked: root.jump(modelData.y)
                background: Item {}
                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: !entry.isLetter
                        text: entry.modelData.icon ?? ""
                        iconSize: 21
                        fill: entry.selected ? 1 : 0
                        color: Appearance.colors.colOnSurface
                        opacity: entry.selected ? 1 : entry.hovered ? 0.8 : 0.45
                        Behavior on opacity { NumberAnimation { duration: root.motionDuration } }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: entry.isLetter
                        text: entry.modelData.letter ?? ""
                        font.pixelSize: Math.min(12, Math.max(8, root.letterHeight - 6))
                        font.weight: entry.selected ? Font.Bold : Font.Normal
                        color: Appearance.colors.colOnSurface
                        opacity: entry.selected ? 0.82 : entry.hovered ? 0.7 : 0.38
                        Behavior on opacity { NumberAnimation { duration: root.motionDuration } }
                    }
                }
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: entry.hovered && !entry.isLetter
                    x: entry.width + 8
                    y: (entry.height - implicitHeight) / 2
                    text: Translation.tr(entry.modelData.label)
                }
            }
        }
    }
}
