"""Read-only cooling integration using a private fake daemon, never real hardware."""

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


def sample():
    return {
        "timestamp": time.time(), "cpu_temp_c": 50.0, "ac_online": False,
        "gpu": {"power_state": "D3cold", "runtime_status": "suspended", "in_use": False,
                "temperature_c": None, "utilization_percent": None, "memory_used_mb": None,
                "memory_total_mb": None, "clients": [], "error": None},
        "control": {"performance_mode": "Balanced", "fan_control": "Automatic", "fan_target_rpm": None,
                    "high_temperature_cooling": False, "fan_reason": "firmware", "control_temp_c": 50,
                    "healthy": True, "error": None, "collisions": 0},
        "cpu_turbo_allowed": False, "cpu_turbo_reason": "on_battery",
    }


@unittest.skipUnless(shutil.which("qs"), "Requires Quickshell")
class QuickshellCoolingTests(unittest.TestCase):
    def test_socket_stream_and_cooling_widget(self):
        with tempfile.TemporaryDirectory(prefix="quickshell-cooling-") as directory:
            directory = Path(directory)
            shutil.copytree(ROOT / "quickshell/.config/quickshell", directory, dirs_exist_ok=True)
            config = directory / "shell.qml"
            native = bool(os.environ.get("WAYLAND_DISPLAY"))
            fixture = "quickshell-cooling.qml" if native else "quickshell-cooling-service.qml"
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
                    self.fail("Cooling state did not settle.\n" + log.read())

                def listen():
                    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    sockets.append(server)
                    server.bind(str(path))
                    server.listen()
                    server.settimeout(4)
                    return server

                def accept(server):
                    connection, _ = server.accept()
                    sockets.append(connection)
                    connection.settimeout(0.1)
                    wait_for(lambda: state()["connected"])
                    return connection

                def send(data, age=0):
                    data = copy.deepcopy(data)
                    data["timestamp"] = time.time() - age
                    connection.sendall((json.dumps(data) + "\n").encode())
                    return data

                def view_contains(text):
                    return text in state()["ui"]["texts"]

                try:
                    wait_for(lambda: state())
                    self.assertFalse(state()["available"])
                    self.assertFalse(state()["connected"])
                    if native:
                        ipc("openPopup")
                        wait_for(lambda: state()["ui"]["height"] > 50)
                        self.assertEqual(state()["ui"]["width"], 420)
                        self.assertEqual(state()["ui"]["status"], "Controller unavailable")

                    # Start late: the client must retry without restarting Quickshell.
                    server = listen()
                    connection = accept(server)
                    data = sample()
                    packet = json.dumps(data).encode()
                    midpoint = len(packet) // 2
                    connection.sendall(packet[:midpoint])
                    time.sleep(0.1)
                    self.assertFalse(state()["available"], "Accepted an incomplete JSON frame")
                    connection.sendall(packet[midpoint:] + b"\n")
                    wait_for(lambda: state()["available"])
                    self.assertEqual(state()["sample"], data)
                    if native:
                        wait_for(lambda: view_contains("Sleeping"))
                        view = state()["ui"]
                        self.assertEqual(view["label"], "50°")
                        self.assertGreater(view["barWidth"], 28)
                        self.assertEqual(view["color"], "#e6b450")
                        self.assertNotIn("Utilization", view["texts"])
                        self.assertNotIn("VRAM", view["texts"])
                        self.assertNotIn("Fan target", view["texts"])
                        self.assertNotIn("Controller healthy", view["texts"])
                        self.assertEqual(view["status"], "")
                        self.assertTrue(view_contains("Firmware automatic"))
                        self.assertTrue(view_contains("Battery"))
                        self.assertTrue(view_contains("Disabled on battery power."))
                        self.assertLess(view["height"], 700)

                    # Multiple frames per read; zero utilization and VRAM are valid values.
                    active = sample()
                    active["cpu_temp_c"] = 55
                    active["control"].update(fan_reason="warming_up", control_temp_c=65)
                    active["gpu"].update(power_state="D0", runtime_status="active", in_use=True,
                                         temperature_c=65, utilization_percent=0, memory_used_mb=0,
                                         memory_total_mb=6144, clients=["mock-game"])
                    connection.sendall(b"not JSON\n" + (json.dumps(active) + "\n").encode())
                    wait_for(lambda: state()["sample"]["cpu_temp_c"] == 55)
                    if native:
                        wait_for(lambda: view_contains("0 / 6144 MB"))
                        self.assertTrue(view_contains("0%"))
                        self.assertTrue(view_contains("mock-game"))

                    hot = copy.deepcopy(active)
                    hot["cpu_temp_c"] = 79
                    hot["ac_online"] = True
                    hot["control"].update(performance_mode="Gaming", fan_control="Manual", fan_target_rpm=5000,
                                           high_temperature_cooling=True, fan_reason="high_temperature_recovery",
                                           control_temp_c=79)
                    send(hot)
                    wait_for(lambda: state()["sample"]["control"]["high_temperature_cooling"])
                    if native:
                        wait_for(lambda: view_contains("5000 RPM"))
                        self.assertEqual(state()["ui"]["color"], "#f26d78")
                        self.assertEqual(state()["ui"]["fanSummary"], "Custom curve · Target 5000 RPM")
                        self.assertEqual(state()["ui"]["status"], "High-temperature cooling active")
                        self.assertTrue(view_contains("Gaming"))
                        self.assertTrue(view_contains("Custom curve"))
                        self.assertTrue(view_contains("High-temperature cooling is waiting through its recovery period."))

                    turbo = sample()
                    turbo.update(ac_online=True, cpu_turbo_allowed=True, cpu_turbo_reason="ac_and_gpu_off")
                    send(turbo)
                    wait_for(lambda: state()["sample"]["cpu_turbo_allowed"] is True)
                    if native:
                        wait_for(lambda: view_contains("Allowed"))

                    unknown_power = sample()
                    unknown_power.update(ac_online=None, cpu_turbo_reason="ac_unknown")
                    send(unknown_power)
                    wait_for(lambda: state()["sample"]["ac_online"] is None)
                    if native:
                        wait_for(lambda: view_contains("AC power could not be confirmed."))
                        self.assertTrue(view_contains("Unknown"))
                        self.assertEqual(state()["ui"]["status"], "Power source unknown")
                        self.assertEqual(state()["ui"]["color"], "#ffb454")

                    held = sample()
                    held["control"].update(fan_control="Manual", fan_target_rpm=4500,
                                           fan_reason="gpu_temperature_hold", control_temp_c=76)
                    send(held)
                    wait_for(lambda: state()["sample"]["control"]["fan_reason"] == "gpu_temperature_hold")
                    if native:
                        wait_for(lambda: view_contains("Holding a recent GPU temperature (76°C)."))
                        self.assertTrue(view_contains("Sleeping"))
                        self.assertTrue(view_contains("4500 RPM"))

                    fault = sample()
                    fault.update(cpu_temp_c=None, cpu_turbo_allowed=None, cpu_turbo_reason="control_error")
                    fault["control"].update(healthy=False, error="Mock HID <failure>",
                                             performance_mode="Unknown", fan_control="Unknown",
                                             fan_reason="control_error", control_temp_c=None)
                    send(fault)
                    wait_for(lambda: not state()["sample"]["control"]["healthy"])
                    if native:
                        wait_for(lambda: view_contains("Mock HID <failure>"))
                        self.assertEqual(state()["ui"]["label"], "—")
                        self.assertEqual(state()["ui"]["color"], "#f26d78")
                        self.assertEqual(state()["ui"]["status"], "Controller fault")

                    gpu_error = copy.deepcopy(active)
                    gpu_error["gpu"].update(temperature_c=None, utilization_percent=None,
                                             memory_used_mb=None, memory_total_mb=None, error="Mock NVML failure")
                    send(gpu_error)
                    wait_for(lambda: state()["sample"]["gpu"]["error"] == "Mock NVML failure")
                    if native:
                        wait_for(lambda: view_contains("Mock NVML failure"))
                        self.assertEqual(state()["ui"]["color"], "#ffb454")

                    # Junk must not refresh the watchdog or leave stale values looking live.
                    time.sleep(4)
                    malformed = sample()
                    malformed["gpu"]["clients"] = "invalid"
                    send(malformed)
                    connection.sendall(b"[]\nnull\nnot JSON\n")
                    wait_for(lambda: not state()["available"], timeout=2)
                    self.assertTrue(state()["connected"])
                    self.assertIsNone(state()["sample"])
                    if native:
                        self.assertEqual(state()["ui"]["label"], "—")
                        self.assertEqual(state()["ui"]["status"], "Waiting for live data")
                        self.assertFalse(view_contains("Mock NVML failure"))

                    send(sample(), age=15)
                    send(sample(), age=-15)
                    time.sleep(0.1)
                    self.assertFalse(state()["available"], "Accepted a stale or future-dated sample")
                    send(sample())
                    wait_for(lambda: state()["available"])
                    with self.assertRaises(TimeoutError):
                        connection.recv(1)  # The UI must never send control commands.

                    # Replace the server/socket, as happens on a daemon restart.
                    connection.close()
                    server.close()
                    path.unlink()
                    wait_for(lambda: not state()["connected"])
                    self.assertIsNone(state()["sample"])
                    server = listen()
                    connection = accept(server)
                    self.assertFalse(state()["available"])
                    recovered = sample()
                    recovered["cpu_temp_c"] = 60
                    send(recovered)
                    wait_for(lambda: state()["available"] and state()["sample"]["cpu_temp_c"] == 60)
                    if native:
                        wait_for(lambda: state()["ui"]["label"] == "60°")
                        self.assertEqual(state()["ui"]["color"], "#e6b450")
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
