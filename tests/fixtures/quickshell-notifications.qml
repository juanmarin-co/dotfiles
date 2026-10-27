import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

ShellRoot {
    id: test
    property bool batteryDischarging: false
    NotificationService { id: service }
    QtObject {
        id: mockBattery
        property bool ready: false
        property bool isPresent: true
        property bool isLaptopBattery: true
        property real percentage: 1
        property int state: UPowerDeviceState.Charging
    }
    BatteryAlerts {
        battery: mockBattery
        onBattery: test.batteryDischarging
    }

    IpcHandler {
        target: "test"
        function snapshot(): string {
            return JSON.stringify({
                dnd: service.doNotDisturb,
                notifications: service.notifications.map(n => ({
                    id: n.id, summary: n.summary, body: n.body,
                    timeout: service.timeoutFor(n), urgency: n.urgency
                })),
                visible: service.visibleToasts.map(n => n.id)
            });
        }
        function setDnd(enabled: bool): void { service.doNotDisturb = enabled; }
        function sampleBattery(level: real, discharging: bool, ready: bool): void {
            mockBattery.ready = ready;
            mockBattery.percentage = level / 100;
            mockBattery.state = discharging ? (level === 0 ? UPowerDeviceState.Empty : UPowerDeviceState.Discharging)
                : UPowerDeviceState.Charging;
            test.batteryDischarging = discharging;
        }
        function invoke(id: int, identifier: string): void {
            const notification = service.notifications.find(n => n.id === id);
            const action = notification?.actions.find(action => action.identifier === identifier);
            if (action)
                action.invoke();
        }
        function reload(): void { Qt.callLater(() => Quickshell.reload(false)); }
    }
}
