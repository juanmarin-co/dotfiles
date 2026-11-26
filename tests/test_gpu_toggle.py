"""Hardware-free checks for the GPU mode toggle: python -m unittest discover -s tests."""

import importlib.machinery
import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "system/usr/local/bin/gpu-mode"
loader = importlib.machinery.SourceFileLoader("gpu_mode", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
gpu_mode = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = gpu_mode
loader.exec_module(gpu_mode)

REPO = Path(__file__).resolve().parents[1]
SYSTEM = REPO / "system/etc/systemd/system"
POLKIT_RULE = REPO / "system/etc/polkit-1/rules.d/50-gpu-mode.rules"


class RemovalTests(unittest.TestCase):
    def test_remove_writes_each_present_pci_function(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for address in gpu_mode.GPU_FUNCTIONS:
                (root / address).mkdir()
                (root / address / "remove").touch()
            with patch.object(gpu_mode, "PCI_DEVICES", root):
                self.assertEqual(gpu_mode.remove_card(), 0)
            for address in gpu_mode.GPU_FUNCTIONS:
                self.assertEqual((root / address / "remove").read_text(), "1\n")

    def test_remove_skips_absent_functions(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(gpu_mode, "PCI_DEVICES", Path(directory)):
                self.assertEqual(gpu_mode.remove_card(), 0)

    def test_remove_reports_failures_without_aborting_remaining_functions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for address in gpu_mode.GPU_FUNCTIONS:
                (root / address).mkdir()
                # A directory in place of the remove file makes writes fail.
                (root / address / "remove").mkdir()
            with patch.object(gpu_mode, "PCI_DEVICES", root), self.assertLogs(gpu_mode.LOG, level="ERROR"):
                self.assertEqual(gpu_mode.remove_card(), 1)


class ModeFlagTests(unittest.TestCase):
    def test_integrated_flag_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(gpu_mode, "MODE_DIRECTORY", Path(directory)):
                self.assertEqual(gpu_mode.set_mode(True), 0)
                self.assertTrue((Path(directory) / "integrated").exists())
                self.assertEqual(gpu_mode.set_mode(False), 0)
                self.assertFalse((Path(directory) / "integrated").exists())

    def test_unwritable_flag_returns_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            # A regular file where the mode directory belongs blocks flag creation.
            blocked = Path(directory) / "blocked"
            blocked.write_text("not a directory\n")
            with patch.object(gpu_mode, "MODE_DIRECTORY", blocked), self.assertLogs(gpu_mode.LOG, level="ERROR"):
                self.assertEqual(gpu_mode.set_mode(True), 1)

    def test_status_reports_mode_and_application_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            devices = root / "devices"
            devices.mkdir()
            gpu = devices / gpu_mode.GPU_FUNCTIONS[0]
            flag = root / "integrated"
            for integrated in (False, True):
                for present in (False, True):
                    with self.subTest(integrated=integrated, present=present):
                        if integrated:
                            flag.touch()
                        elif flag.exists():
                            flag.unlink()
                        if present:
                            gpu.mkdir()
                        elif gpu.exists():
                            gpu.rmdir()
                        with patch.object(gpu_mode, "MODE_DIRECTORY", root), \
                                patch.object(gpu_mode, "PCI_DEVICES", devices):
                            output = io.StringIO()
                            with redirect_stdout(output):
                                self.assertEqual(gpu_mode.print_status(), 0)
                        text = output.getvalue()
                        self.assertIn("mode=integrated" if integrated else "mode=hybrid", text)
                        self.assertIn("card_present=yes" if present else "card_present=no", text)
                        self.assertIn("applied" if integrated is not present else "pending", text)


class UnitFileTests(unittest.TestCase):
    def test_boot_unit_removes_the_card_before_the_display_manager(self):
        text = (SYSTEM / "gpu-off-boot.service").read_text()
        self.assertIn("ConditionPathExists=" + str(gpu_mode.MODE_DIRECTORY / "integrated"), text)
        self.assertIn("Before=display-manager.service", text)
        self.assertIn("After=systemd-udev-trigger.service", text)
        self.assertIn("ExecStart=/usr/local/bin/gpu-mode remove", text)
        self.assertIn("Type=oneshot", text)
        self.assertIn("WantedBy=multi-user.target", text)

    def test_mode_setters_invoke_matching_subcommands(self):
        for name, subcommand in (("gpu-mode-integrated", "set-integrated"),
                                 ("gpu-mode-hybrid", "set-hybrid")):
            with self.subTest(unit=name):
                text = (SYSTEM / f"{name}.service").read_text()
                self.assertIn(f"ExecStart=/usr/local/bin/gpu-mode {subcommand}", text)
                self.assertIn("Type=oneshot", text)
                self.assertIn("StateDirectory=gpu-mode", text)


class PolkitRuleTests(unittest.TestCase):
    def test_rule_allows_exactly_the_mode_units_for_wheel(self):
        text = POLKIT_RULE.read_text()
        self.assertIn('action.id == "org.freedesktop.systemd1.manage-units"', text)
        for unit in ("gpu-mode-integrated.service", "gpu-mode-hybrid.service"):
            self.assertIn(f'action.lookup("unit") == "{unit}"', text)
        self.assertIn('subject.isInGroup("wheel")', text)
        self.assertIn("polkit.Result.YES", text)
        self.assertNotIn("rz09-control", text)


if __name__ == "__main__":
    unittest.main()
