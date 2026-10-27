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

    Rz09Service {
        id: monitor
        socketPath: Quickshell.env("RZ09_TEST_SOCKET")
    }

    PanelWindow {
        id: panel
        property var popup: null
        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 1
        exclusiveZone: 0
        color: "transparent"
        CoolingWidget { id: cooling; panel: panel; service: monitor }
        Component.onCompleted: {
            popup = cooling.data.find(child => child.grabFocus !== undefined);
            popup.grabFocus = false;
        }
    }

    IpcHandler {
        target: "test"
        function openPopup(): void { cooling.open = true; }
        function snapshot(): string {
            const popup = panel.popup;
            const button = cooling.data.find(child => child.tooltipText !== undefined);
            let labels = [];
            for (const item of popup.data)
                labels = labels.concat(test.texts(item));
            return JSON.stringify({ connected: monitor.connected, available: monitor.available,
                sample: monitor.snapshot, ui: { width: popup.width, height: popup.height, open: cooling.open,
                    barWidth: cooling.width, label: button.text, color: String(button.icon.color),
                    status: cooling.status, fanSummary: cooling.fanSummary, texts: labels } });
        }
    }
}
