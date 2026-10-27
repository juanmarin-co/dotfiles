import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    AutoHidePanel {
        id: panel
        BarButton {
            id: large
            visible: panel.shown
            anchors.verticalCenter: parent.verticalCenter
            text: "Sizing probe"
        }
        BarIconButton { id: compact; visible: false }
    }
    IpcHandler {
        target: "test"
        function hover(value: bool): void { panel.pointerInside = value; }
        function hold(value: bool): void { panel.holdOpen = value; }
        function snapshot(): string {
            return JSON.stringify({ shown: panel.shown, height: panel.height, visible: panel.visible,
                color: String(panel.color), exclusiveZone: panel.exclusiveZone,
                button: [large.width, large.height, large.icon.width, large.font.pixelSize],
                horizontalPadding: [large.leftPadding, large.rightPadding],
                compact: [compact.implicitWidth, compact.implicitHeight, compact.icon.width] });
        }
    }
}
