import QtQuick
import QtQuick.Controls

TextField {
    id: control
    padding: Spacing.control
    placeholderTextColor: "#8a9199"
    color: "#bfbdb6"
    selectionColor: "#e6b450"
    selectedTextColor: "#0b0e14"
    font.family: "Inter"
    font.pixelSize: 13
    background: Rectangle {
        color: "#11151c"
        radius: 5
        border.color: control.activeFocus ? "#e6b450" : "#273344"
    }
}
