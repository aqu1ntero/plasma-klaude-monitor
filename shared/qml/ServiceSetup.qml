// SPDX-License-Identifier: GPL-2.0-or-later
// Installs or updates the background service from the copy bundled in this widget package
// (contents/runtime, added by tools/build.sh). Shown when the service is missing, or older than the
// bundled one. It says exactly what it will change before doing anything, and runs only when the
// user presses the button.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import "RuntimeInfo.js" as RuntimeInfo

ColumnLayout {
    id: setup

    required property var client

    readonly property string bundledVersion: RuntimeInfo.version
    readonly property string runningVersion: client.monitorInfo && client.monitorInfo.version ? client.monitorInfo.version : ""
    // "install", "update" or "" (nothing to do)
    readonly property string mode: client.notInstalled ? "install" : (client.connected && runningVersion && newer(bundledVersion, runningVersion) ? "update" : "")
    readonly property bool needed: mode !== ""
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("../../runtime/install.sh").toString().replace(/^file:\/\//, ""))

    property bool running: false
    property bool done: false
    property bool failed: false
    property string output: ""

    spacing: Kirigami.Units.largeSpacing

    function newer(a, b) {
        const pa = String(a).split(".").map(Number);
        const pb = String(b).split(".").map(Number);
        for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
            const x = pa[i] || 0;
            const y = pb[i] || 0;
            if (x !== y) {
                return x > y;
            }
        }
        return false;
    }

    function install() {
        running = true;
        done = false;
        failed = false;
        output = "";
        // Single-quote the path for the shell (any ' inside becomes '\'').
        const q = String.fromCharCode(39);
        const quoted = q + script.split(q).join(q + "\\" + q + q) + q;
        executable.connectSource("sh " + quoted + " runtime" + (hooksBox.checked ? " --hooks" : "") + " 2>&1");
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            setup.running = false;
            setup.output = (data["stdout"] || "") + (data["stderr"] || "");
            setup.failed = data["exit code"] !== 0;
            setup.done = true;
            if (!setup.failed) {
                setup.client.refresh();
                retry.start();
            }
        }
    }

    // The service may need a moment to register on the bus after it starts.
    Timer {
        id: retry
        interval: 1500
        repeat: true
        property int left: 6
        onTriggered: {
            if (setup.client.connected && !setup.client.notInstalled || --left <= 0) {
                stop();
                left = 6;
            } else {
                setup.client.refresh();
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Icon {
            Layout.preferredWidth: Kirigami.Units.iconSizes.large
            Layout.preferredHeight: Kirigami.Units.iconSizes.large
            Layout.alignment: Qt.AlignTop
            source: Qt.resolvedUrl("../../images/klaude-monitor.svg")
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                Layout.fillWidth: true
                level: 3
                wrapMode: Text.Wrap
                text: setup.mode === "update" ? i18n("Update the Klaude Monitor service") : i18n("Set up the Klaude Monitor service")
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: setup.mode === "update" ? i18n("This widget includes version %1 of the background service, but version %2 is running. Updating replaces the service files and restarts it. Your history and settings are kept.", setup.bundledVersion, setup.runningVersion) : i18n("Klaude Monitor gets its data from a small background service that watches the Claude Code sessions on this computer. Both Klaude Monitor widgets share it. It is not installed yet.")
            }
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        text: i18n("What this will do:")
        font.weight: Font.DemiBold
    }
    Repeater {
        model: [
            i18n("Copy the service to <tt>~/.local/lib/klaude-monitor</tt> and the commands <tt>klaude-monitor</tt>, <tt>klaude-monitord</tt> and <tt>klaude-monitor-hook</tt> to <tt>~/.local/bin</tt>."),
            i18n("Register it as a user service that starts when you log in (systemd), and on D-Bus so the widgets can reach it."),
            i18n("Start it now."),
            i18n("Everything stays in your home folder: no administrator password is needed and nothing is sent over the network.")
        ]
        delegate: RowLayout {
            required property string modelData
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignTop
                text: "•"
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                text: modelData
            }
        }
    }

    QQC2.CheckBox {
        id: hooksBox
        Layout.fillWidth: true
        visible: setup.mode === "install" || !setup.client.hooks
        checked: true
        text: i18n("Also add the Claude Code hooks (recommended)")
    }
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.gridUnit * 1.5
        visible: hooksBox.visible
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        font: Kirigami.Theme.smallFont
        opacity: 0.8
        text: i18n("Adds entries to <tt>~/.claude/settings.json</tt> (and to other Claude config folders in use) so Claude Code reports the exact question, permission or error a session is waiting on. The file is backed up first as <tt>settings.json.klaude-monitor.bak</tt>. Undo with <tt>klaude-monitor hooks uninstall</tt>.")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Button {
            enabled: !setup.running
            icon.name: setup.mode === "update" ? "update-none" : "run-install"
            text: setup.mode === "update" ? i18n("Update service") : i18n("Install service")
            onClicked: setup.install()
        }
        PlasmaComponents3.BusyIndicator {
            visible: setup.running
            running: visible
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            Layout.preferredWidth: Layout.preferredHeight
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: setup.running
            text: i18n("Installing…")
            opacity: 0.8
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: setup.done
        type: setup.failed ? Kirigami.MessageType.Error : Kirigami.MessageType.Positive
        text: setup.failed ? i18n("The installation failed. Details below.") : i18n("Service installed and running. It may take a few seconds to show your sessions.")
    }

    QQC2.TextArea {
        Layout.fillWidth: true
        Layout.maximumHeight: Kirigami.Units.gridUnit * 8
        visible: setup.done && setup.output.length > 0 && setup.failed
        readOnly: true
        wrapMode: Text.Wrap
        font.family: "monospace"
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        text: setup.output
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        font: Kirigami.Theme.smallFont
        opacity: 0.6
        text: i18n("Requires Python 3 with PyGObject, preinstalled on most KDE systems. To remove the service later, run <tt>klaude-monitor uninstall</tt>.")
    }
}
