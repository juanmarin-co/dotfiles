import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var panel
    required property var service
    property alias open: popup.visible
    readonly property bool available: service.available
    readonly property var sample: service.snapshot
    readonly property var gpu: sample?.gpu || null
    readonly property var control: sample?.control || null
    readonly property bool gpuSleeping: gpu?.power_state === "D3cold" && gpu?.runtime_status === "suspended"
    readonly property real hottest: Math.max(sample?.cpu_temp_c ?? -Infinity, gpu?.temperature_c ?? -Infinity)
    readonly property bool critical: available && (!control?.healthy || control?.high_temperature_cooling || hottest >= 85)
    readonly property bool warning: !available || hottest >= 70 || !!gpu?.error || sample?.ac_online === null
    readonly property string fanControl: control?.fan_control === "Manual" ? "Custom curve"
        : control?.fan_control === "Automatic" ? "Firmware automatic" : "Unknown"
    readonly property string fanSummary: control?.fan_control === "Manual" && control.fan_target_rpm !== null
        ? "Custom curve · Target " + control.fan_target_rpm + " RPM" : fanControl
    readonly property string fanReason: fanExplanation()
    readonly property string turboReason: turboExplanation()
    readonly property string gpuState: gpu ? gpu.power_state + " · " + gpu.runtime_status : "Unknown"
    readonly property string status: !available
        ? service.connected ? "Waiting for live data" : "Controller unavailable"
        : !control?.healthy ? "Controller fault"
        : control?.high_temperature_cooling ? "High-temperature cooling active"
        : gpu?.error ? "GPU telemetry unavailable"
        : sample?.ac_online === null ? "Power source unknown" : ""
    implicitWidth: barButton.implicitWidth
    implicitHeight: BarStyle.buttonSize

    function temperature(value) {
        return value === null || value === undefined ? "—" : Math.round(value) + "°C";
    }

    function fanExplanation() {
        switch (control?.fan_reason) {
        case "warming_up": return "Waiting for sustained heat before starting the custom curve.";
        case "temperature_curve": return "Following the CPU/GPU temperature curve.";
        case "gpu_temperature_hold": return "Holding a recent GPU temperature (" + temperature(control.control_temp_c) + ").";
        case "cooldown": return "Waiting for sustained cooling before returning to firmware control.";
        case "high_temperature": return "High-temperature cooling requests the maximum fan target.";
        case "high_temperature_recovery": return "High-temperature cooling is waiting through its recovery period.";
        default: return "";
        }
    }

    function turboExplanation() {
        switch (sample?.cpu_turbo_reason) {
        case "ac_and_gpu_off": return "AC power confirmed; NVIDIA GPU is powered off.";
        case "on_battery": return "Disabled on battery power.";
        case "ac_unknown": return "AC power could not be confirmed.";
        case "gaming_mode": return "Disabled while Gaming hardware mode is active.";
        case "gpu_not_confirmed_off": return "NVIDIA GPU is not confirmed powered off.";
        case "control_error": return "Turbo state could not be confirmed.";
        default: return "";
        }
    }

    BarButton {
        id: barButton
        anchors.fill: parent
        implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
        display: AbstractButton.TextBesideIcon
        icon.source: Qt.resolvedUrl("icons/lucide/fan.svg")
        active: root.available
        highlighted: root.open
        critical: root.critical
        warning: root.warning
        text: root.available && root.sample?.cpu_temp_c != null ? Math.round(root.sample.cpu_temp_c) + "°" : "—"
        tooltipText: root.available
            ? "CPU " + root.temperature(root.sample?.cpu_temp_c) + " · " + root.fanSummary
                + (root.status ? "\n" + root.status : "")
            : root.status
        onClicked: root.open = !root.open
    }

    PopupWindow {
        id: popup
        anchor.window: root.panel
        anchor.rect.x: root.panel.width - width - Spacing.control
        anchor.rect.y: root.panel.height + Spacing.control
        implicitWidth: 420
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
                    text: "Cooling"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
                BluetoothText {
                    Layout.fillWidth: true
                    text: root.status
                    visible: text.length > 0
                    color: root.critical ? "#f26d78" : root.warning ? "#ffb454" : "#8a9199"
                    font.pixelSize: 12
                }
            }

            RowLayout {
                visible: root.available
                Layout.fillWidth: true
                spacing: Spacing.control
                Repeater {
                    model: [
                        { label: "CPU", value: root.temperature(root.sample?.cpu_temp_c), detail: "Package temperature" },
                        { label: "NVIDIA GPU", value: root.gpuSleeping ? "Sleeping"
                            : root.gpu?.temperature_c != null ? root.temperature(root.gpu.temperature_c)
                                : "Not sampled", detail: root.gpuState }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: metric.implicitHeight + 2 * Spacing.section
                        color: "#11151c"
                        radius: 6
                        ColumnLayout {
                            id: metric
                            anchors.fill: parent
                            anchors.margins: Spacing.section
                            spacing: Spacing.tight
                            BluetoothText {
                                text: modelData.label
                                color: "#8a9199"
                            }
                            BluetoothText {
                                Layout.fillWidth: true
                                text: modelData.value
                                font.pixelSize: 22
                            }
                            BluetoothText {
                                Layout.fillWidth: true
                                text: modelData.detail
                                textFormat: Text.PlainText
                                font.pixelSize: 12
                                color: "#8a9199"
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                visible: root.available
                Layout.fillWidth: true
                spacing: Spacing.control
                StatusRow {
                    Layout.fillWidth: true
                    label: "Fan control"
                    value: root.fanControl
                }
                StatusRow {
                    visible: root.control?.fan_control === "Manual" && root.control?.fan_target_rpm !== null
                    Layout.fillWidth: true
                    label: "Fan target"
                    value: (root.control?.fan_target_rpm ?? "—") + " RPM"
                }
                BluetoothText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: root.fanReason
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: "#8a9199"
                    font.pixelSize: 12
                }
                StatusRow {
                    Layout.fillWidth: true
                    label: "Hardware mode"
                    value: root.control?.performance_mode || "Unknown"
                }
                StatusRow {
                    Layout.fillWidth: true
                    label: "CPU turbo"
                    value: root.sample?.cpu_turbo_allowed === true ? "Allowed"
                        : root.sample?.cpu_turbo_allowed === false ? "Disabled" : "Unknown"
                }
                BluetoothText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: root.turboReason
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: "#8a9199"
                    font.pixelSize: 12
                }
                StatusRow {
                    Layout.fillWidth: true
                    label: "Power source"
                    value: root.sample?.ac_online === true ? "AC"
                        : root.sample?.ac_online === false ? "Battery" : "Unknown"
                }
            }

            BluetoothText {
                visible: root.available && !!root.control?.error
                Layout.fillWidth: true
                text: root.control?.error || ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#f26d78"
                font.pixelSize: 12
            }

            Rectangle {
                visible: root.available
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#1b2432"
            }

            ColumnLayout {
                visible: root.available
                Layout.fillWidth: true
                spacing: Spacing.control
                BluetoothText {
                    text: "NVIDIA GPU"
                    font.weight: Font.Medium
                }
                StatusRow {
                    visible: root.gpu?.utilization_percent != null
                    Layout.fillWidth: true
                    label: "Utilization"
                    value: (root.gpu?.utilization_percent ?? "—") + "%"
                }
                StatusRow {
                    visible: root.gpu?.memory_used_mb != null && root.gpu?.memory_total_mb != null
                    Layout.fillWidth: true
                    label: "VRAM"
                    value: (root.gpu?.memory_used_mb ?? "—") + " / " + (root.gpu?.memory_total_mb ?? "—") + " MB"
                }
                StatusRow {
                    Layout.fillWidth: true
                    label: "Device clients"
                    value: root.gpu?.clients.length ? root.gpu.clients.join(", ") : "None detected"
                }
                BluetoothText {
                    visible: !!root.gpu?.error
                    Layout.fillWidth: true
                    text: root.gpu?.error || ""
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: "#ffb454"
                    font.pixelSize: 12
                }
                BluetoothText {
                    visible: !root.gpuSleeping && root.gpu?.temperature_c === null && !root.gpu?.error
                    Layout.fillWidth: true
                    text: "GPU metrics are sampled only while active with a detected client."
                    wrapMode: Text.WordWrap
                    color: "#8a9199"
                    font.pixelSize: 12
                }
            }
        }
    }
}
