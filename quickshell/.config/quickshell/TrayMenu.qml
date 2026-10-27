import QtQuick
import QtQml.Models
import QtQuick.Controls
import QtQuick.Controls.impl
import Quickshell

Menu {
    id: root
    property var entry: null
    property bool expanded: false
    onAboutToShow: expanded = true
    onClosed: Qt.callLater(() => { if (!visible) expanded = false; })
    title: entry?.text || ""
    icon.source: entry?.icon || ""
    enabled: entry?.enabled ?? true
    popupType: Popup.Window
    width: 300
    padding: Spacing.control
    onEntryChanged: {
        if (!entry)
            dismiss();
    }
    background: Rectangle {
        color: "#0b0e14"
        border.color: "#273344"
        radius: 6
    }
    delegate: ActionMenuItem {
        id: submenuButton
        rightPadding: Spacing.control + (subMenu ? 16 + Spacing.control : 0)
        arrow: ColorImage {
            visible: submenuButton.subMenu !== null
            x: submenuButton.width - width - Spacing.control
            y: (submenuButton.height - height) / 2
            width: 16
            height: 16
            sourceSize.width: width
            sourceSize.height: height
            source: Qt.resolvedUrl("icons/lucide/chevron-right.svg")
            color: "#bfbdb6"
        }
    }

    QsMenuOpener {
        id: opener
        menu: root.expanded ? root.entry : null
    }

    Instantiator {
        model: opener.children.values
        delegate: Loader {
            id: loader
            required property var modelData
            required property int index
            readonly property bool submenu: !!modelData && !modelData.isSeparator && modelData.hasChildren
            sourceComponent: !modelData ? null : modelData.isSeparator ? separator
                : submenu ? Qt.createComponent(Qt.resolvedUrl("TrayMenu.qml")) : action
            onLoaded: {
                item.entry = Qt.binding(() => modelData);
                if (submenu)
                    root.insertMenu(index, item);
                else
                    root.insertItem(index, item);
            }
        }
        onObjectRemoved: (index, loader) => {
            // The Loader owns its item; detach it without deleting it twice.
            if (loader.item) {
                if (loader.item.popupType !== undefined)
                    root.takeMenu(index);
                else
                    root.takeItem(index);
            }
        }
    }

    Component {
        id: action
        ActionMenuItem {
            property var entry: null
            text: entry?.text || ""
            icon.source: entry?.icon || ""
            enabled: entry?.enabled ?? false
            // Toggle state belongs to the application, not an optimistic local checkbox.
            checked: !!entry && entry.checkState !== Qt.Unchecked
            checkedMarker: entry?.buttonType === QsMenuButtonType.RadioButton ? "●"
                : entry?.checkState === Qt.PartiallyChecked ? "−" : "✓"
            onTriggered: entry?.triggered()
        }
    }
    Component {
        id: separator
        MenuSeparator {
            property var entry: null
            padding: Spacing.tight
            contentItem: Rectangle { implicitWidth: 1; implicitHeight: 1; color: "#273344" }
        }
    }
    ActionMenuItem {
        visible: opener.children.values.length === 0
        height: visible ? implicitHeight : 0
        enabled: false
        text: "Loading…"
    }
}
