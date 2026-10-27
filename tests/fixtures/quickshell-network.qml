import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: test
    function texts(item) {
        if (item.visible === false)
            return [];
        let result = typeof item.text === "string" && item.text ? [item.text] : [];
        for (const child of item.children || [])
            result = result.concat(texts(child));
        return result;
    }
    NetworkStatus { id: status; devices: [] }
    PanelWindow {
        id: panel
        property var popup: null
        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 1
        exclusiveZone: 0
        color: "transparent"
        NetworkWidget { id: network; panel: panel; networkStatus: status }
        Component.onCompleted: {
            popup = network.data.find(child => child.grabFocus !== undefined);
            popup.grabFocus = false;
        }
    }
    IpcHandler {
        target: "test"
        function setDevices(data: string): void { status.devices = JSON.parse(data).devices; }
        function openPopup(): void { network.open = true; }
        function snapshot(): string {
            let labels = [];
            for (const item of panel.popup.data)
                labels = labels.concat(test.texts(item));
            const buttons = network.children.filter(child => child.tooltipText !== undefined);
            return JSON.stringify({ known: status.vpnKnown, vpns: status.vpns,
                active: status.vpnActive, changing: status.vpnChanging, summary: status.vpnSummary,
                wired: status.wired.map(device => status.wiredDescription(device)),
                wiredConnected: status.wiredConnection !== null,
                ui: { width: panel.popup.width, height: panel.popup.height, barWidth: network.width,
                    buttons: buttons.map(button => {
                        const badge = button.children.find(child => child.objectName === "vpnBadge");
                        return { icon: button.icon.source.toString(), active: button.active,
                            warning: button.warning, text: button.text, badgeVisible: badge.visible,
                            badgeIcon: badge.children[0].source.toString(), badgeColor: String(badge.children[0].color) };
                    }), texts: labels } });
        }
    }
}
