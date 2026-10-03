# SPDX-License-Identifier: GPL-2.0-or-later
"""The monitor daemon: watches Claude Code, owns the session state and serves it over D-Bus.

Exactly one instance runs per user: it owns the well-known bus name and exits if another instance
already does. Widgets talk to it over the session bus; D-Bus activation starts it on demand.
"""

import json
import logging
import os
import signal
import sys
import threading

from gi.repository import Gio, GLib

from . import BUS_NAME, INTERFACE, OBJECT_PATH, __version__, config, hooks, procutil, terminals, transcript
from .history import History, now_ms
from .notify import Notifier
from .sessions import ACTIVE, ENDED, Manager

log = logging.getLogger("klaude-monitord")

LONG_POLL_MS = 20000
DEFAULT_ACCOUNT = os.path.join(os.path.expanduser("~"), ".claude")

INTROSPECTION = f"""
<node>
  <interface name="{INTERFACE}">
    <method name="Ping"><arg type="s" direction="out"/></method>
    <method name="GetState"><arg type="s" direction="out"/></method>
    <method name="WaitForUpdate">
      <arg name="token" type="s" direction="in"/>
      <arg type="s" direction="out"/>
    </method>
    <method name="GetHistory">
      <arg name="filter" type="s" direction="in"/>
      <arg type="s" direction="out"/>
    </method>
    <method name="FocusSession">
      <arg name="id" type="s" direction="in"/>
      <arg type="s" direction="out"/>
    </method>
    <method name="ResumeSession">
      <arg name="id" type="s" direction="in"/>
      <arg type="s" direction="out"/>
    </method>
    <method name="AckError">
      <arg name="id" type="s" direction="in"/>
      <arg type="b" direction="out"/>
    </method>
    <method name="Forget">
      <arg name="id" type="s" direction="in"/>
      <arg type="b" direction="out"/>
    </method>
    <method name="GetConfig"><arg type="s" direction="out"/></method>
    <method name="SetConfig">
      <arg name="config" type="s" direction="in"/>
      <arg type="s" direction="out"/>
    </method>
    <method name="Rescan"><arg type="s" direction="out"/></method>
    <signal name="Changed"><arg name="revision" type="s"/></signal>
  </interface>
</node>
"""


def account_label(path):
    if os.path.normpath(path) == DEFAULT_ACCOUNT:
        return "default"
    base = os.path.basename(os.path.normpath(path)).lstrip(".")
    for prefix in ("claude-", "claude_", "claude"):
        if base.startswith(prefix) and len(base) > len(prefix):
            return base[len(prefix):]
    return base


class Monitor:
    def __init__(self, history=None):
        config.STATE_DIR.mkdir(parents=True, exist_ok=True)
        config.SPOOL_DIR.mkdir(parents=True, exist_ok=True)
        self.cfg = config.load()
        self.history = history or History(config.DB_FILE)
        self.notifier = None
        self.manager = Manager(self.history, self.cfg, notify=self._notify)
        self.accounts = {}       # dir -> label
        self.monitors = {}       # path -> Gio.FileMonitor
        self.pidfds = {}         # pid -> (fd, source id)
        self.waiters = []        # [(invocation, revision, timeout id)]
        self.scan_pending = False
        self.poll_source = None
        self.conn = None
        self.started_at = now_ms()
        self.last_scan = None
        self.hooks_seen = False
        self.hooks_installed = False
        self.hooks_checked = 0
        self.loop = GLib.MainLoop()

    # ---- startup -----------------------------------------------------------------------------
    def start(self):
        Gio.bus_own_name(Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.DO_NOT_QUEUE,
                         self._on_bus, self._on_name, self._on_name_lost)
        for sig in (signal.SIGTERM, signal.SIGINT):
            GLib.unix_signal_add(GLib.PRIORITY_HIGH, sig, self._quit)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGHUP, self._reload)
        self.loop.run()
        self._save()

    def _quit(self):
        log.info("stopping")
        self.loop.quit()
        return GLib.SOURCE_REMOVE

    def _reload(self):
        self.cfg.clear()
        self.cfg.update(config.load())
        self._reschedule_poll()
        self.request_scan()
        return GLib.SOURCE_CONTINUE

    def _on_bus(self, conn, _name):
        self.conn = conn
        node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
        conn.register_object(OBJECT_PATH, node.interfaces[0], self._on_call, None, None)

    def _on_name(self, conn, name):
        log.info("klaude-monitord %s running as %s", __version__, name)
        try:
            self.notifier = Notifier(self._on_notification_action)
        except GLib.Error as e:
            log.warning("notifications unavailable: %s", e.message)
        self._restore()
        self.history.add("monitor_start", None, {"version": __version__}, "monitor", None)
        self.manager.quiet = True
        self.scan()
        self.manager.quiet = False
        self._reschedule_poll()
        GLib.timeout_add_seconds(3600, self._prune)
        self._prune()

    def _on_name_lost(self, conn, name):
        if conn is None:
            log.error("no session bus")
        else:
            log.info("another monitor already owns %s; exiting", name)
        self.loop.quit()

    def _restore(self):
        keep_ms = max(self.cfg["ended_visible_min"], self.cfg["recent_window_min"]) * 60000 + 86400000
        from .sessions import Session
        for d in self.history.load_sessions(now_ms() - keep_ms):
            s = Session.restore(d)
            if s.since is not None:
                self.manager.sessions[s.id] = s
        saved = self.history.get_meta("accounts", [])
        for path in saved:
            if os.path.isdir(path):
                self.accounts[path] = account_label(path)

    def _prune(self):
        self.history.prune(self.cfg["retention_days"])
        return GLib.SOURCE_CONTINUE

    def _reschedule_poll(self):
        if self.poll_source:
            GLib.source_remove(self.poll_source)
        self.poll_source = GLib.timeout_add_seconds(self.cfg["poll_interval_s"], self._on_poll)

    def _on_poll(self):
        self.scan()
        return GLib.SOURCE_CONTINUE

    # ---- watching ----------------------------------------------------------------------------
    def discover_accounts(self):
        dirs = {DEFAULT_ACCOUNT}
        dirs.update(self.cfg.get("extra_config_dirs", []))
        dirs.update(self.accounts)
        for pid in procutil.claude_pids():
            d = procutil.environ(pid).get("CLAUDE_CONFIG_DIR")
            if d:
                dirs.add(os.path.normpath(os.path.expanduser(d)))
        changed = False
        for d in [d for d in self.accounts if not os.path.isdir(d)]:
            del self.accounts[d]  # removed config dir
            changed = True
        for d in dirs:
            d = os.path.normpath(os.path.expanduser(d))
            if os.path.isdir(d) and d not in self.accounts:
                self.accounts[d] = account_label(d)
                changed = True
            self._watch(os.path.join(d, "sessions"))
        if changed:
            self.history.set_meta("accounts", sorted(self.accounts))
        self._watch(str(config.SPOOL_DIR))
        if changed or now_ms() - self.hooks_checked > 60000:
            self.hooks_checked = now_ms()
            installed = any(hooks.status(d) for d in self.accounts)
            if installed != self.hooks_installed:
                self.hooks_installed = installed
                self.manager.touch()

    def _watch(self, path):
        if path in self.monitors or not os.path.isdir(path):
            return
        try:
            mon = Gio.File.new_for_path(path).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
        except GLib.Error as e:
            log.warning("cannot watch %s: %s", path, e.message)
            return
        mon.set_rate_limit(100)
        mon.connect("changed", lambda *_: self.request_scan())
        self.monitors[path] = mon

    def _watch_pid(self, pid):
        if pid in self.pidfds or not hasattr(os, "pidfd_open"):
            return
        try:
            fd = os.pidfd_open(pid)
        except OSError:
            return

        def gone(_fd, _cond):
            self.pidfds.pop(pid, None)
            os.close(fd)
            self.request_scan(50)
            return GLib.SOURCE_REMOVE

        GLib.unix_fd_add_full(GLib.PRIORITY_DEFAULT, fd, GLib.IOCondition.IN, gone)
        self.pidfds[pid] = fd

    def request_scan(self, delay=150):
        if not self.scan_pending:
            self.scan_pending = True
            GLib.timeout_add(delay, self._scan_now)

    def _scan_now(self):
        self.scan_pending = False
        self.scan()
        return GLib.SOURCE_REMOVE

    # ---- the scan ----------------------------------------------------------------------------
    def scan(self):
        m = self.manager
        rev = m.revision
        try:
            self.discover_accounts()
            self.read_spool()
            seen, owner = set(), {}
            for acc in list(self.accounts):
                d = os.path.join(acc, "sessions")
                try:
                    names = os.listdir(d)
                except OSError:
                    continue
                for name in names:
                    if not name.endswith(".json"):
                        continue
                    try:
                        with open(os.path.join(d, name)) as f:
                            data = json.load(f)
                    except (OSError, ValueError):
                        continue  # being rewritten; next scan
                    if not isinstance(data, dict) or not data.get("pid"):
                        continue
                    alive = procutil.is_alive(data["pid"], data.get("procStart"))
                    if not alive:
                        continue  # left behind by a crashed process
                    s = m.apply_state_file(acc, data, True, preload=self._load_transcript)
                    if s:
                        seen.add(s.id)
                        owner[s.pid] = s.id
            now = now_ms()
            for s in list(m.sessions.values()):
                if s.id in seen:
                    self._refresh_live(s)
                    continue
                if not s.alive:
                    continue
                if s.pid and procutil.is_alive(s.pid, s.proc_start):
                    if s.pid in owner:
                        # Same process now runs another session (/clear or a switch).
                        m.set_state(s, ENDED, "monitor", now, {"reason": "replaced"}, force=True)
                    elif s.file_status_time is not None or now - (s.since or now) > 30000:
                        m.lost_state_file(s)
                        self._refresh_live(s)
                    else:
                        self._refresh_live(s)  # hook-only session, state file not written yet
                else:
                    m.process_gone(s)
            m.age()
        except Exception:  # never let one bad file kill the monitor
            log.exception("scan failed")
        self.last_scan = now_ms()
        if m.dirty:
            self._save()
        if m.revision != rev:
            self._publish()

    def _load_transcript(self, s):
        path = s.transcript or (transcript.transcript_path(s.account, s.cwd, s.id) if s.account and s.cwd else None)
        try:
            mtime = os.stat(path).st_mtime_ns if path else None
        except OSError:
            return
        summary = transcript.parse(path)
        if summary is not None:
            s.transcript, s.transcript_mtime, s.t = path, mtime, summary
            if summary.get("last_time"):
                s.last_activity = summary["last_time"]

    def _refresh_live(self, s):
        if s.pid:
            self._watch_pid(s.pid)
        if s.terminal is None and s.pid:
            s.terminal = terminals.detect(s.pid, s.kind)
            self.manager.touch()
        path = s.transcript
        if not path and s.account and s.cwd:
            path = transcript.transcript_path(s.account, s.cwd, s.id)
        if not path:
            return
        try:
            mtime = os.stat(path).st_mtime_ns
        except OSError:
            return
        if mtime != s.transcript_mtime:
            s.transcript = path
            s.transcript_mtime = mtime
            self.manager.apply_transcript(s, transcript.parse(path))

    def read_spool(self):
        try:
            names = sorted(n for n in os.listdir(config.SPOOL_DIR) if n.endswith(".json"))
        except OSError:
            return
        for name in names:
            path = os.path.join(config.SPOOL_DIR, name)
            try:
                with open(path) as f:
                    meta_line, _, payload = f.read().partition("\n")
                ev = json.loads(meta_line)
                ev["payload"] = json.loads(payload)
                if ev.get("account"):
                    ev["account"] = os.path.normpath(ev["account"])
                    if ev["account"] not in self.accounts and os.path.isdir(ev["account"]):
                        self.accounts[ev["account"]] = account_label(ev["account"])
                        self.history.set_meta("accounts", sorted(self.accounts))
                else:
                    ev["account"] = DEFAULT_ACCOUNT
                self.hooks_seen = True
                s = self.manager.apply_hook(ev)
                if s is not None and s.alive:
                    self._refresh_live(s)
            except (OSError, ValueError, AttributeError) as e:
                log.warning("bad hook event %s: %s", name, e)
            try:
                os.unlink(path)
            except OSError:
                pass

    def _save(self):
        self.history.save_sessions(self.manager.sessions.values())
        self.manager.dirty = False

    # ---- notifications -----------------------------------------------------------------------
    def _notify(self, kind, session, detail):
        if not self.notifier:
            return
        if kind == "dismiss":
            self.notifier.close(session.id)
            return
        if self.manager.quiet:
            return
        self.notifier.send(kind, session, detail, self.cfg)

    def _on_notification_action(self, sid):
        threading.Thread(target=self._focus_or_resume, args=(sid,), daemon=True).start()

    # ---- D-Bus -------------------------------------------------------------------------------
    def state_json(self):
        hooks = self.hooks_installed or self.hooks_seen or any(s.hooked for s in self.manager.sessions.values())
        extra = {
            "token": self.token(),
            "monitor": {
                "version": __version__, "startedAt": self.started_at, "lastScan": self.last_scan,
                "hooks": hooks, "pollInterval": self.cfg["poll_interval_s"],
                "recentWindowMin": self.cfg["recent_window_min"],
            },
            "accounts": [{"dir": d, "label": label} for d, label in sorted(self.accounts.items())],
        }
        labels = self.accounts if len(self.accounts) > 1 else {}
        return json.dumps(self.manager.snapshot(labels, extra), ensure_ascii=False)

    def _publish(self):
        rev = str(self.manager.revision)
        body = self.state_json()
        waiters, self.waiters = self.waiters, []
        for inv, _rev, src in waiters:
            GLib.source_remove(src)
            inv.return_value(GLib.Variant("(s)", (body,)))
        if self.conn:
            self.conn.emit_signal(None, OBJECT_PATH, INTERFACE, "Changed", GLib.Variant("(s)", (rev,)))

    def token(self):
        return f"{self.started_at}:{self.manager.revision}"

    def _long_poll(self, inv, token):
        if token != self.token():
            inv.return_value(GLib.Variant("(s)", (self.state_json(),)))
            return

        def timeout():
            for i, w in enumerate(self.waiters):
                if w[0] is inv:
                    del self.waiters[i]
                    break
            inv.return_value(GLib.Variant("(s)", (self.state_json(),)))
            return GLib.SOURCE_REMOVE

        self.waiters.append((inv, token, GLib.timeout_add(LONG_POLL_MS, timeout)))

    def _focus_or_resume(self, sid, resume=False):
        s = self.manager.sessions.get(sid)
        if s is None:
            return {"ok": False, "action": "none", "message": "unknown session"}
        if not resume and s.alive and s.pid:
            ok, msg = terminals.focus(s.pid, s.terminal)
            return {"ok": ok, "action": "focus", "message": msg}
        if s.alive and not resume:
            return {"ok": False, "action": "none", "message": "no terminal"}
        if s.alive:
            return {"ok": False, "action": "resume", "message": "session is still running"}
        ok, msg = terminals.open_resume(s.cwd, s.id, s.account, DEFAULT_ACCOUNT, self.cfg,
                                        (s.terminal or {}).get("kind"))
        return {"ok": ok, "action": "resume", "message": msg}

    def _threaded(self, inv, fn, *args):
        def work():
            try:
                result = fn(*args)
            except Exception as e:  # report, don't crash
                log.exception("action failed")
                result = {"ok": False, "action": "none", "message": str(e)}
            GLib.idle_add(lambda: inv.return_value(GLib.Variant("(s)", (json.dumps(result),))) and False)

        threading.Thread(target=work, daemon=True).start()

    def _on_call(self, _conn, _sender, _path, _iface, method, params, inv):
        args = params.unpack()
        reply = lambda value, sig="(s)": inv.return_value(GLib.Variant(sig, (value,)))
        try:
            if method == "Ping":
                reply(__version__)
            elif method == "GetState":
                reply(self.state_json())
            elif method == "WaitForUpdate":
                self._long_poll(inv, args[0])
            elif method == "GetHistory":
                f = json.loads(args[0] or "{}")
                reply(json.dumps(self.history.events(
                    limit=f.get("limit", 200), session_id=f.get("session"), since=f.get("since"),
                    kinds=f.get("kinds")), ensure_ascii=False))
            elif method == "FocusSession":
                self._threaded(inv, self._focus_or_resume, args[0])
            elif method == "ResumeSession":
                self._threaded(inv, self._focus_or_resume, args[0], True)
            elif method == "AckError":
                ok = self.manager.ack_error(args[0])
                reply(ok, "(b)")
                self._after_change()
            elif method == "Forget":
                s = self.manager.sessions.get(args[0])
                ok = bool(s and (not s.alive or s.state not in ACTIVE)) and self.manager.forget(args[0])
                reply(ok, "(b)")
                self._after_change()
            elif method == "GetConfig":
                reply(json.dumps({"values": self.cfg, "defaults": config.DEFAULTS}))
            elif method == "SetConfig":
                merged = config.sanitize({**self.cfg, **json.loads(args[0] or "{}")})
                config.save(merged)
                self.cfg.clear()
                self.cfg.update(merged)
                self._reschedule_poll()
                self.manager.age()
                self.request_scan()
                reply(json.dumps({"values": self.cfg, "defaults": config.DEFAULTS}))
                self._after_change(force=True)
            elif method == "Rescan":
                self.scan()
                reply(str(self.manager.revision))
            else:
                inv.return_dbus_error(f"{INTERFACE}.Error.UnknownMethod", method)
        except (ValueError, TypeError) as e:
            inv.return_dbus_error(f"{INTERFACE}.Error.InvalidArgs", str(e))

    def _after_change(self, force=False):
        if force:
            self.manager.touch()
        if self.manager.dirty:
            self._save()
            self._publish()


def main(argv=None):
    logging.basicConfig(level=os.environ.get("KLAUDE_MONITOR_LOG", "INFO"),
                        format="%(levelname)s %(name)s: %(message)s", stream=sys.stderr)
    Monitor().start()
    return 0
