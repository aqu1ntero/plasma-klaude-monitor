// SPDX-License-Identifier: GPL-2.0-or-later
// Compact session row (panel popup). Click focuses the session's terminal.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

PlasmaComponents3.ItemDelegate {
    id: row

    required property var session
    required property var labels
    required property var client
    property bool dense: false

    signal feedback(string text, bool ok)

    readonly property bool waiting: session.state === "needs_input"
    readonly property bool canFocus: session.focusable
    readonly property bool canResume: !session.alive && (session.state === "ended" || session.state === "unknown")

    width: ListView.view ? ListView.view.width : implicitWidth
    hoverEnabled: true
    topPadding: dense ? Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing * 1.5
    bottomPadding: topPadding

    function activate() {
        if (canFocus) {
            client.focusSession(session.id, r => row.feedback(r.ok ? "" : i18n("Could not focus the terminal: %1", r.message), r.ok));
        } else if (canResume) {
            client.resumeSession(session.id, r => row.feedback(r.ok ? i18n("Opened a terminal to resume the session") : i18n("Could not resume: %1", r.message), r.ok));
        } else {
            row.feedback(i18n("This session has no terminal that can be focused (%1).", labels.terminalLabel(session) || i18n("unknown")), false);
        }
    }

    onClicked: activate()

    PlasmaComponents3.ToolTip.text: [labels.title(session), labels.shortPath(session.cwd), labels.certaintyTooltip(session), canFocus ? i18n("Click to focus its terminal (%1)", labels.terminalLabel(session)) : (canResume ? i18n("Click to resume it in a new terminal") : "")].filter(x => x).join("\n")
    PlasmaComponents3.ToolTip.visible: hovered && !actions.hovered
    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing * 2

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 3
            radius: 1.5
            color: labels.stateColor(row.session.state)
            opacity: row.waiting ? 1 : 0.6
        }

        Kirigami.Icon {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: labels.stateIcon(row.session.state)
            color: labels.stateColor(row.session.state)
            isMask: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: row.session.project
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.maximumWidth: Math.min(implicitWidth, row.availableWidth * 0.45)
                }
                PlasmaComponents3.Label {
                    visible: !!row.session.accountLabel
                    text: "[" + row.session.accountLabel + "]"
                    opacity: 0.6
                    font: Kirigami.Theme.smallFont
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.session.title && row.session.title !== row.session.project ? "· " + row.session.title : ""
                    elide: Text.ElideRight
                    opacity: 0.75
                }
                PlasmaComponents3.Label {
                    text: labels.stateLabel(row.session.state) + " · " + labels.ago(row.session.since, row.client.now)
                    color: labels.stateColor(row.session.state)
                    font: Kirigami.Theme.smallFont
                    opacity: row.waiting || row.session.state === "error" ? 1 : 0.8
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: labels.detail(row.session)
                elide: Text.ElideRight
                maximumLineCount: row.waiting ? 2 : 1
                wrapMode: row.waiting ? Text.Wrap : Text.NoWrap
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.weight: row.waiting ? Font.DemiBold : Font.Normal
                color: row.waiting ? Kirigami.Theme.textColor : Kirigami.Theme.textColor
                opacity: row.waiting ? 1 : 0.7
            }
        }

        RowLayout {
            id: actions
            property bool hovered: focusBtn.hovered || ackBtn.hovered
            spacing: 0
            opacity: row.hovered || row.activeFocus || row.waiting ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

            PlasmaComponents3.ToolButton {
                id: ackBtn
                visible: row.session.state === "error"
                icon.name: "dialog-ok-apply-symbolic"
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: i18n("Mark error as reviewed")
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                onClicked: row.client.ackError(row.session.id)
            }
            PlasmaComponents3.ToolButton {
                id: focusBtn
                visible: row.canFocus || row.canResume
                icon.name: row.canFocus ? "go-jump-symbolic" : "media-playback-start-symbolic"
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: row.canFocus ? i18n("Open terminal") : i18n("Resume in a new terminal")
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
                onClicked: row.activate()
            }
        }
    }
}
