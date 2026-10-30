//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.desktop

AppWindow {
    id:root
    appTitle:Translation.tr("Welcome")
    width:940; height:740
    property int currentStep:0
    property bool showNextTime:false
    property bool finishing:false
    property string finishError:""
    readonly property var steps:[
        {title:"Language",icon:"language",description:"Choose the language used throughout your desktop.",preferences:["language.ui"]},
        {title:"Appearance",icon:"palette",description:"Make the desktop yours with colors, fonts and wallpaper.",preferences:["appearance.palette.type","appearance.extraBackgroundTint","appearance.fakeScreenRounding"]},
        {title:"Layout",icon:"dashboard",description:"Choose your bar and the controls you use every day.",preferences:["bar.bottom","bar.vertical","dock.enable"]},
        {title:"Ready",icon:"check_circle",description:"Your desktop is ready. Every preference is available in Settings.",preferences:["policies.ai","policies.weeb"]}
    ]
    function openSettings(category,group) { Quickshell.execDetached(["env","QS_SETTINGS_CATEGORY="+category,"QS_SETTINGS_SUBSECTION="+group,"qs","-p",Quickshell.shellPath("settings.qml")]); }
    FileView {
        id:firstRunFile
        path:FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
        watchChanges:true
        printErrors:false
        onSaved:if (root.finishing) root.close()
        onSaveFailed:error => { root.finishing=false; root.finishError=Translation.tr("Could not save your welcome preference. Try again."); }
    }
    function setShowNextTime(show) {
        if (show) { Quickshell.execDetached(["rm","-f",FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)]); root.close(); }
        else if (firstRunFile.loaded && firstRunFile.text()==="Welcome completed.\n") root.close();
        else firstRunFile.setText("Welcome completed.\n");
    }
    ColumnLayout {
        anchors.fill:parent
        anchors.margins:12
        spacing:18
        RowLayout {
            Layout.fillWidth:true
            Repeater {
                model:root.steps
                delegate:RippleButton {
                    id:stepButton
                    required property int index
                    required property var modelData
                    Layout.fillWidth:true
                    implicitHeight:52
                    buttonRadius:Appearance.rounding.full
                    toggled:root.currentStep===index
                    buttonText:Translation.tr(modelData.title)
                    Accessible.name:buttonText
                    colBackgroundToggled:Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover:Appearance.colors.colSecondaryContainerHover
                    colRippleToggled:Appearance.colors.colSecondaryContainerActive
                    contentItem:StyledText { text:stepButton.buttonText; horizontalAlignment:Text.AlignHCenter; color:stepButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0 }
                    onClicked:root.currentStep=index
                }
            }
        }
        Rectangle {
            Layout.fillWidth:true; Layout.fillHeight:true
            radius:Appearance.rounding.normal
            color:Appearance.colors.colLayer1
            StyledFlickable {
                id:page
                anchors.fill:parent; anchors.margins:24
                clip:true
                contentHeight:stepContent.implicitHeight+20
                ColumnLayout {
                    id:stepContent
                    width:page.width
                    spacing:14
                    RowLayout {
                        Layout.fillWidth:true; spacing:16
                        MaterialSymbol { text:root.steps[root.currentStep].icon; iconSize:42; color:Appearance.colors.colPrimary }
                        ColumnLayout {
                            Layout.fillWidth:true; spacing:6
                            StyledText { text:Translation.tr(root.steps[root.currentStep].title); font.family:Appearance.font.family.title; font.variableAxes:Appearance.font.variableAxes.title; font.pixelSize:Appearance.font.pixelSize.title }
                            StyledText { Layout.fillWidth:true; text:Translation.tr(root.steps[root.currentStep].description); color:Appearance.colors.colSubtext; wrapMode:Text.Wrap }
                        }
                    }
                    Repeater { model:root.steps[root.currentStep].preferences; delegate:SettingRow { required property string modelData; setting:SettingsCatalog.entry(modelData) } }
                    RowLayout {
                        visible:root.currentStep===1
                        Layout.fillWidth:true
                        RippleButtonWithIcon { materialIcon:"wallpaper"; mainText:Translation.tr("Choose wallpaper"); onClicked:Quickshell.execDetached([Directories.wallpaperSwitchScriptPath]) }
                        DialogButton { buttonText:Translation.tr("More appearance settings"); onClicked:root.openSettings("appearance","") }
                    }
                    ColumnLayout {
                        visible:root.currentStep===3
                        Layout.fillWidth:true
                        spacing:12
                        StyledText { text:Translation.tr("Useful shortcuts"); font.weight:Font.Medium }
                        StyledText { text:Translation.tr("Super+I  Settings\nSuper+/  Keyboard shortcuts\nSuper+A  Assistant sidebar\nSuper+N  Controls and notifications"); wrapMode:Text.Wrap; color:Appearance.colors.colSubtext; Layout.fillWidth:true }
                        RowLayout {
                            RippleButtonWithIcon { materialIcon:"settings"; mainText:Translation.tr("Open Settings"); onClicked:root.openSettings("appearance","") }
                            DialogButton { buttonText:Translation.tr("Keyboard shortcuts"); onClicked:Quickshell.execDetached(["qs","-p",Quickshell.shellPath(""),"ipc","call","cheatsheet","toggle"]) }
                        }
                    }
                }
            }
        }
        StyledText { visible:!!root.finishError; text:root.finishError; color:Appearance.colors.colError; wrapMode:Text.Wrap; Layout.fillWidth:true }
        RowLayout {
            Layout.fillWidth:true
            enabled:!root.finishing
            StyledSwitch { checked:root.showNextTime; onClicked:root.showNextTime=checked; Accessible.name:Translation.tr("Show welcome next time") }
            StyledText { text:Translation.tr("Show next time"); font.pixelSize:Appearance.font.pixelSize.smaller; color:Appearance.colors.colSubtext }
            Item { Layout.fillWidth:true }
            DialogButton { buttonText:Translation.tr("Back"); enabled:root.currentStep>0; onClicked:root.currentStep-- }
            RippleButtonWithIcon { materialIcon:root.currentStep===3 ? "check" : "arrow_forward"; mainText:root.finishing ? Translation.tr("Finishing…") : root.currentStep===3 ? Translation.tr("Finish") : Translation.tr("Next"); onClicked:{ if (root.currentStep===3) { root.finishError=""; root.finishing=true; root.setShowNextTime(root.showNextTime); } else root.currentStep++; } }
        }
    }
    Behavior on currentStep {
        SequentialAnimation {
            NumberAnimation { target:stepContent; property:"opacity"; to:0; duration:Appearance.animation.elementMoveExit.duration; easing.type:Appearance.animation.elementMoveExit.type; easing.bezierCurve:Appearance.animation.elementMoveExit.bezierCurve }
            PropertyAction {}
            ScriptAction { script:page.contentY=0 }
            NumberAnimation { target:stepContent; property:"opacity"; to:1; duration:Appearance.animation.elementMoveEnter.duration; easing.type:Appearance.animation.elementMoveEnter.type; easing.bezierCurve:Appearance.animation.elementMoveEnter.bezierCurve }
        }
    }
}
