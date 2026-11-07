import QtQuick
import QtQuick.Controls.impl
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window
    required property var service
    screen: Quickshell.screens[0]
    anchors.bottom: true
    margins.bottom: 80
    implicitWidth: 340
    implicitHeight: content.implicitHeight + 2 * Spacing.outer
    exclusiveZone: 0
    color: "transparent"
    visible: service.showing || card.opacity > 0
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dotfiles-media-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: card
        anchors.fill: parent
        color: "#0b0e14"
        border.color: "#273344"
        radius: 8
        opacity: window.service.showing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Spacing.outer
            spacing: Spacing.control
            RowLayout {
                spacing: Spacing.control
                ColorImage {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    sourceSize.width: 24
                    sourceSize.height: 24
                    source: Qt.resolvedUrl("icons/lucide/" + window.service.icon + ".svg")
                    color: "#e6b450"
                }
                BluetoothText {
                    Layout.fillWidth: true
                    text: window.service.label
                    textFormat: Text.PlainText
                    font.weight: Font.Medium
                }
            }
            BluetoothText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: window.service.detail
                textFormat: Text.PlainText
                color: "#8a9199"
                font.pixelSize: 12
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: "#1b2432"
                visible: window.service.level >= 0
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, window.service.level))
                    height: parent.height
                    radius: 2
                    color: "#e6b450"
                }
            }
        }
    }
}
