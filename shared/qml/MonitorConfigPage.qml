// SPDX-License-Identifier: GPL-2.0-or-later
// "Monitor" settings page. These settings live in the daemon (~/.config/klaude-monitor/config.json)
// and are shared by both widgets: changing them here changes them for the other widget too.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page

    signal configurationChanged

    property var values: null
    property var loaded: null
    property string status: ""
    property bool reachable: false

    function load() {
        client.getConfig(r => {
            reachable = true;
            loaded = r.values;
            values = JSON.parse(JSON.stringify(r.values));
            status = "";
        }, msg => {
            reachable = false;
            status = msg;
        });
        client.callJson("GetState", [], s => {
            hooksLabel.text = s.monitor.hooks ? i18n("Claude Code hooks are active: questions and permissions are reported exactly.") : i18n("No hook events received yet. Install the hooks for exact questions, permissions and errors: klaude-monitor hooks install");
            versionLabel.text = i18n("Monitor %1 · %2 accounts · %3 sessions", s.monitor.version, s.accounts.length, s.counts.total);
        }, null);
    }

    function set(key, value) {
        if (!values || values[key] === value) {
            return;
        }
        const v = Object.assign({}, values);
        v[key] = value;
        values = v;
        page.configurationChanged();
    }

    function saveConfig() {
        if (!values) {
            return;
        }
        client.setConfig(values, r => {
            loaded = r.values;
        }, msg => {
            status = msg;
        });
    }

    MonitorClient {
        id: client
        enabled: false
    }

    Component.onCompleted: load()

    Kirigami.FormLayout {
        Kirigami.InlineMessage {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
            visible: !page.reachable && page.status.length > 0
            type: Kirigami.MessageType.Error
            text: i18n("The monitor service is not reachable: %1", page.status)
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Kirigami.FormData.isSection: true
            visible: page.reachable
            type: Kirigami.MessageType.Information
            text: i18n("These settings belong to the shared monitor service and apply to both widgets.")
        }

        QQC2.Label {
            id: versionLabel
            Kirigami.FormData.label: i18n("Service:")
        }
        QQC2.Label {
            id: hooksLabel
            Kirigami.FormData.label: i18n("Hooks:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("History")
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Keep history for (days):")
            enabled: !!page.values
            from: 1
            to: 3650
            value: page.values ? page.values.retention_days : 14
            onValueModified: page.set("retention_days", value)
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Monitoring")
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Re-check every (seconds) when no events arrive:")
            enabled: !!page.values
            from: 1
            to: 600
            value: page.values ? page.values.poll_interval_s : 5
            onValueModified: page.set("poll_interval_s", value)
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Finished tasks count as recent for (minutes):")
            enabled: !!page.values
            from: 1
            to: 1440
            value: page.values ? page.values.recent_window_min : 30
            onValueModified: page.set("recent_window_min", value)
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Keep ended sessions listed for (minutes):")
            enabled: !!page.values
            from: 0
            to: 10080
            value: page.values ? page.values.ended_visible_min : 60
            onValueModified: page.set("ended_visible_min", value)
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Notifications")
        }
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Notify when:")
            text: i18n("Claude needs my input")
            enabled: !!page.values
            checked: page.values ? page.values.notify_needs_input : true
            onToggled: page.set("notify_needs_input", checked)
        }
        QQC2.CheckBox {
            text: i18n("A task finishes")
            enabled: !!page.values
            checked: page.values ? page.values.notify_completed : true
            onToggled: page.set("notify_completed", checked)
        }
        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("…only if it took at least (seconds):")
            enabled: !!page.values && page.values.notify_completed
            from: 0
            to: 86400
            value: page.values ? page.values.notify_min_task_s : 30
            onValueModified: page.set("notify_min_task_s", value)
        }
        QQC2.CheckBox {
            text: i18n("A session hits an error")
            enabled: !!page.values
            checked: page.values ? page.values.notify_error : true
            onToggled: page.set("notify_error", checked)
        }
        QQC2.CheckBox {
            text: i18n("The monitor loses track of a session")
            enabled: !!page.values
            checked: page.values ? page.values.notify_unknown : false
            onToggled: page.set("notify_unknown", checked)
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Terminal")
        }
        QQC2.ComboBox {
            id: termBox
            Kirigami.FormData.label: i18n("Resume sessions in:")
            enabled: !!page.values
            textRole: "text"
            valueRole: "value"
            model: [
                {
                    value: "auto",
                    text: i18n("Automatic (original terminal, Yakuake, Konsole, kitty)")
                },
                {
                    value: "yakuake",
                    text: "Yakuake"
                },
                {
                    value: "konsole",
                    text: "Konsole"
                },
                {
                    value: "kitty",
                    text: "kitty"
                },
                {
                    value: "custom",
                    text: i18n("Custom command")
                }
            ]
            currentIndex: page.values ? Math.max(0, indexOfValue(page.values.preferred_terminal)) : 0
            onActivated: page.set("preferred_terminal", currentValue)
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Custom command:")
            visible: page.values && page.values.preferred_terminal === "custom"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 18
            placeholderText: "alacritty --working-directory {cwd} -e sh -c {cmd}"
            text: page.values ? page.values.custom_terminal_cmd : ""
            onTextEdited: page.set("custom_terminal_cmd", text)
        }
        QQC2.Label {
            visible: page.values && page.values.preferred_terminal === "custom"
            text: i18n("{cwd} is the project folder and {cmd} the claude --resume command (both already quoted).")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
        }
        QQC2.Label {
            text: i18n("Opening a running session always focuses the terminal it runs in.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
        }
    }
}
