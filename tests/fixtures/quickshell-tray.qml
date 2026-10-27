import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io

ShellRoot {
    id: test
    property var menu: null

    function buttons() { return tray.children[0].children.filter(child => child.modelData !== undefined); }
    function buttonFor(id) { return buttons().find(button => button.modelData.id === id); }
    function rows(menu) {
        const result = [];
        for (let i = 0; i < menu.count; ++i) {
            const item = menu.itemAt(i);
            result.push({ text: item.text || "", enabled: item.enabled,
                checked: item.checked || false, marker: item.checkedMarker || "",
                submenu: item.subMenu ? item.subMenu.title : "",
                separator: item.entry?.isSeparator || false });
        }
        return result;
    }
    function rowFor(text) {
        for (let i = 0; i < menu.count; ++i) {
            if (menu.itemAt(i).text === text)
                return menu.itemAt(i);
        }
        return null;
    }

    Window {
        visible: true
        width: 640
        height: 600
        TrayWidget { id: tray; x: 16; y: 16 }
    }
    Component.onCompleted: {
        menu = tray.data.find(child => child.popupType !== undefined);
        menu.popupType = Popup.Item;
    }

    IpcHandler {
        target: "test"
        function snapshot(): string {
            return JSON.stringify({ width: tray.width, open: tray.open,
                items: test.buttons().map(button => ({ id: button.modelData.id,
                    tooltip: button.tooltipText, attention: button.critical, opacity: button.opacity,
                    iconStatus: button.contentItem.children[0].status })),
                menu: test.rows(test.menu) });
        }
        function primary(id: string): void {
            const button = test.buttonFor(id);
            tray.activateItem(button, button.modelData);
        }
        function secondary(id: string): void { test.buttonFor(id).modelData.secondaryActivate(); }
        function scroll(id: string, delta: int, horizontal: bool): void {
            test.buttonFor(id).modelData.scroll(delta, horizontal);
        }
        function openMenu(id: string): void {
            const button = test.buttonFor(id);
            tray.showMenu(button, button.modelData);
        }
        function trigger(text: string): void {
            const item = test.rowFor(text);
            if (item && !item.subMenu)
                item.click();
        }
        function openSubmenu(text: string): void {
            const submenu = test.rowFor(text).subMenu;
            submenu.popupType = Popup.Item;
            submenu.open();
        }
        function submenuRows(text: string): string { return JSON.stringify(test.rows(test.rowFor(text).subMenu)); }
        function triggerSubmenu(text: string, child: string): void {
            const submenu = test.rowFor(text).subMenu;
            for (let i = 0; i < submenu.count; ++i) {
                const item = submenu.itemAt(i);
                if (item.text === child)
                    item.click();
            }
        }
        function closeMenu(): void { tray.open = false; }
    }
}
