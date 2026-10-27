"""Exercise the notification protocol on a private D-Bus, without showing windows."""

import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ("qs", "notify-send", "dbus-run-session", "gdbus")


def protocol_suite():
    class ProtocolTests(unittest.TestCase):
        @classmethod
        def setUpClass(cls):
            cls.directory = tempfile.TemporaryDirectory(prefix="quickshell-notifications-")
            directory = Path(cls.directory.name)
            source = ROOT / "quickshell/.config/quickshell"
            for name in ("NotificationService.qml", "BatteryAlerts.qml"):
                shutil.copy(source / name, directory)
            icons = directory / "icons/lucide"
            icons.mkdir(parents=True)
            shutil.copy(source / "icons/lucide/battery-warning.svg", icons)
            cls.config = directory / "shell.qml"
            shutil.copy(ROOT / "tests/fixtures/quickshell-notifications.qml", cls.config)
            cls.env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QS_NO_RELOAD_POPUP="1")
            cls.env.pop("WAYLAND_DISPLAY", None)
            cls.env.pop("DISPLAY", None)
            cls.log = (directory / "quickshell.log").open("w+")
            cls.process = subprocess.Popen(
                ["qs", "--path", str(cls.config), "--no-color"],
                env=cls.env, stdout=cls.log, stderr=subprocess.STDOUT,
            )
            try:
                cls.wait_for(lambda: cls.snapshot(), timeout=5)
            except Exception:
                cls.process.terminate()
                cls.process.wait(timeout=5)
                cls.log.seek(0)
                raise AssertionError(cls.log.read()) from None

        @classmethod
        def tearDownClass(cls):
            cls.process.terminate()
            cls.process.wait(timeout=5)
            cls.log.seek(0)
            log = cls.log.read()
            cls.log.close()
            cls.directory.cleanup()
            for error in (" ERROR", "ReferenceError", "Unable to assign", "Binding loop"):
                if error in log:
                    raise AssertionError(log)

        @classmethod
        def ipc(cls, target, function, *args):
            return subprocess.check_output(
                ["qs", "--path", str(cls.config), "ipc", "--any-display", "call",
                 target, function, *map(str, args)],
                env=cls.env, text=True, stderr=subprocess.PIPE, timeout=3,
            ).strip()

        @classmethod
        def snapshot(cls):
            return json.loads(cls.ipc("test", "snapshot"))

        @classmethod
        def wait_for(cls, predicate, timeout=2):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                try:
                    value = predicate()
                    if value:
                        return value
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    pass
                time.sleep(0.05)
            raise AssertionError("Timed out waiting for notification state")

        def setUp(self):
            self.sample_battery(100, discharging=False)
            self.ipc("notifications", "dismissAll")
            self.ipc("test", "setDnd", "false")
            self.wait_for(lambda: not self.snapshot()["notifications"])

        def send(self, summary, timeout=None, urgency="normal", replace=None, body="Body"):
            command = ["notify-send", "--print-id", "--app-name=Quickshell tests",
                       f"--urgency={urgency}"]
            if timeout is not None:
                command.append(f"--expire-time={timeout}")
            if replace is not None:
                command.append(f"--replace-id={replace}")
            return int(subprocess.check_output(
                [*command, summary, body], env=self.env, text=True, timeout=3,
            ).strip())

        def contains(self, identifier):
            return any(n["id"] == identifier for n in self.snapshot()["notifications"])

        def sample_battery(self, level, discharging=True, ready=True):
            self.ipc("test", "sampleBattery", level, str(discharging).lower(), str(ready).lower())

        def wait_count(self, count):
            self.wait_for(lambda: len(self.snapshot()["notifications"]) == count)

        def test_battery_thresholds_are_one_shot_and_bypass_dnd(self):
            self.ipc("test", "setDnd", "true")
            self.sample_battery(0, ready=False)
            time.sleep(0.1)
            self.assertEqual(self.snapshot()["notifications"], [])
            self.sample_battery(16)
            self.assertEqual(self.snapshot()["notifications"], [])
            self.sample_battery(15)
            self.wait_count(1)
            low = self.snapshot()["notifications"][0]
            self.assertEqual(low["summary"], "Low battery")
            self.assertIn("15%", low["body"])
            self.assertEqual(low["urgency"], 2)
            self.assertEqual(low["timeout"], 0)
            self.assertEqual(self.snapshot()["visible"], [low["id"]])
            self.sample_battery(14)
            time.sleep(0.1)
            self.assertEqual(len(self.snapshot()["notifications"]), 1)
            self.sample_battery(5)
            self.wait_count(2)
            critical = self.snapshot()["notifications"][-1]
            self.assertEqual(critical["summary"], "Battery critically low")
            self.assertEqual(critical["urgency"], 2)
            self.assertEqual(len(self.snapshot()["visible"]), 2)
            self.sample_battery(4)
            time.sleep(0.1)
            self.assertEqual(len(self.snapshot()["notifications"]), 2)

        def test_battery_starting_empty_only_sends_critical(self):
            self.sample_battery(0)
            self.wait_count(1)
            self.assertEqual(self.snapshot()["notifications"][0]["summary"], "Battery critically low")
            self.sample_battery(7)
            time.sleep(0.1)
            self.assertEqual(len(self.snapshot()["notifications"]), 1)

        def test_battery_does_not_alert_while_plugged_in(self):
            for level in (15, 5, 0):
                self.sample_battery(level, discharging=False)
            time.sleep(0.1)
            self.assertEqual(self.snapshot()["notifications"], [])

        def test_battery_rearms_after_recharge_not_brief_replug(self):
            self.sample_battery(15)
            self.wait_count(1)
            self.sample_battery(16, discharging=False)
            self.sample_battery(15)
            time.sleep(0.1)
            self.assertEqual(len(self.snapshot()["notifications"]), 1)
            self.sample_battery(20, discharging=False)
            self.sample_battery(15)
            self.wait_count(2)
            self.sample_battery(5)
            self.wait_count(3)
            self.sample_battery(9, discharging=False)
            self.sample_battery(5)
            time.sleep(0.1)
            self.assertEqual(len(self.snapshot()["notifications"]), 3)
            self.sample_battery(10, discharging=False)
            self.sample_battery(5)
            self.wait_count(4)

        def test_battery_reload_does_not_repeat_alert(self):
            self.sample_battery(15)
            self.wait_count(1)
            identifier = self.snapshot()["notifications"][0]["id"]
            self.ipc("test", "reload")
            time.sleep(0.3)
            self.wait_for(lambda: self.contains(identifier))
            self.sample_battery(15)
            time.sleep(0.1)
            self.assertEqual(len(self.snapshot()["notifications"]), 1)

        def test_default_timeout_and_critical_persistence(self):
            normal = self.send("Default timeout")
            critical = self.send("Critical", urgency="critical")
            state = {n["id"]: n for n in self.snapshot()["notifications"]}
            self.assertEqual(state[normal]["timeout"], 5000)
            self.assertEqual(state[critical]["timeout"], 0)
            self.wait_for(lambda: not self.contains(normal), timeout=6)
            self.assertTrue(self.contains(critical))

        def test_explicit_timeout_and_zero_persistence(self):
            persistent = self.send("Persistent", timeout=0, body="<b>Literal text</b>")
            short = self.send("Short timeout", timeout=150)
            self.wait_for(lambda: not self.contains(short))
            self.assertTrue(self.contains(persistent))
            self.assertEqual(self.snapshot()["notifications"][0]["body"], "<b>Literal text</b>")

        def test_replacement_restarts_expiry_without_duplicate(self):
            identifier = self.send("Before replacement", timeout=300)
            time.sleep(0.15)
            self.assertEqual(self.send("After replacement", timeout=600, replace=identifier), identifier)
            time.sleep(0.25)
            state = self.snapshot()["notifications"]
            self.assertEqual(len(state), 1)
            self.assertEqual(state[0]["summary"], "After replacement")
            self.wait_for(lambda: not self.contains(identifier))

        def test_dnd_and_hidden_notifications_expire(self):
            normal = self.send("Normal", timeout=0)
            critical = self.send("Critical", timeout=100, urgency="critical")
            self.ipc("test", "setDnd", "true")
            self.assertEqual(self.snapshot()["visible"], [critical])
            hidden = self.send("Hidden short notification", timeout=150)
            self.wait_for(lambda: not self.contains(hidden))
            self.assertTrue(self.contains(normal))
            self.assertTrue(self.contains(critical))
            self.ipc("test", "setDnd", "false")
            self.assertEqual(set(self.snapshot()["visible"]), {normal, critical})

        def test_visible_limit_and_dismiss_all(self):
            identifiers = [self.send(f"Notification {i}", timeout=0) for i in range(4)]
            self.assertEqual(self.snapshot()["visible"], list(reversed(identifiers[-3:])))
            self.ipc("notifications", "dismissAll")
            self.wait_for(lambda: not self.snapshot()["notifications"])

        def test_application_close_request(self):
            identifier = self.send("Application closes this", timeout=0)
            subprocess.run(
                ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                 "--object-path", "/org/freedesktop/Notifications", "--method",
                 "org.freedesktop.Notifications.CloseNotification", str(identifier)],
                env=self.env, capture_output=True, check=True, timeout=3,
            )
            self.wait_for(lambda: not self.contains(identifier))

        def test_actions_invoke_and_dismiss(self):
            read_fd, write_fd = os.pipe()
            sender = subprocess.Popen(
                ["notify-send", "--app-name=Quickshell tests", "--expire-time=0",
                 "--action=default=Open", "--action=review=Review", "--id-fd", str(write_fd),
                 "Action test"],
                env=self.env, pass_fds=(write_fd,), stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True,
            )
            os.close(write_fd)
            try:
                ready, _, _ = select.select([read_fd], [], [], 3)
                self.assertTrue(ready, "notify-send did not return a notification ID")
                identifier = int(os.read(read_fd, 128).strip())
                self.ipc("test", "invoke", identifier, "review")
                stdout, stderr = sender.communicate(timeout=3)
                self.assertEqual(sender.returncode, 0, stderr)
                self.assertEqual(stdout.strip(), "review")
                self.wait_for(lambda: not self.contains(identifier))
            finally:
                os.close(read_fd)
                if sender.poll() is None:
                    sender.kill()
                    sender.communicate()

        def test_z_reload_preserves_notifications_and_dnd(self):
            identifier = self.send("Survives reload", timeout=0)
            self.ipc("test", "setDnd", "true")
            self.ipc("test", "reload")
            time.sleep(0.3)
            self.wait_for(lambda: self.snapshot()["dnd"] and self.contains(identifier), timeout=3)
            self.assertEqual(self.snapshot()["visible"], [])

    return unittest.defaultTestLoader.loadTestsFromTestCase(ProtocolTests)


@unittest.skipUnless(all(shutil.which(tool) for tool in TOOLS), "Quickshell notification tools unavailable")
class QuickshellNotificationTests(unittest.TestCase):
    def test_private_bus_protocol(self):
        result = subprocess.run(
            ["dbus-run-session", "--", sys.executable, str(Path(__file__).resolve()), "--session"],
            capture_output=True, text=True, timeout=40,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    if "--session" in sys.argv:
        result = unittest.TextTestRunner(verbosity=2).run(protocol_suite())
        sys.exit(not result.wasSuccessful())
    unittest.main()
