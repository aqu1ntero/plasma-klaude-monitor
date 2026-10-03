# SPDX-License-Identifier: GPL-2.0-or-later
"""Session model and state machine.

Every session is in exactly one state, so per-state counts never count a session twice:

    needs_input  Claude waits for a permission, an answer or a plan approval.
    working      a turn is running.
    completed    the last turn finished recently (recent_window_min); then the session becomes idle.
    idle         alive, waiting for a new prompt, nothing recent to report.
    error        the last turn failed (API error, StopFailure); stays until new activity or an ack.
    ended        the process exited and Claude Code reported it (SessionEnd hook).
    unknown      the monitor lost track: the process vanished without an exit event, or its state
                 file is missing/unreadable. Never reported as "completed".

Signals come from three sources with different certainty:
    hook        Claude Code hooks (high)
    state-file  <config>/sessions/<pid>.json written by Claude Code (medium)
    transcript  inferred from the transcript, or recovered at monitor start (low)

A signal only changes the state if it is at least as recent as the one that set the current state,
so a late re-read of an older state file never overrides a newer hook event.
"""

import os

from .history import now_ms

NEEDS_INPUT = "needs_input"
WORKING = "working"
COMPLETED = "completed"
IDLE = "idle"
ERROR = "error"
ENDED = "ended"
UNKNOWN = "unknown"
STATES = (NEEDS_INPUT, WORKING, ERROR, COMPLETED, UNKNOWN, IDLE, ENDED)
ACTIVE = (NEEDS_INPUT, WORKING)

CERTAINTY = {"hook": "high", "state-file": "medium", "transcript": "low", "recovered": "low", "monitor": "low"}
RANK = {"high": 3, "medium": 2, "low": 1}

# A working session with no transcript activity for this long is flagged as possibly stale.
STALE_MS = 20 * 60 * 1000


class Session:
    def __init__(self, sid):
        self.id = sid
        self.pid = None
        self.proc_start = None
        self.account = None
        self.cwd = ""
        self.name = None
        self.kind = None  # interactive | bg | ...
        self.started_at = None
        self.state = UNKNOWN
        self.source = "monitor"
        self.since = None          # when the current state started
        self.signal_time = 0       # time of the signal that set the current state
        self.file_status_time = None  # statusUpdatedAt already applied from the state file
        self.alive = False
        self.task_started = None   # start of the current/last turn
        self.last_activity = None
        self.last_event = None     # {"kind", "text", "time"}
        self.waiting = None        # {"kind": permission|question|plan|elicitation|input, "text", "tool", "since"}
        self.result = None
        self.error = None
        self.ended_reason = None
        self.terminal = None       # {"kind", "label", "pid"}
        self.t = {}                # last transcript summary
        self.transcript = None
        self.transcript_mtime = None
        self.hooked = False        # a hook event was seen for this session

    @property
    def project(self):
        return os.path.basename(self.cwd.rstrip("/")) or self.cwd or "?"

    @property
    def certainty(self):
        return CERTAINTY.get(self.source, "low")

    def to_json(self, now, account_label=None):
        stale = (
            self.state == WORKING and self.last_activity is not None and now - self.last_activity > STALE_MS
        )
        return {
            "id": self.id,
            "pid": self.pid,
            "alive": self.alive,
            "kind": self.kind,
            "account": self.account,
            "accountLabel": account_label,
            "cwd": self.cwd,
            "project": self.project,
            "branch": self.t.get("branch"),
            "title": self.t.get("title") or self.name,
            "state": self.state,
            "source": self.source,
            "certainty": "low" if stale else self.certainty,
            "stale": stale,
            "since": self.since,
            "startedAt": self.started_at,
            "lastActivity": self.last_activity,
            "lastEvent": self.last_event,
            "summary": self.t.get("summary"),
            "tool": self.t.get("tool") if self.state in ACTIVE else None,
            "prompt": self.t.get("prompt"),
            "model": self.t.get("model"),
            "waiting": self.waiting if self.state == NEEDS_INPUT else None,
            "result": (self.result or self.t.get("result")) if self.state in (COMPLETED, IDLE, ENDED) else None,
            "error": self.error if self.state == ERROR else None,
            "endedReason": self.ended_reason if self.state in (ENDED, UNKNOWN) else None,
            "terminal": self.terminal,
            "focusable": bool(self.alive and self.terminal and self.terminal.get("kind") != "none"),
            "hooked": self.hooked,
        }

    PERSIST = (
        "pid", "proc_start", "account", "cwd", "name", "kind", "started_at", "state", "source", "since",
        "signal_time", "file_status_time", "alive", "task_started", "last_activity", "last_event", "waiting",
        "result", "error", "ended_reason", "terminal", "hooked",
    )

    def persisted(self):
        d = {k: getattr(self, k) for k in self.PERSIST}
        d["id"] = self.id
        return d

    @classmethod
    def restore(cls, d):
        s = cls(d["id"])
        for k in cls.PERSIST:
            if k in d:
                setattr(s, k, d[k])
        return s


WAIT_KINDS = {"permission": "permission", "question": "question", "plan": "plan", "input": "input",
              "elicitation": "elicitation", "user_input": "input", "approval": "plan"}


def waiting_detail(pending_question, waiting_for):
    """Waiting detail from the transcript's open question and the state file's waitingFor."""
    if pending_question:
        return {"kind": "question", "text": pending_question}
    w = (waiting_for or "").strip()
    if w.lower() in WAIT_KINDS:
        return {"kind": WAIT_KINDS[w.lower()], "text": None}
    return {"kind": "input", "text": w or None}


class Manager:
    """Owns all sessions. Pure logic: callers feed it state files, hook events and transcripts."""

    def __init__(self, history, cfg, notify=None, clock=now_ms):
        self.history = history
        self.cfg = cfg
        self.notify = notify or (lambda kind, session, detail: None)
        self.clock = clock
        self.sessions = {}
        self.revision = 1
        self.updated_at = clock()
        self.quiet = False  # suppress notifications (initial recovery)
        self.dirty = False

    # ---- bookkeeping -------------------------------------------------------------------------
    def touch(self):
        self.revision += 1
        self.updated_at = self.clock()
        self.dirty = True

    def get(self, sid, create=True):
        s = self.sessions.get(sid)
        if s is None and create:
            s = Session(sid)
            self.sessions[sid] = s
        return s

    def event(self, kind, s, detail=None, source=None, event_time=None):
        now = self.clock()
        self.history.add(kind, s, detail, source, CERTAINTY.get(source, "low"), event_time or now, now)
        if s is not None:
            text = None
            if isinstance(detail, dict):
                text = detail.get("text") or detail.get("tool") or detail.get("reason")
            s.last_event = {"kind": kind, "text": text, "time": event_time or now}

    # ---- the transition ------------------------------------------------------------------------
    def set_state(self, s, state, source, when, detail=None, force=False):
        """Move s to state if the signal is not older than the current one. Returns True if applied."""
        when = int(when or self.clock())
        if not force and when < s.signal_time:
            return False
        prev = s.state
        s.signal_time = max(s.signal_time, when)
        if state == prev:
            # Same state, maybe better source or more detail.
            if RANK[CERTAINTY.get(source, "low")] >= RANK[s.certainty]:
                s.source = source
            if state == NEEDS_INPUT and detail:
                s.waiting = {**(s.waiting or {}), **{k: v for k, v in detail.items() if v}}
                self.touch()
            return True
        s.state = state
        s.source = source
        s.since = when
        detail = dict(detail or {})

        if state == NEEDS_INPUT:
            s.waiting = {"kind": detail.get("kind", "input"), "text": detail.get("text"),
                         "tool": detail.get("tool"), "since": when}
            if prev not in ACTIVE:
                s.task_started = s.task_started if prev == NEEDS_INPUT else when
            self.event("needs_input", s, s.waiting, source, when)
            self.notify("needs_input", s, s.waiting)
        elif state == WORKING:
            if prev == NEEDS_INPUT:
                self.event("input_resolved", s, {"kind": (s.waiting or {}).get("kind"),
                                                 "tool": (s.waiting or {}).get("tool")}, source, when)
            else:
                s.task_started = when
                s.result = None
                self.event("task_start", s, {"text": s.t.get("prompt")}, source, when)
            s.waiting = None
            s.error = None
        elif state == COMPLETED:
            duration = when - s.task_started if s.task_started else None
            s.waiting = None
            s.result = detail.get("result") or s.t.get("result")
            self.event("task_end", s, {"duration": duration, "text": s.result}, source, when)
            if duration is None or duration >= self.cfg.get("notify_min_task_s", 30) * 1000:
                self.notify("completed", s, {"duration": duration, "text": s.result})
        elif state == ERROR:
            s.waiting = None
            s.error = detail.get("text") or s.t.get("error") or "Error"
            self.event("error", s, {"text": s.error}, source, when)
            self.notify("error", s, {"text": s.error})
        elif state == ENDED:
            s.waiting = None
            s.alive = False
            s.ended_reason = detail.get("reason")
            if s.result is None:
                s.result = s.t.get("result")
            self.event("session_end", s, {"reason": s.ended_reason}, source, when)
        elif state == UNKNOWN:
            s.ended_reason = detail.get("reason")
            self.event("session_lost", s, {"reason": s.ended_reason, "previous": prev}, source, when)
            self.notify("unknown", s, {"reason": s.ended_reason})
        elif state == IDLE:
            s.waiting = None
        self.touch()
        return True

    # ---- state files -------------------------------------------------------------------------
    def apply_state_file(self, account, data, alive, preload=None):
        """data: parsed <account>/sessions/<pid>.json. Returns the session (or None).

        preload(session) may fill session.t from the transcript before a new session is classified,
        so a session first seen waiting already knows its question.
        """
        sid = data.get("sessionId")
        if not sid:
            return None
        s = self.get(sid)
        new = s.since is None
        changed = False
        for attr, key in (("pid", "pid"), ("proc_start", "procStart"), ("cwd", "cwd"), ("name", "name"),
                          ("kind", "kind"), ("started_at", "startedAt")):
            value = data.get(key)
            if value is not None and getattr(s, attr) != value:
                setattr(s, attr, value)
                changed = True
        if s.account != account:
            s.account = account
            changed = True
        if not alive:
            return s
        if not s.alive:
            s.alive = True
            changed = True
        if s.state in (ENDED, UNKNOWN) and not new:
            # A session we had lost is alive again (resumed, or the monitor missed it).
            s.signal_time = 0
        status = data.get("status")
        when = data.get("statusUpdatedAt") or data.get("updatedAt") or self.clock()
        if new:
            if preload:
                preload(s)
            self._first_sight(s, status, when, data.get("waitingFor"))
        elif status and s.file_status_time != when:
            self._apply_status(s, status, data.get("waitingFor"), "state-file", when)
        s.file_status_time = when
        if changed:
            self.touch()
        return s

    def _first_sight(self, s, status, when, waiting_for=None):
        """A session the monitor had never seen (monitor started after it, or a brand new one)."""
        recovering = self.quiet or (s.started_at and self.clock() - s.started_at > 60000)
        if recovering:
            kind = "session_resumed" if self.history.known_session(s.id) else "session_recovered"
            self.event(kind, s, {"text": s.name}, "recovered", s.started_at)
        else:
            self.event("session_start", s, {"text": s.name}, "state-file", s.started_at)
        state = {"busy": WORKING, "waiting": NEEDS_INPUT}.get(status, IDLE)
        s.state = state
        s.source = "recovered" if recovering else "state-file"
        s.since = when
        s.signal_time = when
        s.task_started = when if state in ACTIVE else None
        if state == NEEDS_INPUT:
            s.waiting = {**waiting_detail(s.t.get("pending_question"), waiting_for), "tool": None, "since": when}
            self.event("needs_input", s, s.waiting, s.source, when)
            self.notify("needs_input", s, s.waiting)
        self.touch()

    def _apply_status(self, s, status, waiting_for, source, when):
        if status == "busy":
            self.set_state(s, WORKING, source, when)
        elif status == "waiting":
            self.set_state(s, NEEDS_INPUT, source, when, waiting_detail(s.t.get("pending_question"), waiting_for))
        elif status == "idle":
            self._went_idle(s, source, when)

    def _went_idle(self, s, source, when, detail=None):
        err = s.t.get("error")
        err_time = s.t.get("error_time") or 0
        if err and err_time >= (s.task_started or 0):
            self.set_state(s, ERROR, source, when, {"text": err})
        elif s.state in ACTIVE:
            self.set_state(s, COMPLETED, source, when, detail)
        elif s.state in (UNKNOWN, ENDED):
            self.set_state(s, IDLE, source, when)

    # ---- hooks -------------------------------------------------------------------------------
    def apply_hook(self, ev):
        """ev: {"ts", "pid", "account", "payload": <hook stdin JSON>}."""
        p = ev.get("payload") or {}
        sid = p.get("session_id")
        name = p.get("hook_event_name")
        if not sid or not name:
            return None
        when = int(ev.get("ts") or self.clock())
        s = self.get(sid)
        s.hooked = True
        if ev.get("pid") and (s.pid is None or name == "SessionStart"):
            s.pid = ev["pid"]
        if p.get("cwd") and not s.cwd:
            s.cwd = p["cwd"]
        if ev.get("account") and not s.account:
            s.account = ev["account"]
        if p.get("transcript_path"):
            s.transcript = p["transcript_path"]
        if s.since is None:
            # First thing we hear about it.
            s.since = when
            s.started_at = s.started_at or when
            s.state = IDLE
            s.source = "hook"
            s.signal_time = 0
        tool = p.get("tool_name")
        if name == "SessionStart":
            src = p.get("source")
            if src in ("resume", "compact") or (src != "clear" and self.history.known_session(sid) and s.last_event):
                self.event("session_resumed", s, {"reason": src}, "hook", when)
            else:
                self.event("session_start", s, {"reason": src}, "hook", when)
            s.alive = True
            if s.state in (ENDED, UNKNOWN):
                self.set_state(s, IDLE, "hook", when, force=True)
        elif name == "UserPromptSubmit":
            if p.get("prompt"):
                s.t["prompt"] = p["prompt"].strip().replace("\n", " ")[:160]
            self.set_state(s, WORKING, "hook", when)
        elif name == "PreToolUse" and tool in ("AskUserQuestion", "ExitPlanMode"):
            from .transcript import question_text
            if tool == "AskUserQuestion":
                detail = {"kind": "question", "text": question_text(p.get("tool_input") or {}), "tool": tool}
            else:
                detail = {"kind": "plan", "text": None, "tool": tool}
            self.set_state(s, NEEDS_INPUT, "hook", when, detail)
        elif name == "PostToolUse" and tool in ("AskUserQuestion", "ExitPlanMode"):
            if s.state == NEEDS_INPUT:
                self.set_state(s, WORKING, "hook", when)
        elif name == "PermissionRequest":
            from .transcript import describe_tool
            detail = {"kind": "permission", "tool": tool,
                      "text": describe_tool(tool or "?", p.get("tool_input"))}
            self.set_state(s, NEEDS_INPUT, "hook", when, detail)
        elif name == "PermissionDenied":
            self.event("permission_denied", s, {"tool": tool, "reason": p.get("reason")}, "hook", when)
            self.touch()
        elif name == "Notification":
            ntype = p.get("notification_type")
            if ntype in ("permission_prompt", "elicitation_dialog"):
                detail = {"kind": "permission" if ntype == "permission_prompt" else "elicitation",
                          "text": p.get("message")}
                if s.state == NEEDS_INPUT and s.waiting and s.waiting.get("text"):
                    detail.pop("text")  # keep the more specific PermissionRequest text
                self.set_state(s, NEEDS_INPUT, "hook", when, detail)
        elif name == "Stop":
            result = p.get("last_assistant_message")
            result = " ".join(result.split())[:240] if isinstance(result, str) and result.strip() else None
            self._went_idle(s, "hook", when, {"result": result})
            if result and s.state == COMPLETED:
                s.result = result
            if s.state not in ACTIVE:
                s.signal_time = max(s.signal_time, when)
        elif name == "StopFailure":
            err = p.get("error") or p.get("error_details") or "Error"
            if isinstance(err, dict):
                err = err.get("message") or err.get("type") or "Error"
            self.set_state(s, ERROR, "hook", when, {"text": str(err)[:240]})
        elif name == "SessionEnd":
            self.set_state(s, ENDED, "hook", when, {"reason": p.get("reason")}, force=True)
        self.touch()
        return s

    # ---- transcripts -------------------------------------------------------------------------
    def apply_transcript(self, s, summary):
        if summary is None:
            return
        old = s.t
        s.t = summary
        if summary.get("last_time"):
            s.last_activity = max(s.last_activity or 0, summary["last_time"])
        # A question that appeared while the state file already said "waiting".
        if s.state == NEEDS_INPUT and summary.get("pending_question") and s.waiting and not s.waiting.get("text"):
            s.waiting["kind"] = "question"
            s.waiting["text"] = summary["pending_question"]
        # An API error at the end of an idle session we had recorded as finished.
        if (summary.get("error") and s.state in (COMPLETED, IDLE) and s.alive
                and (summary.get("error_time") or 0) >= (s.task_started or 0)
                and summary.get("error_time") != old.get("error_time")):
            self.set_state(s, ERROR, "transcript", summary.get("error_time") or self.clock(),
                           {"text": summary["error"]})
        if summary != old:
            self.touch()

    # ---- liveness ----------------------------------------------------------------------------
    def process_gone(self, s, reason="process exited without an exit event"):
        """The process is gone and no SessionEnd was recorded."""
        s.alive = False
        if s.state not in (ENDED, UNKNOWN):
            self.set_state(s, UNKNOWN, "monitor", self.clock(), {"reason": reason}, force=True)
        self.touch()

    def lost_state_file(self, s):
        if s.state not in (ENDED, UNKNOWN):
            self.set_state(s, UNKNOWN, "monitor", self.clock(), {"reason": "state file missing"}, force=True)

    def ack_error(self, sid):
        s = self.sessions.get(sid)
        if not s or s.state != ERROR:
            return False
        self.event("error_acked", s, {"text": s.error}, "monitor")
        self.set_state(s, IDLE if s.alive else ENDED, "monitor", self.clock(), force=True)
        return True

    def forget(self, sid):
        """Drop a session from the live list (its history stays)."""
        if self.sessions.pop(sid, None) is not None:
            self.touch()
            return True
        return False

    # ---- periodic ----------------------------------------------------------------------------
    def age(self):
        """Completed -> idle after the recent window; drop ended/unknown sessions after their window."""
        now = self.clock()
        recent = self.cfg.get("recent_window_min", 30) * 60000
        keep = self.cfg.get("ended_visible_min", 60) * 60000
        for sid, s in list(self.sessions.items()):
            if s.state == COMPLETED and now - (s.since or now) > recent:
                s.state = IDLE
                self.touch()
            elif s.state in (ENDED, UNKNOWN) and not s.alive and now - (s.since or now) > keep:
                del self.sessions[sid]
                self.touch()

    # ---- output ------------------------------------------------------------------------------
    ORDER = {NEEDS_INPUT: 0, WORKING: 1, ERROR: 2, COMPLETED: 3, UNKNOWN: 4, IDLE: 5, ENDED: 6}

    def snapshot(self, labels=None, extra=None):
        now = self.clock()
        labels = labels or {}
        counts = {k: 0 for k in STATES}
        items = []
        for s in self.sessions.values():
            if s.since is None:
                continue
            counts[s.state] += 1
            items.append(s.to_json(now, labels.get(s.account)))

        def key(x):
            # Waiting sessions: the one waiting longest first. Others: most recent change first.
            since = x["since"] or 0
            return (self.ORDER[x["state"]], since if x["state"] == NEEDS_INPUT else -since)

        items.sort(key=key)
        counts["total"] = len(items)
        out = {"revision": self.revision, "updatedAt": self.updated_at, "now": now, "counts": counts,
               "sessions": items}
        if extra:
            out.update(extra)
        return out
