pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id:root
    required property string value
    property string label:Translation.tr("Time")
    signal chosen(string value)
    property bool suppressTriggerClick:false
    implicitWidth:140
    implicitHeight:40
    // Qt time-format tokens: hh:mm for 24-hour time, or h:mm ap / h:mm AP.
    property string timeFormat:"hh:mm"
    readonly property bool twelveHour:/ap/i.test(timeFormat)
    readonly property var parts:parseTime(value)
    readonly property int hour24:parts ? parts.hour : 0
    readonly property int minute:parts ? parts.minute : 0
    readonly property bool pm:hour24>=12
    readonly property string hourText:twelveHour ? String(hour24%12 || 12) : String(hour24).padStart(2,"0")

    function parseTime(text) {
        const match=String(text).match(/^([01]\d|2[0-3]):([0-5]\d)$/);
        return match ? {hour:Number(match[1]),minute:Number(match[2])} : null;
    }
    function formatStored(hour,minute) {
        const total=((Math.round(hour)*60+Math.round(minute))%1440+1440)%1440;
        return String(Math.floor(total/60)).padStart(2,"0")+":"+String(total%60).padStart(2,"0");
    }
    function hourFromDisplay(hour,pm,twelveHour) {
        return twelveHour ? Number(hour)%12+(pm ? 12 : 0) : Number(hour);
    }
    function displayTime(text,format) {
        const parsed=parseTime(text);
        if (!parsed) return String(text);
        const twelve=/ap/i.test(format);
        const hour=twelve ? String(parsed.hour%12 || 12) : String(parsed.hour).padStart(2,"0");
        const period=/AP/.test(format) ? parsed.hour>=12 ? "PM" : "AM" : parsed.hour>=12 ? "pm" : "am";
        return hour+":"+String(parsed.minute).padStart(2,"0")+(twelve ? " "+period : "");
    }
    property string hourDraft:hourText.padStart(2,"0")
    property string minuteDraft:String(minute).padStart(2,"0")
    function commitHourText(text) {
        const n=Number(text);
        if (!/^\d{1,2}$/.test(text) || n<(twelveHour ? 1 : 0) || n>(twelveHour ? 12 : 23)) return false;
        chosen(formatStored(hourFromDisplay(n,pm,twelveHour),minute));
        return true;
    }
    function commitMinuteText(text) {
        const n=Number(text);
        if (!/^\d{1,2}$/.test(text) || n<0 || n>59) return false;
        chosen(formatStored(hour24,n));
        return true;
    }
    function syncDrafts() { hourDraft=hourText.padStart(2,"0");minuteDraft=String(minute).padStart(2,"0"); }
    onHourTextChanged:if (!hourValue.activeFocus) hourDraft=hourText.padStart(2,"0")
    onMinuteChanged:if (!minuteValue.activeFocus) minuteDraft=String(minute).padStart(2,"0")
    function adjustHour(delta) { chosen(formatStored(hour24+delta,minute));syncDrafts(); }
    function adjustMinute(delta) { chosen(formatStored(hour24,minute+delta));syncDrafts(); }
    function choosePeriod(pm) { commitHourText(hourDraft);commitMinuteText(minuteDraft);chosen(formatStored(hourFromDisplay(hour24%12 || 12,pm,true),minute));syncDrafts(); }
    function positionPopup() {
        if (!picker.parent) return;
        const point=root.mapToItem(picker.parent,0,0);
        const below=picker.parent.height-point.y-root.height-8;
        const above=point.y-8;
        picker.x=Math.max(8,Math.min(point.x+root.width-picker.width,picker.parent.width-picker.width-8));
        const preferredY=below>=picker.height || below>=above ? point.y+root.height+8 : point.y-picker.height-8;
        picker.y=Math.max(8,Math.min(preferredY,picker.parent.height-picker.height-8));
    }
    function open() { positionPopup();picker.open(); }
    function close() { picker.close();suppressTriggerClick=false; }
    component TimeReadout:CompactTextField {
        id:readout
        color:activeFocus ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        background:Rectangle { color:readout.activeFocus ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3;radius:Appearance.rounding.small }
    }
    TimeReadout {
        id:field
        anchors.fill:parent
        readOnly:true
        selectByMouse:false
        activeFocusOnTab:true
        text:root.displayTime(root.value,root.timeFormat)
        horizontalAlignment:Text.AlignHCenter
        Accessible.role:Accessible.Button
        Accessible.name:root.label+": "+text
        Accessible.description:Translation.tr("Open time picker")
        Keys.onReturnPressed:event => { root.open();event.accepted=true; }
        Keys.onSpacePressed:event => { root.open();event.accepted=true; }
        Accessible.onPressAction:root.open()
        MouseArea {
            id:trigger
            anchors.fill:parent
            hoverEnabled:true
            cursorShape:Qt.PointingHandCursor
            onPressed:if (picker.visible) { root.suppressTriggerClick=true;picker.close(); }
            onClicked: {
                if (root.suppressTriggerClick) { root.suppressTriggerClick=false;return; }
                root.open();
            }
            onReleased:if (!containsMouse) root.suppressTriggerClick=false
            onCanceled:root.suppressTriggerClick=false
            onExited:if (!pressed) root.suppressTriggerClick=false
        }
    }
    Popup {
        enter: OverlayTransition {}
        exit: OverlayTransition { entering: false }
        id:picker
        parent:Overlay.overlay
        width:Math.min(root.twelveHour ? 278 : 198,parent ? parent.width-16 : 278)
        height:timeColumns.implicitHeight+24
        padding:12
        modal:true
        Overlay.modal:Rectangle { color:"transparent" }
        focus:true
        closePolicy:Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background:Rectangle { color:Appearance.m3colors.m3surfaceContainerHigh;radius:Appearance.rounding.normal }
        onOpened: { root.positionPopup();root.syncDrafts();hourValue.forceActiveFocus();hourValue.selectAll(); }
        contentItem:RowLayout {
            id:timeColumns
            spacing:10
            Keys.onReturnPressed:event => { picker.close();root.suppressTriggerClick=false;event.accepted=true; }
            Keys.onEscapePressed:event => { picker.close();root.suppressTriggerClick=false;event.accepted=true; }
            ColumnLayout {
                spacing:6
                Layout.fillWidth:true
                RippleButton {
                    Layout.fillWidth:true;implicitHeight:34
                    buttonRadius:Appearance.rounding.small
                    autoRepeat:true
                    colBackground:Appearance.colors.colSecondaryContainer
                    colBackgroundHover:Appearance.colors.colSecondaryContainerHover
                    Accessible.name:Translation.tr("Increase hour")
                    onClicked:root.adjustHour(1)
                    contentItem:MaterialSymbol { text:"add";iconSize:20;color:Appearance.colors.colOnSecondaryContainer;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter }
                }
                TimeReadout {
                    id:hourValue
                    Layout.fillWidth:true;Layout.preferredWidth:72;Layout.preferredHeight:48
                    readOnly:false;selectByMouse:true
                    text:activeFocus ? root.hourDraft : root.hourText.padStart(2,"0")
                    maximumLength:2
                    inputMethodHints:Qt.ImhDigitsOnly
                    validator:IntValidator { bottom:root.twelveHour ? 1 : 0;top:root.twelveHour ? 12 : 23 }
                    onTextEdited:root.hourDraft=text
                    onEditingFinished:{ root.commitHourText(root.hourDraft);root.syncDrafts(); }
                    onActiveFocusChanged:if (activeFocus) { root.hourDraft=root.hourText.padStart(2,"0");Qt.callLater(() => hourValue.selectAll()); }
                    Keys.onReturnPressed:event => { root.commitHourText(root.hourDraft);root.syncDrafts();picker.close();event.accepted=true; }
                    horizontalAlignment:Text.AlignHCenter
                    font.family:Appearance.font.family.numbers
                    font.pixelSize:26
                    Accessible.name:Translation.tr("Hour: %1").arg(text)
                    Accessible.description:Translation.tr("Use Up and Down to change the hour.")
                    Keys.onUpPressed:event => { root.adjustHour(1);root.syncDrafts();event.accepted=true; }
                    Keys.onDownPressed:event => { root.adjustHour(-1);root.syncDrafts();event.accepted=true; }
                    Keys.onRightPressed:event => { minuteValue.forceActiveFocus();event.accepted=true; }
                }
                RippleButton {
                    Layout.fillWidth:true;implicitHeight:34
                    buttonRadius:Appearance.rounding.small
                    autoRepeat:true
                    colBackground:Appearance.colors.colSecondaryContainer
                    colBackgroundHover:Appearance.colors.colSecondaryContainerHover
                    Accessible.name:Translation.tr("Decrease hour")
                    onClicked:root.adjustHour(-1)
                    contentItem:MaterialSymbol { text:"remove";iconSize:20;color:Appearance.colors.colOnSecondaryContainer;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter }
                }
            }
            StyledText { text:":";font.pixelSize:26;color:Appearance.colors.colSubtext }
            ColumnLayout {
                spacing:6
                Layout.fillWidth:true
                RippleButton {
                    Layout.fillWidth:true;implicitHeight:34
                    buttonRadius:Appearance.rounding.small
                    autoRepeat:true
                    colBackground:Appearance.colors.colSecondaryContainer
                    colBackgroundHover:Appearance.colors.colSecondaryContainerHover
                    Accessible.name:Translation.tr("Increase minute")
                    onClicked:root.adjustMinute(1)
                    contentItem:MaterialSymbol { text:"add";iconSize:20;color:Appearance.colors.colOnSecondaryContainer;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter }
                }
                TimeReadout {
                    id:minuteValue
                    Layout.fillWidth:true;Layout.preferredWidth:72;Layout.preferredHeight:48
                    readOnly:false;selectByMouse:true
                    text:activeFocus ? root.minuteDraft : String(root.minute).padStart(2,"0")
                    maximumLength:2
                    inputMethodHints:Qt.ImhDigitsOnly
                    validator:IntValidator { bottom:0;top:59 }
                    onTextEdited:root.minuteDraft=text
                    onEditingFinished:{ root.commitMinuteText(root.minuteDraft);root.syncDrafts(); }
                    onActiveFocusChanged:if (activeFocus) { root.minuteDraft=String(root.minute).padStart(2,"0");Qt.callLater(() => minuteValue.selectAll()); }
                    Keys.onReturnPressed:event => { root.commitMinuteText(root.minuteDraft);root.syncDrafts();picker.close();event.accepted=true; }
                    horizontalAlignment:Text.AlignHCenter
                    font.family:Appearance.font.family.numbers
                    font.pixelSize:26
                    Accessible.name:Translation.tr("Minute: %1").arg(text)
                    Accessible.description:Translation.tr("Use Up and Down to change the minute.")
                    Keys.onUpPressed:event => { root.adjustMinute(1);root.syncDrafts();event.accepted=true; }
                    Keys.onDownPressed:event => { root.adjustMinute(-1);root.syncDrafts();event.accepted=true; }
                    Keys.onLeftPressed:event => { hourValue.forceActiveFocus();event.accepted=true; }
                    Keys.onRightPressed:event => { if (root.twelveHour) amButton.forceActiveFocus();event.accepted=true; }
                }
                RippleButton {
                    Layout.fillWidth:true;implicitHeight:34
                    buttonRadius:Appearance.rounding.small
                    autoRepeat:true
                    colBackground:Appearance.colors.colSecondaryContainer
                    colBackgroundHover:Appearance.colors.colSecondaryContainerHover
                    Accessible.name:Translation.tr("Decrease minute")
                    onClicked:root.adjustMinute(-1)
                    contentItem:MaterialSymbol { text:"remove";iconSize:20;color:Appearance.colors.colOnSecondaryContainer;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter }
                }
            }
            Item {
                visible:root.twelveHour
                Layout.alignment:Qt.AlignVCenter
                Layout.preferredWidth:60
                implicitHeight:88
                SelectionIndicator {
                    anchors.fill:parent
                    container:periodButtons
                    selectedItem:root.pm ? pmButton : amButton
                    hoveredItem:periodButtons.hoveredChoice
                    radius:Appearance.rounding.small
                    animate:picker.opened
                }
                ColumnLayout {
                id:periodButtons
                anchors.fill:parent
                property Item hoveredChoice:null
                spacing:8
                RippleButton {
                    id:amButton
                    onIsHoveredChanged:if (isHovered) periodButtons.hoveredChoice=amButton;else if (periodButtons.hoveredChoice===amButton) periodButtons.hoveredChoice=null
                    Layout.fillWidth:true;implicitHeight:40
                    buttonRadius:Appearance.rounding.small
                    toggled:!root.pm
                    colBackground:"transparent"
                    colBackgroundHover:"transparent"
                    colBackgroundToggled:"transparent"
                    colBackgroundToggledHover:"transparent"
                    colRippleToggled:Appearance.colors.colSecondaryContainerActive
                    Accessible.role:Accessible.RadioButton
                    Accessible.checked:toggled
                    Accessible.name:Translation.tr("AM")
                    onClicked:root.choosePeriod(false)
                    Keys.onDownPressed:event => { pmButton.forceActiveFocus();event.accepted=true; }
                    Keys.onLeftPressed:event => { minuteValue.forceActiveFocus();event.accepted=true; }
                    contentItem:StyledText { text:"AM";horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;color:amButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2 }
                }
                RippleButton {
                    id:pmButton
                    onIsHoveredChanged:if (isHovered) periodButtons.hoveredChoice=pmButton;else if (periodButtons.hoveredChoice===pmButton) periodButtons.hoveredChoice=null
                    Layout.fillWidth:true;implicitHeight:40
                    buttonRadius:Appearance.rounding.small
                    toggled:root.pm
                    colBackground:"transparent"
                    colBackgroundHover:"transparent"
                    colBackgroundToggled:"transparent"
                    colBackgroundToggledHover:"transparent"
                    colRippleToggled:Appearance.colors.colSecondaryContainerActive
                    Accessible.role:Accessible.RadioButton
                    Accessible.checked:toggled
                    Accessible.name:Translation.tr("PM")
                    onClicked:root.choosePeriod(true)
                    Keys.onUpPressed:event => { amButton.forceActiveFocus();event.accepted=true; }
                    Keys.onLeftPressed:event => { minuteValue.forceActiveFocus();event.accepted=true; }
                    contentItem:StyledText { text:"PM";horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;color:pmButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2 }
                }
                }
            }
        }
    }
}
