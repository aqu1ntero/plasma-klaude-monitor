# Architecture

## Components

| Component | Where | Responsibility |
| --- | --- | --- |
| Event monitor | `daemon/klaude_monitord/service.py` (`scan`, `read_spool`, watchers) | Watches Claude Code's state files and the hook spool with inotify, the session processes with pidfd, and re-checks everything every `poll_interval_s` as a fallback |
| Transcript reader | `daemon/klaude_monitord/transcript.py` | Reads the tail of a session transcript: title, current tool, pending question, last result, API errors, recap |
| Session manager | `daemon/klaude_monitord/sessions.py` | The state machine: one state per session, with source and certainty |
| History | `daemon/klaude_monitord/history.py` | SQLite (`~/.local/state/klaude-monitor/history.db`): events with event and detection times, last known session states, retention |
| Notifications | `daemon/klaude_monitord/notify.py` | `org.freedesktop.Notifications`, sent once by the daemon, with an *Open terminal* action |
| Terminal integration | `daemon/klaude_monitord/terminals.py` | Detects the terminal of a session; focuses Yakuake/Konsole/kitty tabs and windows (KWin script); resumes ended sessions |
| D-Bus API | `daemon/klaude_monitord/service.py` (`_on_call`) | `io.github.aqu1ntero.KlaudeMonitor` on the session bus |
| Hook | `hook/klaude-monitor-hook` | Claude Code hook (POSIX sh): writes each event to the spool |
| Hook installer | `daemon/klaude_monitord/hooks.py` | Adds/removes its own entries in `settings.json` |
| Shared QML | `shared/qml/` | `MonitorClient` (D-Bus long poll), `Labels`, `logic.js` (filter/sort/group), delegates, history view, shared settings page |
| Panel widget | `plasmoids/panel/` | Compact icon with badges + popup |
| Desktop widget | `plasmoids/desktop/` | Dashboard |

## Data sources

1. **State files**: `<config>/sessions/<pid>.json`, written by Claude Code 2.1+ for every running session:
   `sessionId`, `cwd`, `pid`, `procStart`, `status` (`busy` / `idle` / `waiting`), `waitingFor`,
   `statusUpdatedAt`, `kind`, `name`. The monitor checks that `pid` still exists *and* has the same start time
   (`procStart`, field 22 of `/proc/<pid>/stat`) to avoid pid reuse.
2. **Transcripts**: `<config>/projects/<cwd with non-alphanumerics as ->/<sessionId>.jsonl`. Only the last 512 KB
   are parsed.
3. **Hooks** (optional): `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Notification`, `PermissionRequest`,
   `PermissionDenied`, `Stop`, `StopFailure`, and `PreToolUse`/`PostToolUse` for `AskUserQuestion|ExitPlanMode`.
   The hook writes `<ts>-<pid>.json` (a metadata line + the hook's stdin JSON) into
   `~/.local/state/klaude-monitor/spool/` with an atomic rename. Files wait there if the daemon is stopped.

Config dirs ("accounts") are `~/.claude`, the `CLAUDE_CONFIG_DIR` of every running `claude` process, the ones seen
in hook events and `extra_config_dirs`. They are remembered across restarts.

## States

| State | Meaning | Set by |
| --- | --- | --- |
| `needs_input` | Waiting for a permission, an answer, a plan approval or MCP input | `status: waiting`, `PermissionRequest`, `Notification` (`permission_prompt`, `elicitation_dialog`), `PreToolUse` of `AskUserQuestion`/`ExitPlanMode` |
| `working` | A turn is running | `status: busy`, `UserPromptSubmit`, answering a question |
| `completed` | The last turn finished less than `recent_window_min` ago | `busy/waiting → idle`, `Stop` |
| `idle` | Alive, nothing recent | `completed` after the window; sessions first seen idle |
| `error` | The last turn failed; stays until new activity or *Mark reviewed* | `StopFailure`, API error in the transcript after the turn started |
| `ended` | The process exited and said so | `SessionEnd`; or the same process switched to another session (`/clear`) |
| `unknown` | The monitor lost track | Process gone without `SessionEnd`; state file missing while the process lives |

Rules:

- **One state per session**, so the counters never count a session twice.
- **Most recent signal wins.** Every signal carries a timestamp (`statusUpdatedAt`, hook time). A signal older than
  the one that set the current state is ignored, so a late re-read of a state file cannot undo a newer hook event.
- **Certainty**: `high` (hook), `medium` (state file), `low` (inferred from the transcript, recovered at monitor
  start, or a working session with no activity for 20 minutes, flagged as possibly stuck).
- **Missing information is never success.** Without an exit event, a vanished session is `unknown`.
- Opening a terminal never changes a state.

## History

`events(session_id, project, kind, detail JSON, source, certainty, event_time, detected_time)`.

Kinds: `session_start`, `session_resumed`, `session_recovered` (found already running when the monitor started),
`session_end`, `session_lost`, `task_start`, `task_end` (with duration and result), `needs_input` (with the
question/permission), `input_resolved` (a confirmation was given), `permission_denied`, `error`, `error_acked`,
`monitor_start`.

Events older than `retention_days` are deleted hourly. The `sessions` table keeps the last known state of each
session so that a restarted monitor continues where it left off (and can tell a resumed session from a new one).

## D-Bus API

Service `io.github.aqu1ntero.KlaudeMonitor`, object `/io/github/aqu1ntero/KlaudeMonitor`, interface
`io.github.aqu1ntero.KlaudeMonitor`. All payloads are JSON strings.

| Method | Returns |
| --- | --- |
| `Ping() → s` | version |
| `GetState() → s` | `{token, revision, updatedAt, now, counts{needs_input, working, completed, idle, error, ended, unknown, total}, sessions[…], monitor{version, startedAt, lastScan, hooks, pollInterval, recentWindowMin}, accounts[…]}` |
| `WaitForUpdate(token) → s` | Same as `GetState`. Returns immediately if `token` differs from the current one, otherwise when the state changes or after 20 s |
| `GetHistory(filter) → s` | `filter = {limit, session, since, kinds[]}` → list of events, newest first |
| `FocusSession(id) → s` | `{ok, action: "focus"\|"resume"\|"none", message}`; focuses a live session's terminal |
| `ResumeSession(id) → s` | Opens a terminal with `claude --resume` for a session that is no longer running |
| `AckError(id) → b` | Marks an error as reviewed |
| `Forget(id) → b` | Drops an ended/lost session from the live list (history is kept) |
| `GetConfig() → s` / `SetConfig(json) → s` | Shared settings `{values, defaults}` |
| `Rescan() → s` | Forces a scan |
| signal `Changed(revision)` | Emitted on every change (for other clients; the widgets use the long poll) |

The token is `<daemon start time>:<revision>`, so a restarted daemon is never mistaken for one the widget is
already in sync with.

Why a long poll instead of signals: the Plasma QML D-Bus module (`org.kde.plasma.workspace.dbus`) can call methods
but cannot subscribe to signals, and the widgets are pure QML (no compiled plugin to install).

## Process model and lifecycle

- `klaude-monitord.service` (systemd user unit, `Type=dbus`, `Restart=on-failure`) is enabled at login.
- `~/.local/share/dbus-1/services/io.github.aqu1ntero.KlaudeMonitor.service` (`SystemdService=`) lets D-Bus start
  it on the first call if it is not running.
- The daemon requests its bus name with `DO_NOT_QUEUE`: a second instance exits at once, so there is never more
  than one monitor, one set of watchers, one history and one notification per event.
- Widgets hold no state of their own beyond their visual settings. Closing, removing or crashing one has no effect
  on the daemon or the other widget; restarting Plasma loses nothing.
