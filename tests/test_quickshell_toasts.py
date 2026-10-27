"""Check native toast window geometry on Wayland; never capture screenshots."""

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


def check_toast_window():
    with tempfile.TemporaryDirectory(prefix="quickshell-toasts-") as directory:
        directory = Path(directory)
        for name in ("NotificationToasts.qml", "NotificationCard.qml", "BluetoothButton.qml",
                     "BluetoothText.qml", "Spacing.qml"):
            shutil.copy(ROOT / "quickshell/.config/quickshell" / name, directory)
        config = directory / "shell.qml"
        shutil.copy(ROOT / "tests/fixtures/quickshell-toasts.qml", config)
        env = dict(os.environ, QT_QPA_PLATFORM="wayland", QS_NO_RELOAD_POPUP="1")
        with (directory / "quickshell.log").open("w+") as log:
            process = subprocess.Popen(
                ["qs", "--path", str(config), "--no-color"],
                env=env, stdout=log, stderr=subprocess.STDOUT,
            )

            def ipc(function):
                return subprocess.check_output(
                    ["qs", "--path", str(config), "ipc", "call", "test", function],
                    env=env, text=True, stderr=subprocess.PIPE, timeout=2,
                ).strip()

            def snapshot():
                return json.loads(ipc("snapshot"))

            def wait_for(predicate):
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    try:
                        if predicate():
                            return
                    except (subprocess.CalledProcessError, json.JSONDecodeError):
                        pass
                    time.sleep(0.05)
                log.seek(0)
                raise AssertionError("Toast window did not reach the expected geometry: "
                                     + repr(snapshot()) + "\n" + log.read())

            try:
                wait_for(lambda: snapshot())
                assert not snapshot()["visible"]
                ipc("displayToast")
                wait_for(lambda: snapshot()["visible"] and snapshot()["height"] > 32)
                state = snapshot()
                assert state["width"] == 420, state
                assert not state["focusable"], state
                ipc("addAction")
                wait_for(lambda: snapshot()["height"] > state["height"])
                ipc("hideToasts")
                wait_for(lambda: not snapshot()["visible"])
                ipc("displayToast")
                wait_for(lambda: snapshot()["visible"] and snapshot()["height"] > 32)
            finally:
                process.terminate()
                process.wait(timeout=3)
            log.seek(0)
            output = log.read()
            assert not any(error in output for error in
                           (" ERROR", "ReferenceError", "Unable to assign", "Binding loop")), output


@unittest.skipUnless(os.environ.get("WAYLAND_DISPLAY") and shutil.which("qs"),
                     "Requires a Wayland session and Quickshell")
class QuickshellToastTests(unittest.TestCase):
    def test_native_toast_window(self):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "--session"],
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    if "--session" in sys.argv:
        check_toast_window()
    else:
        unittest.main()
