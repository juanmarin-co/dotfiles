import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Scope {
    id: root
    property var devices: Networking.devices.values
    readonly property var wifiAdapter: devices.find(device => device.type === DeviceType.Wifi) || null
    readonly property var wired: devices.filter(device => device.type === DeviceType.Wired)
        .sort((a, b) => Number(b.connected) - Number(a.connected)
            || Number(b.hasLink) - Number(a.hasLink) || a.name.localeCompare(b.name))
    readonly property var wiredConnection: wired.find(device => device.nmManaged && device.connected) || null
    property var vpns: []
    property bool vpnKnown: false
    readonly property bool vpnActive: vpns.some(vpn => vpn.state === "activated")
    readonly property bool vpnChanging: vpns.some(vpn => vpn.state !== "activated")
    readonly property string vpnSummary: !vpnKnown ? "VPN status unavailable"
        : vpns.length ? vpns.map(vpn => vpn.name + " · " + vpnState(vpn.state)).join("\n")
        : "No active NetworkManager VPN"

    function vpnState(state) {
        switch (state) {
        case "activated": return "Active";
        case "activating": return "Connecting";
        case "deactivating": return "Disconnecting";
        case "deactivated": return "Inactive";
        default: return "Unknown";
        }
    }

    function wiredState(device) {
        if (!device.nmManaged)
            return "Unmanaged";
        if (!device.hasLink)
            return "Cable disconnected";
        return ConnectionState.toString(device.state);
    }

    function wiredDescription(device) {
        return device.name + " · " + wiredState(device)
            + (device.hasLink && device.linkSpeed > 0
                ? " · " + (device.linkSpeed >= 1000 ? device.linkSpeed / 1000 + " Gbit/s" : device.linkSpeed + " Mbit/s") : "");
    }

    function parseVpns(text) {
        const result = [];
        for (const line of text.trim().split("\n")) {
            if (!line)
                continue;
            const fields = line.split(":");
            const uuid = fields.shift();
            const type = fields.shift();
            if (type !== "vpn" && type !== "wireguard")
                continue;
            if (fields.length < 2)
                throw new Error("Incomplete VPN status");
            const state = fields.pop();
            // UUID/type/state cannot contain colons; profile names can, and nmcli escapes them.
            const name = fields.join(":").replace(/\\([\\:])/g, "$1");
            result.push({ uuid: uuid, type: type, name: name || "Unnamed VPN", state: state });
        }
        return result.sort((a, b) => Number(b.state === "activated") - Number(a.state === "activated")
            || a.name.localeCompare(b.name));
    }

    Process {
        id: monitor
        command: ["nmcli", "--colors", "no", "monitor"]
        environment: ({ LC_ALL: "C" })
        running: true
        onStarted: refresh.restart()
        stdout: SplitParser { onRead: refresh.restart() }
        onExited: {
            root.vpnKnown = false;
            root.vpns = [];
            refresh.stop();
            query.running = false;
            retry.restart();
        }
    }

    Process {
        id: query
        command: ["nmcli", "--terse", "--colors", "no", "--fields", "UUID,TYPE,NAME,STATE", "connection", "show", "--active"]
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { id: output }
        onExited: exitCode => {
            if (!monitor.running)
                return;
            try {
                if (exitCode !== 0)
                    throw new Error("NetworkManager unavailable");
                root.vpns = root.parseVpns(output.text);
                root.vpnKnown = true;
            } catch (error) {
                root.vpns = [];
                root.vpnKnown = false;
            }
        }
    }

    Timer {
        id: refresh
        interval: 150
        onTriggered: {
            if (query.running)
                restart();
            else
                query.running = true;
        }
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: monitor.running = true
    }
}
