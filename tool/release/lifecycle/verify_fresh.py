from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path


if sys.flags.optimize != 0:
    raise RuntimeError("release verification requires Python assertions to be enabled")


root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()

fish_db = root / "fishing" / "fish-journal.sqlite3"
fish_profiles = 0
fish_sessions = 0
if fish_db.exists():
    with sqlite3.connect(fish_db) as connection:
        fish_sessions = connection.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
        row = connection.execute(
            "SELECT value FROM app_settings WHERE key = 'fishing_profiles'"
        ).fetchone()
        if row is not None:
            profiles = json.loads(row[0])
            assert profiles.get("activeProfileId") is None
            fish_profiles = len(profiles.get("profiles", []))
assert fish_profiles == 0
assert fish_sessions == 0

gather_path = root / "gathering" / "sessions.json"
gather_sessions = 0
if gather_path.exists():
    gather = json.loads(gather_path.read_text(encoding="utf-8"))
    gather_sessions = len(gather.get("sessions", []))
assert gather_sessions == 0

result = {
    "fishDatabaseCreated": fish_db.exists(),
    "fishProfiles": fish_profiles,
    "fishSessions": fish_sessions,
    "gatheringStoreCreated": gather_path.exists(),
    "gatheringSessions": gather_sessions,
}
output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, separators=(",", ":")))
