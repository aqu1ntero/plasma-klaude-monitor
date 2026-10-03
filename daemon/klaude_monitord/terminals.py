# SPDX-License-Identifier: GPL-2.0-or-later
"""Find and focus the terminal a Claude session runs in, or open a terminal to resume it.

Focusing works by walking up the session's process tree:
  - Yakuake: the Konsole session whose shell is an ancestor of claude is raised, then the window is
    shown (toggled open when retracted) through a KWin script.
  - Konsole: the matching session becomes the current tab of its window, then KWin activates it.
  - kitty (with remote control): the exact tab/split is focused, then KWin activates the OS window.
  - Anything else: KWin activates the first ancestor that owns a window.
On Wayland only KWin may activate another app's window, so window activation always goes through a
short-lived KWin script. These functions block (D-Bus round trips) and run in a worker thread.
"""

import os
import shlex
import shutil
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

from gi.repository import Gio, GLib

from . import procutil

KNOWN = {
    "yakuake": "Yakuake", "konsole": "Konsole", "kitty": "kitty", "alacritty": "Alacritty",
    "wezterm-gui": "WezTerm", "foot": "foot", "footclient": "foot", "gnome-terminal-": "GNOME Terminal",
    "xterm": "XTerm", "tilix": "Tilix", "terminator": "Terminator", "ghostty": "Ghostty", "kgx": "Console",
    "ptyxis": "Ptyxis", "ptyxis-agent": "Ptyxis", "st": "st", "urxvt": "urxvt", "xfce4-terminal": "Xfce Terminal",
    "qterminal": "QTerminal", "cool-retro-term": "cool-retro-term", "rio": "Rio", "contour": "Contour",
}
MULTIPLEXERS = ("tmux: server", "tmux", "screen", "SCREEN", "zellij")
TIMEOUT_MS = 2500


def _match(comm):
    if comm in KNOWN:
        return comm
    for key in KNOWN:
        if key.endswith("-") and comm.startswith(key):
            return key
    return None


def detect(pid, kind=None):
    """{"kind", "label", "pid"} describing where the session runs."""
    chain = procutil.ancestors(pid)
    mux = None
    for p, comm in chain:
        if comm in MULTIPLEXERS and not mux:
            mux = comm.split(":")[0]
        m = _match(comm)
        if m:
            label = KNOWN[m] + (f" ({mux})" if mux else "")
            return {"kind": "kitty" if m == "kitty" else m.rstrip("-"), "label": label, "pid": p, "mux": mux}
    if mux:
        return {"kind": "mux", "label": mux, "pid": None, "mux": mux}
    if kind == "bg":
        return {"kind": "none", "label": "background", "pid": None, "mux": None}
    for _p, comm in chain:
        if comm in ("sshd", "sshd-session"):
            return {"kind": "none", "label": "ssh", "pid": None, "mux": None}
    return {"kind": "other", "label": chain[0][1] if chain else "?", "pid": None, "mux": None}


# ---- D-Bus helpers -------------------------------------------------------------------------------
def _bus():
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def _call(service, path, iface, method, args=None, sig=None):
    params = GLib.Variant(sig, tuple(args)) if sig else None
    reply = _bus().call_sync(service, path, iface, method, params, None, Gio.DBusCallFlags.NONE, TIMEOUT_MS, None)
    return reply.unpack() if reply else ()


def _children(service, path):
    xml = _call(service, path, "org.freedesktop.DBus.Introspectable", "Introspect")[0]
    return [n.get("name") for n in ET.fromstring(xml).findall("node") if n.get("name")]


def _service_pid(service):
    try:
        return _call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                     "GetConnectionUnixProcessID", [service], "(s)")[0]
    except GLib.Error:
        return None


def _konsole_session_for(service, chain_pids):
    """Konsole session number (as in /Sessions/N) whose shell is in chain_pids."""
    for name in _children(service, "/Sessions"):
        try:
            shell = _call(service, f"/Sessions/{name}", "org.kde.konsole.Session", "processId")[0]
        except GLib.Error:
            continue
        if shell in chain_pids:
            return int(name)
    return None


def _kwin_script(source):
    """Run a one-shot KWin script."""
    d = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir(), "klaude-monitor")
    os.makedirs(d, exist_ok=True)
    name = f"klaude-monitor-{os.getpid()}-{int(time.time() * 1000)}"
    path = os.path.join(d, name + ".js")
    with open(path, "w") as f:
        f.write(source)
    try:
        sid = _call("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "loadScript", [path, name], "(ss)")[0]
        if sid < 0:
            return False
        try:
            _call("org.kde.KWin", f"/Scripting/Script{sid}", "org.kde.kwin.Script", "run")
        except GLib.Error:
            # Older KWin object path
            _call("org.kde.KWin", f"/{sid}", "org.kde.kwin.Script", "run")
        time.sleep(0.3)
        return True
    except GLib.Error:
        return False
    finally:
        try:
            _call("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "unloadScript", [name], "(s)")
        except GLib.Error:
            pass
        try:
            os.unlink(path)
        except OSError:
            pass


ACTIVATE_JS = """
const pids = %(pids)s;
const yakuake = %(yakuake)s;
let target = null;
const wins = workspace.windowList();
for (const pid of pids) {
    for (const w of wins) {
        if (w.pid === pid && !w.deleted && (w.normalWindow || w.dialog || yakuake)) { target = w; break; }
    }
    if (target) break;
}
if (target) {
    if (target.minimized) target.minimized = false;
    workspace.activeWindow = target;
} else if (yakuake) {
    callDBus("org.kde.yakuake", "/yakuake/window", "org.kde.yakuake", "toggleWindowState");
}
"""


def activate_window(pids, yakuake=False):
    return _kwin_script(ACTIVATE_JS % {"pids": list(map(int, pids)), "yakuake": "true" if yakuake else "false"})


# ---- focus ---------------------------------------------------------------------------------------
def focus(pid, terminal):
    """Bring the terminal of a live session to the front. Returns (ok, message)."""
    if not procutil.is_alive(pid):
        return False, "session process is not running"
    chain = procutil.ancestors(pid)
    chain_pids = [pid] + [p for p, _ in chain]
    kind = (terminal or {}).get("kind")
    try:
        if kind == "yakuake":
            return _focus_yakuake(chain_pids)
        if kind == "konsole":
            return _focus_konsole(terminal["pid"], chain_pids)
        if kind == "kitty":
            return _focus_kitty(pid, terminal["pid"], chain_pids)
    except GLib.Error as e:
        # Fall through to plain window activation.
        err = e.message
    else:
        err = None
    if activate_window(chain_pids):
        return True, "window activated" + (f" (terminal tab not selected: {err})" if err else "")
    return False, err or "no window found for this session"


def _focus_yakuake(chain_pids):
    svc = "org.kde.yakuake"
    n = _konsole_session_for(svc, chain_pids)
    if n is not None:
        # Yakuake terminal ids and Konsole session numbers are both creation-ordered; map by rank.
        terms = sorted(int(x) for x in _call(svc, "/yakuake/sessions", "org.kde.yakuake", "terminalIdList")[0].split(",") if x)
        konsole = sorted(int(x) for x in _children(svc, "/Sessions"))
        tid = terms[konsole.index(n)] if len(terms) == len(konsole) and n in konsole else n - 1
        sid = _call(svc, "/yakuake/sessions", "org.kde.yakuake", "sessionIdForTerminalId", [tid], "(i)")[0]
        if sid >= 0:
            _call(svc, "/yakuake/sessions", "org.kde.yakuake", "raiseSession", [sid], "(i)")
    activate_window(chain_pids, yakuake=True)
    return True, "yakuake tab raised" if n is not None else "yakuake shown (tab not found)"


def _focus_konsole(konsole_pid, chain_pids):
    names = _call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames")[0]
    service = None
    for name in names:
        if name.startswith("org.kde.konsole") and _service_pid(name) == konsole_pid:
            service = name
            break
    tab = False
    if service:
        n = _konsole_session_for(service, chain_pids)
        if n is not None:
            for w in _children(service, "/Windows"):
                sessions = _call(service, f"/Windows/{w}", "org.kde.konsole.Window", "sessionList")[0]
                if str(n) in sessions:
                    _call(service, f"/Windows/{w}", "org.kde.konsole.Window", "setCurrentSession", [n], "(i)")
                    tab = True
                    break
    activate_window(chain_pids)
    return True, "konsole tab selected" if tab else "konsole window activated"


def _focus_kitty(pid, kitty_pid, chain_pids):
    env = procutil.environ(pid)
    wid = env.get("KITTY_WINDOW_ID")
    tab = False
    if wid and shutil.which("kitty"):
        r = subprocess.run(["kitty", "@", "--to", f"unix:@kitty-{kitty_pid}", "focus-window", "--match", f"id:{wid}"],
                           capture_output=True, timeout=3)
        tab = r.returncode == 0
    activate_window(chain_pids)
    return True, "kitty window focused" if tab else "kitty activated (enable remote control for exact tabs)"


# ---- open / resume -------------------------------------------------------------------------------
def claude_bin():
    path = os.environ.get("PATH", "") + os.pathsep + os.path.expanduser("~/.local/bin")
    return shutil.which("claude", path=path) or "claude"


def resume_command(session_id, account, default_account):
    env = f"CLAUDE_CONFIG_DIR={shlex.quote(account)} " if account and account != default_account else ""
    return f"{env}{shlex.quote(claude_bin())} --resume {shlex.quote(session_id)}"


def _yakuake_running():
    return _service_pid("org.kde.yakuake") is not None


def open_resume(cwd, session_id, account, default_account, cfg, original_kind=None):
    """Open a new terminal running `claude --resume`. Returns (ok, message)."""
    cwd = cwd if cwd and os.path.isdir(cwd) else os.path.expanduser("~")
    cmd = resume_command(session_id, account, default_account)
    pref = cfg.get("preferred_terminal", "auto")
    if pref == "auto":
        candidates = [original_kind] if original_kind in ("yakuake", "konsole", "kitty") else []
        candidates += ["yakuake", "konsole", "kitty"]
    else:
        candidates = [pref]
    last = "no usable terminal found"
    for term in candidates:
        try:
            if term == "yakuake" and _yakuake_running():
                svc = "org.kde.yakuake"
                _call(svc, "/yakuake/sessions", "org.kde.yakuake", "addSession")
                tid = _call(svc, "/yakuake/sessions", "org.kde.yakuake", "activeTerminalId")[0]
                _call(svc, "/yakuake/sessions", "org.kde.yakuake", "runCommandInTerminal",
                      [tid, f"cd {shlex.quote(cwd)} && {cmd}"], "(is)")
                activate_window([_service_pid(svc) or 0], yakuake=True)
                return True, "opened in yakuake"
            if term == "konsole" and shutil.which("konsole"):
                _spawn(["konsole", "--workdir", cwd, "-e", "sh", "-c", f"{cmd}; exec \"${{SHELL:-sh}}\""], cwd)
                return True, "opened in konsole"
            if term == "kitty" and shutil.which("kitty"):
                _spawn(["kitty", "--directory", cwd, "sh", "-c", f"{cmd}; exec \"${{SHELL:-sh}}\""], cwd)
                return True, "opened in kitty"
            if term == "custom" and cfg.get("custom_terminal_cmd"):
                line = cfg["custom_terminal_cmd"].replace("{cwd}", shlex.quote(cwd)).replace("{cmd}", shlex.quote(cmd))
                _spawn(["sh", "-c", line], cwd)
                return True, "opened in custom terminal"
        except (GLib.Error, OSError) as e:
            last = str(e)
    return False, last


def _spawn(argv, cwd):
    subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
