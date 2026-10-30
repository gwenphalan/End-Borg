pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

// Shared native renderer. Match ink height while preserving font proportions.
Item {
    id: root
    property var clockFont: ({})
    property alias text: glyphs.text
    property alias color: glyphs.color
    property alias font: glyphs.font
    property alias style: glyphs.style
    property alias styleColor: glyphs.styleColor
    property alias horizontalAlignment: glyphs.horizontalAlignment
    property alias animateChange: glyphs.animateChange
    property string calibrationText: "0123456789:AMP"
    readonly property string requestedFamily: clockFont.family || "Google Sans Flex"
    readonly property bool requestedItalic: !!clockFont.italic
    // Pixel outlines contain overlapping contours; rasterize them with the native
    // font engine instead of Qt Quick distance fields.
    readonly property int glyphRenderType: requestedFamily.startsWith("Tiny5") || requestedFamily
                                           === "Press Start 2P" ? Text.NativeRendering : Text.QtRendering
    readonly property bool fontsReady: ClockFonts.readyForFamily(requestedFamily)
    readonly property var profile: ClockFonts.profile(requestedFamily)
    readonly property var controls: ClockFonts.controls(clockFont)
    readonly property alias resolvedFontInfo: fontInfo
    readonly property int resolvedSize: Math.max(1, Math.round(finiteValue(clockFont.size, 90)))
    readonly property real resolvedWeight: supportsAxis("wght") ? axisValue("wght", ClockFonts.fromControl(
                                                                                controls.weight,
                                                                                profile.weightMin,
                                                                                profile.weight,
                                                                                profile.weightMax)) : Math.max(
                                                                      1, Math.min(1000, finiteValue(
                                                                                      clockFont.weight, 400)))
    readonly property real resolvedWidth: ClockFonts.fromControl(controls.width, profile.widthMin,
                                                                 profile.width, profile.widthMax)
    readonly property var supportedAxes: {
        const result = {};
        for (const axis of fontInfo.variableAxes)
            result[String(axis.tag)] = {
                name: axis.name,
                minimumValue: axis.minimumValue,
                maximumValue: axis.maximumValue,
                defaultValue: axis.defaultValue
            };
        return result;
    }
    readonly property string roundnessAxis: supportsAxis("ROND") ? "ROND" : supportsAxis("SOFT") ? "SOFT" : supportsAxis(
                                                                                                       "soft") ? "soft" :
                                                                                                                 ""
    readonly property bool hasNativeRoundness: roundnessAxis.length > 0
    readonly property var appliedVariableAxes: {
        const result = {};
        if (supportsAxis("wght"))
            result.wght = resolvedWeight;
        if (supportsAxis("wdth"))
            result.wdth = axisValue("wdth", resolvedWidth);
        const rounding = supportedAxes[roundnessAxis];
        if (rounding)
            result[roundnessAxis] = rounding.minimumValue + controls.roundness / 100 * (rounding.maximumValue
                                                                                        - rounding.minimumValue);
        return result;
    }
    // A uniform scale matches visible height without forcing glyph widths.
    readonly property real horizontalScale: verticalScale * (requestedFamily === "Big Shoulders Inline" ? 2.2 : 1)
    readonly property real verticalScale: resolvedSize * .72 / Math.max(1,
                                                                        calibrationMetrics.tightBoundingRect.height)
    readonly property rect inkBounds: Qt.rect(fullMetrics.tightBoundingRect.x * horizontalScale, (
                                                  glyphs.baselineOffset + fullMetrics.tightBoundingRect.y)
                                              * verticalScale, fullMetrics.tightBoundingRect.width
                                              * horizontalScale, fullMetrics.tightBoundingRect.height
                                              * verticalScale)
    implicitWidth: glyphs.implicitWidth * horizontalScale
    implicitHeight: glyphs.implicitHeight * verticalScale

    function finiteValue(value, fallback) {
        return value !== undefined && value !== null && Number.isFinite(Number(value)) ? Number(value) :
                                                                                         fallback;
    }
    function supportsAxis(tag) {
        return supportedAxes[tag] !== undefined;
    }
    function axisValue(tag, value) {
        const axis = supportedAxes[tag];
        return axis ? Math.max(axis.minimumValue, Math.min(axis.maximumValue, finiteValue(value,
                                                                                          axis.defaultValue))) :
                      undefined;
    }
    onRequestedFamilyChanged: ClockFonts.ensureLegacyFamily(requestedFamily)
    Component.onCompleted: ClockFonts.ensureLegacyFamily(requestedFamily)
    FontInfo {
        id: fontInfo
        font: {
            const loaded = root.fontsReady;
            return Qt.font({
                               family: root.requestedFamily,
                               styleName: "",
                               italic: root.requestedItalic,
                               pixelSize: 90,
                               weight: 400
                           });
        }
    }
    TextMetrics {
        id: calibrationMetrics
        text: root.calibrationText
        renderType: root.glyphRenderType
        font: Qt.font({
                          family: root.requestedFamily,
                          styleName: "",
                          italic: root.requestedItalic,
                          pixelSize: root.resolvedSize,
                          hintingPreference: Font.PreferNoHinting,
                          weight: Math.round(root.resolvedWeight),
                          variableAxes: root.appliedVariableAxes,
                          features: ({
                                         tnum: 1,
                                         kern: 0
                                     })
                      })
    }
    TextMetrics {
        id: fullMetrics
        text: glyphs.text
        font: glyphs.font
        renderType: root.glyphRenderType
    }
    StyledText {
        id: glyphs
        width: root.width / root.horizontalScale
        height: root.height / root.verticalScale
        renderType: root.glyphRenderType
        font {
            hintingPreference: Font.PreferNoHinting
            features: ({
                           tnum: 1,
                           kern: 0
                       })
            family: root.requestedFamily
            italic: root.requestedItalic
            styleName: ""
            pixelSize: root.resolvedSize
            weight: Math.round(root.resolvedWeight)
            variableAxes: root.appliedVariableAxes
            letterSpacing: Math.max(0, Math.min(.5, root.finiteValue(root.clockFont.letterSpacing, 0)))
                           * root.resolvedSize / root.horizontalScale
        }
        transform: Scale {
            xScale: root.horizontalScale
            yScale: root.verticalScale
        }
        style: Text.Raised
        styleColor: Appearance.colors.colShadow
    }
}
