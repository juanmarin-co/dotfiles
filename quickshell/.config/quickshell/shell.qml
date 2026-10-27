import QtQuick
import Quickshell
import Quickshell.Services.UPower

ShellRoot {
    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Launcher {
        id: launcher
    }

    NotificationService {
        id: notifications
    }

    BatteryAlerts {
        battery: UPower.displayDevice
        onBattery: UPower.onBattery
    }

    NotificationToasts {
        service: notifications
        margins.top: BarStyle.height + Spacing.outer
    }

    Rz09Service {
        id: coolingService
    }

    NetworkStatus {
        id: networkService
    }

    Variants {
        model: Quickshell.screens

        AutoHidePanel {
            id: bar
            required property var modelData
            screen: modelData
            holdOpen: [workspaces, calendar, network, bluetooth, cooling, energy, session, tray]
                .some(widget => widget.open)

            function closePopovers(except) {
                for (const widget of [workspaces, calendar, network, bluetooth, cooling, energy, session, tray]) {
                    if (widget !== except)
                        widget.open = false;
                }
            }

            Connections {
                target: launcher
                function onOpenChanged() {
                    if (launcher.open)
                        bar.closePopovers(null);
                }
            }

            Item {
                anchors.fill: parent
                visible: bar.shown

                WorkspacesWidget {
                    id: workspaces
                    screen: bar.screen
                    anchors.left: parent.left
                    anchors.leftMargin: Spacing.tight
                    anchors.verticalCenter: parent.verticalCenter
                    onOpenChanged: {
                        if (open)
                            bar.closePopovers(workspaces);
                    }
                }

                CalendarWidget {
                    id: calendar
                    panel: bar
                    now: clock.date
                    anchors.centerIn: parent
                    onOpenChanged: {
                        if (open)
                            bar.closePopovers(calendar);
                    }
                }

                BarButton {
                    anchors.right: network.left
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: notifications.doNotDisturb
                        ? Qt.resolvedUrl("icons/lucide/bell-off.svg") : Qt.resolvedUrl("icons/lucide/bell.svg")
                    icon.width: BarStyle.smallIconSize
                    icon.height: BarStyle.smallIconSize
                    highlighted: notifications.doNotDisturb
                    text: notifications.doNotDisturb ? "Do not disturb" : "Notifications on"
                    onClicked: notifications.doNotDisturb = !notifications.doNotDisturb
                }

                NetworkWidget {
                    id: network
                    panel: bar
                    networkStatus: networkService
                    anchors.right: bluetooth.left
                    anchors.verticalCenter: parent.verticalCenter
                    onOpenChanged: {
                        if (open)
                            bar.closePopovers(network);
                    }
                }

                BluetoothWidget {
                    id: bluetooth
                    panel: bar
                    anchors.right: cooling.left
                    anchors.verticalCenter: parent.verticalCenter
                    onOpenChanged: {
                        if (open)
                            bar.closePopovers(bluetooth);
                    }
                }

                CoolingWidget {
                    id: cooling
                    panel: bar
                    service: coolingService
                    anchors.right: energy.left
                    anchors.verticalCenter: parent.verticalCenter
                    onOpenChanged: {
                        if (open)
                            bar.closePopovers(cooling);
                    }
                }

                EnergyWidget {
                    id: energy
                    panel: bar
                    anchors.right: session.left
                    anchors.verticalCenter: parent.verticalCenter
                    onOpenChanged: {
                        if (open)
                            bar.closePopovers(energy);
                    }
                }

                SessionWidget {
                    id: session
                    panel: bar
                    anchors.right: tray.left
                    anchors.verticalCenter: parent.verticalCenter
                    onOpenChanged: {
                        if (open)
                            bar.closePopovers(session);
                    }
                }

                TrayWidget {
                    id: tray
                    anchors.right: parent.right
                    anchors.rightMargin: Spacing.tight
                    anchors.verticalCenter: parent.verticalCenter
                    onOpenChanged: {
                        if (open)
                            bar.closePopovers(tray);
                    }
                }
            }
        }
    }
}
