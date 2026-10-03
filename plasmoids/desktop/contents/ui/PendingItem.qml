// SPDX-License-Identifier: GPL-2.0-or-later
// One pending intervention: what Claude asks, where, since when, and a way to get there.
// Opening the terminal does not mark it as resolved: only Claude Code's own state does.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Rectangle {
    id: item

    required property var session
    required property var labels
    required property var client

    signal feedback(string text, bool ok)

    readonly property bool isError: session.state === "error"
    readonly property color accent: labels.stateColor(session.state)

    implicitHeight: col.implicitHeight + Kirigami.Units.smallSpacing * 3
    radius: Kirigami.Units.cornerRadius
    color: Qt.alpha(accent, 0.10)
    border.width: 1
    border.color: Qt.alpha(accent, 0.5)

    ColumnLayout {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Kirigami.Units.smallSpacing * 1.5
        }
        spacing: Kirigami.Units.smallSpacing / 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: item.labels.stateIcon(item.session.state)
                color: item.accent
                isMask: true
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: item.isError ? i18n("Error to review") : item.labels.waitingKind(item.session.waiting ? item.session.waiting.kind : "")
                font.weight: Font.Bold
                color: item.accent
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                readonly property double at: item.isError ? item.session.since : (item.session.waiting && item.session.waiting.since ? item.session.waiting.since : item.session.since)
                text: i18n("%1 (%2)", item.labels.clock(at), item.labels.ago(at, item.client.now))
                font: Kirigami.Theme.smallFont
                opacity: 0.75
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            readonly property string what: item.isError ? (item.session.error || "") : (item.session.waiting && item.session.waiting.text ? item.session.waiting.text : (item.session.hooked ? "" : i18n("Claude is waiting for you (install the hooks to see the exact question).")))
            visible: what.length > 0
            text: what
            wrapMode: Text.Wrap
            maximumLineCount: 5
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: item.session.project + (item.session.title && item.session.title !== item.session.project ? " · " + item.session.title : "") + " · " + item.session.id.slice(0, 8)
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                elide: Text.ElideRight
            }
            PlasmaComponents3.ToolButton {
                visible: item.isError
                icon.name: "dialog-ok-apply-symbolic"
                text: i18n("Mark reviewed")
                font: Kirigami.Theme.smallFont
                onClicked: item.client.ackError(item.session.id)
            }
            PlasmaComponents3.ToolButton {
                visible: item.session.focusable
                icon.name: "go-jump-symbolic"
                text: i18n("Open terminal")
                font: Kirigami.Theme.smallFont
                onClicked: item.client.focusSession(item.session.id, r => item.feedback(r.ok ? "" : i18n("Could not focus the terminal: %1", r.message), r.ok))
            }
        }
    }
}
