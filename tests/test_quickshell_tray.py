"""Test native SNI/DBusMenu on a private bus and offscreen; never activate real apps."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = all(shutil.which(tool) for tool in ("qs", "dbus-run-session"))
MODULES = all(importlib.util.find_spec(module) for module in ("dbus", "gi"))


def check_tray():
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib

    DBusGMainLoop(set_as_default=True)
    sni = "org.kde.StatusNotifierItem"
    dbusmenu = "com.canonical.dbusmenu"
    properties = "org.freedesktop.DBus.Properties"
    calls = []

    class Menu(dbus.service.Object):
        def __init__(self, bus):
            super().__init__(bus, "/Menu")
            self.revision = 1
            self.nodes = {
                0: {"children-display": "submenu"},
                1: {"label": "_Open", "enabled": True},
                2: {"label": "Checked", "toggle-type": "checkmark", "toggle-state": dbus.Int32(1)},
                3: {"type": "separator"},
                4: {"label": "More", "children-display": "submenu"},
                5: {"label": "Disabled", "enabled": False},
                6: {"label": "Choice A", "toggle-type": "radio", "toggle-state": dbus.Int32(1)},
                7: {"label": "Choice B", "toggle-type": "radio", "toggle-state": dbus.Int32(0)},
                8: {"label": "Nested action"},
            }
            self.children = {0: [1, 2, 3, 4, 5, 6, 7], 4: [8]}

        def layout(self, identifier, depth):
            children = [] if depth == 0 else [self.layout(child, depth - 1 if depth > 0 else -1)
                                             for child in self.children.get(identifier, [])]
            return dbus.Struct((dbus.Int32(identifier), dbus.Dictionary(self.nodes[identifier], signature="sv"),
                                dbus.Array(children, signature="v")), signature="ia{sv}av")

        @dbus.service.method(properties, in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface):
            return {"Version": dbus.UInt32(3), "TextDirection": "ltr", "Status": "normal",
                    "IconThemePath": dbus.Array([], signature="s")}

        @dbus.service.method(properties, in_signature="ss", out_signature="v")
        def Get(self, interface, name):
            return self.GetAll(interface)[name]

        @dbus.service.method(dbusmenu, in_signature="iias", out_signature="u(ia{sv}av)")
        def GetLayout(self, parent, depth, names):
            return dbus.UInt32(self.revision), self.layout(int(parent), int(depth))

        @dbus.service.method(dbusmenu, in_signature="i", out_signature="b")
        def AboutToShow(self, identifier):
            return False

        @dbus.service.method(dbusmenu, in_signature="isvu", out_signature="")
        def Event(self, identifier, event, data, timestamp):
            if event != "clicked":
                return
            identifier = int(identifier)
            calls.append(("menu", identifier))
            updates = []
            if identifier == 2:
                self.nodes[2]["toggle-state"] = dbus.Int32(1 - self.nodes[2]["toggle-state"])
                updates = [(2, {"toggle-state": self.nodes[2]["toggle-state"]})]
            if identifier in (6, 7):
                for target in (6, 7):
                    self.nodes[target]["toggle-state"] = dbus.Int32(target == identifier)
                    updates.append((target, {"toggle-state": self.nodes[target]["toggle-state"]}))
            if updates:
                self.ItemsPropertiesUpdated(updates, [])

        @dbus.service.signal(dbusmenu, signature="a(ia{sv})a(ias)")
        def ItemsPropertiesUpdated(self, updates, removed):
            pass

        @dbus.service.signal(dbusmenu, signature="ui")
        def LayoutUpdated(self, revision, parent):
            pass

    class Item(dbus.service.Object):
        def __init__(self, identifier, only_menu=False):
            self.bus = dbus.SessionBus(private=True)
            self.bus.set_exit_on_disconnect(False)
            super().__init__(self.bus, "/StatusNotifierItem")
            self.menu = Menu(self.bus)
            self.identifier = identifier
            pixmap = dbus.Array([dbus.Struct((16, 16, dbus.ByteArray(bytes([255, 100, 160, 220]) * 256)),
                                            signature="iiay")], signature="(iiay)")
            self.props = {"Id": identifier, "Title": identifier, "Category": "ApplicationStatus",
                          "Status": "Passive" if only_menu else "Active", "IconName": "",
                          "IconPixmap": pixmap, "ItemIsMenu": only_menu, "Menu": dbus.ObjectPath("/Menu"),
                          "ToolTip": dbus.Struct(("", dbus.Array([], signature="(iiay)"), identifier, "Tray details"),
                                                 signature="sa(iiay)ss")}

        @dbus.service.method(properties, in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface):
            return self.props

        @dbus.service.method(properties, in_signature="ss", out_signature="v")
        def Get(self, interface, name):
            return self.props[name]

        @dbus.service.method(sni, in_signature="ii", out_signature="")
        def Activate(self, x, y):
            calls.append(("activate", self.identifier))

        @dbus.service.method(sni, in_signature="ii", out_signature="")
        def SecondaryActivate(self, x, y):
            calls.append(("secondary", self.identifier))

        @dbus.service.method(sni, in_signature="is", out_signature="")
        def Scroll(self, delta, orientation):
            calls.append(("scroll", self.identifier, int(delta), str(orientation)))

        @dbus.service.signal(sni, signature="s")
        def NewStatus(self, status):
            pass

    loop = GLib.MainLoop()
    thread = threading.Thread(target=loop.run, daemon=True)
    thread.start()
    items = []
    try:
        with tempfile.TemporaryDirectory(prefix="quickshell-tray-") as directory:
            directory = Path(directory)
            shutil.copytree(ROOT / "quickshell/.config/quickshell", directory, dirs_exist_ok=True)
            config = directory / "shell.qml"
            shutil.copy(ROOT / "tests/fixtures/quickshell-tray.qml", config)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QS_NO_RELOAD_POPUP="1")
            env.pop("WAYLAND_DISPLAY", None)
            env.pop("DISPLAY", None)
            with (directory / "quickshell.log").open("w+") as log:
                process = subprocess.Popen(["qs", "--path", str(config), "--no-color"], env=env,
                                           stdout=log, stderr=subprocess.STDOUT)

                def ipc(function, *args):
                    return subprocess.check_output(
                        ["qs", "--path", str(config), "ipc", "--any-display", "call", "test", function, *map(str, args)],
                        env=env, text=True, stderr=subprocess.PIPE, timeout=2,
                    ).strip()

                def state():
                    return json.loads(ipc("snapshot"))

                def wait_for(predicate):
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        try:
                            if predicate():
                                return
                        except (subprocess.CalledProcessError, json.JSONDecodeError, dbus.DBusException):
                            pass
                        time.sleep(0.05)
                    log.seek(0)
                    raise AssertionError("Tray state did not settle.\n" + log.read())

                def row(text):
                    return next((row for row in state()["menu"] if row["text"] == text), None)

                try:
                    wait_for(lambda: state())
                    assert state()["width"] == 0, state()
                    bus = dbus.SessionBus()
                    watcher = dbus.Interface(bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher"),
                                             "org.kde.StatusNotifierWatcher")
                    primary = Item("primary")
                    menu_only = Item("menu-only", only_menu=True)
                    items.extend([primary, menu_only])
                    for item in items:
                        watcher.RegisterStatusNotifierItem(item.bus.get_unique_name())
                    wait_for(lambda: len(state()["items"]) == 2 and state()["width"] == 72)
                    wait_for(lambda: all(item["iconStatus"] == 1 for item in state()["items"]))
                    assert all("Tray details" in item["tooltip"] for item in state()["items"])
                    assert next(item for item in state()["items"] if item["id"] == "menu-only")["opacity"] == 0.55
                    ipc("primary", "primary")
                    ipc("secondary", "primary")
                    ipc("scroll", "primary", 120, "false")
                    ipc("scroll", "primary", -120, "true")
                    wait_for(lambda: ("scroll", "primary", -120, "horizontal") in calls)
                    assert ("activate", "primary") in calls
                    assert ("secondary", "primary") in calls
                    assert ("scroll", "primary", 120, "vertical") in calls
                    primary.props["Status"] = "NeedsAttention"
                    primary.NewStatus("NeedsAttention")
                    wait_for(lambda: any(item["id"] == "primary" and item["attention"] for item in state()["items"]))

                    ipc("primary", "menu-only")
                    wait_for(lambda: state()["open"] and row("Open") is not None and row("More") is not None)
                    assert ("activate", "menu-only") not in calls
                    assert row("Checked")["checked"]
                    assert row("Checked")["marker"] == "✓"
                    assert row("Choice A")["marker"] == "●"
                    assert not row("Disabled")["enabled"]
                    assert any(item["separator"] for item in state()["menu"])
                    assert row("More")["submenu"] == "More"
                    ipc("trigger", "Checked")
                    wait_for(lambda: ("menu", 2) in calls and not state()["open"])
                    ipc("primary", "menu-only")
                    wait_for(lambda: row("Checked") is not None and not row("Checked")["checked"])
                    ipc("trigger", "Choice B")
                    wait_for(lambda: ("menu", 7) in calls and not state()["open"])
                    ipc("primary", "menu-only")
                    wait_for(lambda: row("Choice B") is not None and row("Choice B")["checked"] and not row("Choice A")["checked"])
                    ipc("trigger", "Choice B")
                    wait_for(lambda: calls.count(("menu", 7)) == 2 and not state()["open"])
                    ipc("primary", "menu-only")
                    wait_for(lambda: row("Choice B") is not None and row("Choice B")["checked"])
                    ipc("trigger", "Disabled")
                    assert ("menu", 5) not in calls
                    ipc("openSubmenu", "More")
                    wait_for(lambda: any(item["text"] == "Nested action" for item in json.loads(ipc("submenuRows", "More"))))
                    ipc("triggerSubmenu", "More", "Nested action")
                    wait_for(lambda: ("menu", 8) in calls)
                    ipc("closeMenu")
                    wait_for(lambda: not state()["open"])
                    ipc("openMenu", "primary")
                    wait_for(lambda: row("Open") is not None and state()["open"])
                    primary.menu.nodes[1]["label"] = "Updated action"
                    primary.menu.revision += 1
                    primary.menu.LayoutUpdated(primary.menu.revision, 0)
                    wait_for(lambda: row("Updated action") is not None)
                    primary.menu.nodes[9] = {"label": "Dynamic action"}
                    primary.menu.children[0].append(9)
                    primary.menu.revision += 1
                    primary.menu.LayoutUpdated(primary.menu.revision, 0)
                    wait_for(lambda: row("Dynamic action") is not None)
                    primary.menu.children[0].remove(9)
                    primary.menu.revision += 1
                    primary.menu.LayoutUpdated(primary.menu.revision, 0)
                    wait_for(lambda: row("Dynamic action") is None)
                    primary.bus.close()
                    wait_for(lambda: len(state()["items"]) == 1 and not state()["open"])
                    menu_only.bus.close()
                    wait_for(lambda: len(state()["items"]) == 0 and state()["width"] == 0)
                finally:
                    process.terminate()
                    process.wait(timeout=3)
                log.seek(0)
                output = log.read()
                assert not any(error in output for error in
                               (" ERROR", "ReferenceError", "TypeError", "Unable to assign", "Binding loop", "Failed to create")), output
    finally:
        for item in items:
            item.bus.close()
        loop.quit()
        thread.join(timeout=2)


@unittest.skipUnless(TOOLS and MODULES, "Requires Quickshell, dbus-run-session, python-dbus and python-gobject")
class QuickshellTrayTests(unittest.TestCase):
    def test_private_tray_protocol(self):
        result = subprocess.run(["dbus-run-session", "--", sys.executable, str(Path(__file__).resolve()), "--session"],
                                capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    if "--session" in sys.argv:
        check_tray()
    else:
        unittest.main()
