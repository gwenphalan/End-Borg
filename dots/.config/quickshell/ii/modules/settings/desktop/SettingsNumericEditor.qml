pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "SettingsPresentation.js" as Presentation

RowLayout {
    id: root
    required property var setting
    required property real value
    property bool showPresets: false
    property var rawDraft:undefined
    signal invalidEdited(string text)
    signal cancelled()
    signal edited(real value)
    signal previewed(real value)
    signal previewEnded()
    readonly property bool previewsClockSize: setting.path === "background.widgets.clock.digital.font.size"
    property real previewValue: NaN
    readonly property real displayedValue: Number.isFinite(previewValue) ? previewValue : value
    readonly property var presentation: Presentation.numeric(setting)
    readonly property real displayScale: presentation.displayScale
    readonly property real lower: Number(presentation.min)
    readonly property real upper: presentation.unboundedSlider ? Math.max(480,Math.ceil((value+120)/120)*120) : Number(presentation.max)
    readonly property bool bounded: Number.isFinite(lower) && Number.isFinite(upper) && upper > lower
    readonly property var sliderSteps:presentation.fontSizeSteps ? Presentation.fontSizes(value) : []
    function numberForSlider(position) { return sliderSteps.length ? sliderSteps[Math.max(0,Math.min(sliderSteps.length-1,Math.round(position)))] : position; }
    readonly property string displayUnit: presentation.displayUnit
    spacing: 12
    function finishPreview() {
        previewValue=NaN;
        previewEnded();
    }
    Component.onDestruction: previewEnded()
    CommittedSlider {
        id: slider
        Layout.fillWidth: true
        Layout.minimumWidth: 96
        enabled: root.enabled && root.bounded
        from:root.sliderSteps.length ? 0 : root.lower
        to:root.sliderSteps.length ? root.sliderSteps.length-1 : root.upper
        stepSize: root.presentation.sliderStep
        value:root.sliderSteps.length ? Presentation.nearestFontSizeIndex(root.value,root.sliderSteps) : root.value
        snapMode:root.presentation.sliderStep>0 ? Slider.SnapAlways : Slider.NoSnap
        stopIndicatorValues:root.sliderSteps.length ? root.sliderSteps.map((_,i)=>i) : []
        configuration: StyledSlider.Configuration.M
        usePercentTooltip: false
        tooltipContent: Number((root.numberForSlider(value) * root.displayScale).toFixed(2)) + (root.displayUnit ? " " + root.displayUnit : "")
        Accessible.name: Translation.tr(root.setting.label)
        onMoved: {
            if (!root.previewsClockSize) return;
            root.previewValue=root.numberForSlider(value);
            root.previewed(root.previewValue);
        }
        onCommitted: position => {
            const number=root.numberForSlider(position);
            root.edited(root.setting.type === "int" ? Math.round(number) : number);
            root.finishPreview();
        }
        onEnabledChanged:if (!enabled) root.finishPreview()
    }
    Loader {
        active:root.presentation.unboundedSlider===true
        visible:active
        Layout.preferredWidth:180
        sourceComponent:UnboundedNumberInput {
            number:root.displayedValue * root.displayScale
            minimum:root.lower * root.displayScale
            increment:root.presentation.step * root.displayScale
            integral:false
            stepValues:root.sliderSteps
            unit:root.displayUnit
            rawDraft:root.rawDraft
            Accessible.name:Translation.tr(root.setting.label)
            onEdited:number => root.edited(number/root.displayScale)
            onInvalidEdited:text => root.invalidEdited(text)
            onCancelled:root.cancelled()
        }
    }
    NumberInput {
        visible:!root.presentation.unboundedSlider
        Layout.preferredWidth: Math.max(116, implicitWidth)
        enabled: root.enabled
        number: root.displayedValue * root.displayScale
        minimum: root.lower * root.displayScale
        maximum: (root.presentation.max ?? 1000000) * root.displayScale
        increment: root.presentation.step * root.displayScale
        integral: root.presentation.displayIntegral
        unit: root.displayUnit
        rawDraft:root.rawDraft
        onInvalidEdited:text => root.invalidEdited(text)
        onCancelled:root.cancelled()
        Accessible.name: Translation.tr(root.setting.label)
        onEdited: number => root.edited(root.setting.type === "int" ? Math.round(number / root.displayScale) : number / root.displayScale)
    }
}
