import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking

Item {
    id: root
    required property var panel
    required property var networkStatus
    property alias open: popup.visible
    readonly property var adapter: networkStatus.wifiAdapter
    readonly property bool powered: Networking.wifiEnabled
    readonly property var networks: adapter ? adapter.networks.values.slice()
        .sort((a, b) => Number(b.connected) - Number(a.connected)
            || b.signalStrength - a.signalStrength || a.name.localeCompare(b.name)) : []
    readonly property var connectedNetwork: networks.find(n => n.connected) || null
    readonly property var wiredConnection: networkStatus.wiredConnection
    readonly property var wiredDevice: wiredConnection || (connectedNetwork ? null
        : networkStatus.wired.find(device => device.hasLink) || null)
    readonly property string connectionText: wiredDevice
        ? "Wired · " + (wiredDevice.network?.name || wiredDevice.name) + " · " + networkStatus.wiredState(wiredDevice)
        : !powered ? "Wi-Fi off" : connectedNetwork ? connectedNetwork.name : "Wi-Fi disconnected"
    property var passwordNetwork: null
    property string error: ""

    implicitWidth: barButton.implicitWidth
    implicitHeight: BarStyle.buttonSize

    function needsPassword(network) {
        return network.security === WifiSecurityType.WpaPsk
            || network.security === WifiSecurityType.Wpa2Psk
            || network.security === WifiSecurityType.Sae;
    }

    function promptPassword(network) {
        passwordNetwork = network;
        password.clear();
        password.forceActiveFocus();
    }

    function connectNetwork(network) {
        if (network.connected || network.stateChanging)
            return;
        error = "";
        if (network.known || network.security === WifiSecurityType.Open
                || network.security === WifiSecurityType.Owe) {
            network.connect();
        } else if (needsPassword(network)) {
            promptPassword(network);
        } else {
            error = "Configure this network in NetworkManager first.";
        }
    }

    function submitPassword() {
        if (!passwordNetwork || password.text.length === 0)
            return;
        error = "";
        passwordNetwork.connectWithPsk(password.text);
        password.clear();
        passwordNetwork = null;
    }

    function clearPassword() {
        password.clear();
        passwordNetwork = null;
    }

    onOpenChanged: {
        clearPassword();
        if (open && powered) {
            error = "";
            scanTimer.restart();
        } else {
            scanTimer.stop();
        }
    }
    onPoweredChanged: {
        if (!powered) {
            clearPassword();
            scanTimer.stop();
        } else if (open) {
            scanTimer.restart();
        }
    }

    Binding {
        target: root.adapter
        property: "scannerEnabled"
        when: root.adapter !== null
        value: root.open && root.powered && scanTimer.running
        restoreMode: Binding.RestoreBindingOrValue
    }

    Timer {
        id: scanTimer
        interval: 15000
    }

    BarButton {
        id: barButton
        anchors.fill: parent
        icon.source: Qt.resolvedUrl("icons/lucide/" + (root.wiredDevice ? "ethernet-port.svg" : "wifi.svg"))
        active: root.wiredConnection !== null || (root.powered && root.connectedNetwork !== null)
        warning: (root.wiredDevice !== null && !root.wiredDevice.connected)
            || !root.networkStatus.vpnKnown || root.networkStatus.vpnChanging
        highlighted: root.open
        text: root.connectionText + "\n" + root.networkStatus.vpnSummary
        onClicked: root.open = !root.open

        Rectangle {
            objectName: "vpnBadge"
            parent: barButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 16
            height: 16
            radius: 8
            color: "#0b0e14"
            visible: root.networkStatus.vpnActive || root.networkStatus.vpnChanging || !root.networkStatus.vpnKnown
            ColorImage {
                anchors.centerIn: parent
                width: 14
                height: 14
                sourceSize.width: width
                sourceSize.height: height
                source: Qt.resolvedUrl("icons/lucide/" + (root.networkStatus.vpnActive ? "shield-check.svg" : "shield.svg"))
                color: !root.networkStatus.vpnKnown || root.networkStatus.vpnChanging ? "#ffb454" : "#e6b450"
            }
        }
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
            Keys.onEscapePressed: {
                if (root.passwordNetwork)
                    root.clearPassword();
                else
                    popup.visible = false;
            }

            RowLayout {
                spacing: Spacing.control
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Spacing.tight
                    BluetoothText {
                        text: "Network"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                    BluetoothText {
                        Layout.fillWidth: true
                        text: root.connectionText
                        textFormat: Text.PlainText
                        color: "#8a9199"
                        font.pixelSize: 12
                    }
                }
                BluetoothButton {
                    visible: root.powered && root.adapter !== null
                    text: scanTimer.running ? "Stop scan" : "Scan"
                    onClicked: scanTimer.running ? scanTimer.stop() : scanTimer.restart()
                }
                BluetoothButton {
                    text: root.powered ? "Wi-Fi on" : "Wi-Fi off"
                    highlighted: root.powered
                    enabled: root.adapter !== null && Networking.wifiHardwareEnabled
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#1b2432"
            }

            ColumnLayout {
                visible: root.networkStatus.wired.length > 0
                Layout.fillWidth: true
                spacing: Spacing.control
                BluetoothText {
                    text: "Wired"
                    font.weight: Font.Medium
                }
                Repeater {
                    model: root.networkStatus.wired
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Spacing.tight
                        BluetoothText {
                            Layout.fillWidth: true
                            text: modelData.network?.name || modelData.name
                            textFormat: Text.PlainText
                        }
                        BluetoothText {
                            Layout.fillWidth: true
                            text: root.networkStatus.wiredDescription(modelData)
                            textFormat: Text.PlainText
                            font.pixelSize: 12
                            color: "#8a9199"
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Spacing.control
                BluetoothText {
                    text: "VPN · NetworkManager"
                    font.weight: Font.Medium
                }
                BluetoothText {
                    visible: !root.networkStatus.vpnKnown || root.networkStatus.vpns.length === 0
                    Layout.fillWidth: true
                    text: root.networkStatus.vpnSummary
                    color: root.networkStatus.vpnKnown ? "#8a9199" : "#ffb454"
                    font.pixelSize: 12
                }
                Repeater {
                    model: root.networkStatus.vpns
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Spacing.tight
                        BluetoothText {
                            Layout.fillWidth: true
                            text: modelData.name
                            textFormat: Text.PlainText
                        }
                        BluetoothText {
                            Layout.fillWidth: true
                            text: (modelData.type === "wireguard" ? "WireGuard" : "VPN")
                                + " · " + root.networkStatus.vpnState(modelData.state)
                            font.pixelSize: 12
                            color: modelData.state === "activated" ? "#8a9199" : "#ffb454"
                        }
                    }
                }
            }

            BluetoothText {
                text: "Wi-Fi"
                font.weight: Font.Medium
            }

            ColumnLayout {
                visible: root.powered && root.passwordNetwork !== null
                Layout.fillWidth: true
                spacing: Spacing.control
                BluetoothText {
                    Layout.fillWidth: true
                    text: "Connect to " + (root.passwordNetwork?.name || "")
                    textFormat: Text.PlainText
                    font.weight: Font.Medium
                }
                StyledTextField {
                    id: password
                    Layout.fillWidth: true
                    placeholderText: "Password"
                    echoMode: TextInput.Password
                    onAccepted: root.submitPassword()
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Spacing.control
                    BluetoothButton {
                        text: "Cancel"
                        onClicked: root.clearPassword()
                    }
                    BluetoothButton {
                        text: "Connect"
                        highlighted: true
                        enabled: password.text.length > 0
                        onClicked: root.submitPassword()
                    }
                }
            }

            ListView {
                id: networkList
                visible: root.powered && root.passwordNetwork === null && count > 0
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? Math.min(contentHeight, 360) : 0
                clip: true
                spacing: Spacing.control
                model: root.networks
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    id: networkRow
                    required property var modelData
                    readonly property bool actionsAvailable: root.open && root.powered
                        && root.passwordNetwork === null
                    onActionsAvailableChanged: {
                        if (!actionsAvailable)
                            actionsMenu.dismiss();
                    }
                    width: networkList.width
                    height: rowContent.implicitHeight + 2 * Spacing.control
                    color: actionsMenu.visible ? "#1b2432" : rowMouse.containsMouse ? "#161d27" : "#11151c"
                    radius: 6

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: networkRow.modelData.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: root.connectNetwork(networkRow.modelData)
                    }

                    Connections {
                        target: networkRow.modelData
                        function onConnectionFailed(reason) {
                            if (!root.open)
                                return;
                            if (reason === ConnectionFailReason.NoSecrets && root.needsPassword(networkRow.modelData)) {
                                root.error = "A password is required. Check it and try again.";
                                root.promptPassword(networkRow.modelData);
                            } else {
                                root.error = "Could not connect: " + ConnectionFailReason.toString(reason);
                            }
                        }
                    }

                    RowLayout {
                        id: rowContent
                        anchors.fill: parent
                        anchors.margins: Spacing.control
                        spacing: Spacing.control
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Spacing.tight
                            BluetoothText {
                                Layout.fillWidth: true
                                text: networkRow.modelData.name
                                textFormat: Text.PlainText
                                font.weight: Font.Medium
                            }
                            BluetoothText {
                                Layout.fillWidth: true
                                text: (networkRow.modelData.stateChanging || networkRow.modelData.connected
                                    ? ConnectionState.toString(networkRow.modelData.state) + " · " : "")
                                    + Math.round(networkRow.modelData.signalStrength * 100) + "% · "
                                    + WifiSecurityType.toString(networkRow.modelData.security)
                                    + (networkRow.modelData.known ? " · Saved" : "")
                                color: networkRow.modelData.connected ? "#aad94c" : "#8a9199"
                                font.pixelSize: 12
                            }
                        }
                        BarIconButton {
                            id: actionsButton
                            icon.source: Qt.resolvedUrl("icons/lucide/ellipsis.svg")
                            highlighted: actionsMenu.visible
                            text: "Network actions"
                            enabled: !networkRow.modelData.stateChanging
                            onClicked: actionsMenu.popup()

                            Menu {
                                id: actionsMenu
                                y: actionsButton.height
                                width: 180
                                padding: Spacing.control
                                background: Rectangle {
                                    color: "#0b0e14"
                                    border.color: "#273344"
                                    radius: 6
                                }
                                ActionMenuItem {
                                    text: networkRow.modelData.connected ? "Disconnect" : "Connect"
                                    enabled: !networkRow.modelData.stateChanging
                                    onTriggered: {
                                        if (networkRow.modelData.connected)
                                            networkRow.modelData.disconnect();
                                        else
                                            root.connectNetwork(networkRow.modelData);
                                    }
                                }
                                ActionMenuItem {
                                    text: "Forget network"
                                    visible: networkRow.modelData.known
                                    height: visible ? implicitHeight : 0
                                    destructive: true
                                    enabled: !networkRow.modelData.stateChanging
                                    onTriggered: networkRow.modelData.forget()
                                }
                            }
                        }
                    }
                }
            }

            BluetoothText {
                visible: !root.adapter || !root.powered || root.networks.length === 0
                Layout.fillWidth: true
                Layout.topMargin: Spacing.control
                Layout.bottomMargin: Spacing.control
                text: !root.adapter ? "No Wi-Fi adapter available."
                    : !Networking.wifiHardwareEnabled ? "Wi-Fi is blocked by a hardware switch or rfkill."
                    : !root.powered ? "Wi-Fi is off. Turn it on to see networks."
                    : scanTimer.running ? "Looking for networks…" : "No networks found. Try scanning."
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#8a9199"
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
