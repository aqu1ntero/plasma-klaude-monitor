# SPDX-License-Identifier: GPL-2.0-or-later
"""Add/remove the Klaude Monitor hook in Claude Code's settings.json (one per config dir).

Only entries whose command contains MARKER are touched; everything else in the file is kept.
A backup of the original file is written next to it before the first change.
"""

import json
import os
import shutil

MARKER = "klaude-monitor-hook"

# event -> matcher (None: the event takes no matcher)
EVENTS = {
    "SessionStart": None,
    "SessionEnd": None,
    "UserPromptSubmit": None,
    "Notification": None,
    "PermissionRequest": "*",
    "PermissionDenied": "*",
    "Stop": None,
    "StopFailure": None,
    "PreToolUse": "AskUserQuestion|ExitPlanMode",
    "PostToolUse": "AskUserQuestion|ExitPlanMode",
}


def settings_path(config_dir):
    return os.path.join(config_dir, "settings.json")


def _load(path):
    try:
        with open(path) as f:
            text = f.read()
    except FileNotFoundError:
        return {}
    data = json.loads(text) if text.strip() else {}
    if not isinstance(data, dict):
        raise ValueError(f"{path}: not a JSON object")
    return data


def _write(path, data):
    real = os.path.realpath(path)  # keep symlinked settings (dotfile managers) intact
    tmp = real + ".klaude-monitor.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if os.path.exists(real):
        shutil.copymode(real, tmp)
    os.replace(tmp, real)


def _strip(hooks):
    """Remove our entries; returns the number removed."""
    removed = 0
    for event in list(hooks):
        groups = hooks[event]
        if not isinstance(groups, list):
            continue
        kept = []
        for g in groups:
            if isinstance(g, dict) and isinstance(g.get("hooks"), list):
                inner = [h for h in g["hooks"] if MARKER not in str(h.get("command", ""))]
                removed += len(g["hooks"]) - len(inner)
                if inner:
                    kept.append({**g, "hooks": inner})
            else:
                kept.append(g)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    return removed


def status(config_dir):
    try:
        data = _load(settings_path(config_dir))
    except (OSError, ValueError):
        return []
    found = []
    for event, groups in (data.get("hooks") or {}).items():
        for g in groups if isinstance(groups, list) else []:
            for h in (g.get("hooks") or []) if isinstance(g, dict) else []:
                if MARKER in str(h.get("command", "")):
                    found.append(event)
    return found


def install(config_dir, command):
    path = settings_path(config_dir)
    data = _load(path)
    if os.path.exists(path) and not os.path.exists(path + ".klaude-monitor.bak"):
        shutil.copy2(os.path.realpath(path), path + ".klaude-monitor.bak")
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError(f"{path}: 'hooks' is not an object")
    _strip(hooks)
    for event, matcher in EVENTS.items():
        group = {"hooks": [{"type": "command", "command": command, "timeout": 5}]}
        if matcher is not None:
            group = {"matcher": matcher, **group}
        hooks.setdefault(event, []).append(group)
    os.makedirs(config_dir, exist_ok=True)
    _write(path, data)
    return list(EVENTS)


def uninstall(config_dir):
    path = settings_path(config_dir)
    if not os.path.exists(path):
        return 0
    data = _load(path)
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return 0
    removed = _strip(hooks)
    if not hooks:
        del data["hooks"]
    if removed:
        _write(path, data)
    return removed
