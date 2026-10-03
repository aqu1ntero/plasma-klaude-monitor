// SPDX-License-Identifier: GPL-2.0-or-later
// Client of the klaude-monitord daemon. Both widgets use this same file (copied into each package
// at build time); neither runs a monitor of its own.
//
// Updates are pushed through a long poll: WaitForUpdate(token) returns as soon as the daemon's
// state changes, or after ~20 s with the current state. The first call auto-starts the daemon via
// D-Bus activation. If the daemon is unreachable the client retries with backoff.
import QtQuick
import org.kde.plasma.workspace.dbus as DBus

QtObject {
    id: client

    readonly property string serviceName: "io.github.aqu1ntero.KlaudeMonitor"
    readonly property string objectPath: "/io/github/aqu1ntero/KlaudeMonitor"

    // Set to false to pause polling (e.g. while the widget is being configured).
    property bool enabled: true

    property var data: null
    readonly property var sessions: data ? data.sessions : []
    readonly property var counts: data ? data.counts : ({})
    readonly property var monitorInfo: data ? data.monitor : ({})
    readonly property bool hooks: !!(data && data.monitor && data.monitor.hooks)

    property bool connected: false
    property bool everConnected: false
    property string errorText: ""
    property bool notInstalled: false
    property double receivedAt: 0
    property int failures: 0
    property bool _polling: false

    // Wall clock, ticking every second, for "x min ago" texts.
    property double now: Date.now()

    signal attention(var session)   // a session started needing input
    signal finished(var session)    // a task finished
    signal failed(var session)      // a session hit an error

    function count(state) {
        return counts && counts[state] !== undefined ? counts[state] : 0;
    }

    function _message(member, args) {
        return {
            service: serviceName,
            path: objectPath,
            iface: serviceName,
            member: member,
            arguments: args || []
        };
    }

    function _unwrap(reply) {
        let v = reply;
        while (v !== null && v !== undefined && typeof v === "object" && v.value !== undefined) {
            v = v.value;
        }
        return v;
    }

    // call("Member", [stringArgs], onResult(value), onError(message))
    function call(member, args, onResult, onError) {
        DBus.SessionBus.asyncCall(_message(member, args), reply => {
            if (onResult) {
                onResult(_unwrap(reply));
            }
        }, err => {
            const msg = err && err.error ? err.error.message : String(err);
            if (onError) {
                onError(msg);
            } else {
                console.warn("klaude-monitor:", member, msg);
            }
        });
    }

    function callJson(member, args, onResult, onError) {
        call(member, args, value => {
            let parsed = null;
            try {
                parsed = JSON.parse(value);
            } catch (e) {
                if (onError) {
                    onError(String(e));
                }
                return;
            }
            if (onResult) {
                onResult(parsed);
            }
        }, onError);
    }

    function _apply(json) {
        let next;
        try {
            next = JSON.parse(json);
        } catch (e) {
            return;
        }
        const prev = data;
        data = next;
        receivedAt = Date.now();
        if (!prev) {
            return;
        }
        const before = {};
        for (const s of prev.sessions) {
            before[s.id] = s.state;
        }
        for (const s of next.sessions) {
            const was = before[s.id];
            if (was === s.state) {
                continue;
            }
            if (s.state === "needs_input") {
                attention(s);
            } else if (s.state === "completed" && (was === "working" || was === "needs_input")) {
                finished(s);
            } else if (s.state === "error") {
                failed(s);
            }
        }
    }

    function poll() {
        if (!enabled || _polling) {
            return;
        }
        _polling = true;
        const token = data && connected ? data.token : "";
        call("WaitForUpdate", [token], json => {
            _polling = false;
            connected = true;
            everConnected = true;
            notInstalled = false;
            failures = 0;
            errorText = "";
            _apply(json);
            _schedule(0);
        }, msg => {
            _polling = false;
            connected = false;
            failures += 1;
            errorText = msg;
            notInstalled = msg.indexOf("ServiceUnknown") >= 0 || msg.indexOf("not provided by any .service") >= 0;
            _schedule(Math.min(30000, 1000 * Math.pow(2, Math.min(failures, 5))));
        });
    }

    function refresh() {
        // Force an immediate fresh state (also re-arms polling after errors).
        callJson("GetState", [], state => {
            connected = true;
            everConnected = true;
            notInstalled = false;
            failures = 0;
            _apply(JSON.stringify(state));
            if (!_polling) {
                _schedule(0);
            }
        }, msg => {
            errorText = msg;
        });
    }

    function _schedule(ms) {
        _timer.interval = Math.max(1, ms);
        _timer.restart();
    }

    // Actions -------------------------------------------------------------------------------
    // onDone({ok, action, message})
    function focusSession(id, onDone) {
        callJson("FocusSession", [id], r => {
            if (onDone) {
                onDone(r);
            }
        }, msg => {
            if (onDone) {
                onDone({
                    ok: false,
                    action: "none",
                    message: msg
                });
            }
        });
    }

    function resumeSession(id, onDone) {
        callJson("ResumeSession", [id], r => {
            if (onDone) {
                onDone(r);
            }
        }, msg => {
            if (onDone) {
                onDone({
                    ok: false,
                    action: "none",
                    message: msg
                });
            }
        });
    }

    function ackError(id) {
        call("AckError", [id], null, null);
    }

    function forget(id) {
        call("Forget", [id], null, null);
    }

    // filter: {limit, session, since, kinds}
    function history(filter, onResult, onError) {
        callJson("GetHistory", [JSON.stringify(filter || {})], onResult, onError);
    }

    function getConfig(onResult, onError) {
        callJson("GetConfig", [], onResult, onError);
    }

    function setConfig(values, onResult, onError) {
        callJson("SetConfig", [JSON.stringify(values)], onResult, onError);
    }

    property Timer _timer: Timer {
        interval: 1
        onTriggered: client.poll()
    }

    property Timer _clock: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: client.now = Date.now()
    }

    onEnabledChanged: if (enabled) {
        _schedule(0);
    }
    Component.onCompleted: poll()
}
