import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    QtObject {
        id: fakeAudio
        property real volume: 0.5
        property bool muted: false
    }
    QtObject {
        id: fakeSink
        property bool ready: true
        property var audio: fakeAudio
    }
    QtObject {
        id: player
        property bool isPlaying: true
        property bool canTogglePlaying: true
        property bool canGoNext: true
        property bool canGoPrevious: true
        property string identity: "Test player"
        property string trackTitle: "First track"
        property string trackArtist: "Test artist"
        property int toggles: 0
        property int nexts: 0
        property int previouses: 0
        function togglePlaying() { isPlaying = !isPlaying; toggles++; }
        function next() { nexts++; trackTitle = "Next track title"; }
        function previous() { previouses++; trackTitle = "Previous track title"; }
    }
    MediaService {
        id: controls
        sink: fakeSink
        players: [player]
        backlightDirectory: "file://" + Quickshell.env("BACKLIGHT_TEST_DIR")
    }
    Loader {
        id: osd
        Component.onCompleted: {
            if (Quickshell.env("QT_QPA_PLATFORM") === "wayland")
                setSource("MediaOsd.qml", { service: controls });
        }
    }
    IpcHandler {
        target: "test"
        function noPlayers(): void { controls.players = []; }
        function restorePlayers(): void { controls.players = [player]; }
        function noSink(): void { controls.sink = null; }
        function restoreSink(): void { controls.sink = fakeSink; }
        function disableNext(): void { player.canGoNext = false; }
        function snapshot(): string {
            return JSON.stringify({ showing: controls.showing, mode: controls.mode,
                icon: controls.icon, label: controls.label, detail: controls.detail, level: controls.level,
                volume: fakeAudio.volume, muted: fakeAudio.muted, playing: player.isPlaying,
                toggles: player.toggles, nexts: player.nexts, previouses: player.previouses,
                window: osd.item ? { visible: osd.item.visible, width: osd.item.width,
                    height: osd.item.height, focusable: osd.item.focusable } : null });
        }
    }
}
