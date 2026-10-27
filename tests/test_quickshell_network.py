"""NetworkManager status tests with a fake nmcli; never alter real connections."""

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
QUERY = ["--terse", "--colors", "no", "--fields", "UUID,TYPE,NAME,STATE", "connection", "show", "--active"]
MONITOR = ["--colors", "no", "monitor"]


@unittest.skipUnless(shutil.which("qs"), "Requires Quickshell")
class QuickshellNetworkTests(unittest.TestCase):
    def test_networkmanager_status(self):
        with tempfile.TemporaryDirectory(prefix="quickshell-network-") as directory:
            directory = Path(directory)
            shutil.copytree(ROOT / "quickshell/.config/quickshell", directory, dirs_exist_ok=True)
            native = bool(os.environ.get("WAYLAND_DISPLAY"))
            fixture = "quickshell-network.qml" if native else "quickshell-network-service.qml"
            config = directory / "shell.qml"
            shutil.copy(ROOT / "tests/fixtures" / fixture, config)
            data = directory / "connections"
            data.write_text("wifi:802-11-wireless:Home:activated\nbridge:bridge:virbr0:activated\n")
            events_path = directory / "events"
            os.mkfifo(events_path)
            binaries = directory / "bin"
            binaries.mkdir()
            stub = binaries / "nmcli"
            stub.write_text(f"#!{sys.executable}\n" + '''import json, os, sys, time
from pathlib import Path
root = Path(os.environ["NM_TEST_DATA"])
args = sys.argv[1:]
with (root / "commands").open("a") as log:
    log.write(json.dumps(args) + "\\n")
if os.environ.get("LC_ALL") != "C":
    sys.exit(99)
if args == ["--colors", "no", "monitor"]:
    print("Monitoring", flush=True)
    with (root / "events").open() as events:
        for line in events:
            if line.strip() == "exit":
                sys.exit(1)
            print(line, end="", flush=True)
elif args == ["--terse", "--colors", "no", "--fields", "UUID,TYPE,NAME,STATE", "connection", "show", "--active"]:
    if (root / "fail").exists():
        sys.exit(10)
    text = (root / "connections").read_text()
    (root / "query-started").write_text(str(time.monotonic_ns()))
    if (root / "delay").exists():
        time.sleep(0.5)
    print(text, end="")
else:
    sys.exit(2)
''')
            stub.chmod(0o755)
            env = dict(os.environ, QT_QPA_PLATFORM="wayland" if native else "offscreen", QS_NO_RELOAD_POPUP="1",
                       PATH=str(binaries) + os.pathsep + os.environ["PATH"], NM_TEST_DATA=str(directory))
            with (directory / "quickshell.log").open("w+") as log:
                process = subprocess.Popen(["qs", "--path", str(config), "--no-color"], env=env,
                                           stdout=log, stderr=subprocess.STDOUT)
                events = None

                def ipc(function, *args):
                    return subprocess.check_output(
                        ["qs", "--path", str(config), "ipc", "--any-display", "call", "test", function, *args],
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
                    self.fail("Network status did not settle.\n" + log.read())

                def changed(text):
                    data.write_text(text)
                    events.write("changed\n")
                    events.flush()

                def view_contains(text):
                    return text in state()["ui"]["texts"]

                try:
                    wait_for(lambda: state()["known"])
                    events = events_path.open("w", buffering=1)
                    self.assertEqual(state()["vpns"], [])
                    self.assertFalse(state()["active"])
                    self.assertEqual(state()["summary"], "No active NetworkManager VPN")
                    if native:
                        ipc("openPopup")
                        wait_for(lambda: state()["ui"]["height"] > 50)
                        self.assertEqual(state()["ui"]["width"], 420)
                        self.assertEqual(state()["ui"]["barWidth"], 36)
                        self.assertEqual(len(state()["ui"]["buttons"]), 1)
                        self.assertFalse(state()["ui"]["buttons"][0]["badgeVisible"])
                        self.assertIn("No active NetworkManager VPN", state()["ui"]["buttons"][0]["text"])

                    device = {"type": 2, "name": "enp2s0", "nmManaged": True, "connected": False,
                              "hasLink": False, "linkSpeed": 0, "state": 4, "network": None}
                    ipc("setDevices", json.dumps({"devices": [device]}))
                    wait_for(lambda: len(state()["wired"]) == 1)
                    self.assertIn("Cable disconnected", state()["wired"][0])
                    self.assertFalse(state()["wiredConnected"])
                    device.update(hasLink=True, linkSpeed=100, state=1, network={"name": "Office LAN"})
                    ipc("setDevices", json.dumps({"devices": [device]}))
                    self.assertIn("Connecting", state()["wired"][0])
                    self.assertIn("100 Mbit/s", state()["wired"][0])
                    if native:
                        self.assertTrue(state()["ui"]["buttons"][0]["icon"].endswith("ethernet-port.svg"))
                        self.assertTrue(state()["ui"]["buttons"][0]["warning"])
                    device.update(connected=True, state=2, linkSpeed=1000)
                    ipc("setDevices", json.dumps({"devices": [device]}))
                    self.assertTrue(state()["wiredConnected"])
                    self.assertIn("1 Gbit/s", state()["wired"][0])
                    if native:
                        wait_for(lambda: view_contains("Office LAN"))
                        self.assertTrue(state()["ui"]["buttons"][0]["active"])

                    # Ignore unrelated interfaces, including a TUN named tailscale0.
                    changed("tun:tun:tailscale0:activated\nwg:wireguard:Work\\: EU\\\\dev:activated\n"
                            "ovpn:vpn:Office:activating\n")
                    wait_for(lambda: len(state()["vpns"]) == 2)
                    self.assertTrue(state()["active"])
                    self.assertTrue(state()["changing"])
                    self.assertEqual(state()["vpns"][0]["name"], "Work: EU\\dev")
                    if native:
                        wait_for(lambda: view_contains("WireGuard · Active"))
                        self.assertTrue(view_contains("VPN · Connecting"))
                        self.assertTrue(view_contains("Work: EU\\dev"))
                        button = state()["ui"]["buttons"][0]
                        self.assertTrue(button["icon"].endswith("ethernet-port.svg"))
                        self.assertTrue(button["badgeVisible"])
                        self.assertTrue(button["badgeIcon"].endswith("shield-check.svg"))
                        self.assertEqual(button["badgeColor"], "#ffb454")
                        self.assertIn("Work: EU\\dev", button["text"])

                    changed("ovpn:vpn:Office:deactivating\n")
                    wait_for(lambda: len(state()["vpns"]) == 1 and not state()["active"])
                    self.assertEqual(state()["vpns"][0]["state"], "deactivating")
                    if native:
                        wait_for(lambda: view_contains("VPN · Disconnecting"))
                        self.assertTrue(state()["ui"]["buttons"][0]["badgeVisible"])
                        self.assertTrue(state()["ui"]["buttons"][0]["badgeIcon"].endswith("shield.svg"))

                    # Changes while a query is running must trigger a later fresh query.
                    (directory / "delay").touch()
                    previous = (directory / "query-started").read_text()
                    changed("old:wireguard:Old:activated\n")
                    wait_for(lambda: (directory / "query-started").read_text() != previous)
                    changed("new:wireguard:Newest:activated\n")
                    wait_for(lambda: state()["vpns"] and state()["vpns"][0]["name"] == "Newest")
                    (directory / "delay").unlink()
                    if native:
                        self.assertEqual(state()["ui"]["buttons"][0]["badgeColor"], "#e6b450")

                    (directory / "fail").touch()
                    events.write("changed\n")
                    events.flush()
                    wait_for(lambda: not state()["known"])
                    self.assertEqual(state()["vpns"], [])
                    self.assertFalse(state()["active"])
                    if native:
                        wait_for(lambda: view_contains("VPN status unavailable"))
                        self.assertTrue(state()["ui"]["buttons"][0]["warning"])
                        self.assertTrue(state()["ui"]["buttons"][0]["badgeVisible"])
                        self.assertEqual(state()["ui"]["buttons"][0]["badgeColor"], "#ffb454")
                        self.assertTrue(state()["ui"]["buttons"][0]["active"])
                    (directory / "fail").unlink()
                    changed("recovered:wireguard:Recovered:activated\n")
                    wait_for(lambda: state()["known"] and state()["active"])

                    # Losing the event monitor invalidates status; it restarts automatically.
                    data.write_text("")
                    events.write("exit\n")
                    events.flush()
                    wait_for(lambda: not state()["known"])
                    self.assertEqual(state()["vpns"], [])
                    wait_for(lambda: state()["known"])
                    self.assertEqual(state()["vpns"], [])
                    self.assertFalse(state()["active"])
                    if native:
                        self.assertFalse(state()["ui"]["buttons"][0]["badgeVisible"])
                    commands = [json.loads(line) for line in (directory / "commands").read_text().splitlines()]
                    self.assertTrue(all(command in (QUERY, MONITOR) for command in commands))
                    self.assertGreaterEqual(commands.count(MONITOR), 2)
                finally:
                    if events:
                        events.close()
                    process.terminate()
                    process.wait(timeout=3)
                log.seek(0)
                output = log.read()
                self.assertFalse(any(error in output for error in
                                     (" ERROR", "ReferenceError", "TypeError", "Unable to assign", "Binding loop")), output)


if __name__ == "__main__":
    unittest.main()
