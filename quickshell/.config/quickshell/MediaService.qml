import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

Scope {
    id: root
    property var sink: Pipewire.defaultAudioSink
    property var players: Mpris.players.values
    property var lastPlayer: null
    property var displayPlayer: null
    property string mode: ""
    property string action: ""
    property string message: ""
    property real brightness: 0
    property alias backlightDirectory: backlight.directory
    property bool showing: false
    readonly property var audio: sink?.audio ?? null
    readonly property string icon: mode === "volume"
        ? (audio?.muted || !audio?.volume ? "volume-x" : "volume-2")
        : mode === "brightness" ? "sun"
        : action === "next" ? "skip-forward" : action === "previous" ? "skip-back"
        : displayPlayer?.isPlaying ? "play" : "pause"
    readonly property string label: message || (mode === "volume"
        ? (audio?.muted ? "Muted" : "Volume · " + Math.round((audio?.volume ?? 0) * 100) + "%")
        : mode === "brightness" ? "Brightness · " + Math.round(brightness * 100) + "%"
        : action === "next" ? "Next track" : action === "previous" ? "Previous track"
        : displayPlayer?.isPlaying ? "Playing" : "Paused")
    readonly property string detail: mode === "media" && !message && displayPlayer
        ? [displayPlayer.trackTitle || displayPlayer.identity, displayPlayer.trackArtist].filter(Boolean).join(" · ") : ""
    readonly property real level: message ? -1 : mode === "volume" ? (audio?.muted ? 0 : audio?.volume ?? 0)
        : mode === "brightness" ? brightness : -1

    function show(kind, notice = "") {
        mode = kind;
        message = notice;
        showing = true;
        dismiss.restart();
    }

    function volume(steps) {
        if (!sink?.ready || !audio) {
            show("volume", "No audio output");
            return;
        }
        audio.volume = Math.max(0, Math.min(1, audio.volume + steps / 100));
        show("volume");
    }

    function mute() {
        if (!sink?.ready || !audio) {
            show("volume", "No audio output");
            return;
        }
        audio.muted = !audio.muted;
        show("volume");
    }

    function media(command) {
        const player = players.find(p => p.isPlaying)
            || (players.includes(lastPlayer) ? lastPlayer : null) || players[0];
        action = command;
        displayPlayer = player || null;
        if (!player) {
            show("media", "No media player");
            return;
        }
        lastPlayer = player;
        if (command === "playPause" && player.canTogglePlaying)
            player.togglePlaying();
        else if (command === "next" && player.canGoNext)
            player.next();
        else if (command === "previous" && player.canGoPrevious)
            player.previous();
        else {
            show("media", "Control unavailable");
            return;
        }
        // Labels and track details follow the player's asynchronous MPRIS updates.
        show("media");
    }

    PwObjectTracker { objects: [root.sink] }
    BacklightService {
        id: backlight
        onAdjusted: level => { root.brightness = level; root.show("brightness"); }
        onFailed: message => root.show("brightness", message)
    }
    Timer {
        id: dismiss
        interval: 1500
        onTriggered: root.showing = false
    }
    IpcHandler {
        target: "media"
        function volumeUp(): void { root.volume(5); }
        function volumeDown(): void { root.volume(-5); }
        function mute(): void { root.mute(); }
        function playPause(): void { root.media("playPause"); }
        function next(): void { root.media("next"); }
        function previous(): void { root.media("previous"); }
        function brightnessUp(): void { backlight.change(5); }
        function brightnessDown(): void { backlight.change(-5); }
    }
}
