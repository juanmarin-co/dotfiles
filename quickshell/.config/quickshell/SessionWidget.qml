import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var panel
    property alias open: popup.visible
    property var pendingAction: null
    property string error: ""
    readonly property bool busy: executor.running
    readonly property var actions: [
        { key: "lock", label: "Lock", icon: "lock-keyhole.svg", confirm: false },
        { key: "suspend", label: "Suspend", icon: "moon.svg", confirm: false },
        { key: "logout", label: "Log out", icon: "log-out.svg", confirm: true },
        { key: "reboot", label: "Reboot", icon: "rotate-cw.svg", confirm: true },
        { key: "shutdown", label: "Shut down", icon: "power.svg", confirm: true }
    ]
    implicitWidth: barButton.implicitWidth
    implicitHeight: BarStyle.buttonSize

    function commandFor(key) {
        switch (key) {
        case "lock": return ["swaylock", "-f", "-c", "000000"];
        // swayidle's before-sleep hook locks the session before suspend.
        case "suspend": return ["systemctl", "suspend"];
        case "logout": return ["niri", "msg", "action", "quit", "--skip-confirmation"];
        case "reboot": return ["systemctl", "reboot"];
        case "shutdown": return ["systemctl", "poweroff"];
        default: return [];
        }
    }

    function requestAction(key) {
        const action = actions.find(action => action.key === key);
        if (!action || busy)
            return;
        error = "";
        if (action.confirm)
            pendingAction = action;
        else
            executeAction(key);
    }

    function executeAction(key) {
        const command = commandFor(key);
        if (command.length === 0 || busy)
            return;
        executor.command = command;
        executor.running = true;
    }

    onOpenChanged: {
        pendingAction = null;
        error = "";
    }

    Process {
        id: executor
        stderr: StdioCollector { id: failure }
        onExited: exitCode => {
            if (exitCode === 0)
                popup.visible = false;
            else
                root.error = failure.text.trim() || "Could not complete the session action.";
        }
    }

    BarButton {
        id: barButton
        anchors.fill: parent
        icon.source: Qt.resolvedUrl("icons/lucide/power.svg")
        highlighted: root.open
        text: "Session"
        onClicked: popup.visible = !popup.visible
    }

    PopupWindow {
        id: popup
        anchor.window: root.panel
        anchor.rect.x: root.panel.width - width - Spacing.control
        anchor.rect.y: root.panel.height + Spacing.control
        implicitWidth: 360
        implicitHeight: content.implicitHeight + 2 * Spacing.outer
        color: "transparent"
        grabFocus: true

        Rectangle {
            anchors.fill: parent
            color: "#0b0e14"
            border.color: "#273344"
            radius: 8
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Spacing.outer
            spacing: Spacing.section

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Spacing.tight
                BluetoothText {
                    text: "Session"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
                BluetoothText {
                    Layout.fillWidth: true
                    text: root.busy ? "Working…" : "Lock, sleep, or end the session"
                    color: "#8a9199"
                    font.pixelSize: 12
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#1b2432"
            }

            ColumnLayout {
                visible: root.pendingAction === null
                Layout.fillWidth: true
                spacing: Spacing.control
                Repeater {
                    model: root.actions
                    delegate: Button {
                        id: actionButton
                        required property var modelData
                        Layout.fillWidth: true
                        padding: Spacing.control
                        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
                        text: modelData.label
                        icon.source: Qt.resolvedUrl("icons/lucide/" + modelData.icon)
                        icon.width: 16
                        icon.height: 16
                        icon.color: "#bfbdb6"
                        enabled: !root.busy
                        font.family: "Inter"
                        font.pixelSize: 13
                        contentItem: IconLabel {
                            text: actionButton.text
                            icon: actionButton.icon
                            font: actionButton.font
                            color: "#bfbdb6"
                            spacing: Spacing.control
                            alignment: Qt.AlignLeft
                        }
                        background: Rectangle {
                            radius: 5
                            color: actionButton.down ? "#273344"
                                : actionButton.hovered ? "#1b2432" : "transparent"
                        }
                        onClicked: root.requestAction(modelData.key)
                    }
                }
            }

            ColumnLayout {
                visible: root.pendingAction !== null
                Layout.fillWidth: true
                spacing: Spacing.control
                BluetoothText {
                    Layout.fillWidth: true
                    text: (root.pendingAction?.label || "") + "?"
                    font.weight: Font.Medium
                }
                BluetoothText {
                    Layout.fillWidth: true
                    text: "Applications will close. Save your work before continuing."
                    color: "#8a9199"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Spacing.control
                    BluetoothButton {
                        text: "Cancel"
                        enabled: !root.busy
                        onClicked: root.pendingAction = null
                    }
                    BluetoothButton {
                        id: confirmButton
                        text: root.pendingAction?.label || "Confirm"
                        highlighted: true
                        enabled: !root.busy && root.pendingAction !== null
                        background: Rectangle {
                            radius: 5
                            color: confirmButton.down ? "#d95757" : "#f26d78"
                        }
                        onClicked: root.executeAction(root.pendingAction.key)
                    }
                }
            }

            BluetoothText {
                visible: text !== ""
                Layout.fillWidth: true
                text: root.error
                wrapMode: Text.WordWrap
                color: "#f26d78"
                font.pixelSize: 12
            }
        }
    }
}
