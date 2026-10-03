// SPDX-License-Identifier: GPL-2.0-or-later
// Panel popup: sessions grouped by priority (needs you, in progress, recently completed, errors…),
// a filter, the recent history and a shortcut to the settings.
import QtQuick
import QtQuick.Layouts
import Qt.labs.qmlmodels
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import "shared"
import "shared/logic.js" as Logic

PlasmaExtras.Representation {
    id: full

    required property var plasmoidItem
    required property var client
    required property var labels

    property string stateFilter: Plasmoid.configuration.defaultFilter
    property string searchText: ""
    property string feedbackText: ""
    property bool feedbackOk: true
    // The service setup card replaces the session list when the service is missing (or on request,
    // when a newer bundled version can be installed).
    property bool showSetup: false
    readonly property bool setupVisible: setupCard.mode === "install" || (showSetup && setupCard.needed)

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 14
    Layout.preferredWidth: Kirigami.Units.gridUnit * 26
    Layout.preferredHeight: Kirigami.Units.gridUnit * 30
    collapseMarginsHint: true

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
            showCompleted: Plasmoid.configuration.showCompleted,
            showIdle: Plasmoid.configuration.showIdle,
            showEnded: Plasmoid.configuration.showEnded,
            hiddenProjects: Logic.parseList(Plasmoid.configuration.hiddenProjects)
        });
        Logic.sync(rowModel, Logic.rows(Logic.sort(list, Plasmoid.configuration.defaultSort), Plasmoid.configuration.groupByState));
    }

    Connections {
        target: full.client
        function onDataChanged() {
            full.rebuild();
        }
    }
    Connections {
        target: Plasmoid.configuration
        function onValueChanged() {
            full.rebuild();
        }
    }
    onStateFilterChanged: rebuild()
    onSearchTextChanged: rebuild()
    Component.onCompleted: rebuild()

    Timer {
        id: feedbackTimer
        interval: 5000
        onTriggered: full.feedbackText = ""
    }

    ListModel {
        id: rowModel
    }

    header: PlasmaExtras.PlasmoidHeading {
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.TabBar {
                    id: tabs
                    Layout.fillWidth: true
                    PlasmaComponents3.TabButton {
                        text: full.plasmoidItem.needs > 0 ? i18n("Sessions (%1 need you)", full.plasmoidItem.needs) : i18n("Sessions")
                        icon.name: "utilities-terminal-symbolic"
                    }
                    PlasmaComponents3.TabButton {
                        text: i18n("History")
                        icon.name: "view-history-symbolic"
                    }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "configure"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    text: Plasmoid.internalAction("configure").text
                    PlasmaComponents3.ToolTip.text: text
                    PlasmaComponents3.ToolTip.visible: hovered
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: tabs.currentIndex === 0 && !full.setupVisible
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.SearchField {
                    id: search
                    Layout.fillWidth: true
                    onTextChanged: full.searchText = text
                }
                PlasmaComponents3.ComboBox {
                    id: stateBox
                    textRole: "text"
                    valueRole: "value"
                    model: [
                        {
                            value: "all",
                            text: i18n("All")
                        },
                        {
                            value: "active",
                            text: i18n("Active")
                        },
                        {
                            value: "needs_input",
                            text: full.labels.stateLabel("needs_input")
                        },
                        {
                            value: "working",
                            text: full.labels.stateLabel("working")
                        },
                        {
                            value: "completed",
                            text: full.labels.stateLabel("completed")
                        },
                        {
                            value: "error",
                            text: full.labels.stateLabel("error")
                        },
                        {
                            value: "unknown",
                            text: full.labels.stateLabel("unknown")
                        }
                    ]
                    Component.onCompleted: currentIndex = Math.max(0, indexOfValue(full.stateFilter))
                    onActivated: full.stateFilter = currentValue
                }
            }
        }
    }

    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaComponents3.ToolBar.Footer
        contentItem: RowLayout {
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: full.feedbackText || (full.client.connected ? i18n("Updated %1", full.labels.ago(full.client.monitorInfo.lastScan, full.client.now)) : "")
                color: full.feedbackText && !full.feedbackOk ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                opacity: full.feedbackText ? 1 : 0.6
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                visible: full.client.connected
                text: i18n("%1 sessions", full.client.counts.total || 0)
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: !full.client.connected && full.client.failures > 0 && !full.client.notInstalled
            type: Kirigami.MessageType.Warning
            text: i18n("Cannot reach the monitor service: %1", full.client.errorText)
            actions: [
                Kirigami.Action {
                    text: i18n("Retry")
                    icon.name: "view-refresh"
                    onTriggered: full.client.refresh()
                }
            ]
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: setupCard.mode === "update" && !full.showSetup
            type: Kirigami.MessageType.Information
            text: i18n("This widget includes a newer version of the monitor service.")
            actions: [
                Kirigami.Action {
                    text: i18n("Update…")
                    icon.name: "update-none"
                    onTriggered: full.showSetup = true
                }
            ]
        }

        PlasmaComponents3.ScrollView {
            id: setupScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: full.setupVisible
            PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

            contentItem: Flickable {
                contentHeight: setupCard.implicitHeight + Kirigami.Units.largeSpacing * 2
                clip: true
                ServiceSetup {
                    id: setupCard
                    x: Kirigami.Units.largeSpacing
                    y: Kirigami.Units.largeSpacing
                    width: setupScroll.availableWidth - Kirigami.Units.largeSpacing * 2
                    client: full.client
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: full.client.connected && !full.client.hooks && !Plasmoid.configuration.hooksHintDismissed && full.client.sessions.length > 0
            type: Kirigami.MessageType.Information
            text: i18n("Tip: install the Claude Code hooks to see the exact question or permission each session waits for: klaude-monitor hooks install")
            showCloseButton: true
            onVisibleChanged: if (!visible && full.client.connected && !full.client.hooks && full.client.sessions.length > 0) {
                Plasmoid.configuration.hooksHintDismissed = true;
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !full.setupVisible
            currentIndex: tabs.currentIndex

            PlasmaComponents3.ScrollView {
                PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                contentItem: ListView {
                    id: list
                    clip: true
                    model: rowModel
                    spacing: 0
                    highlightMoveDuration: 0
                    keyNavigationEnabled: true

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: list.count === 0 && full.client.connected
                        iconName: "utilities-terminal-symbolic"
                        text: full.client.sessions.length === 0 ? i18n("No Claude Code sessions") : i18n("No sessions match the filter")
                        explanation: full.client.sessions.length === 0 ? i18n("Sessions appear here as soon as Claude Code starts.") : ""
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
                                labels: full.labels
                            }
                        }
                        DelegateChoice {
                            roleValue: "session"
                            SessionRow {
                                required property string payload
                                session: JSON.parse(payload)
                                labels: full.labels
                                client: full.client
                                dense: Plasmoid.configuration.density === "compact"
                                onFeedback: (text, ok) => full.showFeedback(text, ok)
                            }
                        }
                    }
                }
            }

            HistoryView {
                client: full.client
                labels: full.labels
                hiddenProjects: Logic.parseList(Plasmoid.configuration.hiddenProjects)
                limit: Plasmoid.configuration.historyLimit
                active: tabs.currentIndex === 1 && full.plasmoidItem.expanded
            }
        }
    }
}
