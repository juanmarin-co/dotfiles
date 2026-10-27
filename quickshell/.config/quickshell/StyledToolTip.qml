import QtQuick
import QtQuick.Controls

ToolTip {
    id: tooltip
    delay: 600
    popupType: Popup.Window
    x: parent ? (parent.width - implicitWidth) / 2 : 0
    y: parent ? parent.height + Spacing.control : Spacing.control
    padding: Spacing.control
    contentItem: BluetoothText {
        text: tooltip.text
        textFormat: Text.PlainText
    }
    background: Rectangle {
        color: "#11151c"
        border.color: "#273344"
        radius: 5
    }
}
