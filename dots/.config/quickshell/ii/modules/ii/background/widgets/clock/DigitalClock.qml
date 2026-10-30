pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: clockColumn
    spacing: 4

    property bool isVertical: Config.options.background.widgets.clock.digital.vertical
    property color colText: Appearance.colors.colOnSecondaryContainer
    property var textHorizontalAlignment: Text.AlignHCenter

    // Time
    ClockFace {
        id: timeTextTop
        Layout.fillWidth: true
        text: clockColumn.isVertical ? DateTime.time.split(":")[0].padStart(2, "0") : DateTime.time
        color: clockColumn.colText
        horizontalAlignment: Text.AlignHCenter
        clockFont: Config.options.background.widgets.clock.digital.font
        animateChange: Config.options.background.widgets.clock.digital.animateChange
    }

    Loader {
        Layout.topMargin: clockColumn.isVertical ? -Math.max(0, Math.min(40,
            timeTextTop.implicitHeight - timeTextTop.inkBounds.height - 8))
            : 0
        Layout.fillWidth: true
        active: clockColumn.isVertical
        visible: active
        sourceComponent: ClockFace {
            // Keep the formatted suffix (am/pm or AM/PM) in vertical mode.
            text: DateTime.time.split(":").slice(1).join(":").trim()
            color: clockColumn.colText
            horizontalAlignment: clockColumn.textHorizontalAlignment
            clockFont: timeTextTop.clockFont
            animateChange: Config.options.background.widgets.clock.digital.animateChange
        }
    }

    // Date
    ClockText {
        visible: Config.options.background.widgets.clock.digital.showDate
        Layout.fillWidth: true
        text: DateTime.longDate
        color: clockColumn.colText
        horizontalAlignment: clockColumn.textHorizontalAlignment
    }

    // Quote
    ClockText {
        visible: Config.options.background.widgets.clock.quote.enable && Config.options.background.widgets.clock.quote.text.length > 0
        font.pixelSize: Appearance.font.pixelSize.normal
        text: Config.options.background.widgets.clock.quote.text
        animateChange: false
        color: clockColumn.colText
        horizontalAlignment: clockColumn.textHorizontalAlignment
    }
}
