# SPDX-License-Identifier: GPL-2.0-or-later
"""Desktop notifications (org.freedesktop.Notifications), sent once by the daemon.

Widgets never notify on their own, so having both widgets open never doubles a notification.
"""

import logging

from gi.repository import Gio, GLib

log = logging.getLogger(__name__)

SERVICE = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"
APP_NAME = "Klaude Monitor"
ICON = "klaude-monitor"

# Notification texts. The daemon has no locale-specific catalog; Spanish and English are built in.
TEXTS = {
    "en": {
        "needs_input": "Claude needs you", "completed": "Claude finished", "error": "Claude hit an error",
        "unknown": "Lost track of a Claude session", "open": "Open terminal",
        "permission": "Permission", "question": "Question", "plan": "Plan approval",
    },
    "es": {
        "needs_input": "Claude te necesita", "completed": "Claude terminó", "error": "Error en Claude",
        "unknown": "Se perdió el rastro de una sesión", "open": "Abrir terminal",
        "permission": "Permiso", "question": "Pregunta", "plan": "Aprobar plan",
    },
}


def _lang():
    import os
    for var in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"):
        v = os.environ.get(var)
        if v:
            code = v.split(":")[0][:2]
            return code if code in TEXTS else "en"
    return "en"


def _dur(ms):
    if not ms:
        return ""
    m = int(ms // 60000)
    if m < 1:
        return f"{int(ms // 1000)}s"
    return f"{m}m" if m < 60 else f"{m // 60}h {m % 60}m"


class Notifier:
    def __init__(self, on_action):
        self.on_action = on_action  # (session_id) -> None
        self.ids = {}  # notification id -> session id
        self.by_session = {}  # session id -> notification id (replace instead of stacking)
        self.t = TEXTS[_lang()]
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.bus.signal_subscribe(SERVICE, SERVICE, "ActionInvoked", PATH, None, Gio.DBusSignalFlags.NONE,
                                  self._on_action, None)
        self.bus.signal_subscribe(SERVICE, SERVICE, "NotificationClosed", PATH, None, Gio.DBusSignalFlags.NONE,
                                  self._on_closed, None)

    def send(self, kind, session, detail, cfg):
        if not cfg.get(f"notify_{kind}", False):
            return
        t = self.t
        title = t.get(kind, kind)
        name = session.t.get("title") or session.name or session.project
        body = f"<b>{GLib.markup_escape_text(session.project)}</b> · {GLib.markup_escape_text(name or '')}"
        text = (detail or {}).get("text")
        if kind == "needs_input":
            label = t.get((detail or {}).get("kind"), "")
            if text:
                body += f"\n{GLib.markup_escape_text(label + ': ' if label else '')}{GLib.markup_escape_text(text)}"
        elif kind == "completed":
            d = _dur((detail or {}).get("duration"))
            if d:
                title += f" · {d}"
            if text:
                body += "\n" + GLib.markup_escape_text(text[:200])
        elif text or (detail or {}).get("reason"):
            body += "\n" + GLib.markup_escape_text(str(text or detail.get("reason"))[:200])
        actions = ["default", t["open"], "open", t["open"]] if session.alive else []
        hints = {
            "desktop-entry": GLib.Variant("s", "klaude-monitor"),
            "urgency": GLib.Variant("y", 2 if kind in ("needs_input", "error") else 1),
            "x-kde-origin-name": GLib.Variant("s", session.project),
        }
        replaces = self.by_session.get(session.id, 0)
        params = GLib.Variant("(susssasa{sv}i)", (APP_NAME, replaces, ICON, title, body, actions, hints, -1))

        def done(bus, res):
            try:
                nid = bus.call_finish(res).unpack()[0]
            except GLib.Error as e:
                log.warning("notification failed: %s", e.message)
                return
            self.ids[nid] = session.id
            self.by_session[session.id] = nid

        self.bus.call(SERVICE, PATH, SERVICE, "Notify", params, None, Gio.DBusCallFlags.NONE, 5000, None, done)

    def close(self, session_id):
        """Withdraw the notification shown for a session, if any."""
        nid = self.by_session.pop(session_id, None)
        if nid is None:
            return
        self.ids.pop(nid, None)
        self.bus.call(SERVICE, PATH, SERVICE, "CloseNotification", GLib.Variant("(u)", (nid,)), None,
                      Gio.DBusCallFlags.NONE, 5000, None, None)

    def _on_action(self, _bus, _sender, _path, _iface, _signal, params, _data):
        nid, action = params.unpack()
        sid = self.ids.get(nid)
        if sid and action in ("default", "open"):
            self.on_action(sid)

    def _on_closed(self, _bus, _sender, _path, _iface, _signal, params, _data):
        nid = params.unpack()[0]
        sid = self.ids.pop(nid, None)
        if sid and self.by_session.get(sid) == nid:
            del self.by_session[sid]
