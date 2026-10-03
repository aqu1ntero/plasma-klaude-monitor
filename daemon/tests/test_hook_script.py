# SPDX-License-Identifier: GPL-2.0-or-later
"""The sh hook writes one well-formed spool file and never fails."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

HOOK = Path(__file__).resolve().parents[2] / "hook" / "klaude-monitor-hook"


class HookScript(unittest.TestCase):
    def run_hook(self, payload, extra_env=None):
        with tempfile.TemporaryDirectory() as d:
            env = {**os.environ, "XDG_STATE_HOME": d, **(extra_env or {})}
            r = subprocess.run(["sh", str(HOOK)], input=payload, capture_output=True, text=True, env=env, timeout=10)
            spool = Path(d, "klaude-monitor", "spool")
            files = sorted(spool.glob("*.json"))
            leftovers = list(spool.glob(".*"))
            contents = [f.read_text() for f in files]
        return r, contents, leftovers

    def test_writes_spool_file(self):
        payload = json.dumps({"session_id": "abc", "hook_event_name": "Stop"})
        r, files, leftovers = self.run_hook(payload, {"CLAUDE_CONFIG_DIR": '/tmp/we"ird'})
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")
        self.assertEqual(len(files), 1)
        self.assertEqual(leftovers, [])
        meta, _, body = files[0].partition("\n")
        meta = json.loads(meta)
        self.assertGreater(meta["ts"], 1_600_000_000_000)
        self.assertEqual(meta["account"], '/tmp/we"ird')
        self.assertEqual(json.loads(body)["session_id"], "abc")

    def test_never_fails(self):
        with tempfile.TemporaryDirectory() as d:
            ro = Path(d, "ro")
            ro.mkdir()
            ro.chmod(0o500)
            env = {**os.environ, "XDG_STATE_HOME": str(ro)}
            r = subprocess.run(["sh", str(HOOK)], input="{}", capture_output=True, text=True, env=env, timeout=10)
            ro.chmod(0o700)
        self.assertEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
