// SPDX-License-Identifier: GPL-2.0-or-later
// Chronological history of important events (from the daemon's SQLite store).
// Shows when each event happened and, when it differs, when the monitor detected it.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

ColumnLayout {
    id: view

    required property var client
    required property var labels
    property int limit: 100
    property string kindFilter: "important"   // all | important | attention | errors
    property string textFilter: ""
    property var hiddenProjects: []
    property bool showFilter: true
    property bool active: visible

    property var events: []
    property bool loading: false
    property string error: ""

    readonly property var importantKinds: ["session_start", "session_resumed", "session_recovered", "session_end", "session_lost", "task_start", "task_end", "needs_input", "input_resolved", "permission_denied", "error", "error_acked"]

    spacing: Kirigami.Units.smallSpacing

    function kinds() {
        switch (kindFilter) {
        case "attention":
            return ["needs_input", "input_resolved", "permission_denied"];
        case "errors":
            return ["error", "error_acked", "session_lost", "permission_denied"];
        case "important":
            return importantKinds;
        default:
            return null;
        }
    }

    function reload() {
        if (!active) {
            return;
        }
        loading = true;
        const f = {
            limit: limit
        };
        const k = kinds();
        if (k) {
            f.kinds = k;
        }
        client.history(f, list => {
            loading = false;
            error = "";
            events = list;
        }, msg => {
            loading = false;
            error = msg;
        });
    }

    readonly property var shown: {
        const t = textFilter.toLowerCase();
        return events.filter(e => hiddenProjects.indexOf(e.project) < 0 && (!t || [e.project, labels.eventLabel(e.kind), labels.eventDetail(e)].join(" ").toLowerCase().indexOf(t) >= 0));
    }

    // Reload when the monitor's state changes (debounced) or the view becomes visible.
    Connections {
        target: view.client
        function onDataChanged() {
            reloadTimer.restart();
        }
    }
    Timer {
        id: reloadTimer
        interval: 400
        onTriggered: view.reload()
    }
    onActiveChanged: if (active) {
        reload();
    }
    onKindFilterChanged: reload()
    Component.onCompleted: reload()

    RowLayout {
        Layout.fillWidth: true
        visible: view.showFilter
        spacing: Kirigami.Units.smallSpacing

        PlasmaExtras.SearchField {
            Layout.fillWidth: true
            onTextChanged: view.textFilter = text
        }
        PlasmaComponents3.ComboBox {
            id: kindBox
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    value: "important",
                    text: i18n("Important")
                },
                {
                    value: "attention",
                    text: i18n("Interventions")
                },
                {
                    value: "errors",
                    text: i18n("Errors")
                },
                {
                    value: "all",
                    text: i18n("Everything")
                }
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(view.kindFilter))
            onActivated: view.kindFilter = currentValue
        }
    }

    PlasmaComponents3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        contentItem: ListView {
            id: list
            clip: true
            model: view.shown
            spacing: 0
            reuseItems: true

            PlasmaExtras.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                visible: list.count === 0 && !view.loading
                iconName: "view-history-symbolic"
                text: view.error ? i18n("History unavailable") : i18n("No events yet")
                explanation: view.error
            }

            delegate: RowLayout {
                id: ev
                required property var modelData
                width: ListView.view.width
                spacing: Kirigami.Units.smallSpacing

                readonly property double lag: modelData.detected_time - modelData.event_time

                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                    text: view.labels.clock(ev.modelData.event_time)
                    font.features: {
                        "tnum": 1
                    }
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                    elide: Text.ElideRight
                    HoverHandler {
                        id: timeHover
                    }
                    PlasmaComponents3.ToolTip.text: i18n("Happened: %1\nDetected: %2", view.labels.clockSeconds(ev.modelData.event_time), view.labels.clockSeconds(ev.modelData.detected_time))
                    PlasmaComponents3.ToolTip.visible: timeHover.hovered
                }
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    source: view.labels.eventIcon(ev.modelData.kind)
                    color: view.labels.eventColor(ev.modelData.kind)
                    isMask: true
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: view.labels.eventLabel(ev.modelData.kind) + (ev.modelData.project ? " · " + ev.modelData.project : "")
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.weight: ev.modelData.kind === "needs_input" || ev.modelData.kind === "error" ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        readonly property string d: view.labels.eventDetail(ev.modelData)
                        visible: d.length > 0
                        text: d
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.65
                        elide: Text.ElideRight
                    }
                    PlasmaComponents3.Label {
                        visible: ev.lag >= 5000
                        text: i18n("detected %1 later", view.labels.duration(ev.lag))
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.italic: true
                        opacity: 0.5
                    }
                }
            }
        }
    }
}
