"""GPU mode widget states driven by a fake daemon, never real hardware."""

import copy
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


def sample(mode, applied, present):
    return {
        "timestamp": time.time(), "cpu_temp_c": 50.0, "ac_online": True,
        "gpu": {"card_present": present,
                "power_state": "D0" if present else "unknown",
                "runtime_status": "active" if present else "unknown", "in_use": False,
                "mode": mode, "mode_applied": applied,
                "temperature_c": None, "utilization_percent": None, "memory_used_mb": None,
                "memory_total_mb": None, "clients": [], "error": None},
        "control": {"performance_mode": "Gaming" if present else "Balanced",
                    "fan_control": "Automatic", "fan_target_rpm": None,
                    "high_temperature_cooling": False, "fan_reason": "firmware", "control_temp_c": 50,
                    "healthy": True, "error": None, "collisions": 0},
        "cpu_turbo_allowed": not present,
        "cpu_turbo_reason": "dgpu_active" if present else "dgpu_absent",
    }


@unittest.skipUnless(shutil.which("qs"), "Requires Quickshell")
class QuickshellGpuModeTests(unittest.TestCase):
    def test_gpu_mode_states_and_widget(self):
        with tempfile.TemporaryDirectory(prefix="quickshell-gpu-mode-") as directory:
            directory = Path(directory)
            shutil.copytree(ROOT / "quickshell/.config/quickshell", directory, dirs_exist_ok=True)
            config = directory / "shell.qml"
            native = bool(os.environ.get("WAYLAND_DISPLAY"))
            fixture = "quickshell-gpu-mode.qml" if native else "quickshell-gpu-mode-service.qml"
            shutil.copy(ROOT / "tests/fixtures" / fixture, config)
            path = directory / "status.sock"
            env = dict(os.environ, QT_QPA_PLATFORM="wayland" if native else "offscreen", QS_NO_RELOAD_POPUP="1",
                       RZ09_TEST_SOCKET=str(path))
            sockets = []
            with (directory / "quickshell.log").open("w+") as log:
                process = subprocess.Popen(["qs", "--path", str(config), "--no-color"], env=env,
                                           stdout=log, stderr=subprocess.STDOUT)

                def ipc(function):
                    return subprocess.check_output(
                        ["qs", "--path", str(config), "ipc", "--any-display", "call", "test", function],
                        env=env, text=True, stderr=subprocess.PIPE, timeout=2,
                    ).strip()

                def state():
                    return json.loads(ipc("snapshot"))

                def wait_for(predicate, timeout=4):
                    deadline = time.monotonic() + timeout
                    while time.monotonic() < deadline:
                        try:
                            if predicate():
                                return
                        except (subprocess.CalledProcessError, json.JSONDecodeError):
                            pass
                        time.sleep(0.05)
                    log.seek(0)
                    self.fail("GPU mode state did not settle.\n" + log.read())

                def view_contains(text):
                    return text in state()["ui"]["texts"]

                def send(data, age=0):
                    data = copy.deepcopy(data)
                    data["timestamp"] = time.time() - age
                    connection.sendall((json.dumps(data) + "\n").encode())
                    return data

                try:
                    wait_for(lambda: state())
                    self.assertFalse(state()["available"])
                    self.assertFalse(state()["connected"])
                    if native:
                        ipc("openPopup")
                        wait_for(lambda: state()["ui"]["height"] > 50)
                        self.assertEqual(state()["ui"]["label"], "—")
                        self.assertEqual(state()["ui"]["status"], "Controller unavailable")

                    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    sockets.append(server)
                    server.bind(str(path))
                    server.listen()
                    server.settimeout(4)
                    connection, _ = server.accept()
                    sockets.append(connection)
                    connection.settimeout(0.1)
                    wait_for(lambda: state()["connected"])

                    integrated = sample("integrated", True, False)
                    send(integrated)
                    wait_for(lambda: state()["available"])
                    self.assertEqual(state()["sample"]["gpu"]["mode"], "integrated")
                    self.assertTrue(state()["sample"]["gpu"]["mode_applied"])
                    self.assertFalse(state()["sample"]["gpu"]["card_present"])
                    if native:
                        wait_for(lambda: state()["ui"]["label"] == "iGPU")
                        self.assertEqual(state()["ui"]["status"], "dGPU removed from the PCI bus")
                        self.assertTrue(view_contains("GPU Mode"))
                        self.assertTrue(view_contains("Removed"))
                        self.assertTrue(view_contains("Not required"))
                        self.assertFalse(view_contains("Reboot now"))
                        self.assertTrue(view_contains("Integrated"))
                        self.assertTrue(view_contains("Hybrid"))
                        ipc("closePopup")
                        wait_for(lambda: state()["ui"]["color"] == "#565b66")  # dimmed while integrated
                        ipc("openPopup")

                    pending = sample("integrated", False, True)
                    send(pending)
                    wait_for(lambda: state()["sample"]["gpu"]["mode_applied"] is False)
                    if native:
                        wait_for(lambda: state()["ui"]["color"] == "#ffb454")
                        self.assertEqual(state()["ui"]["label"], "iGPU")
                        self.assertEqual(state()["ui"]["status"], "Integrated selected — reboot to apply")
                        self.assertTrue(view_contains("Present"))
                        self.assertTrue(view_contains("Pending"))
                        self.assertTrue(view_contains("Reboot now"))

                    hybrid = sample("hybrid", True, True)
                    send(hybrid)
                    wait_for(lambda: state()["sample"]["gpu"]["mode"] == "hybrid")
                    if native:
                        wait_for(lambda: state()["ui"]["label"] == "dGPU")
                        self.assertEqual(state()["ui"]["status"], "dGPU present and available")
                        self.assertTrue(view_contains("Not required"))
                        self.assertFalse(view_contains("Reboot now"))
                        ipc("closePopup")
                        wait_for(lambda: state()["ui"]["color"] == "#bfbdb6")  # normal while hybrid
                        ipc("openPopup")

                    # Selecting a mode asks for confirmation; tests never execute the switch.
                    if native:
                        ipc("selectIntegrated")
                        wait_for(lambda: state()["ui"]["pending"] == "integrated")
                        self.assertTrue(view_contains("Integrated at next reboot?"))
                        self.assertTrue(view_contains("Takes effect after the next reboot."))
                        self.assertTrue(view_contains("Cancel"))
                        self.assertTrue(view_contains("Switch"))

                    # A rejected frame must not refresh the watchdog: let the last sample expire first.
                    time.sleep(4)
                    # Frames missing the GPU mode fields are rejected, not half-accepted.
                    malformed = sample("hybrid", True, True)
                    del malformed["gpu"]["mode"]
                    send(malformed)
                    wait_for(lambda: not state()["available"], timeout=2)
                    self.assertTrue(state()["connected"])
                    self.assertIsNone(state()["sample"])

                    send(hybrid)
                    wait_for(lambda: state()["available"])
                    send(sample("integrated", True, False))
                    wait_for(lambda: state()["sample"]["gpu"]["mode"] == "integrated")

                    with self.assertRaises(TimeoutError):
                        connection.recv(1)  # The UI must never send control commands.
                finally:
                    process.terminate()
                    process.wait(timeout=3)
                    for connection in sockets:
                        connection.close()
                log.seek(0)
                output = log.read()
                self.assertFalse(any(error in output for error in
                                     (" ERROR", "ReferenceError", "TypeError", "Unable to assign", "Binding loop")), output)


if __name__ == "__main__":
    unittest.main()
