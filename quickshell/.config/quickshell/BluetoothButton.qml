import QtQuick
import QtQuick.Controls

Button {
    id: control
    padding: Spacing.control
    implicitWidth: label.implicitWidth + leftPadding + rightPadding
    implicitHeight: label.implicitHeight + topPadding + bottomPadding
    opacity: enabled ? 1 : 0.45
    contentItem: BluetoothText {
        id: label
        text: control.text
        color: control.highlighted ? "#0b0e14" : "#e6b450"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 5
        color: control.highlighted ? "#e6b450"
            : control.down ? "#273344"
            : control.hovered ? "#1b2432" : "transparent"
    }
}
