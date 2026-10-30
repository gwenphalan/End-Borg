import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.tool_app
import qs.modules.settings.desktop as SettingsControls

RowLayout {
    id:bar
    required property var workspace
    readonly property bool inputFocused:fov.inputFocused || coefficientOne.inputFocused || coefficientTwo.inputFocused || zoom.inputFocused || modeControls.inputFocused
    implicitHeight:96
    readonly property bool compact:workspace.width<1500
    spacing:compact ? 10 : 16
    component Caption:StyledText {font.pixelSize:13;color:Appearance.colors.colSubtext}
    component Divider:Rectangle {Layout.preferredWidth:1;Layout.fillHeight:true;Layout.topMargin:6;Layout.bottomMargin:6;color:Appearance.colors.colOutlineVariant}
    component FieldIcon:MaterialSymbol {
        property string description:""
        iconSize:20;color:Appearance.colors.colSubtext
        HoverHandler {id:hover}
        StyledToolTip {text:parent.description;extraVisibleCondition:hover.hovered}
    }
    ColumnLayout {
        visible:bar.workspace.stage==="lens";Layout.fillWidth:false;spacing:6
        Caption {text:"Lens profile"}
        ToolProfilePicker {
            id:profiles
            objectName:"lensProfilePicker"
            Layout.preferredWidth:bar.compact ? 270 : 330;Layout.fillWidth:false
            profiles:bar.workspace.lensProfiles.map(profile=>({id:profile.path,name:profile.name}))
            selectedId:bar.workspace.lensProfilePath
            canSave:!!bar.workspace.calibration
            busy:bar.workspace.busy
            onSelectionRequested:id=>{if(id!==bar.workspace.lensProfilePath){if(id)bar.workspace.send("load_preset",{path:id,curves:[]});else bar.workspace.send("clear_profile");}}
            onSaveRequested:name=>bar.workspace.send("save_profile",{name:name})
            onRenameRequested:(id,name)=>bar.workspace.send("rename_profile",{path:id,name:name})
            onUpdateRequested:id=>bar.workspace.send("update_profile",{path:id})
            onDeleteRequested:id=>bar.workspace.send("delete_profile",{path:id})
        }
    }
    Divider {visible:bar.workspace.stage==="lens"}
    ColumnLayout {visible:bar.workspace.stage==="lens";Layout.fillWidth:false;spacing:6
        Caption {text:"Lens"}
        GridLayout {
            columns:bar.compact ? 1 : 2;columnSpacing:8;rowSpacing:5
            RowLayout {spacing:8
            FieldIcon {text:"panorama_horizontal";description:"Horizontal field of view"}
            NumberInput {
                id:fov;objectName:"ribbonFov"
                Layout.preferredWidth:155;Layout.fillWidth:false
                number:bar.workspace.ribbonSettings.hfov ?? bar.workspace.defaultHfov
                minimum:1;maximum:179;increment:.1;unit:"°"
                Accessible.name:"Horizontal field of view"
                onEdited:value=>bar.workspace.queueRibbonSettings({hfov:value})
            }
            ToolIconButton {text:"restart_alt";Accessible.name:"Default horizontal FOV";enabled:bar.workspace.ribbonSettings.hfov!==null;onClicked:bar.workspace.queueRibbonSettings({hfov:null});StyledToolTip {text:parent.Accessible.name}}
            }
            RowLayout {spacing:8
            FieldIcon {text:"lens_blur";description:"Radial distortion model"}
            SettingsControls.SettingsPresetDropdown {
                objectName:"ribbonRadialModel"
                Layout.preferredWidth:135;Layout.fillWidth:false
                label:"Radial model";choices:[{name:"Auto",value:0},{name:"k1",value:1},{name:"k1 + k2",value:2}]
                value:bar.workspace.ribbonSettings.order
                onChosen:value=>bar.workspace.queueRibbonSettings({order:value})
            }

            }
        }
    }
    Divider {visible:bar.workspace.stage==="lens"}
    ColumnLayout {visible:bar.workspace.stage==="lens";Layout.fillWidth:false;spacing:5
        Caption {text:"Coefficients"}
        GridLayout {
            columns:2;columnSpacing:7;rowSpacing:5
            Caption {text:"k1"}
            UnboundedNumberInput {
                id:coefficientOne;objectName:"ribbonK1"
                Layout.preferredWidth:170;Layout.fillWidth:false
                number:bar.workspace.ribbonCoefficients[0];minimum:-Infinity;increment:.001;integral:false;displayDecimals:6
                enabled:!!bar.workspace.calibration
                Accessible.name:"Radial coefficient k1"
                onEdited:value=>bar.workspace.queueRibbonCoefficient(0,value)
                onInvalidEdited:bar.workspace.cancelRibbonCoefficient()
            }
            Caption {text:"k2"}
            UnboundedNumberInput {
                id:coefficientTwo;objectName:"ribbonK2"
                Layout.preferredWidth:170;Layout.fillWidth:false
                number:bar.workspace.ribbonCoefficients[1];minimum:-Infinity;increment:.001;integral:false;displayDecimals:6
                enabled:!!bar.workspace.calibration && bar.workspace.calibration.order===2
                Accessible.name:"Radial coefficient k2"
                onEdited:value=>bar.workspace.queueRibbonCoefficient(1,value)
                onInvalidEdited:bar.workspace.cancelRibbonCoefficient()
            }
        }
    }
    RippleButtonWithIcon {
        objectName:"ribbonCalculate";visible:bar.workspace.stage==="lens"
        materialIcon:"calculate";mainText:"Calculate";buttonRadius:height/2
        implicitHeight:36
        colBackground:Appearance.colors.colPrimary
        colBackgroundHover:Appearance.colors.colPrimaryHover
        contentColor:Appearance.colors.colOnPrimary
        Layout.fillWidth:false
        Accessible.name:"Calculate lens correction";enabled:bar.workspace.curves.length>0
        onClicked:bar.workspace.calculateFromRibbon()
        StyledToolTip {text:parent.Accessible.name}
    }
    ModeOperations {
        id:modeControls
        visible:bar.workspace.stage!=="lens"
        Layout.fillWidth:false
        workspace:bar.workspace
    }
    ToolIconButton {
        visible:bar.workspace.stage==="lens"
        text:"grid_on";toggled:bar.workspace.ribbonSettings.snapping;Accessible.name:"Snap to pixels"
        onClicked:bar.workspace.queueRibbonSettings({snapping:!bar.workspace.ribbonSettings.snapping})
        StyledToolTip {text:parent.Accessible.name}
    }
    Item {Layout.fillWidth:true}
    Divider {}
    ColumnLayout {
        Layout.fillWidth:false;spacing:8
        RowLayout {
            Layout.fillWidth:true
            Caption {text:"View"}
            Item {Layout.fillWidth:true}
            ToolIconButton {
                objectName:"toggleRegionsVisibility"
                text:"polyline";toggled:bar.workspace.showRegions
                Accessible.name:bar.workspace.showRegions ? "Hide regions" : "Show regions"
                onClicked:bar.workspace.showRegions=!bar.workspace.showRegions
                StyledToolTip {text:parent.Accessible.name}
            }
            ToolIconButton {
                objectName:"toggleCalibrationCurvesVisibility"
                text:"gesture";toggled:bar.workspace.showCalibrationCurves
                Accessible.name:bar.workspace.showCalibrationCurves ? "Hide calibration curves" : "Show calibration curves"
                onClicked:bar.workspace.showCalibrationCurves=!bar.workspace.showCalibrationCurves
                StyledToolTip {text:parent.Accessible.name}
            }

        }
        RowLayout {
            spacing:10
            ToolZoomControl {
                id:zoom;resetBeforeInput:true;percent:bar.workspace.activeView.viewZoomPercent;atReset:bar.workspace.activeView.viewAtReset
                onZoomEdited:value=>bar.workspace.activeView.setZoomPercent(value)
                onResetRequested:bar.workspace.activeView.fit()
            }
            ToolIconButton {
                objectName:"toggleCorrectedView"
                text:bar.workspace.stage!=="lens" || bar.workspace.corrected ? "visibility" : "visibility_off"
                toggled:bar.workspace.stage!=="lens" || bar.workspace.corrected;enabled:bar.workspace.stage==="lens" && bar.workspace.preview!==""
                Accessible.name:bar.workspace.stage!=="lens" ? "Corrected image · required for reference plane" : bar.workspace.corrected ? "Corrected · Switch to original" : "Original · Switch to corrected"
                onClicked:bar.workspace.toggleRibbonView()
                StyledToolTip {text:parent.Accessible.name+" · Tab"}
            }
        }
    }
    function profileFinished(success,message) {profiles.complete(success,message);}
}
