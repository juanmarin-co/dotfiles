import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool active: false
    property var cards: ({})
    property string error: ""
    readonly property bool busy: change.running

    function refresh() {
        if (!snapshot.running && !change.running)
            snapshot.running = true;
    }

    function selectProfile(card, index) {
        if (busy)
            return;
        error = "";
        change.command = ["wpctl", "set-profile", String(card.id), String(index)];
        change.running = true;
    }

    onActiveChanged: {
        if (active)
            refresh();
    }

    Timer {
        interval: 3000
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: snapshot
        command: ["pw-dump"]
        stdout: StdioCollector { id: output }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.cards = {};
                root.error = "Could not read audio profiles.";
                return;
            }
            try {
                const cards = {};
                for (const object of JSON.parse(output.text)) {
                    const info = object.info;
                    const address = info?.props?.["api.bluez5.address"];
                    if (object.type !== "PipeWire:Interface:Device" || !address)
                        continue;
                    const params = info.params;
                    cards[address] = {
                        id: object.id,
                        current: params.Profile?.[0]?.index ?? -1,
                        profiles: (params.EnumProfile || [])
                            .filter(p => p.name.startsWith("a2dp-sink") && p.available !== "no")
                            .map(p => ({
                                index: p.index,
                                label: p.description.match(/codec ([^)]+)/)?.[1] || p.name
                            }))
                    };
                }
                root.cards = cards;
            } catch (error) {
                root.cards = {};
                root.error = "Could not parse audio profiles.";
            }
        }
    }

    Process {
        id: change
        stderr: StdioCollector { id: failure }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.error = failure.text.trim() || "Could not switch codec.";
            root.refresh();
        }
    }
}
