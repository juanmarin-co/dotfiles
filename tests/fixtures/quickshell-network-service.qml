import Quickshell
import Quickshell.Io

ShellRoot {
    NetworkStatus { id: status; devices: [] }
    IpcHandler {
        target: "test"
        function setDevices(data: string): void { status.devices = JSON.parse(data).devices; }
        function snapshot(): string {
            return JSON.stringify({ known: status.vpnKnown, vpns: status.vpns,
                active: status.vpnActive, changing: status.vpnChanging, summary: status.vpnSummary,
                wired: status.wired.map(device => status.wiredDescription(device)),
                wiredConnected: status.wiredConnection !== null, ui: null });
        }
    }
}
