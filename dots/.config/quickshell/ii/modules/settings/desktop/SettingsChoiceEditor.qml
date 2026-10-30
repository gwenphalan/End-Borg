pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.services

ColumnLayout {
    id:root
    required property var choices
    required property var value
    property string label:""
    property bool fillRow:false
    signal chosen(var value)
    readonly property var filtered:choices.filter(c => !filter.text || c.name.toLowerCase().includes(filter.text.toLowerCase()))
    spacing:8
    Flow {
        Layout.fillWidth:true; Layout.preferredHeight:childrenRect.height
        visible:root.choices.length<=4
        spacing:6
        Repeater {
            model:root.choices.length<=4 ? root.choices : []
            delegate:RippleButton {
                required property var modelData
                implicitHeight:42
                implicitWidth:root.fillRow ? Math.max(80,(root.width-(root.choices.length-1)*6)/root.choices.length) : Math.min(root.width,Math.max(88,label.implicitWidth+32))
                buttonRadius:Appearance.rounding.full
                toggled:root.value===modelData.value
                colBackground:Appearance.colors.colLayer3
                colBackgroundToggled:Appearance.colors.colSecondaryContainer
                Accessible.name:root.label+": "+modelData.name
                onClicked:root.chosen(modelData.value)
                contentItem:StyledText { id:label; elide:Text.ElideRight; text:parent.modelData.name; horizontalAlignment:Text.AlignHCenter; verticalAlignment:Text.AlignVCenter; color:parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2 }
            }
        }
    }
    SearchField {
        id:filter
        Layout.fillWidth:true
        visible:root.choices.length>8
        placeholderText:Translation.tr("Filter choices")
        Accessible.name:root.label+": "+Translation.tr("Filter choices")
        wrapMode:TextInput.NoWrap
    }
    ListView {
        id:list
        Layout.fillWidth:true
        Layout.preferredHeight:Math.min(contentHeight,264)
        visible:root.choices.length>4
        clip:true; spacing:2
        model:root.choices.length>4 ? root.filtered : []
        boundsBehavior:Flickable.StopAtBounds
        ScrollBar.vertical:SpotlightScrollBar { scrolling:list.moving }
        delegate:RippleButton {
            required property var modelData
            width:list.width; implicitHeight:44
            buttonRadius:Appearance.rounding.small
            toggled:root.value===modelData.value
            colBackgroundToggled:Appearance.colors.colSecondaryContainer
            Accessible.name:root.label+": "+modelData.name
            onClicked:root.chosen(modelData.value)
            contentItem:RowLayout {
                StyledText { Layout.fillWidth:true; text:parent.parent.modelData.name; elide:Text.ElideRight; color:parent.parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2 }
                MaterialSymbol { text:parent.parent.toggled ? "check_circle" : "radio_button_unchecked"; iconSize:20; color:parent.parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext }
            }
        }
    }
    StyledText { visible:root.choices.length>4 && !root.filtered.length; text:Translation.tr("No matching choices"); color:Appearance.colors.colSubtext }
}
