// SPDX-License-Identifier: GPL-2.0-or-later
// Detailed session card (desktop widget).
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Item {
    id: card

    required property var session
    required property var labels
    required property var client
    property string density: "normal"   // compact | normal | comfortable
    property bool showCwd: true
    property bool showId: true

    signal feedback(string text, bool ok)

    readonly property bool waiting: session.state === "needs_input"
    readonly property bool canFocus: session.focusable
    readonly property bool canResume: !session.alive && (session.state === "ended" || session.state === "unknown")
    readonly property bool compact: density === "compact"
    readonly property real pad: compact ? Kirigami.Units.smallSpacing : (density === "comfortable" ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing * 2)

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: body.implicitHeight + pad * 2 + Kirigami.Units.smallSpacing

    function activate() {
        if (canFocus) {
            client.focusSession(session.id, r => card.feedback(r.ok ? "" : i18n("Could not focus the terminal: %1", r.message), r.ok));
        } else if (canResume) {
            client.resumeSession(session.id, r => card.feedback(r.ok ? i18n("Opened a terminal to resume the session") : i18n("Could not resume: %1", r.message), r.ok));
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: card.waiting ? Qt.alpha(Kirigami.Theme.negativeTextColor, 0.10) : Qt.alpha(Kirigami.Theme.textColor, hover.hovered ? 0.07 : 0.04)
        border.width: card.waiting ? 1 : 0
        border.color: Qt.alpha(Kirigami.Theme.negativeTextColor, 0.6)

        Rectangle {
            width: 3
            radius: 1.5
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
                margins: card.pad / 2
            }
            color: card.labels.stateColor(card.session.state)
        }
        HoverHandler {
            id: hover
        }
        TapHandler {
            onDoubleTapped: card.activate()
        }
    }

    ColumnLayout {
        id: body
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: card.pad
            leftMargin: card.pad + Kirigami.Units.smallSpacing * 2
        }
        spacing: card.compact ? 0 : Kirigami.Units.smallSpacing / 2

        // Line 1: project, account, title, state chip
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: card.labels.stateIcon(card.session.state)
                color: card.labels.stateColor(card.session.state)
                isMask: true
            }
            PlasmaComponents3.Label {
                text: card.session.project
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.maximumWidth: Math.min(implicitWidth, body.width * 0.45)
            }
            PlasmaComponents3.Label {
                visible: !!card.session.accountLabel
                text: "[" + card.session.accountLabel + "]"
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: card.session.title && card.session.title !== card.session.project ? card.session.title : ""
                elide: Text.ElideRight
                opacity: 0.8
            }
            Rectangle {
                implicitWidth: chip.implicitWidth + Kirigami.Units.smallSpacing * 2
                implicitHeight: chip.implicitHeight + 2
                radius: height / 2
                color: Qt.alpha(card.labels.stateColor(card.session.state), 0.18)
                PlasmaComponents3.Label {
                    id: chip
                    anchors.centerIn: parent
                    text: card.labels.stateLabel(card.session.state) + (card.session.certainty !== "high" ? " · " + card.labels.certaintyLabel(card.session.certainty) : "")
                    font: Kirigami.Theme.smallFont
                    color: card.labels.stateColor(card.session.state)
                }
                HoverHandler {
                    id: chipHover
                }
                PlasmaComponents3.ToolTip.text: card.labels.certaintyTooltip(card.session)
                PlasmaComponents3.ToolTip.visible: chipHover.hovered
            }
        }

        // Pending intervention (highlighted)
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: card.waiting
            text: card.labels.waitingText(card.session.waiting)
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.weight: Font.DemiBold
            color: Kirigami.Theme.textColor
        }

        // What it is doing / result / error
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: !card.waiting && text.length > 0
            text: card.labels.detail(card.session)
            wrapMode: card.compact ? Text.NoWrap : Text.Wrap
            maximumLineCount: card.compact ? 1 : 3
            elide: Text.ElideRight
            color: card.session.state === "error" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            opacity: card.session.state === "error" ? 1 : 0.85
        }

        // Last event summary (Claude's recap or last prompt), when it adds something
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            readonly property string extra: card.session.summary && card.labels.detail(card.session) !== card.session.summary ? card.session.summary : (card.session.prompt && card.session.state !== "working" && card.session.prompt !== card.session.title ? "› " + card.session.prompt : "")
            visible: !card.compact && extra.length > 0
            text: extra
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
            opacity: 0.65
        }

        // Meta line: times, terminal, cwd, id
        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            visible: true

            PlasmaComponents3.Label {
                text: card.labels.stateLabel(card.session.state) + " · " + card.labels.ago(card.session.since, card.client.now)
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
            PlasmaComponents3.Label {
                visible: !!card.session.lastActivity
                text: i18n("activity %1", card.labels.ago(card.session.lastActivity, card.client.now))
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
            PlasmaComponents3.Label {
                visible: !!card.session.lastEvent
                text: card.session.lastEvent ? i18n("last event: %1", card.labels.eventLabel(card.session.lastEvent.kind)) : ""
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
            PlasmaComponents3.Label {
                visible: !!card.session.terminal
                text: card.labels.terminalLabel(card.session)
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
            PlasmaComponents3.Label {
                visible: !!card.session.model && !card.compact
                text: card.session.model || ""
                font: Kirigami.Theme.smallFont
                opacity: 0.5
            }
            PlasmaComponents3.Label {
                visible: card.showCwd && !card.compact && !!card.session.cwd
                text: card.labels.shortPath(card.session.cwd) + (card.session.branch ? " (" + card.session.branch + ")" : "")
                font: Kirigami.Theme.smallFont
                opacity: 0.5
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, body.width)
            }
            PlasmaComponents3.Label {
                visible: card.showId && !card.compact
                text: card.session.id.slice(0, 8)
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.45
                HoverHandler {
                    id: idHover
                }
                PlasmaComponents3.ToolTip.text: i18n("Session %1 (pid %2)", card.session.id, card.session.pid || "?")
                PlasmaComponents3.ToolTip.visible: idHover.hovered
            }
        }

        // Actions
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: card.canFocus || card.canResume || card.session.state === "error" || !card.session.alive

            Item {
                Layout.fillWidth: true
            }
            PlasmaComponents3.ToolButton {
                visible: card.session.state === "error"
                icon.name: "dialog-ok-apply-symbolic"
                text: i18n("Mark reviewed")
                font: Kirigami.Theme.smallFont
                onClicked: card.client.ackError(card.session.id)
            }
            PlasmaComponents3.ToolButton {
                visible: !card.session.alive
                icon.name: "edit-clear-symbolic"
                text: i18n("Dismiss")
                font: Kirigami.Theme.smallFont
                onClicked: card.client.forget(card.session.id)
            }
            PlasmaComponents3.ToolButton {
                visible: card.canFocus || card.canResume
                icon.name: card.canFocus ? "go-jump-symbolic" : "media-playback-start-symbolic"
                text: card.canFocus ? i18n("Open terminal") : i18n("Resume")
                font: Kirigami.Theme.smallFont
                onClicked: card.activate()
            }
        }
    }
}
