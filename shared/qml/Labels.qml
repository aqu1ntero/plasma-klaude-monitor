// SPDX-License-Identifier: GPL-2.0-or-later
// Texts, icons and colors for states and events, shared by both widgets.
import QtQuick
import org.kde.kirigami as Kirigami

QtObject {
    // Display order of the groups (needs you first, always).
    readonly property var groupOrder: ["needs_input", "working", "error", "completed", "unknown", "idle", "ended"]

    function stateLabel(state) {
        switch (state) {
        case "needs_input":
            return i18n("Needs you");
        case "working":
            return i18n("Working");
        case "completed":
            return i18n("Completed");
        case "idle":
            return i18n("Idle");
        case "error":
            return i18n("Error");
        case "ended":
            return i18n("Ended");
        default:
            return i18n("Unknown");
        }
    }

    function groupLabel(state) {
        switch (state) {
        case "needs_input":
            return i18n("Needs your input");
        case "working":
            return i18n("In progress");
        case "completed":
            return i18n("Recently completed");
        case "error":
            return i18n("Errors");
        case "idle":
            return i18n("Idle");
        case "ended":
            return i18n("Ended");
        default:
            return i18n("Unknown state");
        }
    }

    function stateIcon(state) {
        switch (state) {
        case "needs_input":
            return "notification-active-symbolic";
        case "working":
            return "state-sync-symbolic";
        case "completed":
            return "state-ok-symbolic";
        case "idle":
            return "state-pause-symbolic";
        case "error":
            return "state-warning-symbolic";
        case "ended":
            return "state-offline-symbolic";
        default:
            return "question-symbolic";
        }
    }

    function stateColor(state) {
        switch (state) {
        case "needs_input":
            return Kirigami.Theme.negativeTextColor;
        case "working":
            return Kirigami.Theme.highlightColor;
        case "completed":
            return Kirigami.Theme.positiveTextColor;
        case "error":
            return Kirigami.Theme.neutralTextColor;
        default:
            return Kirigami.Theme.disabledTextColor;
        }
    }

    function certaintyLabel(c) {
        switch (c) {
        case "high":
            return i18nc("certainty of a session state", "certain");
        case "medium":
            return i18nc("certainty of a session state", "likely");
        default:
            return i18nc("certainty of a session state", "uncertain");
        }
    }

    function certaintyTooltip(s) {
        const src = {
            "hook": i18n("reported by a Claude Code hook"),
            "state-file": i18n("read from Claude Code's session state file"),
            "transcript": i18n("inferred from the transcript"),
            "recovered": i18n("recovered when the monitor started"),
            "monitor": i18n("inferred by the monitor")
        }[s.source] || s.source;
        let t = i18n("State %1: %2", certaintyLabel(s.certainty), src);
        if (s.stale) {
            t += "\n" + i18n("No activity for a long time: it may be stuck.");
        }
        return t;
    }

    function waitingKind(kind) {
        switch (kind) {
        case "permission":
            return i18n("Permission");
        case "question":
            return i18n("Question");
        case "plan":
            return i18n("Plan approval");
        case "elicitation":
            return i18n("Input requested");
        default:
            return i18n("Waiting for you");
        }
    }

    function waitingText(w) {
        if (!w) {
            return "";
        }
        const kind = waitingKind(w.kind);
        return w.text ? kind + ": " + w.text : kind;
    }

    function endedReason(r) {
        switch (r) {
        case "replaced":
            return i18n("replaced by a new session in the same terminal");
        case "state file missing":
            return i18n("Claude Code's state file disappeared");
        case "process exited without an exit event":
            return i18n("the process ended without reporting it");
        case "clear":
            return i18n("cleared");
        case "logout":
            return i18n("logged out");
        case "prompt_input_exit":
            return i18n("exited");
        default:
            return r || "";
        }
    }

    // One line describing what the session is doing / waiting for / produced.
    function detail(s) {
        switch (s.state) {
        case "needs_input":
            return waitingText(s.waiting);
        case "working":
            return s.tool || s.prompt || "";
        case "error":
            return s.error || "";
        case "unknown":
            return s.endedReason ? endedReason(s.endedReason) : (s.summary || "");
        case "ended":
            return s.result || endedReason(s.endedReason);
        default:
            return s.summary || s.result || s.prompt || "";
        }
    }

    function eventLabel(kind) {
        switch (kind) {
        case "session_start":
            return i18n("Session started");
        case "session_resumed":
            return i18n("Session resumed");
        case "session_recovered":
            return i18n("Session found running");
        case "session_end":
            return i18n("Session ended");
        case "session_lost":
            return i18n("Session lost");
        case "task_start":
            return i18n("Task started");
        case "task_end":
            return i18n("Task finished");
        case "needs_input":
            return i18n("Input requested");
        case "input_resolved":
            return i18n("Input given");
        case "permission_denied":
            return i18n("Permission denied");
        case "error":
            return i18n("Error");
        case "error_acked":
            return i18n("Error reviewed");
        case "monitor_start":
            return i18n("Monitor started");
        default:
            return kind;
        }
    }

    function eventIcon(kind) {
        switch (kind) {
        case "needs_input":
            return "notification-active-symbolic";
        case "input_resolved":
            return "dialog-ok-apply-symbolic";
        case "task_start":
            return "media-playback-start-symbolic";
        case "task_end":
            return "state-ok-symbolic";
        case "error":
        case "permission_denied":
            return "state-warning-symbolic";
        case "session_lost":
            return "question-symbolic";
        case "session_end":
            return "state-offline-symbolic";
        case "monitor_start":
            return "view-refresh-symbolic";
        default:
            return "utilities-terminal-symbolic";
        }
    }

    function eventColor(kind) {
        switch (kind) {
        case "needs_input":
            return Kirigami.Theme.negativeTextColor;
        case "error":
        case "permission_denied":
            return Kirigami.Theme.neutralTextColor;
        case "task_end":
            return Kirigami.Theme.positiveTextColor;
        default:
            return Kirigami.Theme.textColor;
        }
    }

    function eventDetail(e) {
        const d = e.detail || {};
        if (e.kind === "needs_input") {
            return waitingText(d);
        }
        if (e.kind === "task_end" && d.duration) {
            return duration(d.duration) + (d.text ? " · " + d.text : "");
        }
        if (e.kind === "session_lost" || e.kind === "session_end") {
            return endedReason(d.reason);
        }
        if (e.kind === "monitor_start") {
            return d.version ? "v" + d.version : "";
        }
        return d.text || d.tool || d.reason || "";
    }

    function ago(ms, now) {
        if (!ms) {
            return "";
        }
        const s = Math.max(0, Math.floor((now - ms) / 1000));
        if (s < 10) {
            return i18nc("time ago", "now");
        }
        if (s < 60) {
            return i18nc("time ago", "%1 s", s);
        }
        const m = Math.floor(s / 60);
        if (m < 60) {
            return i18nc("time ago", "%1 min", m);
        }
        const h = Math.floor(m / 60);
        if (h < 24) {
            return i18nc("time ago, hours and minutes", "%1 h %2 min", h, m % 60);
        }
        return i18nc("time ago", "%1 d", Math.floor(h / 24));
    }

    function duration(ms) {
        if (!ms) {
            return "";
        }
        const s = Math.floor(ms / 1000);
        if (s < 60) {
            return i18nc("duration", "%1 s", s);
        }
        const m = Math.floor(s / 60);
        if (m < 60) {
            return i18nc("duration", "%1 min", m);
        }
        return i18nc("duration, hours and minutes", "%1 h %2 min", Math.floor(m / 60), m % 60);
    }

    function clock(ms) {
        if (!ms) {
            return "";
        }
        const d = new Date(ms);
        const today = new Date();
        const sameDay = d.toDateString() === today.toDateString();
        return sameDay ? Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat)) : Qt.formatDateTime(d, Qt.locale().dateTimeFormat(Locale.ShortFormat));
    }

    function clockSeconds(ms) {
        return ms ? Qt.formatDateTime(new Date(ms), Qt.locale().dateTimeFormat(Locale.LongFormat)) : "";
    }

    function shortPath(path) {
        return (path || "").replace(/^\/home\/[^\/]+/, "~");
    }

    function terminalLabel(s) {
        if (!s.terminal) {
            return "";
        }
        if (s.terminal.kind === "none") {
            return s.terminal.label === "background" ? i18n("background session") : s.terminal.label;
        }
        return s.terminal.label;
    }

    function title(s) {
        return s.title || s.project;
    }
}
