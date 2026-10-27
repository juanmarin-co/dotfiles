import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property string socketPath: "/run/rz09-control/status.sock"
    property var snapshot: null
    readonly property bool connected: feed.connected
    readonly property bool available: connected && snapshot !== null

    function nullableNumber(value) {
        return value === null || (typeof value === "number" && Number.isFinite(value));
    }

    function accept(line) {
        try {
            const sample = JSON.parse(line);
            const gpu = sample?.gpu;
            const control = sample?.control;
            if (!gpu || !control || typeof sample.timestamp !== "number" || !Number.isFinite(sample.timestamp)
                || !(sample.ac_online === null || typeof sample.ac_online === "boolean")
                || !nullableNumber(sample.cpu_temp_c)
                || !["temperature_c", "utilization_percent", "memory_used_mb", "memory_total_mb"]
                    .every(key => nullableNumber(gpu[key]))
                || typeof gpu.power_state !== "string" || typeof gpu.runtime_status !== "string"
                || typeof gpu.in_use !== "boolean" || !Array.isArray(gpu.clients)
                || !gpu.clients.every(client => typeof client === "string")
                || !(gpu.error === null || typeof gpu.error === "string")
                || typeof control.healthy !== "boolean" || typeof control.high_temperature_cooling !== "boolean"
                || typeof control.performance_mode !== "string" || typeof control.fan_control !== "string"
                || !nullableNumber(control.fan_target_rpm)
                || (control.control_temp_c !== undefined && !nullableNumber(control.control_temp_c))
                || !(control.error === null || typeof control.error === "string")
                || !(sample.cpu_turbo_allowed === null || typeof sample.cpu_turbo_allowed === "boolean"))
                return;
            const age = Date.now() - sample.timestamp * 1000;
            if (age < -5000 || age >= 5000)
                return;
            root.snapshot = sample;
            expiry.interval = Math.max(1, 5000 - Math.max(0, age));
            expiry.restart();
        } catch (error) {
            // Ignore malformed frames without extending the last valid sample's lifetime.
        }
    }

    Socket {
        id: feed
        path: root.socketPath
        connected: true
        parser: SplitParser {
            onRead: line => root.accept(line)
        }
        onConnectedChanged: {
            if (!connected) {
                root.snapshot = null;
                expiry.stop();
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: !feed.connected
        onTriggered: feed.connected = true
    }

    Timer {
        id: expiry
        onTriggered: root.snapshot = null
    }
}
