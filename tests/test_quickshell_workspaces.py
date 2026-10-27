"""Test workspace window menus with stubbed Niri IPC; never switch real windows."""

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


@unittest.skipUnless(shutil.which("qs"), "Requires Quickshell")
class QuickshellWorkspaceTests(unittest.TestCase):
    def test_workspace_window_menu(self):
        with tempfile.TemporaryDirectory(prefix="quickshell-workspaces-") as directory:
            directory = Path(directory)
            source = ROOT / "quickshell/.config/quickshell"
            for name in ("WorkspaceWindowMenu.qml", "ActionMenuItem.qml", "BluetoothText.qml", "Spacing.qml", "StyledToolTip.qml"):
                shutil.copy(source / name, directory)
            config = directory / "shell.qml"
            shutil.copy(ROOT / "tests/fixtures/quickshell-workspaces.qml", config)
            data = directory / "data"
            applications = data / "applications"
            applications.mkdir(parents=True)
            icon = data / "app-icon.svg"
            shutil.copy(source / "icons/lucide/power.svg", icon)
            for identifier, name in (("app", "App"), ("com.mitchellh.ghostty", "Ghostty"),
                                     ("dev.zed.Zed", "Zed"), ("firefox", "Firefox")):
                (applications / (identifier + ".desktop")).write_text(
                    f"[Desktop Entry]\nType=Application\nName={name}\nIcon={icon}\nExec=/bin/true\nStartupWMClass={identifier}\n"
                )
            (directory / "workspaces.json").write_text(json.dumps([
                {"id": 45, "idx": 1, "output": "eDP-1"},
                {"id": 900, "idx": 2, "output": "eDP-1"},
                {"id": 901, "idx": 2, "output": "DP-1"},
                {"id": 777, "idx": 3, "output": "eDP-1"},
            ]))
            (directory / "windows.json").write_text(json.dumps([
                {"id": 11, "workspace_id": 900, "title": "Bravo", "app_id": "app", "is_focused": False},
                {"id": 12, "workspace_id": 900, "title": "Focus <b>title</b>\ncontinued", "app_id": "app", "is_focused": True},
                {"id": 13, "workspace_id": 900, "title": None, "app_id": "fallback", "is_focused": False},
                {"id": 14, "workspace_id": 45, "title": "Wrong workspace", "is_focused": False},
                {"id": 15, "workspace_id": 901, "title": "Wrong monitor", "is_focused": False},
                {"id": 16, "workspace_id": 900, "title": None, "app_id": None, "is_focused": False},
                {"id": 17, "workspace_id": 900, "title": "shell prompt", "app_id": "com.mitchellh.ghostty", "is_focused": False},
                {"id": 18, "workspace_id": 900, "title": "code project", "app_id": "dev.zed.Zed", "is_focused": False},
                {"id": 19, "workspace_id": 900, "title": "Page — Mozilla Firefox", "app_id": "firefox", "is_focused": False},
            ]))
            binaries = directory / "bin"
            binaries.mkdir()
            stub = binaries / "niri"
            stub.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
from pathlib import Path
root = Path(os.environ["NIRI_MENU_TEST_DATA"])
args = sys.argv[1:]
if args == ["msg", "--json", "workspaces"]:
    print((root / "workspaces.json").read_text())
elif args == ["msg", "--json", "windows"]:
    print((root / "windows.json").read_text())
elif args[:4] == ["msg", "action", "focus-window", "--id"]:
    (root / "focus.json").write_text(json.dumps(args))
else:
    sys.exit(2)
''')
            stub.chmod(0o755)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QS_NO_RELOAD_POPUP="1",
                       PATH=str(binaries) + os.pathsep + os.environ["PATH"], NIRI_MENU_TEST_DATA=str(directory),
                       XDG_DATA_HOME=str(data), XDG_DATA_DIRS=str(directory / "empty-data"))
            env.pop("WAYLAND_DISPLAY", None)
            env.pop("DISPLAY", None)
            with (directory / "quickshell.log").open("w+") as log:
                process = subprocess.Popen(
                    ["qs", "--path", str(config), "--no-color"],
                    env=env, stdout=log, stderr=subprocess.STDOUT,
                )

                def ipc(function, *args):
                    return subprocess.check_output(
                        ["qs", "--path", str(config), "ipc", "--any-display", "call", "test", function, *map(str, args)],
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
                    self.fail("Workspace menu did not settle.\n" + log.read())

                try:
                    wait_for(lambda: snapshot()["appCount"] >= 4)
                    ipc("loadWorkspace", 2)
                    wait_for(lambda: not snapshot()["loading"])
                    state = snapshot()
                    self.assertEqual(state["error"], "")
                    self.assertEqual([w["id"] for w in state["windows"]], [12, 11, 18, 13, 19, 17, 16])
                    self.assertEqual(state["labels"], [
                        "Focus <b>title</b> continued", "Bravo", "code project", "fallback",
                        "Page — Mozilla Firefox", "shell prompt", "Untitled window",
                    ])
                    items = {item["text"]: item for item in state["items"]}
                    for title, app in (("shell prompt", "Ghostty"), ("code project", "Zed"),
                                       ("Page — Mozilla Firefox", "Firefox")):
                        self.assertEqual(items[title]["tooltip"], app)
                        self.assertTrue(items[title]["icon"].endswith("/app-icon.svg"))
                    self.assertTrue(all(item["format"] == 0 for item in state["items"]))
                    self.assertEqual(sum(bool(item["checked"]) for item in state["items"]), 1)
                    ipc("activateWindow", 11)
                    wait_for(lambda: (directory / "focus.json").exists())
                    self.assertEqual(json.loads((directory / "focus.json").read_text()),
                                     ["msg", "action", "focus-window", "--id", "11"])
                    ipc("loadWorkspace", 3)
                    wait_for(lambda: not snapshot()["loading"])
                    self.assertEqual(snapshot()["windows"], [])
                    self.assertEqual(snapshot()["error"], "")
                    ipc("loadWorkspace", 99)
                    wait_for(lambda: not snapshot()["loading"])
                    self.assertEqual(snapshot()["error"], "Workspace is no longer available")
                    (directory / "windows.json").write_text("not JSON")
                    ipc("loadWorkspace", 2)
                    wait_for(lambda: not snapshot()["loading"])
                    self.assertEqual(snapshot()["error"], "Could not read windows")
                finally:
                    process.terminate()
                    process.wait(timeout=3)
                log.seek(0)
                output = log.read()
                self.assertFalse(any(error in output for error in
                                     (" ERROR", "ReferenceError", "Unable to assign", "Binding loop")), output)


if __name__ == "__main__":
    unittest.main()
