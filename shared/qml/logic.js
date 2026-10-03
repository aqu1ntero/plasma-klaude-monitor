// SPDX-License-Identifier: GPL-2.0-or-later
// Filtering, sorting and grouping of sessions, shared by both widgets.
.pragma library

var GROUP_ORDER = ["needs_input", "working", "error", "completed", "unknown", "idle", "ended"];

function parseList(text) {
    return String(text || "").split(",").map(function (x) { return x.trim(); }).filter(function (x) { return x.length > 0; });
}

// o: {text, state, project, showCompleted, showIdle, showEnded, hiddenProjects (array)}
function filter(sessions, o) {
    var text = String(o.text || "").toLowerCase();
    var hidden = o.hiddenProjects || [];
    return (sessions || []).filter(function (s) {
        if (s.state === "needs_input") {
            // Never hide a session that needs you because of a visibility setting; only the
            // explicit search/state/project filters do.
        } else {
            if (hidden.indexOf(s.project) >= 0) return false;
            if (!o.showCompleted && s.state === "completed") return false;
            if (!o.showIdle && s.state === "idle") return false;
            if (!o.showEnded && s.state === "ended") return false;
        }
        if (o.state && o.state !== "all") {
            if (o.state === "active") {
                if (s.state !== "needs_input" && s.state !== "working") return false;
            } else if (s.state !== o.state) {
                return false;
            }
        }
        if (o.project && s.project !== o.project) return false;
        if (text) {
            var hay = [s.project, s.title, s.cwd, s.id, s.branch, s.tool, s.prompt,
                       s.waiting ? s.waiting.text : "", s.error, s.result].join(" ").toLowerCase();
            if (hay.indexOf(text) < 0) return false;
        }
        return true;
    });
}

// Sessions waiting for you always come first, whatever the chosen order.
function sort(list, key) {
    var rank = function (s) { return GROUP_ORDER.indexOf(s.state); };
    var activity = function (s) { return s.lastActivity || s.since || 0; };
    return list.slice().sort(function (a, b) {
        var wa = a.state === "needs_input" ? 0 : 1;
        var wb = b.state === "needs_input" ? 0 : 1;
        if (wa !== wb) return wa - wb;
        if (wa === 0) return (a.since || 0) - (b.since || 0); // waiting longest first
        switch (key) {
        case "project":
            var c = String(a.project).localeCompare(String(b.project));
            return c !== 0 ? c : activity(b) - activity(a);
        case "state":
            return rank(a) - rank(b) || (b.since || 0) - (a.since || 0);
        case "since":
            return (b.since || 0) - (a.since || 0);
        default: // "activity"
            return activity(b) - activity(a);
        }
    });
}

// Flat list of rows: group headers (when grouped) followed by their sessions.
function rows(list, grouped) {
    var out = [];
    if (!grouped) {
        list.forEach(function (s) { out.push({ key: "s:" + s.id, kind: "session", payload: JSON.stringify(s) }); });
        return out;
    }
    GROUP_ORDER.forEach(function (state) {
        var members = list.filter(function (s) { return s.state === state; });
        if (members.length === 0) return;
        out.push({ key: "h:" + state, kind: "header", payload: JSON.stringify({ state: state, count: members.length }) });
        members.forEach(function (s) { out.push({ key: "s:" + s.id, kind: "session", payload: JSON.stringify(s) }); });
    });
    return out;
}

function projects(sessions) {
    var seen = {};
    (sessions || []).forEach(function (s) { seen[s.project] = true; });
    return Object.keys(seen).sort();
}

// Update a ListModel in place (keeps scroll position and delegates) to match rows [{key, ...}].
function sync(model, items) {
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (i < model.count) {
            var cur = model.get(i);
            if (cur.key !== item.key || cur.payload !== item.payload || cur.kind !== item.kind) {
                // Moved item: find it further down and move it here, else replace.
                var found = -1;
                for (var j = i + 1; j < model.count; j++) {
                    if (model.get(j).key === item.key) { found = j; break; }
                }
                if (found >= 0) {
                    model.move(found, i, 1);
                }
                model.set(i, item);
            }
        } else {
            model.append(item);
        }
    }
    if (model.count > items.length) {
        model.remove(items.length, model.count - items.length);
    }
}
