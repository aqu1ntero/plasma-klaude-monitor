#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Feed the running monitor with fake Claude Code sessions (for testing and screenshots).

    tools/demo.py start     create a demo account with several sessions in different states
    tools/demo.py step      advance the scenario (a question gets answered, a task finishes…)
    tools/demo.py stop      remove everything the demo created

The demo account lives in $XDG_RUNTIME_DIR/klaude-demo/.claude-demo and is registered through the
monitor's extra_config_dirs setting. Each fake session is backed by a `sleep` process, so the
monitor's liveness checks (pid + start time) behave exactly as with real sessions.
"""

import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

BASE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "klaude-demo")
ACCOUNT = os.path.join(BASE, ".claude-demo")
STATE = os.path.join(BASE, "state.json")
SPOOL = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "klaude-monitor", "spool")
HOME = os.path.expanduser("~")

SESSIONS = [
    # name, project, status, title
    ("ask", "api-server", "waiting", "Migrate auth to OAuth 2.1"),
    ("perm", "infra", "waiting", "Rotate staging certificates"),
    ("work", "web-frontend", "busy", "Fix flaky checkout test"),
    ("done", "docs-site", "busy", "Write the release notes"),
    ("err", "data-pipeline", "busy", "Backfill March events"),
    ("idle", "dotfiles", "idle", "Tidy shell aliases"),
]


def cli(*args):
    return subprocess.run(["klaude-monitor", *args], capture_output=True, text=True)


def now_ms():
    return int(time.time() * 1000)


def iso(ms):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(ms / 1000)) + ".000Z"


def proc_start(pid):
    with open(f"/proc/{pid}/stat") as f:
        raw = f.read()
    return raw[raw.rfind(")") + 2:].split()[19]


def transcript_path(cwd, sid):
    return os.path.join(ACCOUNT, "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd), f"{sid}.jsonl")


def append(path, *entries):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")


def write_state(s, status, waiting=None):
    t = now_ms()
    data = {"pid": s["pid"], "sessionId": s["id"], "cwd": s["cwd"], "startedAt": s["started"],
            "procStart": s["procStart"], "version": "demo", "kind": "interactive", "entrypoint": "cli",
            "name": s["project"], "status": status, "updatedAt": t, "statusUpdatedAt": t}
    if waiting:
        data["waitingFor"] = waiting
    path = os.path.join(ACCOUNT, "sessions", f"{s['pid']}.json")
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def hook(s, name, **payload):
    os.makedirs(SPOOL, exist_ok=True)
    t = now_ms()
    body = {"session_id": s["id"], "hook_event_name": name, "cwd": s["cwd"],
            "transcript_path": transcript_path(s["cwd"], s["id"]), **payload}
    path = os.path.join(SPOOL, f"{t}-{os.getpid()}-{uuid.uuid4().hex[:6]}.json")
    with open(path + ".tmp", "w") as f:
        f.write(json.dumps({"ts": t, "pid": s["pid"], "account": ACCOUNT}) + "\n" + json.dumps(body))
    os.replace(path + ".tmp", path)


def start():
    if os.path.exists(STATE):
        stop()
    os.makedirs(os.path.join(ACCOUNT, "sessions"), exist_ok=True)
    cfg = json.loads(cli("config").stdout or "{}")
    extra = cfg.get("extra_config_dirs", [])
    saved = {"extra_before": extra, "sessions": {}}
    cli("config", "extra_config_dirs=" + json.dumps(extra + [ACCOUNT]))
    base = now_ms()
    for i, (key, project, status, title) in enumerate(SESSIONS):
        p = subprocess.Popen(["sleep", "86400"], start_new_session=True)
        sid = str(uuid.uuid4())
        cwd = os.path.join(HOME, "src", project)
        started = base - (i + 1) * 7 * 60000
        s = {"key": key, "pid": p.pid, "procStart": proc_start(p.pid), "id": sid, "cwd": cwd,
             "project": project, "started": started}
        saved["sessions"][key] = s
        tp = transcript_path(cwd, sid)
        append(tp, {"type": "ai-title", "aiTitle": title},
               {"type": "user", "timestamp": iso(started), "gitBranch": "main",
                "message": {"content": title}})
        if key == "ask":
            append(tp, {"type": "assistant", "timestamp": iso(base - 90000), "message": {
                "model": "claude-opus-5-5", "content": [
                    {"type": "text", "text": "Two options for the token store."},
                    {"type": "tool_use", "id": "toolu_ask", "name": "AskUserQuestion", "input": {"questions": [
                        {"question": "Keep refresh tokens in Redis or in Postgres?"}]}}]}})
        elif key == "work":
            append(tp, {"type": "assistant", "timestamp": iso(base - 5000), "message": {
                "model": "claude-sonnet-5-5", "content": [
                    {"type": "tool_use", "id": "toolu_w", "name": "Bash",
                     "input": {"command": "npm test -- checkout.spec.ts --repeat 20"}}]}})
        elif key == "idle":
            append(tp, {"type": "assistant", "timestamp": iso(base - 3 * 3600000), "message": {
                "model": "claude-haiku-4-5", "content": [{"type": "text", "text": "Aliases cleaned up."}]}})
        write_state(s, status, "permission" if key == "perm" else None)
    with open(STATE, "w") as f:
        json.dump(saved, f)
    time.sleep(1.5)  # let the monitor see the sessions before the hook events
    perm = saved["sessions"]["perm"]
    hook(perm, "PermissionRequest", tool_name="Bash",
         tool_input={"command": "kubectl -n staging delete secret tls-staging"})
    print("demo started: 6 sessions (klaude-monitor status)")


def step():
    with open(STATE) as f:
        saved = json.load(f)
    ss = saved["sessions"]
    t = now_ms()
    # docs-site finishes its task
    append(transcript_path(ss["done"]["cwd"], ss["done"]["id"]),
           {"type": "assistant", "timestamp": iso(t), "message": {"model": "claude-opus-5-5", "content": [
               {"type": "text", "text": "Release notes drafted in CHANGELOG.md (12 entries, 3 breaking changes)."}]}},
           {"type": "system", "subtype": "turn_duration", "durationMs": 420000, "timestamp": iso(t)})
    write_state(ss["done"], "idle")
    hook(ss["done"], "Stop", last_assistant_message="Release notes drafted in CHANGELOG.md (12 entries, 3 breaking changes).")
    # data-pipeline fails
    append(transcript_path(ss["err"]["cwd"], ss["err"]["id"]),
           {"type": "assistant", "isApiErrorMessage": True, "timestamp": iso(t),
            "message": {"content": [{"type": "text", "text": "API Error: 529 Overloaded — the request was not completed"}]}})
    hook(ss["err"], "StopFailure", error="API Error: 529 Overloaded")
    write_state(ss["err"], "idle")
    print("step: docs-site finished, data-pipeline failed")


def stop():
    if not os.path.exists(STATE):
        print("demo not running")
        return
    with open(STATE) as f:
        saved = json.load(f)
    for s in saved["sessions"].values():
        try:
            os.kill(s["pid"], signal.SIGTERM)
        except OSError:
            pass
    cli("config", "extra_config_dirs=" + json.dumps(saved.get("extra_before", [])))
    shutil.rmtree(BASE, ignore_errors=True)
    time.sleep(1.5)  # let the monitor notice the processes are gone, then drop them from the list
    cli("forget", *[s["id"] for s in saved["sessions"].values()])
    print("demo stopped (its sessions stay in the history)")


if __name__ == "__main__":
    {"start": start, "step": step, "stop": stop}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
