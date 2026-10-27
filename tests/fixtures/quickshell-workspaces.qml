import QtQml
import Quickshell
import Quickshell.Io

ShellRoot {
    QtObject {
        id: output
        property string name: "eDP-1"
    }
    WorkspaceWindowMenu {
        id: menu
        screen: output
    }
    IpcHandler {
        target: "test"
        function loadWorkspace(index: int): void { menu.loadWindows(index); }
        function activateWindow(id: int): void { menu.activateWindow(id); }
        function snapshot(): string {
            const items = [];
            for (let i = 0; i < menu.count; ++i) {
                const item = menu.itemAt(i);
                const label = item.contentItem.children.find(child => child.textFormat !== undefined);
                items.push({ text: item.text, format: label.textFormat, checked: item.checked,
                    tooltip: item.tooltipText, icon: item.icon.source.toString() });
            }
            return JSON.stringify({
                appCount: DesktopEntries.applications.values.length,
                loading: menu.loading, error: menu.error, windows: menu.windows,
                labels: menu.windows.map(window => menu.labelFor(window)), items: items
            });
        }
    }
}
