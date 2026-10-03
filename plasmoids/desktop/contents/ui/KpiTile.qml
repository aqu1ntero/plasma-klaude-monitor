// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Rectangle {
    id: tile

    property string value: "0"
    property string label: ""
    property string hint: ""
    property color accent: Kirigami.Theme.textColor
    property bool highlighted: false
    property bool selected: false
    property bool clickable: true

    signal clicked

    Layout.fillWidth: true
    Layout.minimumWidth: Kirigami.Units.gridUnit * 4
    implicitHeight: col.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.cornerRadius
    color: highlighted ? Qt.alpha(accent, 0.16) : Qt.alpha(Kirigami.Theme.textColor, hover.hovered && clickable ? 0.08 : 0.04)
    border.width: selected ? 2 : (highlighted ? 1 : 0)
    border.color: selected ? Kirigami.Theme.highlightColor : Qt.alpha(accent, 0.6)

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.smallSpacing * 2
        spacing: 0

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: tile.value
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
            font.weight: Font.Bold
            font.features: {
                "tnum": 1
            }
            color: tile.value === "0" ? Kirigami.Theme.disabledTextColor : tile.accent
            elide: Text.ElideRight
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: tile.label
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            elide: Text.ElideRight
        }
    }

    HoverHandler {
        id: hover
        cursorShape: tile.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: tile.clickable
        onTapped: tile.clicked()
    }
    PlasmaComponents3.ToolTip.text: hint
    PlasmaComponents3.ToolTip.visible: hover.hovered && hint.length > 0
}
