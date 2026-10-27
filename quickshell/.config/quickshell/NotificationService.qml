import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Scope {
    id: root
    property alias doNotDisturb: state.doNotDisturb
    readonly property var notifications: server.trackedNotifications.values
    readonly property var visibleToasts: notifications
        .filter(n => !doNotDisturb || n.urgency === NotificationUrgency.Critical)
        .slice(-3).reverse()

    PersistentProperties {
        id: state
        reloadableId: "notification-settings"
        property bool doNotDisturb: false
    }

    function timeoutFor(notification) {
        if (notification.urgency === NotificationUrgency.Critical || notification.expireTimeout === 0)
            return 0;
        // Quickshell 0.3.2 exposes the original timeout in milliseconds.
        return notification.expireTimeout < 0 ? 5000 : notification.expireTimeout;
    }

    NotificationServer {
        id: server
        actionsSupported: true
        imageSupported: true
        onNotification: notification => notification.tracked = true
    }

    // Timers belong to every tracked notification, even when its toast is hidden.
    Variants {
        model: root.notifications
        Scope {
            required property var modelData

            function restartExpiry() {
                if (expiry.interval > 0)
                    expiry.restart();
                else
                    expiry.stop();
            }

            Component.onCompleted: restartExpiry()
            Timer {
                id: expiry
                interval: root.timeoutFor(modelData)
                onTriggered: modelData.expire()
            }
            Connections {
                target: modelData
                function onSummaryChanged() { restartExpiry(); }
                function onBodyChanged() { restartExpiry(); }
                function onImageChanged() { restartExpiry(); }
                function onActionsChanged() { restartExpiry(); }
                function onHintsChanged() { restartExpiry(); }
                function onExpireTimeoutChanged() { restartExpiry(); }
                function onUrgencyChanged() { restartExpiry(); }
            }
        }
    }

    IpcHandler {
        target: "notifications"
        function toggleDnd(): void { root.doNotDisturb = !root.doNotDisturb; }
        function dismissAll(): void { root.notifications.slice().forEach(n => n.dismiss()); }
    }
}
