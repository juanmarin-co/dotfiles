import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

Item {
    id: root
    required property var panel
    property alias open: popup.visible
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter !== null && adapter.enabled
    readonly property bool powerBusy: adapter !== null
        && (adapter.state === BluetoothAdapterState.Enabling
            || adapter.state === BluetoothAdapterState.Disabling)
    readonly property bool scanning: adapter !== null && adapter.discovering
    readonly property var pairedDevices: adapter
        ? adapter.devices.values.filter(d => d.paired)
            .sort((a, b) => Number(b.connected) - Number(a.connected)
                || (a.name || a.address).localeCompare(b.name || b.address)) : []
    readonly property var nearbyDevices: adapter && (showNearby || scanning)
        ? adapter.devices.values.filter(d => !d.paired)
            .sort((a, b) => (a.name || a.address).localeCompare(b.name || b.address)) : []
    property bool showNearby: false
    property var scanAdapter: null
    property bool stopRequested: false
    property bool scanStarted: false
    property string scanError: ""

    implicitWidth: barButton.implicitWidth
    implicitHeight: BarStyle.buttonSize

    AudioProfiles {
        id: audioProfiles
        active: root.open && root.powered
    }

    function startScan() {
        if (!powered || powerBusy || scanning || scanAdapter)
            return;
        showNearby = true;
        scanError = "";
        scanStarted = false;
        stopRequested = false;
        scanAdapter = adapter;
        scanAdapter.discovering = true;
        scanTimeout.restart();
        scanStartCheck.restart();
    }

    function stopScan() {
        scanTimeout.stop();
        if (!scanAdapter)
            return;
        stopRequested = true;
        if (scanAdapter.discovering) {
            scanAdapter.discovering = false;
            scanAdapter = null;
            stopRequested = false;
        } else if (scanStarted) {
            scanAdapter = null;
            stopRequested = false;
        }
    }

    onOpenChanged: {
        if (!open)
            stopScan();
    }
    onAdapterChanged: stopScan()
    onPoweredChanged: {
        if (!powered)
            stopScan();
    }
    Component.onDestruction: stopScan()

    Timer {
        id: scanTimeout
        interval: 30000
        onTriggered: root.stopScan()
    }

    Timer {
        id: scanStartCheck
        interval: 3000
        onTriggered: {
            if (root.scanAdapter && !root.scanAdapter.discovering) {
                root.scanError = "Scan did not start. Check the Bluetooth service.";
                root.scanAdapter = null;
                root.stopRequested = false;
                scanTimeout.stop();
            }
        }
    }

    Connections {
        target: root.scanAdapter
        function onDiscoveringChanged() {
            if (root.scanAdapter.discovering) {
                root.scanStarted = true;
                // A close/stop can arrive before BlueZ starts discovery.
                if (root.stopRequested)
                    root.stopScan();
            } else if (root.scanStarted) {
                root.stopScan();
            }
        }
    }

    BarButton {
        id: barButton
        anchors.fill: parent
        icon.source: Qt.resolvedUrl("icons/lucide/bluetooth.svg")
        icon.width: BarStyle.smallIconSize
        icon.height: BarStyle.smallIconSize
        active: root.powered
        highlighted: root.open
        text: root.powered ? "Bluetooth" : "Bluetooth off"
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
            focus: true
            Keys.onEscapePressed: popup.visible = false

            RowLayout {
                spacing: Spacing.control
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.tight
                    BluetoothText {
                        text: "Bluetooth"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                    BluetoothText {
                        Layout.fillWidth: true
                        text: root.scanning ? "Looking for nearby devices…"
                            : root.adapter ? root.adapter.name : "No adapter found"
                        color: "#8a9199"
                        font.pixelSize: 12
                    }
                }
                BluetoothButton {
                    visible: root.powered
                    text: root.scanAdapter && !root.stopRequested ? "Stop scan"
                        : root.scanning ? "Scanning…" : "Scan"
                    enabled: !root.powerBusy && !root.stopRequested
                        && (root.scanAdapter !== null || !root.scanning)
                    onClicked: root.scanAdapter ? root.stopScan() : root.startScan()
                }
                BluetoothButton {
                    text: root.powerBusy ? "Working…" : root.powered ? "On" : "Off"
                    highlighted: root.powered
                    enabled: root.adapter !== null && !root.powerBusy
                        && root.adapter.state !== BluetoothAdapterState.Blocked
                    onClicked: root.adapter.enabled = !root.adapter.enabled
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#1b2432"
            }

            ScrollView {
                id: deviceScroll
                visible: root.powered
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? Math.min(deviceColumn.implicitHeight, 360) : 0
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: deviceColumn
                    width: deviceScroll.availableWidth
                    spacing: Spacing.control

                    BluetoothText {
                        text: "PAIRED · " + root.pairedDevices.length
                        color: "#8a9199"
                        font.pixelSize: 11
                    }
                    Repeater {
                        model: root.pairedDevices
                        delegate: BluetoothDeviceRow {
                            required property var modelData
                            device: modelData
                            audio: audioProfiles
                            widgetOpen: root.open
                            Layout.fillWidth: true
                        }
                    }
                    BluetoothText {
                        visible: root.pairedDevices.length === 0
                        text: "No paired devices."
                        color: "#8a9199"
                        Layout.margins: Spacing.control
                    }
                    BluetoothText {
                        visible: root.showNearby || root.scanning
                        text: "NEARBY · " + root.nearbyDevices.length
                        color: "#8a9199"
                        font.pixelSize: 11
                        Layout.topMargin: Spacing.tight
                    }
                    Repeater {
                        model: root.nearbyDevices
                        delegate: BluetoothDeviceRow {
                            required property var modelData
                            device: modelData
                            audio: audioProfiles
                            widgetOpen: root.open
                            Layout.fillWidth: true
                        }
                    }
                    BluetoothText {
                        visible: (root.showNearby || root.scanning) && root.nearbyDevices.length === 0
                        text: root.scanning ? "Looking for devices…" : "No nearby devices found."
                        color: "#8a9199"
                        Layout.margins: Spacing.control
                    }
                }
            }

            BluetoothText {
                visible: !root.powered
                Layout.fillWidth: true
                Layout.topMargin: Spacing.control
                Layout.bottomMargin: Spacing.control
                text: !root.adapter ? "No Bluetooth adapter available."
                    : root.adapter.state === BluetoothAdapterState.Blocked
                        ? "Bluetooth is blocked. Check your hardware switch or rfkill."
                    : root.powerBusy ? "Changing adapter power…"
                    : "Bluetooth is off. Turn it on to connect your devices."
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#8a9199"
            }

            BluetoothText {
                visible: root.powered && (root.showNearby || root.scanning)
                Layout.fillWidth: true
                text: "Nearby results may be cached. New-device pairing isn't available yet."
                wrapMode: Text.WordWrap
                color: "#8a9199"
                font.pixelSize: 11
            }

            BluetoothText {
                visible: text !== ""
                Layout.fillWidth: true
                text: root.scanError || audioProfiles.error
                wrapMode: Text.WordWrap
                color: "#f26d78"
                font.pixelSize: 12
            }
        }
    }
}
