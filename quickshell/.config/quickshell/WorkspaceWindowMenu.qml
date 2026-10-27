import QtQuick
import QtQml.Models
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Menu {
    id: root
    required property var screen
    property int workspaceIndex: 0
    property var workspaceId: null
    property var windows: []
    property bool loading: false
    property string error: ""
    popupType: Popup.Window
    width: 360
    padding: Spacing.control
    y: parent ? parent.height + Spacing.control : 0

    function openFor(button) {
        if (loading)
            return;
        parent = button;
        loadWindows(button.modelData.coordinates[1] + 1);
        popup();
    }

    function loadWindows(index) {
        if (loading)
            return;
        workspaceIndex = index;
        windows = [];
        error = "";
        loading = true;
        workspaceQuery.running = true;
    }

    function appNameFor(window) {
        const entry = window.app_id ? DesktopEntries.heuristicLookup(window.app_id) : null;
        return entry?.name || window.app_id || "";
    }

    function iconFor(window) {
        const icon = window.app_id ? DesktopEntries.heuristicLookup(window.app_id)?.icon || "" : "";
        return icon.startsWith("/") ? "file://" + icon : icon ? Quickshell.iconPath(icon, true) : "";
    }

    function labelFor(window) {
        return (window.title || "").replace(/\s+/g, " ").trim()
            || appNameFor(window) || "Untitled window";
    }

    function fail(message) {
        error = message;
        loading = false;
    }

    function activateWindow(id) {
        dismiss();
        focusProcess.command = ["niri", "msg", "action", "focus-window", "--id", String(id)];
        focusProcess.running = true;
    }

    background: Rectangle {
        color: "#0b0e14"
        border.color: "#273344"
        radius: 6
    }

    ActionMenuItem {
        visible: root.loading || root.windows.length === 0
        height: visible ? implicitHeight : 0
        enabled: false
        text: root.loading ? "Loading…" : root.error || "No windows on this workspace"
    }

    Instantiator {
        model: root.windows
        onObjectAdded: (index, object) => root.insertItem(index, object)
        onObjectRemoved: (index, object) => root.removeItem(object)
        delegate: ActionMenuItem {
            required property var modelData
            text: root.labelFor(modelData)
            icon.source: root.iconFor(modelData)
            tooltipText: root.appNameFor(modelData)
            checked: modelData.is_focused
            enabled: !focusProcess.running
            onTriggered: root.activateWindow(modelData.id)
        }
    }

    Process {
        id: workspaceQuery
        command: ["niri", "msg", "--json", "workspaces"]
        stdout: StdioCollector { id: workspaceOutput }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fail("Could not read workspaces");
                return;
            }
            try {
                // The native workspace API exposes position, while Niri's windows use stable IDs.
                const workspace = JSON.parse(workspaceOutput.text)
                    .find(w => w.output === root.screen.name && w.idx === root.workspaceIndex);
                if (!workspace) {
                    root.fail("Workspace is no longer available");
                    return;
                }
                root.workspaceId = workspace.id;
                windowQuery.running = true;
            } catch (error) {
                root.fail("Could not read workspaces");
            }
        }
    }

    Process {
        id: windowQuery
        command: ["niri", "msg", "--json", "windows"]
        stdout: StdioCollector { id: windowOutput }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.fail("Could not read windows");
                return;
            }
            try {
                root.windows = JSON.parse(windowOutput.text)
                    .filter(w => w.workspace_id === root.workspaceId)
                    .sort((a, b) => Number(b.is_focused) - Number(a.is_focused)
                        || root.labelFor(a).localeCompare(root.labelFor(b)));
                root.loading = false;
            } catch (error) {
                root.fail("Could not read windows");
            }
        }
    }

    Process { id: focusProcess }
}
