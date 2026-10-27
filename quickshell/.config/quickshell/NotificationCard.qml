import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

Rectangle {
    id: card
    required property var notification
    readonly property var actions: notification.actions.filter(action => action.identifier !== "default")
    implicitHeight: content.implicitHeight + 2 * Spacing.outer
    color: "#0b0e14"
    border.color: notification.urgency === NotificationUrgency.Critical ? "#f26d78" : "#273344"
    radius: 8

    function iconSource() {
        const icon = notification.image || notification.appIcon;
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (icon.startsWith("file:") || icon.startsWith("image:"))
            return icon;
        return icon ? Quickshell.iconPath(icon, true) : "";
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            const action = card.notification.actions.find(action => action.identifier === "default");
            if (mouse.button === Qt.LeftButton && action)
                action.invoke();
            else
                card.notification.dismiss();
        }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Spacing.outer
        spacing: Spacing.control

        RowLayout {
            spacing: Spacing.control
            Image {
                source: card.iconSource()
                visible: source.toString().length > 0
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                sourceSize.width: 24
                sourceSize.height: 24
                fillMode: Image.PreserveAspectFit
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Spacing.tight
                BluetoothText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: card.notification.appName
                    textFormat: Text.PlainText
                    color: "#8a9199"
                    font.pixelSize: 11
                }
                BluetoothText {
                    Layout.fillWidth: true
                    text: card.notification.summary
                    textFormat: Text.PlainText
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                }
            }
        }

        BluetoothText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: card.notification.body
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 6
        }

        Flow {
            Layout.fillWidth: true
            visible: card.actions.length > 0
            spacing: Spacing.control
            Repeater {
                model: card.actions
                delegate: BluetoothButton {
                    required property var modelData
                    width: Math.min(implicitWidth, parent.width)
                    text: modelData.text
                    onClicked: modelData.invoke()
                }
            }
        }
    }
}
