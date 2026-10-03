# SPDX-License-Identifier: GPL-2.0-or-later
"""Read the tail of a Claude Code transcript (<config>/projects/<cwd>/<session>.jsonl) into a summary.

Only the last chunk of the file is parsed: everything the monitor shows (title, current tool, pending
question, last result, API errors) lives at the end, and transcripts can grow to many megabytes.
"""

import json
import os
import re
from datetime import datetime

TAIL_BYTES = 512 * 1024


def transcript_path(config_dir, cwd, session_id):
    return os.path.join(config_dir, "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd), f"{session_id}.jsonl")


def oneline(text, limit=160):
    text = re.sub(r"\s+", " ", str(text or "")).strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def iso_ms(value):
    if not value:
        return None
    try:
        return int(datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return None


def _blocks(entry):
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, list):
        return [b for b in content if isinstance(b, dict)]
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return []


def describe_tool(name, inp):
    inp = inp if isinstance(inp, dict) else {}
    if name == "AskUserQuestion":
        return f"{name}: {question_text(inp)}"
    arg = None
    for key in ("command", "file_path", "path", "pattern", "description", "url", "query", "prompt", "skill"):
        if inp.get(key):
            arg = inp[key]
            break
    return f"{name}: {oneline(arg, 100)}" if arg else name


def question_text(inp):
    qs = inp.get("questions") if isinstance(inp, dict) else None
    if isinstance(qs, list) and qs and isinstance(qs[0], dict):
        text = qs[0].get("question") or qs[0].get("header") or ""
        more = f" (+{len(qs) - 1})" if len(qs) > 1 else ""
        return oneline(text, 200) + more
    return oneline((inp or {}).get("question", ""), 200) if isinstance(inp, dict) else ""


def _read_tail(path):
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > TAIL_BYTES:
                f.seek(size - TAIL_BYTES)
                f.readline()  # drop the partial first line
            data = f.read()
    except OSError:
        return None
    entries = []
    for line in data.splitlines():
        try:
            obj = json.loads(line)
        except ValueError:
            continue  # a line still being written
        if isinstance(obj, dict):
            entries.append(obj)
    return entries


def parse(path):
    """Summary dict, or None when the transcript cannot be read."""
    entries = _read_tail(path)
    if entries is None:
        return None
    s = {
        "title": None, "branch": None, "model": None, "tool": None, "prompt": None, "result": None,
        "summary": None, "error": None, "error_time": None, "pending_question": None,
        "pending_question_time": None, "last_time": None, "turn_end_time": None,
    }
    open_tools = {}  # tool_use id -> (name, input, time) not yet answered by a tool_result
    for e in entries:
        t = e.get("type")
        ts = iso_ms(e.get("timestamp"))
        if ts and not e.get("isSidechain"):
            s["last_time"] = ts
        if e.get("gitBranch"):
            s["branch"] = e["gitBranch"]
        if t == "ai-title" and e.get("aiTitle"):
            s["title"] = e["aiTitle"]
        elif t == "last-prompt" and e.get("lastPrompt"):
            s["prompt"] = oneline(e["lastPrompt"])
        elif t == "assistant" and not e.get("isSidechain"):
            msg = e.get("message") or {}
            if msg.get("model") and not str(msg["model"]).startswith("<"):
                s["model"] = str(msg["model"]).removeprefix("claude-")
            if e.get("isApiErrorMessage"):
                text = " ".join(b.get("text", "") for b in _blocks(e) if b.get("type") == "text")
                s["error"] = oneline(text or e.get("error") or "API error")
                s["error_time"] = ts
                continue
            for b in _blocks(e):
                if b.get("type") == "tool_use":
                    s["tool"] = describe_tool(b.get("name", "?"), b.get("input"))
                    open_tools[b.get("id")] = (b.get("name"), b.get("input"), ts)
                elif b.get("type") == "text" and b.get("text", "").strip():
                    s["result"] = oneline(b["text"], 240)
            # Any real assistant output after an error means Claude recovered.
            if s["error"] and ts and s["error_time"] and ts > s["error_time"]:
                s["error"] = s["error_time"] = None
        elif t == "user" and not e.get("isSidechain"):
            for b in _blocks(e):
                if b.get("type") == "tool_result":
                    open_tools.pop(b.get("tool_use_id"), None)
                elif b.get("type") == "text" and not e.get("isMeta"):
                    text = b.get("text", "")
                    if text and not text.startswith("<"):
                        s["prompt"] = oneline(text)
                        s["tool"] = None
        elif t == "system":
            sub = e.get("subtype")
            if sub == "turn_duration":
                s["turn_end_time"] = ts
            elif sub == "away_summary" and e.get("content"):
                s["summary"] = oneline(re.sub(r"\(disable recaps in /config\)", "", e["content"]), 240)
            elif sub == "api_error":
                err = e.get("error")
                if isinstance(err, dict):
                    err = err.get("message") or err.get("type")
                s["error"] = oneline(err or "API error")
                s["error_time"] = ts
    for name, inp, ts in open_tools.values():
        if name == "AskUserQuestion":
            s["pending_question"] = question_text(inp)
            s["pending_question_time"] = ts
        elif name == "ExitPlanMode":
            s["pending_question"] = "Approve the plan?"
            s["pending_question_time"] = ts
    return s
