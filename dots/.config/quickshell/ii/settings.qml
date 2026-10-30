//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.desktop
import qs.modules.ii.overview

AppWindow {
    id:root
    appTitle:Translation.tr("Settings")
    // Keep the settings workspace readable even when shell surfaces are translucent.
    color:Appearance.colors.colLayer0Base
    showWindowChrome:false
    minimumWidth:740
    width:1080
    // Header, spacing and outer insets add 92px to the category list.
    height:Math.min(Math.max(minimumHeight,Math.ceil(navigation.implicitHeight)+92),Math.max(minimumHeight,Screen.desktopAvailableHeight-32))
    SettingsAppearancePreview {}
    property bool searchOpen:false
    function revealSearch() { searchOpen=true; Qt.callLater(() => { search.forceActiveFocus(); search.selectAll(); }); }
    function hideSearch() { searchDelay.stop(); search.clear(); query=""; searchOpen=false; searchToggle.forceActiveFocus(); }
    readonly property bool reducedMotion:Config.options.launcher.reducedMotion
    property Item selectedNavButton:null
    property Item hoveredNavButton:null
    function hoverCategory(button) { hoveredNavButton=button; }
    readonly property string navigationCategory:nextPage.category
    property int pageDirection:1
    function navHeading(index) {
        const category=SettingsCatalog.categories[index];
        return category && (index===0 || SettingsCatalog.categories[index-1].navGroup!==category.navGroup) ? category.navGroup : "";
    }
    property string categoryId:Quickshell.env("QS_SETTINGS_PAGE")==="homeAssistant" ? "home" : Quickshell.env("QS_SETTINGS_CATEGORY") || Persistent.states.settingsApp.category
    property string groupId:Quickshell.env("QS_SETTINGS_PAGE")==="homeAssistant" ? "tools.home" : Quickshell.env("QS_SETTINGS_SUBSECTION") || Persistent.states.settingsApp.subsection
    property string query:""
    property bool discarding:false
    property bool closeAfterSave:false
    property bool saveConfirmed:false
    property bool saveConfirmationFading:false
    property string feedbackText:""
    property string feedbackAction:"retry"
    property string feedbackPath:""
    function reviewFeedback() {
        const setting=SettingsCatalog.entry(feedbackPath);
        if (!setting) return;
        const tool=SettingsCatalog.actions.find(action => action.path===SettingsCatalog.toolActionFor(feedbackPath));
        navigate(tool ? tool.category : setting.category,tool ? tool.group : SettingsCatalog.destination(setting));
    }
    Timer { id:saveConfirmationDelay; interval:1600; onTriggered:root.saveConfirmationFading=true }
    function saveAndClose() {
        closeAfterSave=true;
        if (SettingsCatalog.committing) { closeDialog.close();return; }
        if (!SettingsCatalog.saveAll()) { closeAfterSave=false; closeDialog.close(); }
    }
    Connections {
        target:SettingsCatalog
        function onFeedbackRequested(text,kind,action,settingPath) {
            if (kind==="success") {
                root.saveConfirmationFading=false;
                root.saveConfirmed=SettingsCatalog.unappliedCount===0;
                if (root.saveConfirmed) saveConfirmationDelay.restart();
            } else {
                root.saveConfirmed=false;
                root.saveConfirmationFading=false;
                root.feedbackText=text;
                root.feedbackAction=action;
                root.feedbackPath=settingPath;
            }
        }
        function onUnappliedCountChanged() {
            if (SettingsCatalog.unappliedCount) { root.saveConfirmed=false;root.saveConfirmationFading=false;saveConfirmationDelay.stop(); }
        }
        function onSaved() {
            if (root.closeAfterSave) { root.closeAfterSave=false; root.discarding=SettingsCatalog.unappliedCount===0; root.close(); }
        }
        function onErrorChanged() {
            if (root.closeAfterSave && SettingsCatalog.error) { root.closeAfterSave=false; closeDialog.close(); }
        }
    }
    onReducedMotionChanged:if (reducedMotion && pageAnimation && pageAnimation.running) {
        pageAnimation.stop();
        content.opacity=1;
        content.x=0;
    }
    property var nextPage:({category:categoryId,group:groupId})
    closeHandler:() => {
        if (SettingsCatalog.committing) { root.closeAfterSave=true;closeDialog.close();return false; }
        if (!discarding && SettingsCatalog.unappliedCount) { SettingsCatalog.dismissPopups(); Qt.callLater(() => closeDialog.open()); return false; }
        return true;
    }
    function navigate(category,group) {
        category=SettingsCatalog.category(category).id;
        group=SettingsCatalog.canonicalGroup(category,group);
        if (category===categoryId && group===groupId && !query && !search.text) return;
        pageDirection=category===categoryId && !!groupId && group===SettingsCatalog.parentGroup(groupId) ? -1 : 1;
        root.hideSearch();
        SettingsCatalog.dismissPopups();
        nextPage={category:category,group:group};
        // Apply immediately. Waiting for an exit animation made every navigation
        // feel like a load, even when the destination was already available.
        pageAnimation.stop();
        root.applyPage();
        content.x=0;
        if (root.reducedMotion) content.opacity=1;
        else pageAnimation.restart();
    }
    Component.onCompleted: Qt.callLater(() => { if (groupId==="tools.wallpaper") { categoryId="appearance";groupId=""; } if (groupId==="tools.translation") { categoryId="language";groupId="__advanced__"; } categoryId=SettingsCatalog.category(categoryId).id; groupId=SettingsCatalog.canonicalGroup(categoryId,groupId); })
    Shortcut { sequence:"Ctrl+S"; onActivated:SettingsCatalog.saveAll() }
    Shortcut { sequence:"Ctrl+W"; onActivated:root.close() }
    function applyPage() {
        categoryId=nextPage.category; groupId=nextPage.group;
        Persistent.states.settingsApp.category=categoryId;
        Persistent.states.settingsApp.subsection=groupId;
        navReveal.restart();
    }
    Timer {
        id:navReveal; interval:root.reducedMotion ? 0 : Appearance.animation.elementMoveSmall.duration
        onTriggered:{
            const index=SettingsCatalog.categories.findIndex(c => c.id===root.categoryId);
            const item=categoryRepeater.itemAt(index);
            if (!item) return;
            const bottom=item.y+item.height;
            if (item.y<navFlickable.contentY) navFlickable.contentY=item.y;
            else if (bottom>navFlickable.contentY+navFlickable.height) navFlickable.contentY=Math.max(0,Math.min(item.y,bottom-navFlickable.height));
        }
    }
    Shortcut { sequence:"Ctrl+F"; onActivated:root.revealSearch() }
    Shortcut { sequence:"Ctrl+K"; onActivated:root.revealSearch() }
    Shortcut { sequence:"Ctrl+Z"; enabled:SettingsCatalog.history.length>0 && (!root.activeFocusItem || typeof root.activeFocusItem.undo !== "function"); onActivated:SettingsCatalog.undo() }
    Shortcut { sequence:"Escape"; enabled:root.searchOpen; onActivated:root.hideSearch() }
    TapHandler {
        parent:root.contentItem
        enabled:root.searchOpen && !search.text.trim().length
        acceptedButtons:Qt.LeftButton | Qt.RightButton
        gesturePolicy:TapHandler.DragThreshold
        onPressedChanged:if (pressed) {
            const fieldPoint=search.mapFromItem(root.contentItem,point.position.x,point.position.y);
            const togglePoint=searchToggle.mapFromItem(root.contentItem,point.position.x,point.position.y);
            if (fieldPoint.x>=0 && fieldPoint.x<=search.width && fieldPoint.y>=0 && fieldPoint.y<=search.height) return;
            if (togglePoint.x>=0 && togglePoint.x<=searchToggle.width && togglePoint.y>=0 && togglePoint.y<=searchToggle.height) return;
            root.hideSearch();
        }
    }
    RowLayout {
        anchors.fill:parent
        spacing:0
        Rectangle {
            Layout.preferredWidth:224
            Layout.fillHeight:true
            radius:Appearance.rounding.normal
            color:Appearance.colors.colLayer0
            ColumnLayout {
                anchors.fill:parent
                anchors.margins:12
                spacing:20
                Item {
                    id:sidebarHeader
                    Layout.fillWidth:true
                    Layout.fillHeight:false
                    Layout.preferredHeight:48
                    Layout.maximumHeight:48
                    implicitHeight:48
                    property real searchProgress:root.searchOpen ? 1 : 0
                    onSearchProgressChanged:if (!root.searchOpen && searchProgress===0) searchToggle.forceActiveFocus(Qt.OtherFocusReason)
                    Behavior on searchProgress {
                        enabled:!root.reducedMotion
                        NumberAnimation {
                            duration:Appearance.animation.elementResize.duration
                            easing.type:Easing.BezierSpline
                            easing.bezierCurve:Appearance.animationCurves.emphasized
                        }
                    }
                    StyledText {
                        id:settingsTitle
                        anchors.left:parent.left;anchors.leftMargin:12
                        anchors.verticalCenter:parent.verticalCenter
                        text:Translation.tr("Settings")
                        font.family:Appearance.font.family.title
                        font.pixelSize:Appearance.font.pixelSize.title
                        font.weight:Font.Bold
                        font.variableAxes:({})
                    }
                    IconToolbarButton {
                        id:searchToggle
                        anchors.right:parent.right
                        anchors.verticalCenter:parent.verticalCenter
                        implicitWidth:40;implicitHeight:40
                        visible:!root.searchOpen && sidebarHeader.searchProgress===0
                        text:"search"
                        Accessible.name:Translation.tr("Search settings")
                        onClicked:root.revealSearch()
                        StyledToolTip { text:Translation.tr("Search settings · Ctrl+K") }
                    }
                    Item {
                        z:2
                        anchors.right:parent.right
                        anchors.verticalCenter:parent.verticalCenter
                        width:40+(parent.width-40)*Math.max(0,Math.min(1,sidebarHeader.searchProgress))
                        height:48
                        clip:true
                        visible:root.searchOpen || sidebarHeader.searchProgress>0
                        Rectangle {
                            anchors.fill:parent
                            radius:Appearance.rounding.normal
                            color:Appearance.colors.colLayer0Base
                        }
                        SearchField {
                            id:search
                            anchors.fill:parent
                            enabled:root.searchOpen
                            opacity:1
                            showClearButton:false
                            rightPadding:40
                            placeholderText:Translation.tr("Search settings")
                            Accessible.name:Translation.tr("Search all settings")
                            onTextChanged:searchDelay.restart()
                            Keys.onEscapePressed:root.hideSearch()
                        }
                        IconToolbarButton {
                            id:searchClose
                            anchors.right:parent.right;anchors.rightMargin:2
                            anchors.verticalCenter:parent.verticalCenter
                            implicitWidth:36;implicitHeight:36
                            text:root.searchOpen ? "close" : "search"
                            Accessible.name:Translation.tr(root.searchOpen ? "Close search" : "Search settings")
                            onClicked:root.searchOpen ? root.hideSearch() : root.revealSearch()
                            contentItem:MaterialSymbol {
                                anchors.centerIn:parent
                                text:searchClose.text
                                iconSize:22
                                color:searchClose.colText
                                animateChange:false
                            }
                        }
                    }
                }
                Timer { id:searchDelay; interval:120; onTriggered:root.query=search.text.trim() }
                StyledFlickable {
                    id:navFlickable
                    Layout.fillWidth:true; Layout.fillHeight:true
                    contentHeight:navigation.implicitHeight
                    clip:true
                    HoverHandler {
                        onHoveredChanged:if (!hovered) root.hoveredNavButton=null
                    }
                    ScrollBar.vertical: SpotlightScrollBar {
                        scrolling:navFlickable.moving
                        reducedMotion:Config.options.launcher.reducedMotion
                    }
                    SelectionIndicator {
                        id:categoryIndicator
                        container:navFlickable.contentItem
                        selectedItem:root.query ? null : root.selectedNavButton
                        hoveredItem:root.hoveredNavButton
                    }
                    ColumnLayout {
                        id:navigation
                        width:Math.max(0,parent.width-14)
                        spacing:4
                        Repeater {
                            id:categoryRepeater
                            model:SettingsCatalog.categories
                            delegate:ColumnLayout {
                                id:category
                                required property var modelData
                                required property int index
                                property alias navItem:navButton
                                Layout.fillWidth:true
                                spacing:2
                                RowLayout {
                                    visible:!!root.navHeading(category.index)
                                    Layout.leftMargin:12
                                    Layout.topMargin:category.index ? 14 : 0
                                    Layout.bottomMargin:6
                                    spacing:6
                                    MaterialSymbol { text:category.modelData.navGroupIcon || "category";iconSize:14;color:Appearance.colors.colSubtext }
                                    StyledText { text:Translation.tr(root.navHeading(category.index));color:Appearance.colors.colSubtext;font.pixelSize:Appearance.font.pixelSize.smaller }
                                }
                                RippleButton {
                                    id:navButton
                                    objectName:"settingsCategory"
                                    Layout.fillWidth:true
                                    implicitHeight:42
                                    leftPadding:12; rightPadding:12
                                    topPadding:0; bottomPadding:0
                                    buttonRadius:height/2
                                    toggled:root.navigationCategory===category.modelData.id && !root.query
                                    onToggledChanged:if (toggled) root.selectedNavButton=navButton
                                    onIsHoveredChanged: {
                                        if (isHovered) root.hoverCategory(navButton);
                                    }
                                    Component.onCompleted:if (toggled) root.selectedNavButton=navButton
                                    rippleEnabled:!root.reducedMotion
                                    background:Rectangle {
                                        radius:height/2
                                        color:"transparent"
                                        Rectangle {
                                            anchors.fill:parent; anchors.margins:2
                                            radius:parent.radius
                                            visible:navButton.visualFocus
                                            color:"transparent"
                                            border.width:2
                                            border.color:navButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                        }
                                    }
                                    Accessible.name:Translation.tr(category.modelData.title)
                                    onClicked:root.navigate(category.modelData.id,"")
                                    contentItem:Item {
                                        implicitHeight:24
                                        RowLayout {
                                            anchors.fill:parent
                                            spacing:12
                                            MaterialSymbol {
                                                objectName:"categoryIcon"
                                                Layout.preferredWidth:24; Layout.preferredHeight:24
                                                Layout.alignment:Qt.AlignVCenter
                                                horizontalAlignment:Text.AlignHCenter
                                                verticalAlignment:Text.AlignVCenter
                                                text:category.modelData.icon; iconSize:22
                                                color:navButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                                            }
                                            StyledText {
                                                objectName:"categoryLabel"
                                                Layout.fillWidth:true; Layout.fillHeight:true
                                                verticalAlignment:Text.AlignVCenter
                                                text:Translation.tr(category.modelData.title)
                                                color:navButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                                                elide:Text.ElideRight
                                                font.weight:navButton.toggled ? Font.Medium : Font.Normal
                                            }
                                        }
                                    }
                                }

                            }
                        }
                    }
                }

            }
        }
        Rectangle {
            Layout.fillWidth:true; Layout.fillHeight:true
            radius:Appearance.rounding.normal
            color:Appearance.colors.colLayer1
            ColumnLayout {
                anchors.fill:parent
                spacing:0
                Item {
                    Layout.fillWidth:true; Layout.fillHeight:true
                    SettingsContent {
                        id:content
                        width:parent.width; height:parent.height
                        visible:Config.ready
                        categoryId:root.categoryId
                        groupId:root.groupId
                        query:root.query
                        onNavigate:(category,group) => root.navigate(category,group)
                    }
                    StyledText { anchors.centerIn:parent; visible:!Config.ready; text:Config.lastError ? Translation.tr("Settings could not be loaded.") : Translation.tr("Loading settings…"); color:Appearance.colors.colSubtext }
                }
                RowLayout {
                    visible:!!SettingsCatalog.error || !!Config.lastError
                    Layout.fillWidth:true
                    Layout.leftMargin:24; Layout.rightMargin:96
                    Layout.topMargin:8; Layout.bottomMargin:20
                    spacing:10
                    MaterialSymbol {
                        Layout.alignment:Qt.AlignTop
                        Layout.topMargin:6
                        text:"error";iconSize:20;color:Appearance.m3colors.m3error
                    }
                    StyledText {
                        Layout.fillWidth:true
                        text:SettingsCatalog.error ? root.feedbackText || SettingsCatalog.error : Config.lastError
                        color:Appearance.m3colors.m3error
                        wrapMode:Text.Wrap
                        Accessible.role:Accessible.AlertMessage
                    }
                    DialogButton {
                        buttonText:SettingsCatalog.error && root.feedbackAction==="edit" ? Translation.tr("Review") : Translation.tr("Retry")
                        onClicked:{
                            if (SettingsCatalog.error && root.feedbackAction==="edit") root.reviewFeedback();
                            else if (SettingsCatalog.unappliedCount) SettingsCatalog.saveAll();
                            else Config.reload();
                        }
                    }
                }
            }
        }
    }
    RippleButton {
        id:saveButton
        z:100
        anchors.right:parent.right
        anchors.bottom:parent.bottom
        anchors.margins:24
        opacity:SettingsCatalog.unappliedCount>0 || root.saveConfirmed && !root.saveConfirmationFading ? 1 : 0
        onOpacityChanged:if (opacity===0 && root.saveConfirmationFading) {
            root.saveConfirmed=false;
            root.saveConfirmationFading=false;
        }
        visible:opacity>0
        enabled:!SettingsCatalog.committing && !root.saveConfirmed && SettingsCatalog.unappliedCount>0
        Behavior on opacity {
            enabled:!root.reducedMotion
            NumberAnimation { duration:Appearance.animation.elementMoveFast.duration; easing.type:Appearance.animation.elementMoveFast.type; easing.bezierCurve:Appearance.animation.elementMoveFast.bezierCurve }
        }
        property real pressScale:down ? 0.88 : 1
        scale:root.reducedMotion ? 1 : opacity*pressScale
        Behavior on pressScale {
            enabled:!root.reducedMotion
            NumberAnimation {
                duration:Appearance.animation.elementMoveFast.duration
                easing.type:Easing.OutSine
            }
        }
        readonly property bool morphActive:down || SettingsCatalog.committing || root.saveConfirmed
        background:MaterialShape {
            shape:saveButton.morphActive ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Square
            color:saveButton.buttonColor
            animation:NumberAnimation {
                duration:root.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration
                easing.type:Easing.OutSine
            }
        }
        implicitWidth:56
        implicitHeight:56
        buttonRadius:Appearance.rounding.normal
        colBackground:Appearance.m3colors.m3primary
        colBackgroundHover:Appearance.colors.colPrimaryHover
        // Preserve the filled surface while busy or briefly confirming success.
        buttonColor:saveButton.enabled && saveButton.isHovered ? colBackgroundHover : colBackground
        contentItem:MaterialSymbol {
            id:saveSymbol
            text:SettingsCatalog.committing ? "progress_activity" : root.saveConfirmed ? "check" : "save"
            iconSize:28
            NumberAnimation on rotation {
                id:saveRotation
                from:0; to:360
                duration:1000
                loops:Animation.Infinite
                running:SettingsCatalog.committing && !root.reducedMotion
                onRunningChanged:if (!running) saveSymbol.rotation=0
            }
            Connections {
                target:SettingsCatalog
                function onCommittingChanged() {
                    if (!SettingsCatalog.committing) Qt.callLater(() => saveSymbol.rotation=0);
                }
            }
            color:Appearance.m3colors.m3onPrimary
            horizontalAlignment:Text.AlignHCenter
            verticalAlignment:Text.AlignVCenter
        }
        onClicked:SettingsCatalog.saveAll()
        Accessible.name:root.saveConfirmed ? Translation.tr("Settings saved") : SettingsCatalog.committing ? Translation.tr("Saving settings") : Translation.tr("Save settings")
        Accessible.description:root.saveConfirmed ? "" : Translation.tr("Ctrl+S")
        StyledToolTip { text:root.saveConfirmed ? Translation.tr("Saved") : Translation.tr("Save (Ctrl+S)") }
    }
    Shortcut { sequence:"Alt+Left"; enabled:!!root.groupId; onActivated:root.navigate(root.categoryId,SettingsCatalog.parentGroup(root.groupId)) }
    ParallelAnimation {
        id:pageAnimation
        NumberAnimation {
            target:content;property:"opacity";from:0;to:1
            duration:root.reducedMotion ? 0 : Appearance.animation.elementMoveEnter.duration
            easing.type:Appearance.animation.elementMoveEnter.type
            easing.bezierCurve:Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target:content;property:"x";from:root.pageDirection*18;to:0
            duration:root.reducedMotion ? 0 : Appearance.animation.elementMoveEnter.duration
            easing.type:Appearance.animation.elementMoveEnter.type
            easing.bezierCurve:Appearance.animation.elementMoveEnter.bezierCurve
        }
    }
    SaveChangesDialog {
        id:closeDialog
        busy:SettingsCatalog.committing
        message:Translation.tr("Your settings contain unsaved changes.\nChanges that are not saved will be lost.")
        onDiscardRequested:{ SettingsCatalog.discardAll();root.discarding=true;root.close(); }
        onSaveRequested:root.saveAndClose()
    }
}
