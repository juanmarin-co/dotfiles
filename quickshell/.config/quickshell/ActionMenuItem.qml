import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

MenuItem {
    id: control
    property bool destructive: false
    property string tooltipText: ""
    property string checkedMarker: "✓"
    padding: Spacing.control
    implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
    indicator: null
    opacity: enabled ? 1 : 0.45
    contentItem: RowLayout {
        spacing: Spacing.control
        Image {
            source: control.icon.source
            visible: source.toString().length > 0
            Layout.preferredWidth: control.icon.width
            Layout.preferredHeight: control.icon.height
            sourceSize.width: control.icon.width
            sourceSize.height: control.icon.height
            fillMode: Image.PreserveAspectFit
        }
        BluetoothText {
            Layout.fillWidth: true
            text: (control.checked ? control.checkedMarker + "  " : "") + control.text
            textFormat: Text.PlainText
            color: control.destructive ? "#f26d78" : control.checked ? "#e6b450" : "#bfbdb6"
            verticalAlignment: Text.AlignVCenter
        }
    }
    StyledToolTip {
        parent: control
        visible: control.hovered && control.tooltipText.length > 0
        text: control.tooltipText
    }
    background: Rectangle {
        color: control.highlighted ? "#1b2432" : "transparent"
        radius: 4
    }
}
