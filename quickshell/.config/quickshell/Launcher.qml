import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    property bool open: false
    property alias query: search.text
    readonly property var results: {
        const query = search.text.trim().toLocaleLowerCase();
        const terms = query.split(/\s+/).filter(term => term.length > 0);
        return DesktopEntries.applications.values.filter(entry => {
            if (entry.noDisplay || entry.command.length === 0)
                return false;
            const text = [entry.name, entry.genericName, ...entry.keywords].join(" ").toLocaleLowerCase();
            return terms.every(term => text.includes(term));
        }).sort((a, b) => Number(b.name.toLocaleLowerCase().startsWith(query))
            - Number(a.name.toLocaleLowerCase().startsWith(query)) || a.name.localeCompare(b.name));
    }

    function toggle() {
        open = !open;
    }

    function moveSelection(offset) {
        if (apps.count === 0)
            return;
        apps.currentIndex = Math.max(0, Math.min(apps.count - 1, apps.currentIndex + offset));
        apps.positionViewAtIndex(apps.currentIndex, ListView.Contain);
    }

    function launch(entry) {
        if (!entry)
            return;
        open = false;
        if (entry.runInTerminal) {
            Quickshell.execDetached({
                command: ["ghostty", "-e", ...entry.command],
                workingDirectory: entry.workingDirectory
            });
        } else {
            entry.execute();
        }
    }

    onOpenChanged: {
        if (open) {
            search.clear();
            apps.currentIndex = apps.count > 0 ? 0 : -1;
            Qt.callLater(() => search.forceActiveFocus());
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggle(); }
        function close(): void { root.open = false; }
    }

    PanelWindow {
        id: window
        visible: root.open
        screen: Quickshell.screens[0]
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "dotfiles-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 520
            height: content.implicitHeight + 2 * Spacing.outer
            color: "#0b0e14"
            border.color: "#273344"
            radius: 8

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: Spacing.outer
                spacing: Spacing.section

                StyledTextField {
                    id: search
                    Layout.fillWidth: true
                    focus: true
                    placeholderText: "Search applications…"
                    Keys.onEscapePressed: root.open = false
                    Keys.onDownPressed: root.moveSelection(1)
                    Keys.onUpPressed: root.moveSelection(-1)
                    onAccepted: root.launch(root.results[apps.currentIndex])
                }

                ListView {
                    id: apps
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 360)
                    visible: count > 0
                    clip: true
                    spacing: Spacing.control
                    model: root.results
                    onCountChanged: currentIndex = count > 0 ? 0 : -1
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        required property int index
                        width: apps.width
                        height: rowContent.implicitHeight + 2 * Spacing.control
                        radius: 5
                        color: ListView.isCurrentItem ? "#1b2432"
                            : rowMouse.containsMouse ? "#161d27" : "transparent"

                        RowLayout {
                            id: rowContent
                            anchors.fill: parent
                            anchors.margins: Spacing.control
                            spacing: Spacing.control

                            Item {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                Image {
                                    id: appIcon
                                    anchors.fill: parent
                                    source: appRow.modelData.icon.startsWith("/")
                                        ? "file://" + appRow.modelData.icon
                                        : Quickshell.iconPath(appRow.modelData.icon, true)
                                    sourceSize.width: 24
                                    sourceSize.height: 24
                                    fillMode: Image.PreserveAspectFit
                                }
                                BluetoothText {
                                    anchors.centerIn: parent
                                    visible: appIcon.source.toString().length === 0 || appIcon.status === Image.Error
                                    text: appRow.modelData.name.charAt(0).toUpperCase()
                                    color: "#8a9199"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Spacing.tight
                                BluetoothText {
                                    Layout.fillWidth: true
                                    text: appRow.modelData.name
                                }
                                BluetoothText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: appRow.modelData.genericName
                                    color: "#8a9199"
                                    font.pixelSize: 11
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launch(appRow.modelData)
                        }
                    }
                }

                BluetoothText {
                    visible: apps.count === 0
                    Layout.fillWidth: true
                    Layout.margins: Spacing.control
                    text: "No applications found."
                    color: "#8a9199"
                }
            }
        }
    }
}
