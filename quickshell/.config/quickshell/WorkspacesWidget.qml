import QtQuick
import Quickshell.WindowManager

Item {
    id: root
    required property var screen
    property alias open: windowMenu.visible
    // Niri orders workspaces along the vertical coordinate.
    readonly property var workspaces: WindowManager.screenProjection(screen).windowsets
        .filter(workspace => workspace.shouldDisplay)
        .sort((a, b) => (a.coordinates[1] ?? 0) - (b.coordinates[1] ?? 0))
    implicitWidth: row.implicitWidth
    implicitHeight: BarStyle.buttonSize

    WorkspaceWindowMenu {
        id: windowMenu
        screen: root.screen
    }

    Row {
        id: row
        anchors.fill: parent
        Repeater {
            model: root.workspaces
            delegate: BarButton {
                id: button
                required property var modelData
                text: "Workspace " + modelData.name
                active: modelData.active
                highlighted: modelData.active
                critical: modelData.urgent
                enabled: modelData.canActivate
                onClicked: {
                    windowMenu.dismiss();
                    modelData.activate();
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: windowMenu.openFor(button)
                }
                contentItem: Item {
                    Rectangle {
                        anchors.centerIn: parent
                        width: BarStyle.workspaceDotSize
                        height: width
                        radius: width / 2
                        color: button.highlighted || button.critical ? button.icon.color : "transparent"
                        border.color: button.icon.color
                    }
                }
            }
        }
    }
}
