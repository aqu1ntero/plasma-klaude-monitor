// SPDX-License-Identifier: GPL-2.0-or-later
// Klaude Monitor — desktop dashboard. Same data and service as the panel widget; no monitor of
// its own. Resizable: two columns when wide, tabs when narrow.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "shared"

PlasmoidItem {
    id: root

    readonly property int needs: monitor.count("needs_input")

    Plasmoid.icon: "klaude-monitor"
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    Plasmoid.status: needs > 0 ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus

    // On the desktop the dashboard is shown directly; squeezed into a panel it becomes an icon.
    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 12

    toolTipMainText: i18n("Klaude Monitor")
    toolTipSubText: needs > 0 ? i18np("%1 session needs you", "%1 sessions need you", needs) : i18n("%1 sessions", monitor.counts.total || 0)

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl("../images/klaude-monitor.svg")
        }
        Rectangle {
            visible: root.needs > 0
            anchors.top: parent.top
            anchors.right: parent.right
            width: Math.max(height, badge.implicitWidth + 4)
            height: parent.height * 0.45
            radius: height / 2
            color: Kirigami.Theme.negativeTextColor
            PlasmaComponents3.Label {
                id: badge
                anchors.centerIn: parent
                text: root.needs
                color: "white"
                font.bold: true
                font.pixelSize: parent.height * 0.7
            }
        }
    }

    fullRepresentation: Dashboard {
        client: monitor
        labels: texts
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: monitor.refresh()
        }
    ]

    MonitorClient {
        id: monitor
    }

    Labels {
        id: texts
    }
}
