// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

RowLayout {
    id: header

    required property string groupState
    required property int count
    required property var labels

    width: ListView.view ? ListView.view.width : implicitWidth
    spacing: Kirigami.Units.smallSpacing

    Item {
        Layout.preferredWidth: Kirigami.Units.smallSpacing
    }
    PlasmaComponents3.Label {
        text: header.labels.groupLabel(header.groupState)
        color: header.groupState === "needs_input" ? header.labels.stateColor(header.groupState) : Kirigami.Theme.textColor
        font.weight: Font.Bold
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        topPadding: Kirigami.Units.smallSpacing * 2
        opacity: header.groupState === "needs_input" ? 1 : 0.7
    }
    PlasmaComponents3.Label {
        text: header.count
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        topPadding: Kirigami.Units.smallSpacing * 2
        opacity: 0.5
    }
    Kirigami.Separator {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignBottom
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        opacity: 0.5
    }
}
