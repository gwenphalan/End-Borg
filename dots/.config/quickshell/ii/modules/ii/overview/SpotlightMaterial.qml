import QtQuick
import qs.modules.common
import qs.modules.common.functions

Rectangle {
    id: root
    property color baseColor: Appearance.colors.colBackgroundSurfaceContainer
    readonly property real materialOpacity: Config.options.appearance.transparency.enable
        ? Math.max(0.86, Math.min(0.94, baseColor.a)) : 1
    gradient: Gradient {
        GradientStop {
            position: 0
            color: ColorUtils.applyAlpha(ColorUtils.mix(root.baseColor, Appearance.m3colors.m3surfaceBright, 0.95),
                Math.min(1, root.materialOpacity + 0.025))
        }
        GradientStop {
            position: 0.48
            color: ColorUtils.applyAlpha(root.baseColor, root.materialOpacity)
        }
        GradientStop {
            position: 1
            color: ColorUtils.applyAlpha(ColorUtils.mix(root.baseColor, Appearance.m3colors.m3background, 0.96),
                Config.options.appearance.transparency.enable ? root.materialOpacity - 0.025 : 1)
        }
    }
}
