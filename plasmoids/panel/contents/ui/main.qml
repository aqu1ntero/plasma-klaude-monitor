// SPDX-License-Identifier: GPL-2.0-or-later
// Klaude Monitor — panel widget. A client of the shared klaude-monitord service; it runs no
// monitor of its own, so it can be added, removed or restarted without affecting anything else.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "shared"

PlasmoidItem {
    id: root

    readonly property int needs: monitor.count("needs_input")
    readonly property int working: monitor.count("working")
    readonly property int errors: monitor.count("error")
    readonly property int completed: monitor.count("completed")
    readonly property int unknown: monitor.count("unknown")

    // Visual pulses, consumed by the compact representation.
    signal attentionPulse
    signal finishPulse

    Plasmoid.icon: "klaude-monitor"
    Plasmoid.status: needs > 0 ? PlasmaCore.Types.NeedsAttentionStatus : (working > 0 || errors > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus)

    toolTipMainText: i18n("Klaude Monitor")
    toolTipSubText: {
        if (!monitor.connected) {
            return monitor.notInstalled ? i18n("The monitor service is not installed") : i18n("Connecting to the monitor…");
        }
        const parts = [];
        if (needs > 0)
            parts.push(i18np("%1 needs you", "%1 need you", needs));
        if (working > 0)
            parts.push(i18n("%1 working", working));
        if (completed > 0)
            parts.push(i18n("%1 recently completed", completed));
        if (errors > 0)
            parts.push(i18np("%1 error", "%1 errors", errors));
        if (unknown > 0)
            parts.push(i18n("%1 unknown", unknown));
        let text = parts.length ? parts.join(" · ") : i18n("No active Claude sessions");
        const waitingOnes = monitor.sessions.filter(s => s.state === "needs_input").slice(0, 4);
        for (const s of waitingOnes) {
            text += "\n• " + s.project + ": " + texts.waitingText(s.waiting);
        }
        return text;
    }

    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
        client: monitor
        labels: texts
    }

    fullRepresentation: FullRepresentation {
        plasmoidItem: root
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
        onAttention: if (Plasmoid.configuration.pulseOnAttention) {
            root.attentionPulse();
        }
        onFinished: if (Plasmoid.configuration.flashOnFinish) {
            root.finishPulse();
        }
    }

    Labels {
        id: texts
    }
}
