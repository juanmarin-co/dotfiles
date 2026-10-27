import QtQuick
import Quickshell

PanelWindow {
    id: root
    property bool holdOpen: false
    property bool pointerInside: false
    property bool revealed: false
    readonly property bool shown: revealed || holdOpen
    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: shown ? BarStyle.height : 2
    exclusiveZone: 0
    color: shown ? "#0b0e14" : "transparent"

    function updateHover() {
        if (pointerInside) {
            hideDelay.stop();
            showDelay.restart();
        } else {
            showDelay.stop();
            if (!holdOpen)
                hideDelay.restart();
        }
    }

    onPointerInsideChanged: updateHover()
    onHoldOpenChanged: {
        if (holdOpen) {
            showDelay.stop();
            hideDelay.stop();
            revealed = true;
        } else {
            updateHover();
        }
    }

    HoverHandler {
        parent: root.contentItem
        onHoveredChanged: root.pointerInside = hovered
    }
    Timer {
        id: showDelay
        interval: 120
        onTriggered: {
            if (root.pointerInside)
                root.revealed = true;
        }
    }
    Timer {
        id: hideDelay
        interval: 600
        onTriggered: {
            if (!root.pointerInside && !root.holdOpen)
                root.revealed = false;
        }
    }
}
