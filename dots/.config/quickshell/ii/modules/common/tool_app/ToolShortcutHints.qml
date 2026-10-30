import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property int horizontalAlignment: Qt.AlignLeft
    property var hints: [] // [{keys:["Shift","LMB"], action:"Select curve"}]

    Layout.minimumWidth: 0
    implicitWidth: hintRow.implicitWidth
    implicitHeight: hintRow.implicitHeight
    clip: true

    RowLayout {
        id: hintRow
        x: root.horizontalAlignment === Qt.AlignRight ? root.width-width : root.horizontalAlignment === Qt.AlignHCenter ? (root.width-width)/2 : 0
        anchors.verticalCenter: parent.verticalCenter

        spacing: 10

        Repeater {
            model: root.hints

            RowLayout {
                required property var modelData
                required property int index

                spacing: 6

                Repeater {
                    model: modelData.keys

                    Loader {
                        id: hintToken

                        required property string modelData
                        readonly property bool mouse: ["LMB", "RMB", "MMB", "SCROLL", "SCROLLUP", "SCROLLDOWN", "WHEEL"].includes(modelData.toUpperCase().replace(/[ _-]/g, ""))

                        sourceComponent: mouse ? mouseHint : keyboardHint

                        Component {
                            id: mouseHint

                            ToolMouseHint {
                                button: hintToken.modelData
                            }

                        }

                        Component {
                            id: keyboardHint

                            KeyboardKey {
                                key: hintToken.modelData
                                pixelSize: Appearance.font.pixelSize.smaller
                            }

                        }

                    }

                }

                StyledText {
                    text: "–"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: modelData.action
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    visible: index < root.hints.length - 1
                    text: "|"
                    leftPadding: 4
                    color: Appearance.colors.colOutline
                }

            }

        }

    }

}
