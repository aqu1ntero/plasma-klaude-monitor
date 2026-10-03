# SPDX-License-Identifier: GPL-2.0-or-later
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from klaude_monitord import config, hooks, transcript  # noqa: E402
from klaude_monitord.history import History  # noqa: E402
from klaude_monitord.sessions import Manager  # noqa: E402

ACC = "/home/u/.claude"


class Clock:
    def __init__(self, t=1_000_000_000_000):
        self.t = t

    def __call__(self):
        return self.t

    def advance(self, ms):
        self.t += ms


def state_file(status, when, sid="s1", pid=4242, waiting=None, started=None):
    return {"pid": pid, "sessionId": sid, "cwd": "/work/proj", "startedAt": started or when, "procStart": "1",
            "status": status, "statusUpdatedAt": when, "waitingFor": waiting, "kind": "interactive",
            "name": "proj-1"}


def hook(name, when, sid="s1", **payload):
    return {"ts": when, "pid": 4242, "account": ACC,
            "payload": {"session_id": sid, "hook_event_name": name, "cwd": "/work/proj", **payload}}


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.history = History(Path(self.tmp.name) / "h.db")
        self.clock = Clock()
        self.notes = []
        self.cfg = dict(config.DEFAULTS)
        self.m = Manager(self.history, self.cfg, notify=lambda k, s, d: self.notes.append(k), clock=self.clock)

    def tearDown(self):
        self.history.db.close()
        self.tmp.cleanup()

    def kinds(self):
        return [e["kind"] for e in reversed(self.history.events())]

    def feed(self, status, waiting=None):
        self.clock.advance(1000)
        return self.m.apply_state_file(ACC, state_file(status, self.clock(), waiting=waiting), True)


class StateMachine(Base):
    def test_turn_lifecycle_from_state_files(self):
        self.cfg["notify_min_task_s"] = 0
        s = self.feed("idle")
        self.assertEqual(s.state, "idle")
        self.feed("busy")
        self.assertEqual(s.state, "working")
        self.feed("waiting", waiting="permission")
        self.assertEqual(s.state, "needs_input")
        self.assertEqual((s.waiting["kind"], s.waiting["text"]), ("permission", None))
        self.feed("busy")
        self.feed("idle")
        self.assertEqual(s.state, "completed")
        self.assertEqual(self.kinds(), ["session_start", "task_start", "needs_input", "input_resolved", "task_end"])
        self.assertEqual([n for n in self.notes if n != "dismiss"], ["needs_input", "completed"])

    def test_notification_withdrawn_when_answered(self):
        self.feed("busy")
        self.feed("waiting", waiting="permission")
        self.feed("busy")
        self.assertEqual(self.notes, ["needs_input", "dismiss"])

    def test_short_task_not_notified(self):
        self.feed("busy")
        self.feed("idle")
        self.assertEqual(self.notes, [])

    def test_counts_never_double_count(self):
        self.feed("busy")
        self.m.apply_state_file(ACC, state_file("waiting", self.clock(), sid="s2", pid=99), True)
        snap = self.m.snapshot()
        self.assertEqual(snap["counts"]["working"], 1)
        self.assertEqual(snap["counts"]["needs_input"], 1)
        self.assertEqual(snap["counts"]["total"], 2)
        self.assertEqual(sum(v for k, v in snap["counts"].items() if k != "total"), 2)
        self.assertEqual(snap["sessions"][0]["state"], "needs_input")  # waiting sessions first

    def test_older_signal_does_not_override(self):
        s = self.feed("busy")
        t_busy = self.clock()
        self.m.apply_hook(hook("PermissionRequest", t_busy + 500, tool_name="Bash", tool_input={"command": "rm x"}))
        self.assertEqual(s.state, "needs_input")
        self.assertEqual(s.waiting["text"], "Bash: rm x")
        # A re-read of an older state file (same busy) is ignored; a stale one too.
        self.m.apply_state_file(ACC, state_file("busy", t_busy + 100), True)
        self.assertEqual(s.state, "needs_input")
        # The Notification that follows keeps the more specific text.
        self.m.apply_hook(hook("Notification", t_busy + 600, notification_type="permission_prompt",
                               message="Claude needs your permission to use Bash"))
        self.assertEqual(s.waiting["text"], "Bash: rm x")
        self.assertEqual(s.source, "hook")

    def test_better_detail_updates_notification(self):
        s = self.feed("waiting", waiting="permission")
        self.m.apply_hook(hook("PermissionRequest", self.clock() + 100, tool_name="Bash",
                               tool_input={"command": "make deploy"}))
        self.assertEqual(s.waiting["text"], "Bash: make deploy")
        self.assertEqual(self.notes, ["needs_input", "needs_input"])

    def test_lost_process_is_unknown_not_completed(self):
        s = self.feed("busy")
        self.m.process_gone(s)
        self.assertEqual(s.state, "unknown")
        self.assertNotIn("task_end", self.kinds())
        self.assertEqual(self.kinds()[-1], "session_lost")

    def test_session_end_hook_is_ended(self):
        s = self.feed("idle")
        self.m.apply_hook(hook("SessionEnd", self.clock() + 10, reason="prompt_input_exit"))
        self.m.process_gone(s)
        self.assertEqual(s.state, "ended")
        self.assertEqual(s.ended_reason, "prompt_input_exit")

    def test_aging(self):
        s = self.feed("busy")
        self.feed("idle")
        self.clock.advance(self.cfg["recent_window_min"] * 60000 + 1)
        self.m.age()
        self.assertEqual(s.state, "idle")
        self.m.process_gone(s)
        self.clock.advance(self.cfg["ended_visible_min"] * 60000 + 1)
        self.m.age()
        self.assertNotIn("s1", self.m.sessions)

    def test_error_from_transcript_then_ack(self):
        s = self.feed("busy")
        self.m.apply_transcript(s, {"error": "Overloaded", "error_time": self.clock() + 10})
        self.feed("idle")
        self.assertEqual(s.state, "error")
        self.assertEqual(s.error, "Overloaded")
        self.assertTrue(self.m.ack_error("s1"))
        self.assertEqual(s.state, "idle")
        self.assertIn("error_acked", self.kinds())

    def test_stop_failure_hook(self):
        s = self.feed("busy")
        self.m.apply_hook(hook("StopFailure", self.clock() + 5, error="rate_limit"))
        self.assertEqual(s.state, "error")
        self.assertIn("error", self.notes)

    def test_question_hook(self):
        s = self.feed("busy")
        self.m.apply_hook(hook("PreToolUse", self.clock() + 5, tool_name="AskUserQuestion",
                               tool_input={"questions": [{"question": "Which database?"}]}))
        self.assertEqual(s.state, "needs_input")
        self.assertEqual(s.waiting, {"kind": "question", "text": "Which database?", "tool": "AskUserQuestion",
                                     "since": self.clock() + 5})
        self.m.apply_hook(hook("PostToolUse", self.clock() + 50, tool_name="AskUserQuestion"))
        self.assertEqual(s.state, "working")

    def test_first_sight_waiting_knows_the_question(self):
        def preload(sess):
            sess.t = {"pending_question": "Redis or Postgres?"}
        self.clock.advance(1000)
        s = self.m.apply_state_file(ACC, state_file("waiting", self.clock()), True, preload=preload)
        self.assertEqual(s.waiting["text"], "Redis or Postgres?")
        self.assertEqual(self.history.events()[0]["detail"]["text"], "Redis or Postgres?")

    def test_recovered_at_startup_is_low_certainty(self):
        self.m.quiet = True
        s = self.feed("busy")
        self.assertEqual(s.certainty, "low")
        self.assertEqual(self.kinds(), ["session_recovered"])
        self.assertEqual(self.notes, [])

    def test_persist_roundtrip(self):
        s = self.feed("waiting", waiting="Approve the deploy")
        self.history.save_sessions([s])
        restored = self.history.load_sessions(0)[0]
        self.assertEqual(restored["state"], "needs_input")
        self.assertEqual(restored["waiting"]["text"], "Approve the deploy")

    def test_history_times(self):
        self.m.apply_hook(hook("SessionStart", self.clock() - 60000, source="startup"))
        ev = self.history.events()[0]
        self.assertEqual(ev["event_time"], self.clock() - 60000)
        self.assertEqual(ev["detected_time"], self.clock())


class Transcript(unittest.TestCase):
    def test_parse(self):
        lines = [
            {"type": "ai-title", "aiTitle": "Fix login"},
            {"type": "user", "message": {"content": "please fix login"}, "timestamp": "2026-01-01T10:00:00Z"},
            {"type": "assistant", "timestamp": "2026-01-01T10:00:05Z", "gitBranch": "main",
             "message": {"model": "claude-opus-5-5", "content": [
                 {"type": "text", "text": "Let me ask"},
                 {"type": "tool_use", "id": "t1", "name": "AskUserQuestion",
                  "input": {"questions": [{"question": "Keep sessions?"}]}}]}},
        ]
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
            for line in lines:
                f.write(json.dumps(line) + "\n")
            f.write('{"type": "assist')  # partial last line
        try:
            s = transcript.parse(f.name)
        finally:
            os.unlink(f.name)
        self.assertEqual(s["title"], "Fix login")
        self.assertEqual(s["prompt"], "please fix login")
        self.assertEqual(s["model"], "opus-5-5")
        self.assertEqual(s["branch"], "main")
        self.assertEqual(s["pending_question"], "Keep sessions?")
        self.assertTrue(s["tool"].startswith("AskUserQuestion"))

    def test_api_error_cleared_by_later_output(self):
        lines = [
            {"type": "assistant", "isApiErrorMessage": True, "timestamp": "2026-01-01T10:00:00Z",
             "message": {"content": [{"type": "text", "text": "API Error: 529 overloaded"}]}},
        ]
        path = tempfile.mktemp(suffix=".jsonl")
        Path(path).write_text("\n".join(json.dumps(x) for x in lines) + "\n")
        self.assertIn("529", transcript.parse(path)["error"])
        lines.append({"type": "assistant", "timestamp": "2026-01-01T10:01:00Z",
                      "message": {"content": [{"type": "text", "text": "done"}]}})
        Path(path).write_text("\n".join(json.dumps(x) for x in lines) + "\n")
        s = transcript.parse(path)
        os.unlink(path)
        self.assertIsNone(s["error"])
        self.assertEqual(s["result"], "done")

    def test_path(self):
        self.assertEqual(transcript.transcript_path("/c", "/home/a/my.proj", "id"), "/c/projects/-home-a-my-proj/id.jsonl")


class Hooks(unittest.TestCase):
    def test_install_preserves_and_uninstall_restores(self):
        with tempfile.TemporaryDirectory() as d:
            original = {"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "other"}]}]}}
            Path(d, "settings.json").write_text(json.dumps(original))
            hooks.install(d, "/x/klaude-monitor-hook")
            hooks.install(d, "/x/klaude-monitor-hook")  # idempotent
            data = json.loads(Path(d, "settings.json").read_text())
            self.assertEqual(data["model"], "opus")
            self.assertEqual(len(data["hooks"]["Stop"]), 2)
            self.assertEqual(data["hooks"]["PreToolUse"][0]["matcher"], "AskUserQuestion|ExitPlanMode")
            self.assertNotIn("matcher", data["hooks"]["UserPromptSubmit"][0])
            self.assertEqual(sorted(hooks.status(d)), sorted(hooks.EVENTS))
            self.assertTrue(Path(d, "settings.json.klaude-monitor.bak").exists())
            self.assertEqual(hooks.uninstall(d), len(hooks.EVENTS))
            self.assertEqual(json.loads(Path(d, "settings.json").read_text()), original)


class Config(unittest.TestCase):
    def test_sanitize(self):
        c = config.sanitize({"retention_days": 0, "notify_error": "yes", "bogus": 1, "preferred_terminal": "x",
                             "extra_config_dirs": ["/a", 3]})
        self.assertEqual(c["retention_days"], 1)
        self.assertTrue(c["notify_error"])
        self.assertNotIn("bogus", c)
        self.assertEqual(c["preferred_terminal"], "auto")
        self.assertEqual(c["extra_config_dirs"], ["/a"])


if __name__ == "__main__":
    unittest.main()
