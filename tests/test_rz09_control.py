"""Hardware-free policy and protocol checks: python -m unittest discover -s tests."""

import importlib.machinery
import importlib.util
import json
import sys
import tempfile
import unittest
from dataclasses import asdict
from pathlib import Path
from unittest.mock import Mock, patch


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
        policy.evaluate(50, None, True, True, 5)
        desired = policy.evaluate(50, None, False, True, 30)
        self.assertEqual(desired.mode, control.MODE_BALANCED)
        self.assertEqual(desired.target_rpm, 4500)
        self.assertEqual(policy.evaluate(50, None, False, True, 31).target_rpm, 3500)
        self.assertTrue(policy.evaluate(50, None, False, True, 60).manual)
        self.assertFalse(policy.evaluate(50, None, False, True, 61).manual)

    def test_curve_and_downward_hysteresis(self):
        policy = control.FanPolicy()
        policy.evaluate(60, None, False, True, 0)
        for now, (temp, rpm) in enumerate(((60, 3500), (70, 4000), (69, 4000), (67, 3500), (80, 4500)), start=5):
            with self.subTest(temp=temp):
                self.assertEqual(policy.evaluate(temp, None, False, True, now).target_rpm, rpm)

    def test_cpu_only_load_enters_manual_after_five_seconds(self):
        policy = control.FanPolicy()
        self.assertFalse(policy.evaluate(60, None, False, True, 0).manual)
        self.assertFalse(policy.evaluate(80, None, False, True, 4.999).manual)
        desired = policy.evaluate(80, None, False, True, 5)
        self.assertEqual(desired.mode, control.MODE_BALANCED)
        self.assertEqual(desired.target_rpm, 4500)

    def test_brief_spike_resets_manual_entry_timer(self):
        policy = control.FanPolicy()
        policy.evaluate(70, None, False, True, 0)
        policy.evaluate(59, None, False, True, 4)
        self.assertFalse(policy.evaluate(70, None, False, True, 5).manual)
        self.assertFalse(policy.evaluate(70, None, False, True, 9).manual)
        self.assertTrue(policy.evaluate(70, None, False, True, 10).manual)

    def test_automatic_requires_thirty_seconds_strictly_below_58(self):
        policy = control.FanPolicy()
        policy.evaluate(60, None, False, True, 0)
        policy.evaluate(60, None, False, True, 5)
        self.assertEqual(policy.evaluate(50, None, False, True, 6).target_rpm, 3500)
        self.assertTrue(policy.evaluate(50, None, False, True, 35).manual)
        policy.evaluate(58, None, False, True, 36)
        policy.evaluate(50, None, False, True, 37)
        self.assertTrue(policy.evaluate(50, None, False, True, 66).manual)
        self.assertFalse(policy.evaluate(50, None, False, True, 67).manual)

    def test_high_temperature_bypasses_entry_delay(self):
        policy = control.FanPolicy()
        policy.evaluate(60, None, False, True, 0)
        desired = policy.evaluate(85, None, False, True, 1)
        self.assertTrue(desired.high_temperature_cooling)
        self.assertEqual(desired.target_rpm, 5000)

    def test_high_temperature_recovery_can_return_directly_to_automatic(self):
        policy = control.FanPolicy()
        policy.evaluate(85, None, False, True, 0)
        policy.evaluate(50, None, False, True, 1)
        desired = policy.evaluate(50, None, False, True, 31)
        self.assertFalse(desired.high_temperature_cooling)
        self.assertFalse(desired.manual)

    def test_resume_interrupts_continuous_temperature_timers(self):
        policy = control.FanPolicy()
        policy.evaluate(70, None, False, True, 0)
        policy.interrupt_timers()
        self.assertFalse(policy.evaluate(70, None, False, True, 10).manual)
        self.assertTrue(policy.evaluate(70, None, False, True, 15).manual)
        policy.evaluate(50, None, False, True, 16)
        policy.interrupt_timers()
        self.assertTrue(policy.evaluate(50, None, False, True, 50).manual)
        self.assertFalse(policy.evaluate(50, None, False, True, 80).manual)

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


class TurboTests(unittest.TestCase):
    def test_turbo_switch_and_readback(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "no_turbo"
            path.write_text("0\n")
            with patch.object(control, "CPU_NO_TURBO_PATH", path):
                control.set_cpu_turbo(False)
                self.assertEqual(path.read_text().strip(), "1")
                control.set_cpu_turbo(True)
                self.assertEqual(path.read_text().strip(), "0")

    def test_unchanged_turbo_is_not_rewritten(self):
        path = Mock()
        path.read_text.return_value = "1\n"
        with patch.object(control, "CPU_NO_TURBO_PATH", path):
            control.set_cpu_turbo(False)
        path.write_text.assert_not_called()

    def test_invalid_or_unreadable_turbo_reports_failure(self):
        for response in ("invalid", OSError("unavailable")):
            path = Mock()
            if isinstance(response, Exception):
                path.read_text.side_effect = response
            else:
                path.read_text.return_value = response
            with self.subTest(response=response), patch.object(control, "CPU_NO_TURBO_PATH", path):
                with self.assertRaises(control.ControlError):
                    control.set_cpu_turbo(False)
                path.write_text.assert_not_called()

    def test_turbo_write_requires_matching_readback(self):
        path = Mock()
        path.read_text.side_effect = ("0", "0")
        with patch.object(control, "CPU_NO_TURBO_PATH", path):
            with self.assertRaisesRegex(control.ControlError, "readback"):
                control.set_cpu_turbo(False)

    def test_turbo_policy_and_hardware_order_in_both_modes(self):
        for balanced_turbo in (True, False):
            for gaming in (True, False):
                with self.subTest(balanced_turbo=balanced_turbo, gaming=gaming):
                    calls = []
                    hardware = Mock()
                    hardware.ensure.side_effect = lambda desired: calls.append("hardware")
                    with patch.object(control, "CPU_TURBO_ON_BALANCED", balanced_turbo), patch.object(control, "set_cpu_turbo", side_effect=lambda allowed: calls.append(allowed)):
                        allowed = control.apply_control(hardware, control.normal_control(gaming, 5000))
                    expected = balanced_turbo and not gaming
                    self.assertEqual(allowed, expected)
                    self.assertEqual(calls, ["hardware", True] if expected else [False, "hardware"])

    def test_failed_turbo_disable_blocks_gaming_entry(self):
        hardware = Mock()
        with patch.object(control, "set_cpu_turbo", side_effect=control.ControlError("denied")):
            with self.assertRaises(control.ControlError):
                control.apply_control(hardware, control.normal_control(True, 3500))
        hardware.ensure.assert_not_called()

    def test_failed_hardware_exit_does_not_enable_turbo_early(self):
        hardware = Mock()
        hardware.ensure.side_effect = control.ControlError("HID failure")
        with patch.object(control, "CPU_TURBO_ON_BALANCED", True), patch.object(control, "set_cpu_turbo") as turbo:
            with self.assertRaises(control.ControlError):
                control.apply_control(hardware, control.safe_control())
        turbo.assert_not_called()

    def test_reset_respects_turbo_policy_even_if_hid_reset_fails(self):
        for balanced_turbo in (True, False):
            with self.subTest(balanced_turbo=balanced_turbo):
                hardware = Mock()
                hardware.reset.side_effect = control.ControlError("HID failure")
                with patch.object(control, "CPU_TURBO_ON_BALANCED", balanced_turbo), patch.object(control, "HardwareController", return_value=hardware), patch.object(control, "set_cpu_turbo") as turbo:
                    with self.assertLogs(control.LOG, level="ERROR"):
                        self.assertEqual(control.reset_hardware(), 1)
                turbo.assert_called_once_with(balanced_turbo)

    def test_waybar_shows_turbo_disabled(self):
        reading = control.control_reading(control.normal_control(True, 3500), healthy=True, error=None, collisions=0)
        snapshot = control.StatusSnapshot(0, 70, True, control.GPUReading(), reading, False)
        tooltip = json.loads(control.format_waybar(asdict(snapshot)))["tooltip"]
        self.assertIn("CPU turbo: Disabled", tooltip)


class HardwareControllerTests(unittest.TestCase):
    def test_manual_rpm_changes_never_rewrite_mode(self):
        controller = control.HardwareController()
        hid = Mock(collisions=0)
        controller.hid = hid
        controller.applied = control.normal_control(False, 3500)
        controller.ensure(control.normal_control(False, 4000))
        controller.ensure(control.normal_control(False, 5000, True))
        self.assertEqual(hid.set_rpm.call_count, 4)
        self.assertEqual(hid.set_rpm.call_args_list[-2].args, (1, 5000))
        self.assertEqual(hid.set_rpm.call_args_list[-1].args, (2, 5000))
        hid.set_mode.assert_not_called()

    def test_cooling_metadata_alone_never_rewrites_hardware(self):
        controller = control.HardwareController()
        hid = Mock(collisions=0)
        controller.hid = hid
        controller.applied = control.normal_control(False, 5000)
        controller.verify_at = float('inf')
        controller.ensure(control.normal_control(False, 5000, True))
        hid.set_mode.assert_not_called()
        hid.set_rpm.assert_not_called()


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
