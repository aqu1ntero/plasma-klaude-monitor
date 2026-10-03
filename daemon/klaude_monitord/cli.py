# SPDX-License-Identifier: GPL-2.0-or-later
"""klaude-monitor: run the daemon, query it, and manage the Claude Code hooks."""

import argparse
import json
import os
import shutil
import sys
import time

from . import BUS_NAME, INTERFACE, OBJECT_PATH, __version__

ICONS = {"needs_input": "!", "working": "*", "completed": "+", "idle": "-", "error": "x", "ended": ".",
         "unknown": "?"}


def _call(method, *args, timeout=25000):
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    params = GLib.Variant("(" + "s" * len(args) + ")", args) if args else None
    reply = bus.call_sync(BUS_NAME, OBJECT_PATH, INTERFACE, method, params, None,
                          Gio.DBusCallFlags.NONE, timeout, None)
    return reply.unpack()[0]


def _ago(ms):
    if not ms:
        return "-"
    s = max(0, int(time.time() - ms / 1000))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m"
    return f"{s // 3600}h{(s % 3600) // 60:02d}m"


def _accounts():
    from .service import DEFAULT_ACCOUNT
    dirs = {DEFAULT_ACCOUNT}
    try:
        state = json.loads(_call("GetState", timeout=5000))
        dirs.update(a["dir"] for a in state.get("accounts", []))
    except Exception:
        pass
    return sorted(dirs)


def cmd_status(a):
    state = json.loads(_call("GetState"))
    if a.json:
        print(json.dumps(state, indent=2, ensure_ascii=False))
        return 0
    c = state["counts"]
    print(f"needs you {c['needs_input']}  working {c['working']}  completed {c['completed']}  "
          f"errors {c['error']}  unknown {c['unknown']}  idle {c['idle']}  (rev {state['revision']}, "
          f"hooks {'on' if state['monitor']['hooks'] else 'off'})")
    for s in state["sessions"]:
        detail = (s.get("waiting") or {}).get("text") or s.get("error") or s.get("tool") or s.get("result") or ""
        term = (s.get("terminal") or {}).get("label", "")
        print(f" {ICONS.get(s['state'], ' ')} {s['state']:<11} {_ago(s['since']):>6}  {s['project'][:22]:<22} "
              f"{(s.get('title') or '')[:36]:<36} [{s['certainty']}/{term}] {detail[:60]}")
    return 0


def cmd_history(a):
    events = json.loads(_call("GetHistory", json.dumps({"limit": a.limit})))
    for e in reversed(events):
        lag = (e["detected_time"] - e["event_time"]) / 1000
        when = time.strftime("%m-%d %H:%M:%S", time.localtime(e["event_time"] / 1000))
        d = e.get("detail") or {}
        text = d.get("text") or d.get("tool") or d.get("reason") or ""
        lagtxt = f" (+{lag:.0f}s)" if lag >= 2 else ""
        print(f"{when}{lagtxt}  {e['kind']:<17} {(e.get('project') or '')[:20]:<20} {str(text)[:70]}")
    return 0


def _find(prefix):
    state = json.loads(_call("GetState"))
    hits = [s for s in state["sessions"] if s["id"].startswith(prefix) or s["project"] == prefix]
    if len(hits) != 1:
        print(f"{len(hits)} sessions match {prefix!r}", file=sys.stderr)
        return None
    return hits[0]["id"]


def cmd_focus(a):
    sid = _find(a.session)
    if not sid:
        return 1
    r = json.loads(_call("ResumeSession" if a.resume else "FocusSession", sid))
    print(r["message"])
    return 0 if r["ok"] else 1


def cmd_forget(a):
    ok = 0
    for prefix in a.session:
        state = json.loads(_call("GetState"))
        for s in state["sessions"]:
            if s["id"].startswith(prefix) and _call("Forget", s["id"]):
                ok += 1
    print(f"forgot {ok} session(s)")
    return 0


def cmd_hooks(a):
    from . import hooks
    dirs = [os.path.normpath(os.path.expanduser(d)) for d in a.config_dir] or _accounts()
    command = a.command or shutil.which("klaude-monitor-hook") or os.path.expanduser("~/.local/bin/klaude-monitor-hook")
    rc = 0
    for d in dirs:
        try:
            if a.action == "install":
                events = hooks.install(d, command)
                print(f"{d}: installed for {len(events)} events")
            elif a.action == "uninstall":
                print(f"{d}: removed {hooks.uninstall(d)} hook entries")
            else:
                found = hooks.status(d)
                print(f"{d}: {'installed (' + ', '.join(found) + ')' if found else 'not installed'}")
        except (OSError, ValueError) as e:
            print(f"{d}: {e}", file=sys.stderr)
            rc = 1
    return rc


def cmd_config(a):
    if a.set:
        changes = {}
        for item in a.set:
            key, _, value = item.partition("=")
            try:
                changes[key] = json.loads(value)
            except ValueError:
                changes[key] = value
        out = json.loads(_call("SetConfig", json.dumps(changes)))
    else:
        out = json.loads(_call("GetConfig"))
    print(json.dumps(out["values"], indent=2))
    return 0


def cmd_uninstall(a):
    """Stop and remove the service and the hooks (what install.sh runtime / the widgets installed)."""
    import subprocess
    from . import config, hooks
    from .service import DEFAULT_ACCOUNT
    home = os.path.expanduser("~")
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    cfg_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    bindir = os.path.dirname(os.path.realpath(sys.argv[0])) if sys.argv[0].endswith("klaude-monitor") else \
        os.path.join(home, ".local", "bin")
    dirs = set(_accounts_offline(DEFAULT_ACCOUNT))
    for d in sorted(dirs):
        try:
            n = hooks.uninstall(d)
            if n:
                print(f"removed {n} hook entries from {d}/settings.json")
        except (OSError, ValueError) as e:
            print(f"{d}: {e}", file=sys.stderr)
    if shutil.which("systemctl"):
        subprocess.run(["systemctl", "--user", "disable", "--now", "klaude-monitord.service"],
                       capture_output=True)
    files = [
        os.path.join(cfg_home, "systemd", "user", "klaude-monitord.service"),
        os.path.join(data, "dbus-1", "services", f"{BUS_NAME}.service"),
        os.path.join(data, "icons", "hicolor", "scalable", "apps", "klaude-monitor.svg"),
        os.path.join(data, "applications", "klaude-monitor.desktop"),
    ] + [os.path.join(bindir, n) for n in ("klaude-monitord", "klaude-monitor", "klaude-monitor-hook")]
    for f in files:
        try:
            os.unlink(f)
        except OSError:
            pass
    lib = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if os.path.basename(lib) == "klaude-monitor":
        shutil.rmtree(lib, ignore_errors=True)
    if shutil.which("systemctl"):
        subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True)
    if a.purge:
        shutil.rmtree(config.STATE_DIR, ignore_errors=True)
        shutil.rmtree(config.CONFIG_DIR, ignore_errors=True)
        print("removed the service, its history and its settings")
    else:
        print(f"removed the service (history kept in {config.STATE_DIR}; use --purge to delete it)")
    print("The widgets stay installed; remove them from Plasma if you no longer want them.")
    return 0


def _accounts_offline(default):
    """Config dirs to clean: the default one plus those the service remembered."""
    dirs = {default}
    try:
        dirs.update(a["dir"] for a in json.loads(_call("GetState", timeout=3000)).get("accounts", []))
    except Exception:
        pass
    return [d for d in dirs if os.path.isdir(d)]


def cmd_doctor(_a):
    ok = True

    def check(label, good, hint=""):
        nonlocal ok
        ok &= bool(good)
        print(f"[{'ok' if good else '!!'}] {label}" + (f" — {hint}" if not good and hint else ""))

    try:
        version = _call("Ping", timeout=5000)
        check(f"daemon reachable on the session bus (v{version})", True)
    except Exception as e:
        check("daemon reachable on the session bus", False, str(e))
    check("hook script on PATH", shutil.which("klaude-monitor-hook"), "run install.sh runtime")
    for d in _accounts():
        from . import hooks
        check(f"hooks in {d}/settings.json", hooks.status(d), "klaude-monitor hooks install (optional)")
    for tool in ("kpackagetool6", "qdbus6"):
        check(f"{tool} available", shutil.which(tool), "optional")
    return 0 if ok else 1


def main(argv=None):
    p = argparse.ArgumentParser(prog="klaude-monitor", description="Klaude Monitor — Claude Code session monitor")
    p.add_argument("--version", action="version", version=__version__)
    sub = p.add_subparsers(dest="cmd")
    sub.add_parser("daemon", help="run the monitor daemon (normally started by systemd/D-Bus)")
    s = sub.add_parser("status", help="show sessions")
    s.add_argument("--json", action="store_true")
    h = sub.add_parser("history", help="show recent events")
    h.add_argument("-n", "--limit", type=int, default=40)
    f = sub.add_parser("focus", help="focus a session's terminal (id prefix or project name)")
    f.add_argument("session")
    f.add_argument("--resume", action="store_true", help="open a new terminal with claude --resume")
    g = sub.add_parser("forget", help="drop ended/lost sessions from the live list (history is kept)")
    g.add_argument("session", nargs="+", help="session id or id prefix")
    k = sub.add_parser("hooks", help="manage the Claude Code hooks")
    k.add_argument("action", choices=["install", "uninstall", "status"])
    k.add_argument("--config-dir", action="append", default=[], help="Claude config dir (repeatable)")
    k.add_argument("--command", help="hook command (default: klaude-monitor-hook on PATH)")
    c = sub.add_parser("config", help="show or change the shared configuration")
    c.add_argument("set", nargs="*", metavar="KEY=VALUE")
    sub.add_parser("doctor", help="check the installation")
    u = sub.add_parser("uninstall", help="stop and remove the service and the Claude Code hooks")
    u.add_argument("--purge", action="store_true", help="also delete the history and settings")
    a = p.parse_args(argv)
    if a.cmd == "daemon":
        from .service import main as daemon_main
        return daemon_main()
    handlers = {"status": cmd_status, "history": cmd_history, "focus": cmd_focus, "forget": cmd_forget, "hooks": cmd_hooks,
                "config": cmd_config, "doctor": cmd_doctor, "uninstall": cmd_uninstall}
    if a.cmd not in handlers:
        p.print_help()
        return 2
    try:
        return handlers[a.cmd](a)
    except Exception as e:  # D-Bus errors etc.
        print(f"klaude-monitor: {e}", file=sys.stderr)
        return 1
