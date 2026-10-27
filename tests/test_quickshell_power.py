"""Read laptop power APIs and test session controls with harmless command stubs."""

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


def check_power_widgets():
    with tempfile.TemporaryDirectory(prefix="quickshell-power-") as directory:
        directory = Path(directory)
        shutil.copytree(ROOT / "quickshell/.config/quickshell", directory, dirs_exist_ok=True)
        config = directory / "shell.qml"
        shutil.copy(ROOT / "tests/fixtures/quickshell-power.qml", config)
        commands_log = directory / "commands.log"
        binaries = directory / "bin"
        binaries.mkdir()
        for name in ("systemctl", "swaylock", "niri"):
            stub = binaries / name
            stub.write_text('#!/bin/sh\nprintf "%s\\n" "${0##*/} $*" >> "$SESSION_TEST_LOG"\n')
            stub.chmod(0o755)
        env = dict(os.environ, QT_QPA_PLATFORM="wayland", QS_NO_RELOAD_POPUP="1",
                   PATH=str(binaries) + os.pathsep + os.environ["PATH"], SESSION_TEST_LOG=str(commands_log))
        with (directory / "quickshell.log").open("w+") as log:
            process = subprocess.Popen(
                ["qs", "--path", str(config), "--no-color"],
                env=env, stdout=log, stderr=subprocess.STDOUT,
            )

            def ipc(function, *args):
                return subprocess.check_output(
                    ["qs", "--path", str(config), "ipc", "call", "test", function, *args],
                    env=env, text=True, stderr=subprocess.PIPE, timeout=2,
                ).strip()

            def snapshot():
                return json.loads(ipc("snapshot"))

            def wait_for(predicate):
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    try:
                        if predicate():
                            return
                    except (subprocess.CalledProcessError, json.JSONDecodeError):
                        pass
                    time.sleep(0.05)
                log.seek(0)
                raise AssertionError("Power widget state did not settle.\n" + log.read())

            try:
                wait_for(lambda: snapshot()["batteryReady"] and len(snapshot()["profiles"]) == 3)
                initial = snapshot()
                assert 0 <= initial["charge"] <= 100, initial
                assert initial["energy"]["label"] == str(initial["charge"]) + "%", initial
                assert initial["energy"]["barWidth"] > 28, initial
                assert initial["energy"]["tooltip"].startswith(str(initial["charge"]) + "% · "), initial
                assert initial["profile"] in initial["profiles"], initial
                assert not initial["keepAwake"], initial
                assert json.loads(ipc("chargeHints")) == [
                    "Below 40% · Plug in soon", "Below 40% · External power connected",
                    "", "", "Above 80% · Consider unplugging", "",
                ]
                assert json.loads(ipc("iconColors")) == ["#bfbdb6", "#e6b450", "#ffb454", "#f26d78"]
                commands = json.loads(ipc("commands"))
                expected = {
                    "lock": ["swaylock", "-f", "-c", "000000"],
                    "suspend": ["systemctl", "suspend"],
                    "logout": ["niri", "msg", "action", "quit", "--skip-confirmation"],
                    "reboot": ["systemctl", "reboot"],
                    "shutdown": ["systemctl", "poweroff"],
                }
                assert commands == expected, commands
                ipc("activateEnergy")
                wait_for(lambda: snapshot()["energy"]["height"] > 32)
                assert snapshot()["energy"]["width"] == 420
                for key in ("logout", "reboot", "shutdown"):
                    ipc("activateSession")
                    wait_for(lambda: snapshot()["session"]["height"] > 32)
                    ipc("requestAction", key)
                    state = snapshot()["session"]
                    assert state["pending"] == key and not state["busy"], state
                    assert not commands_log.exists(), "Action executed before confirmation"
                    ipc("cancelAction")
                    assert snapshot()["session"]["pending"] == ""
                    ipc("requestAction", key)
                    ipc("closeSession")
                    assert snapshot()["session"]["pending"] == ""
                # Every executable below resolves to our temporary harmless stubs.
                for key in expected:
                    ipc("activateSession")
                    ipc("requestAction", key)
                    if key in ("logout", "reboot", "shutdown"):
                        ipc("confirmAction")
                    wait_for(lambda: not snapshot()["session"]["open"])
                    assert snapshot()["session"]["error"] == ""
                lines = commands_log.read_text().splitlines()
                assert lines == [" ".join(command) for command in expected.values()], lines
                final = snapshot()
                assert final["profile"] == initial["profile"], "Test changed the actual power profile"
                assert not final["keepAwake"], "Test enabled the actual idle inhibitor"
            finally:
                process.terminate()
                process.wait(timeout=3)
            log.seek(0)
            output = log.read()
            assert not any(error in output for error in
                           (" ERROR", "ReferenceError", "Unable to assign", "Binding loop")), output


@unittest.skipUnless(os.environ.get("WAYLAND_DISPLAY") and shutil.which("qs"),
                     "Requires this laptop's Wayland session and Quickshell")
class QuickshellPowerTests(unittest.TestCase):
    def test_power_widgets_with_stubbed_commands(self):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "--session"],
            capture_output=True, text=True, timeout=25,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    if "--session" in sys.argv:
        check_power_widgets()
    else:
        unittest.main()
