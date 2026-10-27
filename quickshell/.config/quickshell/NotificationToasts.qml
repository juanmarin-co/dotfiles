import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window
    required property var service
    screen: Quickshell.screens[0]
    visible: service.visibleToasts.length > 0
    anchors {
        top: true
        right: true
    }
    margins {
        top: Spacing.outer
        right: Spacing.outer
    }
    implicitWidth: 420
    implicitHeight: Math.max(1, stack.implicitHeight)
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dotfiles-notifications"

    ColumnLayout {
        id: stack
        anchors.fill: parent
        spacing: Spacing.control
        Repeater {
            model: window.service.visibleToasts
            delegate: NotificationCard {
                required property var modelData
                notification: modelData
                Layout.fillWidth: true
            }
        }
    }
}
