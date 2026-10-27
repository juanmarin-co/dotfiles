import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var panel
    required property date now
    property alias open: popup.visible
    property date monthDate: new Date(now.getFullYear(), now.getMonth(), 1)
    implicitWidth: clockText.implicitWidth + 2 * Spacing.control
    implicitHeight: BarStyle.buttonSize

    function showToday() {
        monthDate = new Date(now.getFullYear(), now.getMonth(), 1);
    }

    function moveMonth(offset) {
        monthDate = new Date(monthDate.getFullYear(), monthDate.getMonth() + offset, 1);
    }

    onOpenChanged: {
        if (open)
            showToday();
    }

    Button {
        id: clockButton
        anchors.fill: parent
        horizontalPadding: Spacing.control
        verticalPadding: Spacing.tight
        onClicked: popup.visible = !popup.visible
        contentItem: BluetoothText {
            id: clockText
            font.pixelSize: BarStyle.fontSize
            text: Qt.formatDateTime(root.now, "ddd, MMM d  ·  HH:mm:ss")
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 5
            color: clockButton.down ? "#273344" : clockButton.hovered ? "#1b2432" : "transparent"
        }
    }

    PopupWindow {
        id: popup
        anchor.window: root.panel
        anchor.rect.x: (root.panel.width - width) / 2
        anchor.rect.y: root.panel.height + Spacing.control
        implicitWidth: 360
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

            RowLayout {
                spacing: Spacing.control
                BluetoothText {
                    Layout.fillWidth: true
                    text: Qt.formatDate(root.monthDate, "MMMM yyyy")
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                BluetoothButton {
                    text: "‹"
                    implicitWidth: 28
                    onClicked: root.moveMonth(-1)
                }
                BluetoothButton {
                    text: "›"
                    implicitWidth: 28
                    onClicked: root.moveMonth(1)
                }
                BluetoothButton {
                    text: "Today"
                    onClicked: root.showToday()
                }
            }

            DayOfWeekRow {
                id: weekdays
                Layout.fillWidth: true
                locale: monthGrid.locale
                spacing: monthGrid.spacing
                padding: 0
                delegate: BluetoothText {
                    required property string shortName
                    text: shortName
                    width: (weekdays.availableWidth - 6 * weekdays.spacing) / 7
                    height: 20
                    color: "#8a9199"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            MonthGrid {
                id: monthGrid
                Layout.fillWidth: true
                month: root.monthDate.getMonth()
                year: root.monthDate.getFullYear()
                locale: Qt.locale()
                spacing: Spacing.tight
                padding: 0
                delegate: Rectangle {
                    required property var model
                    readonly property bool today: model.day === root.now.getDate()
                        && model.month === root.now.getMonth() && model.year === root.now.getFullYear()
                    width: (monthGrid.availableWidth - 6 * monthGrid.spacing) / 7
                    height: 32
                    radius: 5
                    color: today ? "#e6b450" : "transparent"

                    BluetoothText {
                        anchors.centerIn: parent
                        text: model.day
                        color: parent.today ? "#0b0e14"
                            : model.month === monthGrid.month ? "#bfbdb6" : "#565b66"
                    }
                }
            }
        }
    }
}
