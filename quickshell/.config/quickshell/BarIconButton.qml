import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool active: true
    property bool critical: false
    property bool warning: false
    property string tooltipText: text
    implicitWidth: 28
    implicitHeight: 26
    padding: Spacing.tight
    spacing: Spacing.tight
    font.family: "Inter"
    font.pixelSize: 13
    palette.buttonText: icon.color
    palette.brightText: icon.color

    display: AbstractButton.IconOnly
    icon.width: 16
    icon.height: 16
    icon.color: critical ? "#f26d78" : warning ? "#ffb454" : highlighted ? "#e6b450"
        : active ? "#bfbdb6" : "#565b66"
    background: Rectangle {
        radius: 5
        color: control.down ? "#273344" : control.hovered ? "#1b2432" : "transparent"
    }
    StyledToolTip {
        parent: control
        visible: control.hovered
        text: control.tooltipText
    }
}
