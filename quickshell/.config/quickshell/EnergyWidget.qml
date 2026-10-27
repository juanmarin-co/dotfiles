import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Wayland

Item {
    id: root
    required property var panel
    property alias open: popup.visible
    property alias keepAwake: state.keepAwake
    readonly property var battery: UPower.displayDevice
    readonly property bool batteryReady: battery.ready && battery.isPresent && battery.isLaptopBattery
    readonly property int charge: batteryReady ? Math.round(battery.percentage * 100) : 0
    readonly property string status: batteryReady ? UPowerDeviceState.toString(battery.state) : "Reading battery…"
    readonly property string healthHint: batteryReady ? chargeAdvice(charge, UPower.onBattery) : ""
    readonly property bool healthWarning: healthHint.length > 0
    readonly property var profiles: [
        { label: "Power saver", value: PowerProfile.PowerSaver },
        { label: "Balanced", value: PowerProfile.Balanced },
        ...(PowerProfiles.hasPerformanceProfile
            ? [{ label: "Performance", value: PowerProfile.Performance }] : [])
    ]
    readonly property string remaining: {
        const charging = battery.state === UPowerDeviceState.Charging;
        const seconds = charging ? battery.timeToFull : battery.timeToEmpty;
        if (!batteryReady || seconds <= 0)
            return "";
        const minutes = Math.ceil(seconds / 60);
        const hours = Math.floor(minutes / 60);
        const time = hours > 0 ? hours + "h " + minutes % 60 + "m" : minutes + "m";
        return time + (charging ? " until full" : " remaining");
    }

    implicitWidth: barButton.implicitWidth
    implicitHeight: BarStyle.buttonSize

    function chargeAdvice(level, onBattery) {
        if (level < 40)
            return onBattery ? "Below 40% · Plug in soon" : "Below 40% · External power connected";
        if (level > 80 && !onBattery)
            return "Above 80% · Consider unplugging";
        return "";
    }

    PersistentProperties {
        id: state
        reloadableId: "energy-settings"
        property bool keepAwake: false
    }

    IdleInhibitor {
        window: root.panel
        enabled: root.keepAwake
    }

    BarButton {
        id: barButton
        anchors.fill: parent
        implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
        display: AbstractButton.TextBesideIcon
        icon.source: Qt.resolvedUrl("icons/lucide/" + (!root.batteryReady ? "battery.svg"
            : root.charge > 80 && !UPower.onBattery ? "battery-warning.svg"
            : root.battery.state === UPowerDeviceState.Charging ? "battery-charging.svg"
            : root.charge < 40 ? "battery-low.svg"
            : root.charge <= 65 ? "battery-medium.svg" : "battery-full.svg"))
        active: root.batteryReady
        highlighted: root.open || root.keepAwake
        critical: root.batteryReady && root.charge <= 15
        warning: root.healthWarning
        text: root.batteryReady ? root.charge + "%" : "—"
        tooltipText: (root.batteryReady ? root.charge + "% · " + root.status : "Battery unavailable")
            + (root.keepAwake ? " · Keep awake" : "")
            + (root.healthHint ? "\n" + root.healthHint : "")
        onClicked: popup.visible = !popup.visible
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

            RowLayout {
                spacing: Spacing.control
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.tight
                    BluetoothText {
                        text: "Battery & energy"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                    BluetoothText {
                        Layout.fillWidth: true
                        text: root.healthHint || root.status + (root.remaining ? " · " + root.remaining : "")
                        color: barButton.critical ? "#f26d78" : root.healthWarning ? "#ffb454" : "#8a9199"
                        font.pixelSize: 12
                    }
                }
                BluetoothText {
                    text: root.batteryReady ? root.charge + "%" : "—"
                    color: barButton.critical ? "#f26d78" : root.healthWarning ? "#ffb454" : "#bfbdb6"
                    font.pixelSize: 22
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#1b2432"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Spacing.control
                BluetoothText {
                    text: "Power profile"
                    font.weight: Font.Medium
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.control
                    Repeater {
                        model: root.profiles
                        delegate: BluetoothButton {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.label
                            highlighted: PowerProfiles.profile === modelData.value
                            onClicked: PowerProfiles.profile = modelData.value
                        }
                    }
                }
            }

            RowLayout {
                spacing: Spacing.control
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.tight
                    BluetoothText {
                        text: "Keep awake"
                        font.weight: Font.Medium
                    }
                    BluetoothText {
                        Layout.fillWidth: true
                        text: "Pause automatic locking and screen-off"
                        color: "#8a9199"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
                BluetoothButton {
                    text: root.keepAwake ? "On" : "Off"
                    highlighted: root.keepAwake
                    onClicked: root.keepAwake = !root.keepAwake
                }
            }
        }
    }
}
