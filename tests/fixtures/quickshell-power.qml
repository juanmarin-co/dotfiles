import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

ShellRoot {
    id: test
    property var energyPopup: null
    property var sessionPopup: null

    function popupFor(widget) {
        return widget.data.find(child => child.grabFocus !== undefined);
    }

    PanelWindow {
        id: panel
        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 1
        exclusiveZone: 0
        color: "transparent"
        EnergyWidget { id: energy; panel: panel }
        SessionWidget { id: session; panel: panel }
        BarIconButton { id: colorProbe; visible: false }
    }

    Component.onCompleted: {
        energyPopup = popupFor(energy);
        sessionPopup = popupFor(session);
        energyPopup.grabFocus = false;
        sessionPopup.grabFocus = false;
    }

    IpcHandler {
        target: "test"
        function snapshot(): string {
            const batteryButton = energy.data.find(child => child.tooltipText !== undefined);
            return JSON.stringify({
                batteryReady: energy.batteryReady, charge: energy.charge,
                profiles: energy.profiles.map(profile => profile.value), profile: PowerProfiles.profile,
                keepAwake: energy.keepAwake,
                energy: { open: energy.open, width: test.energyPopup.width, height: test.energyPopup.height,
                    barWidth: energy.width, label: batteryButton.text, tooltip: batteryButton.tooltipText },
                session: { open: session.open, width: test.sessionPopup.width, height: test.sessionPopup.height,
                    pending: session.pendingAction?.key || "", busy: session.busy, error: session.error }
            });
        }
        function activateEnergy(): void { session.open = false; energy.open = true; }
        function activateSession(): void { energy.open = false; session.open = true; }
        function requestAction(key: string): void { session.requestAction(key); }
        function cancelAction(): void { session.pendingAction = null; }
        function closeSession(): void { session.open = false; }
        function confirmAction(): void {
            if (session.pendingAction)
                session.executeAction(session.pendingAction.key);
        }
        function chargeHints(): string {
            return JSON.stringify([
                energy.chargeAdvice(39, true), energy.chargeAdvice(39, false),
                energy.chargeAdvice(40, true), energy.chargeAdvice(80, false),
                energy.chargeAdvice(81, false), energy.chargeAdvice(81, true)
            ]);
        }
        function iconColors(): string {
            const colors = [String(colorProbe.icon.color)];
            colorProbe.highlighted = true;
            colors.push(String(colorProbe.icon.color));
            colorProbe.warning = true;
            colors.push(String(colorProbe.icon.color));
            colorProbe.critical = true;
            colors.push(String(colorProbe.icon.color));
            return JSON.stringify(colors);
        }
        function commands(): string {
            const commands = {};
            for (const action of session.actions)
                commands[action.key] = session.commandFor(action.key);
            return JSON.stringify(commands);
        }
    }
}
