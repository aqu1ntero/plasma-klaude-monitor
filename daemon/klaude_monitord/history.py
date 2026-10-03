# SPDX-License-Identifier: GPL-2.0-or-later
"""Persistent history (SQLite): important events plus the last known state of every session.

Each event keeps two times: when it happened (event_time, from Claude Code or the hook) and when the
monitor noticed it (detected_time). They differ for events replayed after the monitor was stopped.
"""

import json
import sqlite3
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    project TEXT,
    kind TEXT NOT NULL,
    detail TEXT,
    source TEXT,
    certainty TEXT,
    event_time INTEGER NOT NULL,
    detected_time INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS events_time ON events(event_time);
CREATE INDEX IF NOT EXISTS events_session ON events(session_id);
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    data TEXT NOT NULL,
    updated INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT
);
"""

# Event kinds (the widgets translate them).
KINDS = (
    "session_start", "session_resumed", "session_recovered", "session_end", "session_lost",
    "task_start", "task_end", "needs_input", "input_resolved", "permission_denied", "error",
    "error_acked", "monitor_start",
)


def now_ms():
    return int(time.time() * 1000)


class History:
    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(path))
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(SCHEMA)
        self.db.commit()

    def add(self, kind, session=None, detail=None, source=None, certainty=None, event_time=None,
            detected_time=None):
        detected = detected_time or now_ms()
        cur = self.db.execute(
            "INSERT INTO events (session_id, project, kind, detail, source, certainty, event_time, detected_time)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                session.id if session else None,
                session.project if session else None,
                kind,
                json.dumps(detail, ensure_ascii=False) if detail is not None else None,
                source,
                certainty,
                int(event_time or detected),
                detected,
            ),
        )
        self.db.commit()
        return cur.lastrowid

    def events(self, limit=200, session_id=None, since=None, kinds=None):
        sql = "SELECT id, session_id, project, kind, detail, source, certainty, event_time, detected_time FROM events"
        where, args = [], []
        if session_id:
            where.append("session_id = ?")
            args.append(session_id)
        if since:
            where.append("event_time >= ?")
            args.append(int(since))
        if kinds:
            where.append("kind IN (%s)" % ",".join("?" * len(kinds)))
            args.extend(kinds)
        if where:
            sql += " WHERE " + " AND ".join(where)
        sql += " ORDER BY event_time DESC, id DESC LIMIT ?"
        args.append(max(1, min(int(limit), 5000)))
        out = []
        for row in self.db.execute(sql, args):
            out.append({
                "id": row[0], "session": row[1], "project": row[2], "kind": row[3],
                "detail": json.loads(row[4]) if row[4] else None, "source": row[5], "certainty": row[6],
                "event_time": row[7], "detected_time": row[8],
            })
        return out

    def prune(self, retention_days):
        cutoff = now_ms() - int(retention_days) * 86400000
        self.db.execute("DELETE FROM events WHERE event_time < ?", (cutoff,))
        self.db.execute("DELETE FROM sessions WHERE updated < ?", (cutoff,))
        self.db.commit()

    # Last known state of sessions, so a restarted monitor knows what it saw before.
    def save_sessions(self, sessions):
        now = now_ms()
        self.db.executemany(
            "INSERT INTO sessions (id, data, updated) VALUES (?, ?, ?)"
            " ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated = excluded.updated",
            [(s.id, json.dumps(s.persisted(), ensure_ascii=False), now) for s in sessions],
        )
        self.db.commit()

    def load_sessions(self, newer_than_ms):
        rows = self.db.execute("SELECT data FROM sessions WHERE updated >= ?", (int(newer_than_ms),))
        out = []
        for (data,) in rows:
            try:
                out.append(json.loads(data))
            except ValueError:
                pass
        return out

    def known_session(self, session_id):
        row = self.db.execute("SELECT 1 FROM sessions WHERE id = ?", (session_id,)).fetchone()
        if row:
            return True
        row = self.db.execute("SELECT 1 FROM events WHERE session_id = ? LIMIT 1", (session_id,)).fetchone()
        return bool(row)

    def get_meta(self, key, default=None):
        row = self.db.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
        return json.loads(row[0]) if row else default

    def set_meta(self, key, value):
        self.db.execute(
            "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, json.dumps(value)),
        )
        self.db.commit()
