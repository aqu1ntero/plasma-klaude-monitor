// SPDX-License-Identifier: GPL-2.0-or-later
// Panel icon. Designed to be noticed from the corner of the eye:
//   - needs you: a red halo pulses around the icon, and a red pill with a bell shows how many sessions
//     wait for you;
//   - working:   an accent-colored ring spins around the icon, and a pill shows how many tasks run;
//   - errors:    an amber pill.
// "Pills" style (default) shows the pills next to the icon in horizontal panels. "Badges" style keeps
// the icon alone with corner badges (also used in vertical panels, where pills do not fit).
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

    readonly property var cfg: Plasmoid.configuration
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal || vertical
    readonly property int needs: plasmoidItem.needs
    readonly property int working: plasmoidItem.working
    readonly property int errors: plasmoidItem.errors
    readonly property bool connected: client.connected
    readonly property bool pills: cfg.compactStyle !== "badges" && !vertical && connected
    readonly property bool showNeedsPill: pills && needs > 0
    readonly property bool showWorkingPill: pills && working > 0 && cfg.showWorkingCount
    readonly property bool showErrorPill: pills && errors > 0 && cfg.showErrorDot
    readonly property bool anyPill: showNeedsPill || showWorkingPill || showErrorPill
    readonly property real iconSize: vertical ? width : height
    readonly property real pillHeight: Math.max(Kirigami.Units.iconSizes.small, Math.round(iconSize * 0.62))

    Layout.minimumWidth: vertical ? -1 : iconSize + (anyPill ? pillRow.implicitWidth + Kirigami.Units.smallSpacing : 0)
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

    // ---- attention halo (needs you) -------------------------------------------------------------
    Rectangle {
        id: halo
        anchors.centerIn: iconBox
        width: iconBox.width
        height: iconBox.height
        radius: Kirigami.Units.cornerRadius * 2
        color: Kirigami.Theme.negativeTextColor
        visible: compact.needs > 0 && compact.cfg.glowOnAttention
        opacity: 0.55

        SequentialAnimation on opacity {
            running: halo.visible && compact.cfg.pulseOnAttention
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation {
                to: 0.8
                duration: 700
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 0.3
                duration: 700
                easing.type: Easing.InOutSine
            }
        }
    }

    Item {
        id: iconBox
        width: compact.iconSize
        height: compact.iconSize
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        // ---- working ring -------------------------------------------------------------------------
        Canvas {
            id: ring
            anchors.fill: parent
            visible: compact.working > 0 && compact.cfg.animateWorking && compact.connected
            property color color: Kirigami.Theme.highlightColor
            onColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const w = Math.max(2, width * 0.075);
                const r = width / 2 - w / 2;
                ctx.lineWidth = w;
                ctx.lineCap = "round";
                // faint full circle + bright 120° arc that spins
                ctx.strokeStyle = Qt.rgba(color.r, color.g, color.b, 0.25);
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI);
                ctx.stroke();
                ctx.strokeStyle = color;
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, -Math.PI / 2, Math.PI / 6);
                ctx.stroke();
            }
            RotationAnimator on rotation {
                running: ring.visible
                from: 0
                to: 360
                duration: 1400
                loops: Animation.Infinite
            }
        }

        Kirigami.Icon {
            id: icon
            anchors.fill: parent
            anchors.margins: ring.visible ? Math.round(parent.height * 0.16) : (compact.inPanel ? Math.round(parent.height * 0.08) : 0)
            source: Qt.resolvedUrl("../images/klaude-monitor.svg")
            active: compact.containsMouse
            opacity: compact.connected ? 1 : 0.45
            transformOrigin: Item.Center
            Behavior on anchors.margins {
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                }
            }
        }

        // Finished-task flash: a green ring that expands and fades.
        Rectangle {
            id: flash
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(2, parent.width * 0.08)
            border.color: Kirigami.Theme.positiveTextColor
            opacity: 0
        }
        ParallelAnimation {
            id: finishAnim
            NumberAnimation {
                target: flash
                property: "opacity"
                from: 1
                to: 0
                duration: 1600
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: flash
                property: "scale"
                from: 0.3
                to: 1.15
                duration: 1600
                easing.type: Easing.OutCubic
            }
        }

        SequentialAnimation {
            id: attentionAnim
            loops: 3
            NumberAnimation {
                target: icon
                property: "scale"
                to: 1.25
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

        // ---- corner badges (badges style, vertical panels) ---------------------------------------
        Rectangle {
            visible: compact.needs > 0 && !compact.pills
            anchors.top: parent.top
            anchors.right: parent.right
            height: Math.max(Kirigami.Units.iconSizes.small, parent.height * 0.55)
            width: Math.max(height, needsBadgeLabel.implicitWidth + 6)
            radius: height / 2
            color: Kirigami.Theme.negativeTextColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor
            PlasmaComponents3.Label {
                id: needsBadgeLabel
                anchors.centerIn: parent
                text: compact.needs > 9 ? "9+" : compact.needs
                color: "white"
                font.bold: true
                font.pixelSize: Math.max(9, parent.height * 0.72)
            }
        }
        Rectangle {
            visible: compact.working > 0 && !compact.pills && compact.cfg.showWorkingCount
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            height: Math.max(Kirigami.Units.iconSizes.small * 0.8, parent.height * 0.42)
            width: Math.max(height, workingBadgeLabel.implicitWidth + 6)
            radius: height / 2
            color: Kirigami.Theme.highlightColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor
            PlasmaComponents3.Label {
                id: workingBadgeLabel
                anchors.centerIn: parent
                text: compact.working > 9 ? "9+" : compact.working
                color: Kirigami.Theme.highlightedTextColor
                font.bold: true
                font.pixelSize: Math.max(8, parent.height * 0.72)
            }
        }
        Rectangle {
            visible: compact.errors > 0 && !compact.pills && compact.cfg.showErrorDot
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Math.max(7, parent.height * 0.28)
            height: width
            radius: width / 2
            color: Kirigami.Theme.neutralTextColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor
        }

        // Disconnected marker
        Kirigami.Icon {
            visible: !compact.connected && compact.client.failures > 1
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: parent.width * 0.45
            height: width
            source: "state-offline-symbolic"
        }
    }

    // ---- pills (horizontal panels) ----------------------------------------------------------------
    component Pill: Rectangle {
        id: pill
        property string iconName
        property int count
        property color fill
        property color ink: "white"
        property bool spin: false
        implicitWidth: pillRowInner.implicitWidth + height * 0.6
        implicitHeight: compact.pillHeight
        radius: height / 2
        color: fill

        RowLayout {
            id: pillRowInner
            anchors.centerIn: parent
            spacing: Math.round(pill.height * 0.12)
            Kirigami.Icon {
                Layout.preferredWidth: Math.round(pill.height * 0.72)
                Layout.preferredHeight: Layout.preferredWidth
                source: pill.iconName
                color: pill.ink
                isMask: true
                RotationAnimator on rotation {
                    running: pill.spin && pill.visible && compact.cfg.animateWorking
                    from: 0
                    to: 360
                    duration: 1600
                    loops: Animation.Infinite
                }
            }
            PlasmaComponents3.Label {
                text: pill.count > 99 ? "99+" : pill.count
                color: pill.ink
                font.bold: true
                font.pixelSize: Math.max(10, Math.round(pill.height * 0.68))
            }
        }
    }

    Row {
        id: pillRow
        anchors.left: iconBox.right
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Kirigami.Units.smallSpacing
        visible: compact.anyPill

        Pill {
            id: needsPill
            visible: compact.showNeedsPill
            iconName: "notification-active-symbolic"
            count: compact.needs
            fill: Kirigami.Theme.negativeTextColor

            SequentialAnimation on scale {
                running: needsPill.visible && compact.cfg.pulseOnAttention
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation {
                    to: 1.08
                    duration: 700
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1.0
                    duration: 700
                    easing.type: Easing.InOutSine
                }
            }
        }
        Pill {
            visible: compact.showWorkingPill
            iconName: "view-refresh-symbolic"
            count: compact.working
            fill: Kirigami.Theme.highlightColor
            ink: Kirigami.Theme.highlightedTextColor
            spin: true
        }
        Pill {
            visible: compact.showErrorPill
            iconName: "state-warning-symbolic"
            count: compact.errors
            fill: Kirigami.Theme.neutralTextColor
            ink: "black"
        }
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
