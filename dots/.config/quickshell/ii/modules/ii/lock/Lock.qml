pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland

LockScreen {
    id: root

    lockSurface: LockSurface {
        context: root.context
        bedtimeActive: root.bedtimeActive
        bedtimeDeadlineText: root.bedtimeDeadlineText
        bedtimeDelayUntilText: root.bedtimeDelayUntilText
        bedtimeDelaysRemaining: root.bedtimeDelaysRemaining
        bedtimeDelayAllowed: root.bedtimeDelayAllowed
        onBedtimeDelayRequested: root.requestBedtimeDelay()
    }
}
