import QtQuick
import QtQml.Models
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth

Rectangle {
    id: row
    required property var device
    required property var audio
    required property bool widgetOpen
    readonly property var card: audio.cards[device.address] || null
    readonly property bool busy: device.state === BluetoothDeviceState.Connecting
        || device.state === BluetoothDeviceState.Disconnecting
    readonly property bool menuAvailable: widgetOpen && device.adapter.enabled
        && device.connected && card !== null && card.profiles.length > 0
    onMenuAvailableChanged: {
        if (!menuAvailable)
            codecMenu.dismiss();
    }

    implicitHeight: rowContent.implicitHeight + 2 * Spacing.control
    radius: 6
    color: "#11151c"

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
                text: row.device.name || row.device.address
                font.weight: Font.Medium
            }
            BluetoothText {
                Layout.fillWidth: true
                text: (row.device.blocked ? "Blocked"
                    : !row.device.paired ? "Not paired"
                    : BluetoothDeviceState.toString(row.device.state))
                    + (row.device.batteryAvailable
                        ? " · " + Math.round(row.device.battery * 100) + "%" : "")
                color: row.device.connected ? "#aad94c" : "#8a9199"
                font.pixelSize: 12
            }
        }

        BluetoothButton {
            id: codecButton
            visible: row.menuAvailable
            text: (row.card?.profiles.find(p => p.index === row.card.current)?.label || "Codec") + " ▾"
            enabled: !row.audio.busy && !row.busy
            onClicked: codecMenu.popup()

            Menu {
                id: codecMenu
                y: codecButton.height
                width: 160
                padding: Spacing.control
                background: Rectangle {
                    color: "#0b0e14"
                    border.color: "#273344"
                    radius: 6
                }
                Instantiator {
                    model: row.card ? row.card.profiles : []
                    onObjectAdded: (index, object) => codecMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => codecMenu.removeItem(object)
                    delegate: ActionMenuItem {
                        required property var modelData
                        text: modelData.label
                        checked: row.card.current === modelData.index
                        onTriggered: row.audio.selectProfile(row.card, modelData.index)
                    }
                }
            }
        }

        BluetoothButton {
            visible: row.device.paired
            text: row.busy ? "Working…" : row.device.connected ? "Disconnect" : "Connect"
            highlighted: !row.device.connected
            enabled: row.device.adapter.enabled && !row.busy && !row.device.blocked
            onClicked: row.device.connected = !row.device.connected
        }
    }
}
