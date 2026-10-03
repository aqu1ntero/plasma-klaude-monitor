# SPDX-License-Identifier: GPL-2.0-or-later
"""Paths and the shared configuration (one file, read by the daemon, edited from either widget)."""

import json
import os
from pathlib import Path

HOME = Path.home()


def _xdg(var, fallback):
    value = os.environ.get(var)
    return Path(value) if value else HOME / fallback


CONFIG_DIR = _xdg("XDG_CONFIG_HOME", ".config") / "klaude-monitor"
STATE_DIR = _xdg("XDG_STATE_HOME", ".local/state") / "klaude-monitor"
CONFIG_FILE = CONFIG_DIR / "config.json"
DB_FILE = STATE_DIR / "history.db"
# Hook events are dropped here as one file each, so they survive a stopped daemon.
SPOOL_DIR = STATE_DIR / "spool"

DEFAULTS = {
    # History
    "retention_days": 14,
    # Fallback re-scan interval when no inotify/pidfd event arrives.
    "poll_interval_s": 5,
    # A finished task counts as "recently completed" for this long, then the session is just idle.
    "recent_window_min": 30,
    # Ended or lost sessions stay in the live list this long (history keeps them for good).
    "ended_visible_min": 60,
    # Notifications (sent once, by the daemon, whatever widgets are open)
    "notify_needs_input": True,
    "notify_completed": True,
    "notify_error": True,
    "notify_unknown": False,
    "notify_min_task_s": 30,
    # Opening sessions: auto | yakuake | konsole | kitty | custom
    "preferred_terminal": "auto",
    # custom: placeholders {cwd} and {cmd}, e.g. "alacritty --working-directory {cwd} -e sh -c {cmd}"
    "custom_terminal_cmd": "",
    # Claude config dirs to watch besides ~/.claude and the CLAUDE_CONFIG_DIR of running sessions.
    "extra_config_dirs": [],
}

LIMITS = {
    "retention_days": (1, 3650),
    "poll_interval_s": (1, 600),
    "recent_window_min": (1, 1440),
    "ended_visible_min": (0, 10080),
    "notify_min_task_s": (0, 86400),
}


def sanitize(data):
    """Keep only known keys with the right type; clamp numbers."""
    out = dict(DEFAULTS)
    if not isinstance(data, dict):
        return out
    for key, default in DEFAULTS.items():
        if key not in data:
            continue
        value = data[key]
        if isinstance(default, bool):
            if isinstance(value, bool):
                out[key] = value
        elif isinstance(default, int):
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                lo, hi = LIMITS.get(key, (None, None))
                value = int(value)
                if lo is not None:
                    value = max(lo, min(hi, value))
                out[key] = value
        elif isinstance(default, str):
            if isinstance(value, str):
                out[key] = value
        elif isinstance(default, list):
            if isinstance(value, list):
                out[key] = [str(v) for v in value if isinstance(v, str) and v]
    if out["preferred_terminal"] not in ("auto", "yakuake", "konsole", "kitty", "custom"):
        out["preferred_terminal"] = "auto"
    return out


def load():
    try:
        return sanitize(json.loads(CONFIG_FILE.read_text()))
    except (OSError, ValueError):
        return dict(DEFAULTS)


def save(cfg):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(cfg, indent=2) + "\n")
    os.replace(tmp, CONFIG_FILE)
