import Quickshell
import Quickshell.Io

ShellRoot {
    Rz09Service {
        id: monitor
        socketPath: Quickshell.env("RZ09_TEST_SOCKET")
    }
    IpcHandler {
        target: "test"
        function snapshot(): string {
            return JSON.stringify({ connected: monitor.connected, available: monitor.available,
                sample: monitor.snapshot, ui: null });
        }
    }
}
