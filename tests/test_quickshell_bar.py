"""Check auto-hide state and native panel geometry without moving the real pointer."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get("WAYLAND_DISPLAY") and shutil.which("qs"), "Requires Wayland and Quickshell")
class QuickshellBarTests(unittest.TestCase):
    def test_autohide_panel(self):
        with tempfile.TemporaryDirectory(prefix="quickshell-bar-") as directory:
            directory = Path(directory)
            shutil.copytree(ROOT / "quickshell/.config/quickshell", directory, dirs_exist_ok=True)
            config = directory / "shell.qml"
            shutil.copy(ROOT / "tests/fixtures/quickshell-bar.qml", config)
            env = dict(os.environ, QS_NO_RELOAD_POPUP="1")
            with (directory / "quickshell.log").open("w+") as log:
                process = subprocess.Popen(["qs", "--path", str(config), "--no-color"], env=env,
                                           stdout=log, stderr=subprocess.STDOUT)

                def ipc(function, *args):
                    return subprocess.check_output(
                        ["qs", "--path", str(config), "ipc", "call", "test", function, *args],
                        env=env, text=True, stderr=subprocess.PIPE, timeout=2,
                    ).strip()

                def state():
                    return json.loads(ipc("snapshot"))

                def wait_for(predicate):
                    deadline = time.monotonic() + 3
                    while time.monotonic() < deadline:
                        try:
                            if predicate():
                                return
                        except (subprocess.CalledProcessError, json.JSONDecodeError):
                            pass
                        time.sleep(0.03)
                    log.seek(0)
                    self.fail("Bar state did not settle.\n" + log.read())

                try:
                    wait_for(lambda: state()["height"] == 2)
                    self.assertFalse(state()["shown"])
                    self.assertTrue(state()["visible"], "The invisible edge trigger must remain mapped")
                    self.assertEqual(state()["color"], "#00000000")
                    self.assertEqual(state()["exclusiveZone"], 0)
                    self.assertEqual(state()["compact"], [28, 26, 16])
                    ipc("hover", "true")
                    wait_for(lambda: state()["height"] == 44)
                    self.assertTrue(state()["shown"])
                    self.assertEqual(state()["button"], [36, 36, 18, 13])
                    self.assertEqual(state()["horizontalPadding"], [8, 8])
                    self.assertEqual(state()["exclusiveZone"], 0)
                    ipc("hover", "false")
                    time.sleep(0.15)
                    self.assertTrue(state()["shown"], "The bar hid before its grace period")
                    ipc("hover", "true")
                    time.sleep(0.7)
                    self.assertTrue(state()["shown"], "Returning to the bar did not cancel hiding")
                    ipc("hold", "true")
                    ipc("hover", "false")
                    time.sleep(0.7)
                    self.assertTrue(state()["shown"], "An open menu must keep the bar visible")
                    ipc("hold", "false")
                    wait_for(lambda: state()["height"] == 2)
                    ipc("hold", "true")
                    wait_for(lambda: state()["height"] == 44)
                    ipc("hold", "false")
                    wait_for(lambda: state()["height"] == 2)
                    ipc("hover", "true")
                    time.sleep(0.03)
                    ipc("hover", "false")
                    time.sleep(0.2)
                    self.assertFalse(state()["shown"], "A brief edge crossing should not reveal the bar")
                finally:
                    process.terminate()
                    process.wait(timeout=3)
                log.seek(0)
                output = log.read()
                self.assertFalse(any(error in output for error in
                                     (" ERROR", "ReferenceError", "TypeError", "Unable to assign", "Binding loop")), output)


if __name__ == "__main__":
    unittest.main()
