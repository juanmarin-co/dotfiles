import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    required property string label
    required property string value
    property color valueColor: "#bfbdb6"
    spacing: Spacing.control

    BluetoothText {
        Layout.fillWidth: true
        text: root.label
        textFormat: Text.PlainText
        color: "#8a9199"
    }
    BluetoothText {
        Layout.maximumWidth: 240
        text: root.value
        textFormat: Text.PlainText
        color: root.valueColor
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignRight
    }
}
