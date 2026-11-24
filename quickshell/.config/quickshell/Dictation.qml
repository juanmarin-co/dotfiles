import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property string status: ""
    property string stopCommand: ""
    property bool failed: false
    property var samples: []

    function toggle(command) {
        if (worker.running) {
            if (!root.stopCommand) {
                root.stopCommand = command;
                root.status = "Finishing…";
                worker.write(command);
            }
            return;
        }
        hideError.stop();
        root.failed = false;
        root.stopCommand = "";
        root.samples = [];
        root.status = "Starting…";
        worker.running = true;
    }

    IpcHandler {
        target: "dictation"

        function status(): string { return root.status; }
        function toggle(): void { root.toggle("stop\n"); }
        function toggleAndSubmit(): void { root.toggle("submit\n"); }
        function cancel(): void {
            if (worker.running) {
                root.stopCommand = "cancel\n";
                root.status = "";
                worker.write(root.stopCommand);
            }
        }
    }

    Process {
        id: worker
        command: ["node", Qt.resolvedUrl("dictation.mjs").toString().replace(/^file:\/\//, "")]
        stdinEnabled: true

        onStarted: {
            if (root.stopCommand) {
                write(root.stopCommand);
            }
        }

        stdout: SplitParser {
            onRead: line => {
                if (root.stopCommand === "cancel\n") {
                    return;
                }
                const event = JSON.parse(line);
                if (event.type === "waveform" && !root.stopCommand) {
                    root.status = "Recording";
                    root.samples = [...root.samples.slice(-47), event.range];
                } else if (event.type === "error") {
                    root.failed = true;
                    root.status = event.message;
                    console.warn("Dictation:", event.message);
                }
            }
        }

        onExited: (code, exitStatus) => {
            if (root.stopCommand === "cancel\n") {
                return;
            }
            if (code !== 0 || exitStatus !== 0) {
                if (!root.failed) {
                    root.status = "Dictation stopped unexpectedly";
                    console.warn("Dictation helper exited:", code, exitStatus);
                }
                hideError.restart();
            } else {
                root.status = "";
            }
        }
    }

    Timer {
        id: hideError
        interval: 4000
        onTriggered: root.status = ""
    }

    PanelWindow {
        screen: Quickshell.screens[0]
        anchors.top: true
        margins.top: BarStyle.height + Spacing.outer
        implicitWidth: 300
        implicitHeight: 48
        exclusiveZone: 0
        color: "transparent"
        visible: root.status !== ""
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dotfiles-dictation"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: "#0b0e14"
            border.color: "#273344"
            radius: 8

            BluetoothText {
                anchors.left: parent.left
                anchors.right: waveform.visible ? waveform.left : parent.right
                anchors.leftMargin: Spacing.outer
                anchors.rightMargin: Spacing.outer
                anchors.verticalCenter: parent.verticalCenter
                text: root.status
                textFormat: Text.PlainText
                font.weight: Font.Medium
                elide: Text.ElideNone
                wrapMode: Text.Wrap
            }

            Canvas {
                id: waveform
                anchors.right: parent.right
                anchors.rightMargin: Spacing.outer
                anchors.verticalCenter: parent.verticalCenter
                width: 144
                height: 26
                visible: root.status === "Recording"

                Connections {
                    target: root
                    function onSamplesChanged() { waveform.requestPaint(); }
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.fillStyle = "#273344";
                    ctx.fillRect(0, height / 2, width, 1);
                    ctx.fillStyle = "#e6b450";
                    const step = width / 48;
                    const y = height / 2;
                    for (let i = 0; i < root.samples.length; i++) {
                        const [low, high] = root.samples[i];
                        ctx.fillRect((48 - root.samples.length + i) * step,
                                     y - high * y, 2, Math.max(1, (high - low) * y));
                    }
                }
            }
        }
    }
}
