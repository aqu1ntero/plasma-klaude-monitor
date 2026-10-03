// SPDX-License-Identifier: GPL-2.0-or-later
// Desktop dashboard: KPIs, pending interventions, detailed session list and activity history.
import QtQuick
import QtQuick.Layouts
import Qt.labs.qmlmodels
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import "shared"
import "shared/logic.js" as Logic

Item {
    id: dash

    required property var client
    required property var labels

    readonly property var cfg: Plasmoid.configuration
    property string stateFilter: cfg.defaultFilter
    property string projectFilter: ""
    property string sortKey: cfg.defaultSort
    property string searchText: ""
    property string feedbackText: ""
    property bool feedbackOk: true
    property bool showSetup: false
    readonly property bool setupVisible: setupCard.mode === "install" || (showSetup && setupCard.needed)

    readonly property bool wide: width >= Kirigami.Units.gridUnit * 38
    readonly property var sections: {
        const s = [];
        if (cfg.showPending)
            s.push("pending");
        if (cfg.showSessions)
            s.push("sessions");
        if (cfg.showHistory)
            s.push("history");
        return s;
    }
    readonly property var pendingList: client.sessions.filter(s => s.state === "needs_input" || s.state === "error")
    readonly property var projectList: Logic.projects(client.sessions)
    property string currentTab: sections.length ? sections[0] : ""

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.minimumHeight: Kirigami.Units.gridUnit * 14
    Layout.preferredWidth: Kirigami.Units.gridUnit * 46
    Layout.preferredHeight: Kirigami.Units.gridUnit * 30

    function showFeedback(text, ok) {
        if (!text) {
            return;
        }
        feedbackText = text;
        feedbackOk = ok;
        feedbackTimer.restart();
    }

    function rebuild() {
        const list = Logic.filter(client.sessions, {
            text: searchText,
            state: stateFilter,
            project: projectFilter,
            showCompleted: cfg.showCompleted,
            showIdle: cfg.showIdle,
            showEnded: cfg.showEnded,
            hiddenProjects: Logic.parseList(cfg.hiddenProjects)
        });
        Logic.sync(sessionModel, Logic.rows(Logic.sort(list, sortKey), cfg.groupByState));
    }

    Connections {
        target: dash.client
        function onDataChanged() {
            dash.rebuild();
        }
    }
    Connections {
        target: Plasmoid.configuration
        function onValueChanged() {
            dash.rebuild();
        }
    }
    onStateFilterChanged: rebuild()
    onProjectFilterChanged: rebuild()
    onSortKeyChanged: rebuild()
    onSearchTextChanged: rebuild()
    onSectionsChanged: if (sections.indexOf(currentTab) < 0) {
        currentTab = sections.length ? sections[0] : "";
    }
    Component.onCompleted: rebuild()

    Timer {
        id: feedbackTimer
        interval: 5000
        onTriggered: dash.feedbackText = ""
    }

    ListModel {
        id: sessionModel
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ---- header ------------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                source: Qt.resolvedUrl("../images/klaude-monitor.svg")
            }
            Kirigami.Heading {
                Layout.fillWidth: true
                level: 3
                text: i18n("Claude Code sessions")
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                text: dash.feedbackText
                visible: text.length > 0
                color: dash.feedbackOk ? Kirigami.Theme.textColor : Kirigami.Theme.neutralTextColor
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
                Layout.maximumWidth: dash.width * 0.5
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh-symbolic"
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: i18n("Refresh")
                onClicked: dash.client.refresh()
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
            }
            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: Plasmoid.internalAction("configure").text
                onClicked: Plasmoid.internalAction("configure").trigger()
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
            }
        }

        // ---- KPIs --------------------------------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            visible: dash.cfg.showKpis && !dash.setupVisible
            columns: dash.width < Kirigami.Units.gridUnit * 24 ? 3 : 5
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.smallSpacing

            KpiTile {
                value: String(dash.client.count("needs_input"))
                label: i18n("Need you")
                accent: dash.labels.stateColor("needs_input")
                highlighted: dash.client.count("needs_input") > 0
                selected: dash.stateFilter === "needs_input"
                hint: i18n("Sessions waiting for a permission, an answer or an approval")
                onClicked: dash.stateFilter = dash.stateFilter === "needs_input" ? "all" : "needs_input"
            }
            KpiTile {
                value: String(dash.client.count("working"))
                label: i18n("In progress")
                accent: dash.labels.stateColor("working")
                selected: dash.stateFilter === "working"
                onClicked: dash.stateFilter = dash.stateFilter === "working" ? "all" : "working"
            }
            KpiTile {
                value: String(dash.client.count("completed"))
                label: i18n("Completed")
                accent: dash.labels.stateColor("completed")
                selected: dash.stateFilter === "completed"
                hint: i18n("Tasks finished in the last %1 minutes", dash.client.monitorInfo.recentWindowMin || 30)
                onClicked: dash.stateFilter = dash.stateFilter === "completed" ? "all" : "completed"
            }
            KpiTile {
                value: String(dash.client.count("error"))
                label: i18n("Errors")
                accent: dash.labels.stateColor("error")
                highlighted: dash.client.count("error") > 0
                selected: dash.stateFilter === "error"
                hint: dash.client.count("unknown") > 0 ? i18n("Plus %1 sessions in an unknown state", dash.client.count("unknown")) : i18n("Errors that need a review")
                onClicked: dash.stateFilter = dash.stateFilter === "error" ? "all" : "error"
            }
            KpiTile {
                value: dash.client.connected ? dash.labels.ago(dash.client.monitorInfo.lastScan, dash.client.now) : "—"
                label: i18n("Last update")
                accent: dash.client.connected ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                clickable: false
                hint: dash.client.connected ? i18n("Monitor %1, %2", dash.client.monitorInfo.version, dash.client.hooks ? i18n("hooks active") : i18n("no hooks (state files only)")) : dash.client.errorText
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: !dash.client.connected && dash.client.failures > 0 && !dash.client.notInstalled
            type: Kirigami.MessageType.Warning
            text: i18n("Cannot reach the monitor service: %1", dash.client.errorText)
            actions: [
                Kirigami.Action {
                    text: i18n("Retry")
                    icon.name: "view-refresh"
                    onTriggered: dash.client.refresh()
                }
            ]
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: dash.client.connected && !dash.client.hooks && !dash.cfg.hooksHintDismissed && dash.client.sessions.length > 0
            type: Kirigami.MessageType.Information
            text: i18n("Install the Claude Code hooks to see exactly which question or permission each session waits for: klaude-monitor hooks install")
            showCloseButton: true
            onVisibleChanged: if (!visible && dash.client.connected && !dash.client.hooks && dash.client.sessions.length > 0) {
                Plasmoid.configuration.hooksHintDismissed = true;
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: setupCard.mode === "update" && !dash.showSetup
            type: Kirigami.MessageType.Information
            text: i18n("This widget includes a newer version of the monitor service.")
            actions: [
                Kirigami.Action {
                    text: i18n("Update…")
                    icon.name: "update-none"
                    onTriggered: dash.showSetup = true
                }
            ]
        }

        PlasmaComponents3.ScrollView {
            id: setupScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: dash.setupVisible
            PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

            contentItem: Flickable {
                contentHeight: setupCard.implicitHeight + Kirigami.Units.largeSpacing * 2
                clip: true
                ServiceSetup {
                    id: setupCard
                    x: Math.max(Kirigami.Units.largeSpacing, (setupScroll.availableWidth - width) / 2)
                    y: Kirigami.Units.largeSpacing
                    width: Math.min(setupScroll.availableWidth - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 36)
                    client: dash.client
                }
            }
        }

        // ---- tabs (narrow layout) ----------------------------------------------------------
        PlasmaComponents3.TabBar {
            id: tabBar
            Layout.fillWidth: true
            visible: !dash.wide && dash.sections.length > 1 && !dash.setupVisible
            currentIndex: Math.max(0, dash.sections.indexOf(dash.currentTab))
            onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex < dash.sections.length) {
                dash.currentTab = dash.sections[currentIndex];
            }
            Repeater {
                model: dash.sections
                PlasmaComponents3.TabButton {
                    required property string modelData
                    text: modelData === "pending" ? (dash.pendingList.length ? i18n("Pending (%1)", dash.pendingList.length) : i18n("Pending")) : (modelData === "sessions" ? i18n("Sessions") : i18n("History"))
                }
            }
        }

        // ---- body --------------------------------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !dash.setupVisible
            columns: dash.wide ? 2 : 1
            rowSpacing: Kirigami.Units.largeSpacing
            columnSpacing: Kirigami.Units.largeSpacing

            // Sessions (left column when wide)
            ColumnLayout {
                id: sessionsSection
                visible: dash.cfg.showSessions && (dash.wide || dash.currentTab === "sessions")
                Layout.row: 0
                Layout.column: 0
                Layout.rowSpan: dash.wide ? 2 : 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: dash.wide ? 60 : 100
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        visible: dash.wide
                        level: 4
                        text: i18n("Sessions")
                    }
                    PlasmaExtras.SearchField {
                        Layout.fillWidth: true
                        onTextChanged: dash.searchText = text
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.ComboBox {
                        id: stateCombo
                        textRole: "text"
                        valueRole: "value"
                        model: [
                            {
                                value: "all",
                                text: i18n("All states")
                            },
                            {
                                value: "active",
                                text: i18n("Active")
                            },
                            {
                                value: "needs_input",
                                text: dash.labels.stateLabel("needs_input")
                            },
                            {
                                value: "working",
                                text: dash.labels.stateLabel("working")
                            },
                            {
                                value: "completed",
                                text: dash.labels.stateLabel("completed")
                            },
                            {
                                value: "error",
                                text: dash.labels.stateLabel("error")
                            },
                            {
                                value: "unknown",
                                text: dash.labels.stateLabel("unknown")
                            },
                            {
                                value: "idle",
                                text: dash.labels.stateLabel("idle")
                            },
                            {
                                value: "ended",
                                text: dash.labels.stateLabel("ended")
                            }
                        ]
                        currentIndex: Math.max(0, indexOfValue(dash.stateFilter))
                        onActivated: dash.stateFilter = currentValue
                    }
                    PlasmaComponents3.ComboBox {
                        model: [i18n("All projects")].concat(dash.projectList)
                        currentIndex: Math.max(0, dash.projectList.indexOf(dash.projectFilter) + 1)
                        onActivated: index => dash.projectFilter = index === 0 ? "" : dash.projectList[index - 1]
                    }
                    PlasmaComponents3.ComboBox {
                        textRole: "text"
                        valueRole: "value"
                        model: [
                            {
                                value: "activity",
                                text: i18n("Recent activity")
                            },
                            {
                                value: "since",
                                text: i18n("Last state change")
                            },
                            {
                                value: "project",
                                text: i18n("Project")
                            },
                            {
                                value: "state",
                                text: i18n("State")
                            }
                        ]
                        currentIndex: Math.max(0, indexOfValue(dash.sortKey))
                        onActivated: dash.sortKey = currentValue
                    }
                }

                PlasmaComponents3.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                    contentItem: ListView {
                        id: sessionList
                        clip: true
                        model: sessionModel
                        spacing: 0

                        PlasmaExtras.PlaceholderMessage {
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.gridUnit * 2
                            visible: sessionList.count === 0 && dash.client.connected
                            iconName: "utilities-terminal-symbolic"
                            text: dash.client.sessions.length === 0 ? i18n("No Claude Code sessions") : i18n("No sessions match the filters")
                        }

                        delegate: DelegateChooser {
                            role: "kind"
                            DelegateChoice {
                                roleValue: "header"
                                GroupHeader {
                                    required property string payload
                                    readonly property var info: JSON.parse(payload)
                                    groupState: info.state
                                    count: info.count
                                    labels: dash.labels
                                }
                            }
                            DelegateChoice {
                                roleValue: "session"
                                SessionCard {
                                    required property string payload
                                    session: JSON.parse(payload)
                                    labels: dash.labels
                                    client: dash.client
                                    density: dash.cfg.density
                                    showCwd: dash.cfg.showCwd
                                    showId: dash.cfg.showSessionId
                                    onFeedback: (text, ok) => dash.showFeedback(text, ok)
                                }
                            }
                        }
                    }
                }
            }

            // Pending interventions
            ColumnLayout {
                id: pendingSection
                visible: dash.cfg.showPending && (dash.wide || dash.currentTab === "pending")
                Layout.row: dash.wide ? 0 : 0
                Layout.column: dash.wide ? 1 : 0
                Layout.fillWidth: true
                Layout.fillHeight: !dash.wide || !dash.cfg.showHistory
                Layout.preferredWidth: dash.wide ? 40 : 100
                Layout.maximumHeight: dash.wide && dash.cfg.showHistory ? Math.max(Kirigami.Units.gridUnit * 6, pendingCol.implicitHeight + Kirigami.Units.gridUnit * 2) : -1
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    visible: dash.wide
                    level: 4
                    text: dash.pendingList.length ? i18n("Pending (%1)", dash.pendingList.length) : i18n("Pending")
                    color: dash.client.count("needs_input") > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                }

                PlasmaComponents3.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                    contentItem: Flickable {
                        contentHeight: pendingCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: pendingCol
                            width: parent.width
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                visible: dash.pendingList.length === 0
                                text: i18n("Nothing needs you right now.")
                                opacity: 0.6
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Repeater {
                                model: dash.pendingList
                                delegate: PendingItem {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    session: modelData
                                    labels: dash.labels
                                    client: dash.client
                                    onFeedback: (text, ok) => dash.showFeedback(text, ok)
                                }
                            }
                        }
                    }
                }
            }

            // History
            ColumnLayout {
                id: historySection
                visible: dash.cfg.showHistory && (dash.wide || dash.currentTab === "history")
                Layout.row: dash.wide ? 1 : 0
                Layout.column: dash.wide ? 1 : 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: dash.wide ? 40 : 100
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    visible: dash.wide
                    level: 4
                    text: i18n("Activity")
                }
                HistoryView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    client: dash.client
                    labels: dash.labels
                    hiddenProjects: Logic.parseList(dash.cfg.hiddenProjects)
                    limit: dash.cfg.historyLimit
                    kindFilter: dash.cfg.historyFilter
                    active: historySection.visible
                }
            }
        }
    }
}
