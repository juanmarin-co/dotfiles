import QtQml
import Quickshell
import Quickshell.Io

ShellRoot {
    QtObject {
        id: feed
        property var visibleToasts: []
    }
    QtObject {
        id: sample
        property string appName: "Quickshell test"
        property string appIcon: ""
        property string image: ""
        property string summary: "Toast layout test"
        property string body: "Checking window geometry without reading images."
        property int urgency: 1
        property var actions: []
    }
    QtObject {
        id: action
        property string identifier: "open"
        property string text: "Open"
        function invoke(): void {}
    }
    NotificationToasts {
        id: toasts
        service: feed
    }
    IpcHandler {
        target: "test"
        function displayToast(): void { feed.visibleToasts = [sample]; }
        function hideToasts(): void { feed.visibleToasts = []; }
        function addAction(): void { sample.actions = [action]; }
        function snapshot(): string {
            const stack = toasts.contentItem.children[0];
            return JSON.stringify({
                visible: toasts.visible, width: toasts.width, height: toasts.height,
                focusable: toasts.focusable, count: feed.visibleToasts.length,
                stackHeight: stack.height, stackImplicitHeight: stack.implicitHeight,
                cards: stack.children.filter(child => child.notification !== undefined)
                    .map(card => ({ width: card.width, height: card.height, implicitHeight: card.implicitHeight }))
            });
        }
    }
}
