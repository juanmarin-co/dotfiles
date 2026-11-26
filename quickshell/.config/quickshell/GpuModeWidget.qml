import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var panel
    required property var service
    property alias open: popup.visible
    property string error: ""
    property var pendingMode: null
    readonly property bool busy: executor.running
    readonly property bool available: service.available
    readonly property var gpu: service.snapshot?.gpu || null
    readonly property string mode: gpu?.mode || "unknown"
    readonly property bool applied: gpu?.mode_applied ?? true
    readonly property bool integrated: mode === "integrated"
    readonly property string currentLabel: integrated ? "Integrated" : mode === "hybrid" ? "Hybrid" : "Unknown"
    readonly property string status: !available
        ? service.connected ? "Waiting for live data" : "Controller unavailable"
        : !applied ? currentLabel + " selected — reboot to apply"
        : integrated ? "dGPU removed from the PCI bus" : "dGPU present and available"
    readonly property var modes: [
        { key: "hybrid", label: "Hybrid", unit: "gpu-mode-hybrid.service" },
        { key: "integrated", label: "Integrated", unit: "gpu-mode-integrated.service" }
    ]
    implicitWidth: barButton.implicitWidth
    implicitHeight: BarStyle.buttonSize

    function modeFor(key) {
        return modes.find(mode => mode.key === key) || null;
    }

    function requestMode(key) {
        if (busy || !modeFor(key))
            return;
        error = "";
        pendingMode = modeFor(key);
    }

    function applyMode(key) {
        const mode = modeFor(key);
        if (!mode || busy)
            return;
        executor.command = ["systemctl", "start", mode.unit];
        executor.running = true;
    }

    function reboot() {
        if (busy)
            return;
        executor.command = ["systemctl", "reboot"];
        executor.running = true;
    }

    onOpenChanged: {
        pendingMode = null;
        error = "";
    }

    Process {
        id: executor
        stderr: StdioCollector { id: failure }
        onExited: exitCode => {
            if (exitCode === 0)
                root.pendingMode = null;
            else
                root.error = failure.text.trim() || "Could not switch the GPU mode.";
        }
    }

    BarButton {
        id: barButton
        anchors.fill: parent
        implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
        display: AbstractButton.TextBesideIcon
        icon.source: Qt.resolvedUrl("icons/lucide/cpu.svg")
        active: root.available && !root.integrated
        warning: root.available && !root.applied
        highlighted: root.open
        text: !root.available ? "—" : root.integrated ? "iGPU" : "dGPU"
        tooltipText: root.status
        onClicked: root.open = !root.open
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
                    text: "GPU Mode"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
                BluetoothText {
                    Layout.fillWidth: true
                    text: root.busy ? "Working…" : root.status
                    color: root.available && !root.applied ? "#ffb454" : "#8a9199"
                    font.pixelSize: 12
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#1b2432"
            }

            ColumnLayout {
                visible: root.available
                Layout.fillWidth: true
                spacing: Spacing.control
                StatusRow {
                    Layout.fillWidth: true
                    label: "dGPU"
                    value: root.gpu?.card_present ? "Present" : "Removed"
                }
                StatusRow {
                    Layout.fillWidth: true
                    label: "Reboot"
                    value: root.applied ? "Not required" : "Pending"
                    valueColor: root.applied ? "#bfbdb6" : "#ffb454"
                }
            }

            ColumnLayout {
                visible: root.pendingMode === null && root.available
                Layout.fillWidth: true
                spacing: Spacing.control
                Repeater {
                    model: root.modes
                    delegate: Button {
                        id: modeButton
                        required property var modelData
                        Layout.fillWidth: true
                        padding: Spacing.control
                        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
                        text: modelData.label
                        enabled: !root.busy && root.mode !== modelData.key
                        font.family: "Inter"
                        font.pixelSize: 13
                        contentItem: IconLabel {
                            text: modeButton.text
                            font: modeButton.font
                            color: modeButton.enabled ? "#bfbdb6" : "#565b66"
                            spacing: Spacing.control
                            alignment: Qt.AlignLeft
                        }
                        background: Rectangle {
                            radius: 5
                            color: modeButton.down ? "#273344"
                                : modeButton.hovered ? "#1b2432" : "transparent"
                        }
                        onClicked: root.requestMode(modelData.key)
                    }
                }
            }

            ColumnLayout {
                visible: root.pendingMode !== null
                Layout.fillWidth: true
                spacing: Spacing.control
                BluetoothText {
                    Layout.fillWidth: true
                    text: (root.pendingMode?.label || "") + " at next reboot?"
                    font.weight: Font.Medium
                }
                BluetoothText {
                    Layout.fillWidth: true
                    text: "Takes effect after the next reboot."
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
                        onClicked: root.pendingMode = null
                    }
                    BluetoothButton {
                        id: confirmButton
                        text: "Switch"
                        highlighted: true
                        enabled: !root.busy
                        background: Rectangle {
                            radius: 5
                            color: confirmButton.down ? "#d95757" : "#f26d78"
                        }
                        onClicked: root.applyMode(root.pendingMode.key)
                    }
                }
            }

            ColumnLayout {
                visible: root.available && !root.applied && root.pendingMode === null
                Layout.fillWidth: true
                spacing: Spacing.control
                BluetoothButton {
                    Layout.fillWidth: true
                    text: "Reboot now"
                    highlighted: true
                    enabled: !root.busy
                    onClicked: root.reboot()
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
