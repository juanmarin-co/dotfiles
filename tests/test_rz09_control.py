"""Hardware-free policy and protocol checks: python -m unittest discover -s tests."""

import importlib.machinery
import importlib.util
import json
import sys
import unittest
from dataclasses import asdict
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "system/usr/local/bin/rz09-control"
loader = importlib.machinery.SourceFileLoader("rz09_control", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
control = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = control
loader.exec_module(control)


class PolicyTests(unittest.TestCase):
    def test_gaming_requires_both_ac_and_gpu_client(self):
        for ac in (False, True):
            for client in (False, True):
                with self.subTest(ac=ac, client=client):
                    desired = control.FanPolicy().evaluate(50, None, client, ac, 0)
                    self.assertEqual(desired.mode, control.MODE_GAMING if ac and client else control.MODE_BALANCED)
                    self.assertFalse(desired.manual)

    def test_either_sensor_triggers_cooling_without_forcing_a_mode(self):
        for cpu, gpu in ((85, 70), (70, 85)):
            for ac in (False, True):
                with self.subTest(cpu=cpu, gpu=gpu, ac=ac):
                    desired = control.FanPolicy().evaluate(cpu, gpu, True, ac, 0)
                    self.assertEqual(desired.mode, control.MODE_GAMING if ac else control.MODE_BALANCED)
                    self.assertTrue(desired.high_temperature_cooling)
                    self.assertEqual(desired.target_rpm, 5000)

    def test_power_and_client_changes_still_select_mode_while_cooling(self):
        policy = control.FanPolicy()
        policy.evaluate(85, 75, True, True, 0)
        for client, ac, mode in ((True, False, 0), (True, True, 1), (False, True, 0)):
            desired = policy.evaluate(84, 75, client, ac, 1)
            self.assertEqual(desired.mode, mode)
            self.assertEqual(desired.target_rpm, 5000)
            self.assertTrue(desired.high_temperature_cooling)

    def test_recovery_requires_30_continuous_seconds_at_or_below_80(self):
        policy = control.FanPolicy()
        policy.evaluate(85, 75, True, True, 0)
        policy.evaluate(80, 80, True, True, 1)
        self.assertTrue(policy.evaluate(80, 80, True, True, 30).high_temperature_cooling)
        policy.evaluate(81, 80, True, True, 31)
        policy.evaluate(80, 80, True, True, 32)
        self.assertTrue(policy.evaluate(80, 80, True, True, 61).high_temperature_cooling)
        desired = policy.evaluate(80, 80, True, True, 62)
        self.assertFalse(desired.high_temperature_cooling)
        self.assertEqual(desired.mode, control.MODE_GAMING)
        self.assertEqual(desired.target_rpm, 4500)

    def test_gpu_temperature_hold_is_independent_of_performance(self):
        policy = control.FanPolicy()
        policy.evaluate(50, 84, True, True, 0)
        desired = policy.evaluate(50, None, False, True, 30)
        self.assertEqual(desired.mode, control.MODE_BALANCED)
        self.assertEqual(desired.target_rpm, 4500)
        self.assertFalse(policy.evaluate(50, None, False, True, 31).manual)

    def test_curve_and_downward_hysteresis(self):
        policy = control.FanPolicy()
        for now, (temp, rpm) in enumerate(((59, None), (60, 3500), (70, 4000), (69, 4000), (67, 3500), (80, 4500))):
            with self.subTest(temp=temp):
                self.assertEqual(policy.evaluate(temp, None, False, True, now).target_rpm, rpm)

    def test_safe_control_is_balanced_automatic(self):
        desired = control.safe_control()
        self.assertEqual(desired.mode, control.MODE_BALANCED)
        self.assertFalse(desired.manual)
        self.assertFalse(desired.high_temperature_cooling)

    def test_waybar_names_and_highlights_latched_cooling(self):
        desired = control.FanPolicy().evaluate(85, 75, True, True, 0)
        reading = control.control_reading(desired, healthy=True, error=None, collisions=0)
        snapshot = control.StatusSnapshot(0, 79, True, control.GPUReading(), reading)
        formatted = json.loads(control.format_waybar(asdict(snapshot)))
        self.assertIn("critical", formatted["class"])
        self.assertIn("High-temperature cooling: Active", formatted["tooltip"])
        self.assertIn("Power: AC", formatted["tooltip"])
        self.assertNotIn("Emergency", formatted["tooltip"])

    def test_missing_ac_read_is_not_online(self):
        self.assertNotEqual(control.read_text(Path("/nonexistent-rz09-test/online"), "unknown"), "1")


class ProtocolTests(unittest.TestCase):
    def test_setters_use_profile_one_getters_use_zero_and_validate_readback(self):
        hid = control.RazerHID(-1, Path("/not-a-device"))
        state = {"mode": (0, 0), "rpm": 0}
        requests = []

        def ioctl(_fd, operation, buffer, _mutate):
            if operation == control.HIDIOCSFEATURE:
                request = bytearray(buffer)
                requests.append(request)
                command = request[8]
                if command == control.COMMAND_SET_MODE:
                    self.assertEqual(request[9], 1)
                    state["mode"] = tuple(request[11:13])
                elif command == control.COMMAND_SET_RPM:
                    self.assertEqual(request[9], 1)
                    state["rpm"] = request[11]
                else:
                    self.assertEqual(request[9], 0)
                return len(buffer)
            response = bytearray(requests[-1])
            response[1] = 2
            if response[8] == control.COMMAND_GET_MODE:
                response[11:13] = bytes(state["mode"])
            elif response[8] == control.COMMAND_GET_RPM:
                response[11] = state["rpm"]
            response[89] = control.report_checksum(response)
            buffer[:] = response
            return len(buffer)

        with patch.object(control.fcntl, "ioctl", side_effect=ioctl), patch.object(control.time, "sleep"):
            for target in control.TARGETS:
                hid.set_mode(target, control.MODE_GAMING, control.MANUAL)
                hid.set_rpm(target, 5000)
        self.assertEqual([request[8] for request in requests], [2, 130, 1, 129] * 2)
        for request in requests:
            self.assertEqual(request[89], control.report_checksum(request))
        response = bytearray(requests[-1])
        response[1] = 2
        response[9] = 1  # Wrong profile, even with an otherwise valid checksum.
        response[89] = control.report_checksum(response)
        self.assertFalse(hid._valid_response(91, requests[-1], response))

    def test_failed_readback_is_not_reported_as_success(self):
        hid = control.RazerHID(-1, Path("/not-a-device"))
        with patch.object(hid, "command", return_value=bytearray(91)):
            with self.assertRaises(control.HIDError):
                hid.set_mode(1, control.MODE_GAMING, control.MANUAL)
            with self.assertRaises(control.HIDError):
                hid.set_rpm(1, 5000)


if __name__ == "__main__":
    unittest.main()
