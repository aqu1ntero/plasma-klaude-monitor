// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property string cfg_density
    property alias cfg_showKpis: showKpis.checked
    property alias cfg_showPending: showPending.checked
    property alias cfg_showSessions: showSessions.checked
    property alias cfg_showHistory: showHistory.checked
    property string cfg_defaultFilter
    property string cfg_defaultSort
    property alias cfg_groupByState: groupByState.checked
    property alias cfg_showCompleted: showCompleted.checked
    property alias cfg_showIdle: showIdle.checked
    property alias cfg_showEnded: showEnded.checked
    property alias cfg_hiddenProjects: hiddenProjects.text
    property alias cfg_showCwd: showCwd.checked
    property alias cfg_showSessionId: showSessionId.checked
    property alias cfg_historyLimit: historyLimit.value
    property string cfg_historyFilter
    property alias cfg_hooksHintDismissed: hooksHint.checked

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Density:")
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    value: "compact",
                    text: i18n("Compact")
                },
                {
                    value: "normal",
                    text: i18n("Normal")
                },
                {
                    value: "comfortable",
                    text: i18n("Comfortable")
                }
            ]
            currentIndex: Math.max(0, indexOfValue(cfg_density))
            onActivated: cfg_density = currentValue
        }

        QQC2.CheckBox {
            id: showKpis
            Kirigami.FormData.label: i18n("Sections:")
            text: i18n("Summary counters")
        }
        QQC2.CheckBox {
            id: showPending
            text: i18n("Pending interventions")
        }
        QQC2.CheckBox {
            id: showSessions
            text: i18n("Session list")
        }
        QQC2.CheckBox {
            id: showHistory
            text: i18n("Activity history")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Session list")
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Default filter:")
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
                    text: i18n("Needs you")
                },
                {
                    value: "working",
                    text: i18n("Working")
                },
                {
                    value: "error",
                    text: i18n("Error")
                }
            ]
            currentIndex: Math.max(0, indexOfValue(cfg_defaultFilter))
            onActivated: cfg_defaultFilter = currentValue
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Default order:")
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
            currentIndex: Math.max(0, indexOfValue(cfg_defaultSort))
            onActivated: cfg_defaultSort = currentValue
        }
        QQC2.CheckBox {
            id: groupByState
            text: i18n("Group by state")
        }
        QQC2.Label {
            text: i18n("Sessions waiting for you always stay on top.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        QQC2.CheckBox {
            id: showCompleted
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("Recently completed sessions")
        }
        QQC2.CheckBox {
            id: showIdle
            text: i18n("Idle sessions")
        }
        QQC2.CheckBox {
            id: showEnded
            text: i18n("Ended sessions")
        }
        QQC2.CheckBox {
            id: showCwd
            text: i18n("Working directory")
        }
        QQC2.CheckBox {
            id: showSessionId
            text: i18n("Session identifier")
        }
        QQC2.TextField {
            id: hiddenProjects
            Kirigami.FormData.label: i18n("Hidden projects:")
            placeholderText: i18n("comma-separated folder names")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("History")
        }
        QQC2.SpinBox {
            id: historyLimit
            Kirigami.FormData.label: i18n("Entries shown:")
            from: 10
            to: 2000
            stepSize: 10
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Events shown:")
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
            currentIndex: Math.max(0, indexOfValue(cfg_historyFilter))
            onActivated: cfg_historyFilter = currentValue
        }
        QQC2.Label {
            text: i18n("How long history is kept is set in the Monitor page (shared by both widgets).")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
        }
        QQC2.CheckBox {
            id: hooksHint
            Kirigami.FormData.label: i18n("Tips:")
            text: i18n("Hide the tip about Claude Code hooks")
        }
    }
}
