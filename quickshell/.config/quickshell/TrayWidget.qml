import QtQuick
import Quickshell.Services.SystemTray

Item {
    id: root
    property alias open: menu.visible
    property var selectedItem: null
    implicitWidth: icons.implicitWidth
    implicitHeight: BarStyle.buttonSize

    function showMenu(button, item) {
        if (!item?.hasMenu)
            return;
        menu.dismiss();
        selectedItem = item;
        menu.parent = button;
        menu.y = button.height + Spacing.control;
        menu.entry = item.menu;
        menu.popup();
    }

    function activateItem(button, item) {
        if (!item)
            return;
        if (item.onlyMenu)
            showMenu(button, item);
        else {
            menu.dismiss();
            item.activate();
        }
    }

    TrayMenu {
        id: menu
        onClosed: Qt.callLater(() => {
            if (!visible) {
                root.selectedItem = null;
                entry = null;
            }
        })
    }

    Row {
        id: icons
        anchors.fill: parent
        Repeater {
            model: SystemTray.items
            delegate: BarButton {
                id: button
                required property var modelData
                active: modelData?.status !== Status.Passive
                critical: modelData?.status === Status.NeedsAttention
                highlighted: root.open && root.selectedItem === modelData
                opacity: active ? 1 : 0.55
                text: modelData?.tooltipTitle || modelData?.title || modelData?.id || ""
                tooltipText: text + (modelData?.tooltipDescription && modelData.tooltipDescription !== text
                    ? "\n" + modelData.tooltipDescription : "")
                onClicked: root.activateItem(button, modelData)
                contentItem: Item {
                    Image {
                        anchors.centerIn: parent
                        width: BarStyle.iconSize
                        height: width
                        sourceSize.width: width
                        sourceSize.height: height
                        source: button.modelData?.icon || ""
                        fillMode: Image.PreserveAspectFit
                    }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Spacing.tight
                    width: Spacing.tight
                    height: Spacing.tight
                    radius: width / 2
                    color: "#f26d78"
                    visible: button.critical
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            root.showMenu(button, button.modelData);
                        else
                            button.modelData?.secondaryActivate();
                    }
                    onWheel: wheel => {
                        if (wheel.angleDelta.y !== 0)
                            button.modelData?.scroll(wheel.angleDelta.y, false);
                        else if (wheel.angleDelta.x !== 0)
                            button.modelData?.scroll(wheel.angleDelta.x, true);
                        wheel.accepted = true;
                    }
                }
            }
        }
    }
}
