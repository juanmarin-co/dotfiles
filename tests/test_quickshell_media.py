"""Media keys and OSD tests; fake audio/player/backlight, never change real hardware."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qs"), "Requires Quickshell")
class QuickshellMediaTests(unittest.TestCase):
    def test_keys_and_indicators(self):
        with tempfile.TemporaryDirectory(prefix="quickshell-media-") as temporary:
            directory = Path(temporary)
            shutil.copytree(ROOT / "quickshell/.config/quickshell", directory, dirs_exist_ok=True)
            config = directory / "shell.qml"
            shutil.copy(ROOT / "tests/fixtures/quickshell-media.qml", config)
            backlights = directory / "backlights"
            device = backlights / "test_backlight"
            device.mkdir(parents=True)
            (device / "max_brightness").write_text("100\n")
            brightness = device / "brightness"
            brightness.write_text("50\n")
            binaries = directory / "bin"
            binaries.mkdir()
            stub = binaries / "busctl"
            stub.write_text(f"#!{sys.executable}\n" + '''import json, os, sys, time
from pathlib import Path
root = Path(os.environ["BACKLIGHT_TEST_DIR"]).parent
args = sys.argv[1:]
with (root / "commands").open("a") as log:
    log.write(json.dumps(args) + "\\n")
assert args[:-1] == ["--system", "--allow-interactive-authorization=no", "call",
    "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
    "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", "test_backlight"]
time.sleep(0.1)
if (root / "fail").exists():
    sys.exit(1)
(root / "backlights/test_backlight/brightness").write_text(args[-1] + "\\n")
with (root / "completed").open("a") as log:
    log.write(args[-1] + "\\n")
''')
            stub.chmod(0o755)
            native = bool(os.environ.get("WAYLAND_DISPLAY"))
            env = dict(os.environ, QT_QPA_PLATFORM="wayland" if native else "offscreen",
                       QS_NO_RELOAD_POPUP="1", BACKLIGHT_TEST_DIR=str(backlights),
                       PATH=str(binaries) + os.pathsep + os.environ["PATH"])
            with (directory / "quickshell.log").open("w+") as log:
                process = subprocess.Popen(["qs", "--path", str(config), "--no-color"],
                                           env=env, stdout=log, stderr=subprocess.STDOUT)

                def ipc(target, function):
                    return subprocess.check_output(
                        ["qs", "--path", str(config), "ipc", "--any-display", "call", target, function],
                        env=env, text=True, stderr=subprocess.PIPE, timeout=2).strip()

                def state():
                    return json.loads(ipc("test", "snapshot"))

                def key(name):
                    ipc("media", name)

                def wait_for(predicate, timeout=4):
                    deadline = time.monotonic() + timeout
                    while time.monotonic() < deadline:
                        try:
                            if predicate():
                                return
                        except (subprocess.CalledProcessError, json.JSONDecodeError):
                            pass
                        time.sleep(0.04)
                    log.seek(0)
                    self.fail("Media state did not settle.\n" + log.read())

                try:
                    wait_for(lambda: state())
                    self.assertFalse(state()["showing"])
                    key("volumeUp")
                    wait_for(lambda: state()["label"] == "Volume · 55%")
                    self.assertAlmostEqual(state()["volume"], 0.55)
                    self.assertEqual(state()["icon"], "volume-2")
                    self.assertAlmostEqual(state()["level"], 0.55)
                    if native:
                        wait_for(lambda: state()["window"]["visible"])
                        self.assertEqual(state()["window"]["width"], 340)
                        self.assertGreater(state()["window"]["height"], 30)
                        self.assertFalse(state()["window"]["focusable"])
                    key("volumeDown")
                    self.assertAlmostEqual(state()["volume"], 0.5)
                    key("mute")
                    self.assertTrue(state()["muted"])
                    self.assertEqual(state()["label"], "Muted")
                    self.assertEqual(state()["icon"], "volume-x")
                    self.assertEqual(state()["level"], 0)
                    key("mute")
                    for _ in range(25):
                        key("volumeUp")
                    self.assertEqual(state()["volume"], 1)
                    for _ in range(25):
                        key("volumeDown")
                    self.assertEqual(state()["volume"], 0)

                    key("playPause")
                    self.assertFalse(state()["playing"])
                    self.assertEqual(state()["label"], "Paused")
                    self.assertEqual(state()["icon"], "pause")
                    self.assertEqual(state()["detail"], "First track · Test artist")
                    self.assertEqual(state()["level"], -1)
                    key("playPause")
                    self.assertTrue(state()["playing"])
                    self.assertEqual(state()["label"], "Playing")
                    self.assertEqual(state()["icon"], "play")
                    self.assertEqual(state()["toggles"], 2)
                    key("next")
                    self.assertEqual(state()["icon"], "skip-forward")
                    self.assertEqual(state()["nexts"], 1)
                    self.assertIn("Next track title", state()["detail"])
                    key("previous")
                    self.assertEqual(state()["icon"], "skip-back")
                    self.assertEqual(state()["previouses"], 1)
                    self.assertIn("Previous track title", state()["detail"])
                    ipc("test", "disableNext")
                    key("next")
                    self.assertEqual(state()["label"], "Control unavailable")
                    self.assertEqual(state()["nexts"], 1)
                    ipc("test", "noPlayers")
                    key("playPause")
                    self.assertEqual(state()["label"], "No media player")
                    ipc("test", "noSink")
                    key("volumeUp")
                    self.assertEqual(state()["label"], "No audio output")
                    ipc("test", "restoreSink")

                    key("brightnessUp")
                    wait_for(lambda: state()["label"] == "Brightness · 55%")
                    self.assertEqual(brightness.read_text().strip(), "55")
                    self.assertEqual(state()["icon"], "sun")
                    key("brightnessDown")
                    wait_for(lambda: state()["label"] == "Brightness · 50%")
                    # Re-read actual brightness rather than retaining stale cached values.
                    brightness.write_text("95\n")
                    key("brightnessUp")
                    wait_for(lambda: state()["label"] == "Brightness · 100%")
                    completed = (directory / "completed").read_text()
                    key("brightnessUp")
                    wait_for(lambda: (directory / "completed").read_text() != completed)
                    self.assertEqual(brightness.read_text().strip(), "100")
                    brightness.write_text("2\n")
                    key("brightnessDown")
                    wait_for(lambda: state()["label"] == "Brightness · 1%")
                    brightness.write_text("50\n")
                    for _ in range(5):
                        key("brightnessUp")
                    wait_for(lambda: state()["label"] == "Brightness · 75%")
                    self.assertEqual(brightness.read_text().strip(), "75")
                    (directory / "fail").touch()
                    key("brightnessDown")
                    wait_for(lambda: state()["label"] == "Cannot change display brightness")
                    self.assertEqual(state()["level"], -1)
                    self.assertEqual(brightness.read_text().strip(), "75")

                    # Repeated keys extend one overlay's lifetime, not a queue of toasts.
                    key("volumeUp")
                    time.sleep(0.9)
                    key("volumeDown")
                    time.sleep(0.9)
                    self.assertTrue(state()["showing"])
                    wait_for(lambda: not state()["showing"])
                    if native:
                        wait_for(lambda: not state()["window"]["visible"])
                finally:
                    process.terminate()
                    process.wait(timeout=3)
                log.seek(0)
                output = log.read()
                self.assertFalse(any(error in output for error in
                    (" ERROR", "ReferenceError", "TypeError", "Unable to assign", "Binding loop")), output)


if __name__ == "__main__":
    unittest.main()
