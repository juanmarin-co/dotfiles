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
        property bool sentLow: false
        property bool sentCritical: false
    }

    function sendAlert(level, critical) {
        Quickshell.execDetached([
            "notify-send", "--app-name=Battery", "--urgency=critical", "--expire-time=0",
            "--icon", Qt.resolvedUrl("icons/lucide/battery-warning.svg").toString(),
            critical ? "Battery critically low" : "Low battery",
            level + "% remaining. " + (critical ? "Plug in now and save your work." : "Plug in soon.")
        ]);
    }

    function checkBattery() {
        if (!battery || !battery.ready || !battery.isPresent || !battery.isLaptopBattery)
            return;
        const level = Math.round(battery.percentage * 100);
        if (!onBattery) {
            // Re-arm only after meaningful recharge, not a brief plug/unplug.
            if (level >= 20)
                state.sentLow = false;
            if (level >= 10)
                state.sentCritical = false;
            return;
        }
        if (battery.state !== UPowerDeviceState.Discharging && battery.state !== UPowerDeviceState.Empty)
            return;
        if (level <= 5 && !state.sentCritical) {
            state.sentLow = true;
            state.sentCritical = true;
            sendAlert(level, true);
        } else if (level <= 15 && !state.sentLow) {
            state.sentLow = true;
            sendAlert(level, false);
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
