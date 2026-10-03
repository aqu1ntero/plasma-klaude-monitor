# SPDX-License-Identifier: GPL-2.0-or-later
"""Small /proc helpers."""

import os


def _stat_fields(pid):
    try:
        with open(f"/proc/{pid}/stat", "rb") as f:
            raw = f.read().decode(errors="replace")
    except OSError:
        return None
    # comm may contain spaces/parentheses: split after the last ')'.
    end = raw.rfind(")")
    if end < 0:
        return None
    return [raw[raw.find("(") + 1:end]] + raw[end + 2:].split()


def start_time(pid):
    """Process start time in clock ticks (field 22), as Claude Code stores it in procStart."""
    f = _stat_fields(pid)
    return f[20] if f and len(f) > 20 else None


def parent(pid):
    f = _stat_fields(pid)
    try:
        return int(f[2]) if f else None
    except (ValueError, IndexError):
        return None


def comm(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip()
    except OSError:
        return None


def is_alive(pid, proc_start=None):
    """True when pid exists and, if proc_start is given, is still the same process (no pid reuse)."""
    if not pid:
        return False
    st = start_time(pid)
    if st is None:
        return False
    return proc_start is None or str(proc_start) == st


def ancestors(pid, limit=32):
    """[(pid, comm)] from pid's parent up to (excluding) pid 1."""
    out = []
    p = parent(pid)
    while p and p > 1 and len(out) < limit:
        out.append((p, comm(p) or ""))
        p = parent(p)
    return out


def environ(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            data = f.read()
    except OSError:
        return {}
    env = {}
    for item in data.split(b"\0"):
        if b"=" in item:
            k, v = item.split(b"=", 1)
            env[k.decode(errors="replace")] = v.decode(errors="replace")
    return env


def claude_pids():
    out = []
    for name in os.listdir("/proc"):
        if name.isdigit() and comm(int(name)) == "claude":
            out.append(int(name))
    return out
