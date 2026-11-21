import QtQuick
import Quickshell
import Quickshell.Services.UPower

Scope {
    id: root
    required property var battery
    required property bool onBattery

    PersistentProperties {
        id: state
        reloadableId: "battery-alerts"
        property bool sentPlugIn: false
        property bool sentUnplug: false
        property bool sentLow: false
        property bool sentCritical: false
    }

    function sendAlert(summary, body, urgent) {
        const command = ["notify-send", "--app-name=Battery", "--icon",
            Qt.resolvedUrl("icons/lucide/battery-warning.svg").toString()];
        if (urgent)
            command.push("--urgency=critical", "--expire-time=0");
        Quickshell.execDetached(command.concat([summary, body]));
    }

    function checkBattery() {
        if (!battery || !battery.ready || !battery.isPresent || !battery.isLaptopBattery)
            return;
        const level = Math.round(battery.percentage * 100);
        if (level <= 80)
            state.sentUnplug = false;
        if (!onBattery) {
            // Re-arm after recharge so reconnecting at the same level stays quiet.
            if (level >= 40)
                state.sentPlugIn = false;
            if (level >= 20)
                state.sentLow = false;
            if (level >= 10)
                state.sentCritical = false;
            if (level > 80 && !state.sentUnplug) {
                state.sentUnplug = true;
                sendAlert("Consider unplugging", level + "% charged.", false);
            }
            return;
        }
        if (battery.state !== UPowerDeviceState.Discharging && battery.state !== UPowerDeviceState.Empty)
            return;
        if (level <= 15)
            state.sentPlugIn = true;
        if (level <= 5 && !state.sentCritical) {
            state.sentLow = true;
            state.sentCritical = true;
            sendAlert("Battery critically low", level + "% remaining. Plug in now and save your work.", true);
        } else if (level <= 15 && !state.sentLow) {
            state.sentLow = true;
            sendAlert("Low battery", level + "% remaining. Plug in soon.", true);
        } else if (level < 40 && !state.sentPlugIn) {
            state.sentPlugIn = true;
            sendAlert("Plug in soon", level + "% remaining.", false);
        }
    }

    // Coalesce UPower's related property changes and wait until reload state is restored.
    Component.onCompleted: Qt.callLater(root.checkBattery)
    onBatteryChanged: Qt.callLater(root.checkBattery)
    onOnBatteryChanged: Qt.callLater(root.checkBattery)
    Connections {
        target: root.battery
        function onReadyChanged() { Qt.callLater(root.checkBattery); }
        function onIsPresentChanged() { Qt.callLater(root.checkBattery); }
        function onIsLaptopBatteryChanged() { Qt.callLater(root.checkBattery); }
        function onPercentageChanged() { Qt.callLater(root.checkBattery); }
        function onStateChanged() { Qt.callLater(root.checkBattery); }
    }
}
