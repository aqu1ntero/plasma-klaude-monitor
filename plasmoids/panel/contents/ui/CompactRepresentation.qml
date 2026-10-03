// SPDX-License-Identifier: GPL-2.0-or-later
// Panel icon: Klaude icon + red badge with the sessions that need you, a small accent badge with
// the tasks in progress and an amber dot when there are errors. Works in horizontal and vertical
// panels; details stay in the popup.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

MouseArea {
    id: compact

    required property var plasmoidItem
    required property var client
    required property var labels

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal || vertical
    readonly property int needs: plasmoidItem.needs
    readonly property int working: plasmoidItem.working
    readonly property int errors: plasmoidItem.errors
    readonly property bool showText: Plasmoid.configuration.showCountText && !vertical && client.connected && (needs > 0 || working > 0)
    readonly property real iconSize: vertical ? width : height

    Layout.minimumWidth: vertical ? -1 : iconSize + (showText ? countText.implicitWidth + Kirigami.Units.smallSpacing : 0)
    Layout.minimumHeight: vertical ? iconSize : -1
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    property bool wasExpanded: false
    onPressed: wasExpanded = plasmoidItem.expanded
    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) {
            // Middle click: jump straight to the session that has waited longest.
            const s = client.sessions.find(x => x.state === "needs_input" && x.focusable);
            if (s) {
                client.focusSession(s.id, null);
            }
            return;
        }
        plasmoidItem.expanded = !wasExpanded;
    }

    Item {
        id: iconBox
        width: compact.iconSize
        height: compact.iconSize
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Kirigami.Icon {
            id: icon
            anchors.fill: parent
            anchors.margins: compact.inPanel ? Math.round(parent.height * 0.08) : 0
            source: Qt.resolvedUrl("../images/klaude-monitor.svg")
            active: compact.containsMouse
            opacity: compact.client.connected ? 1 : 0.45
            transformOrigin: Item.Center
        }

        // Finished-task flash: a ring that expands and fades.
        Rectangle {
            id: ring
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Kirigami.Theme.positiveTextColor
            opacity: 0
        }
        ParallelAnimation {
            id: finishAnim
            NumberAnimation {
                target: ring
                property: "opacity"
                from: 0.9
                to: 0
                duration: 1400
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: ring
                property: "scale"
                from: 0.4
                to: 1.1
                duration: 1400
                easing.type: Easing.OutCubic
            }
        }

        SequentialAnimation {
            id: attentionAnim
            loops: 3
            NumberAnimation {
                target: icon
                property: "scale"
                to: 1.18
                duration: 160
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: icon
                property: "scale"
                to: 1.0
                duration: 220
                easing.type: Easing.InQuad
            }
        }

        // Needs-you badge (top right)
        Rectangle {
            id: needsBadge
            visible: compact.needs > 0
            anchors.top: parent.top
            anchors.right: parent.right
            height: Math.max(Kirigami.Units.iconSizes.small * 0.8, parent.height * 0.48)
            width: Math.max(height, needsLabel.implicitWidth + 4)
            radius: height / 2
            color: Kirigami.Theme.negativeTextColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor

            PlasmaComponents3.Label {
                id: needsLabel
                anchors.centerIn: parent
                text: compact.needs > 9 ? "9+" : compact.needs
                color: "white"
                font.bold: true
                font.pixelSize: Math.max(8, parent.height * 0.72)
            }

            SequentialAnimation on opacity {
                running: compact.needs > 0 && Plasmoid.configuration.pulseOnAttention
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation {
                    to: 0.55
                    duration: 900
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1
                    duration: 900
                    easing.type: Easing.InOutSine
                }
            }
        }

        // Working badge (bottom right)
        Rectangle {
            visible: compact.working > 0 && Plasmoid.configuration.showWorkingCount
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            height: Math.max(Kirigami.Units.iconSizes.small * 0.6, parent.height * 0.36)
            width: Math.max(height, workingLabel.implicitWidth + 4)
            radius: height / 2
            color: Kirigami.Theme.highlightColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor

            PlasmaComponents3.Label {
                id: workingLabel
                anchors.centerIn: parent
                text: compact.working > 9 ? "9+" : compact.working
                color: Kirigami.Theme.highlightedTextColor
                font.pixelSize: Math.max(7, parent.height * 0.75)
            }
        }

        // Error dot (bottom left)
        Rectangle {
            visible: compact.errors > 0 && Plasmoid.configuration.showErrorDot
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Math.max(5, parent.height * 0.22)
            height: width
            radius: width / 2
            color: Kirigami.Theme.neutralTextColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor
        }

        // Disconnected marker
        Kirigami.Icon {
            visible: !compact.client.connected && compact.client.failures > 1
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: parent.width * 0.45
            height: width
            source: "state-offline-symbolic"
        }
    }

    PlasmaComponents3.Label {
        id: countText
        visible: compact.showText
        anchors.left: iconBox.right
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.StyledText
        text: (compact.needs > 0 ? "<b><font color='" + Kirigami.Theme.negativeTextColor + "'>" + compact.needs + "</font></b>" : "") + (compact.needs > 0 && compact.working > 0 ? " · " : "") + (compact.working > 0 ? compact.working : "")
    }

    Connections {
        target: compact.plasmoidItem
        function onAttentionPulse() {
            attentionAnim.restart();
        }
        function onFinishPulse() {
            finishAnim.restart();
        }
    }
}
