// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-plasma"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Monitor")
        icon: "utilities-terminal"
        source: "shared/MonitorConfigPage.qml"
    }
}
