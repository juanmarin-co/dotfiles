import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property url directory: "file:///sys/class/backlight"
    readonly property string device: devices.count ? devices.get(0, "fileName") : ""
    readonly property string devicePath: device ? String(directory).replace(/^file:\/\//, "") + "/" + device : ""
    property int pendingSteps: 0
    property bool reading: false
    property bool maximumReady: false
    property bool currentReady: false
    property int requested: 0
    signal adjusted(real level)
    signal failed(string message)

    function change(steps) {
        if (!device) {
            failed("No display backlight");
            return;
        }
        pendingSteps += steps;
        if (reading || writer.running)
            return;
        reading = true;
        maximumReady = false;
        currentReady = false;
        maximum.reload();
        current.reload();
    }

    function applyPending() {
        if (!reading || !maximumReady || !currentReady)
            return;
        const max = Number(maximum.text().trim());
        const value = Number(current.text().trim());
        reading = false;
        if (!(max > 0) || !Number.isFinite(value)) {
            pendingSteps = 0;
            failed("Cannot read display brightness");
            return;
        }
        // Keep the display lit at the lower bound.
        requested = Math.max(Math.max(1, Math.round(max / 100)),
            Math.min(max, Math.round(value + max * pendingSteps / 100)));
        pendingSteps = 0;
        writer.command = ["busctl", "--system", "--allow-interactive-authorization=no", "call",
            "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
            "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", device, String(requested)];
        writer.running = true;
    }

    function readFailed() {
        if (reading) {
            reading = false;
            pendingSteps = 0;
            failed("Cannot read display brightness");
        }
    }

    FolderListModel {
        id: devices
        folder: root.directory
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }
    FileView {
        id: maximum
        path: root.devicePath ? root.devicePath + "/max_brightness" : ""
        printErrors: false
        onLoaded: { root.maximumReady = true; root.applyPending(); }
        onLoadFailed: root.readFailed()
    }
    FileView {
        id: current
        path: root.devicePath ? root.devicePath + "/brightness" : ""
        printErrors: false
        onLoaded: { root.currentReady = true; root.applyPending(); }
        onLoadFailed: root.readFailed()
    }
    Process {
        id: writer
        onExited: (code, status) => {
            if (code === 0 && status === 0) {
                root.adjusted(root.requested / Number(maximum.text().trim()));
                if (root.pendingSteps)
                    Qt.callLater(() => root.change(0));
            } else {
                root.pendingSteps = 0;
                root.failed("Cannot change display brightness");
            }
        }
    }
}
