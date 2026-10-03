// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_showWorkingCount: showWorkingCount.checked
    property alias cfg_showErrorDot: showErrorDot.checked
    property string cfg_compactStyle
    property alias cfg_glowOnAttention: glowOnAttention.checked
    property alias cfg_animateWorking: animateWorking.checked
    property alias cfg_pulseOnAttention: pulseOnAttention.checked
    property alias cfg_flashOnFinish: flashOnFinish.checked
    property string cfg_density
    property string cfg_defaultFilter
    property alias cfg_groupByState: groupByState.checked
    property string cfg_defaultSort
    property alias cfg_showCompleted: showCompleted.checked
    property alias cfg_showIdle: showIdle.checked
    property alias cfg_showEnded: showEnded.checked
    property alias cfg_hiddenProjects: hiddenProjects.text
    property alias cfg_historyLimit: historyLimit.value
    property alias cfg_hooksHintDismissed: hooksHint.checked

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Panel icon style:")
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    value: "pills",
                    text: i18n("Icon with counters next to it")
                },
                {
                    value: "badges",
                    text: i18n("Icon with small badges")
                }
            ]
            currentIndex: Math.max(0, indexOfValue(cfg_compactStyle))
            onActivated: cfg_compactStyle = currentValue
        }
        QQC2.Label {
            text: i18n("Vertical panels always use badges.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        QQC2.CheckBox {
            id: showWorkingCount
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("Number of tasks in progress")
        }
        QQC2.CheckBox {
            id: showErrorDot
            text: i18n("Errors")
        }
        QQC2.CheckBox {
            id: glowOnAttention
            Kirigami.FormData.label: i18n("Effects:")
            text: i18n("Red halo while a session needs me")
        }
        QQC2.CheckBox {
            id: pulseOnAttention
            text: i18n("Pulse when a session needs me")
        }
        QQC2.CheckBox {
            id: animateWorking
            text: i18n("Spinning ring while tasks are in progress")
        }
        QQC2.CheckBox {
            id: flashOnFinish
            text: i18n("Flash when a task finishes")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Popup")
        }
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
                }
            ]
            currentIndex: Math.max(0, indexOfValue(cfg_density))
            onActivated: cfg_density = currentValue
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
        QQC2.CheckBox {
            id: groupByState
            Kirigami.FormData.label: i18n("Order:")
            text: i18n("Group by priority")
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Sort within groups by:")
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
        QQC2.Label {
            text: i18n("Sessions waiting for you always stay on top.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Visibility")
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
        QQC2.TextField {
            id: hiddenProjects
            Kirigami.FormData.label: i18n("Hidden projects:")
            placeholderText: i18n("comma-separated folder names")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        }
        QQC2.SpinBox {
            id: historyLimit
            Kirigami.FormData.label: i18n("History entries:")
            from: 10
            to: 1000
            stepSize: 10
        }
        QQC2.CheckBox {
            id: hooksHint
            text: i18n("Hide the tip about Claude Code hooks")
        }
    }
}
