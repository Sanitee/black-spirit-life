from __future__ import annotations

import hashlib
import json
import sqlite3
import argparse
import sys
from pathlib import Path


if sys.flags.optimize != 0:
    raise RuntimeError("release verification requires Python assertions to be enabled")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


parser = argparse.ArgumentParser()
parser.add_argument("root", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--expected-planner-version", required=True)
parser.add_argument("--migration-source-version", required=True)
args = parser.parse_args()
root = args.root.resolve()
output = args.output.resolve()
migration_archive_version = f"v{args.migration_source_version}"
migration_key_prefix = f"migration.stable-v{args.migration_source_version}"

planner_path = root / "planner-state.json"
fish_source = root / "fishing" / "fishing-journal.json"
fish_db = root / "fishing" / "fish-journal.sqlite3"
gather_source = root / "gathering" / "gathering-state.json"
gather_destination = root / "gathering" / "sessions.json"

planner = json.loads(planner_path.read_text(encoding="utf-8"))
assert planner["schemaVersion"] == 1
# Planner preserves the exact prior-version store until a user-visible Planner write;
# installed package identity is verified independently from sq.version.
assert planner["applicationVersion"] == args.expected_planner_version
assert planner["alchemy"]["alchemyMastery"] == 1234
assert planner["cooking"]["cookingMastery"] == 1567
assert planner["processing"]["processingMastery"] == 1789
assert planner["alchemy"]["inventory"] == {"Weeds": 37}
assert planner["cooking"]["inventory"] == {"Wheat": 4242}
assert planner["processing"]["inventory"] == {"Iron Ore": 987}
assert planner["marketTax"] == {
    "enabled": True,
    "valuePack": True,
    "merchantRing": True,
    "familyFameBonus": 0.015,
}
assert planner["afkWeightProfile"] == {
    "maximumWeightLt": 2345.5,
    "currentCarriedWeightLt": 321.25,
    "safetyBufferLt": 47,
    "featheryStepsLevel": 5,
}
assert planner["extensions"]["syntheticFairyProfile"] == (
    "Radiant Fairy - Morning Star V"
)

fish_digest = sha256(fish_source)
fish_archive = (
    root
    / "migration-archive"
    / migration_archive_version
    / f"fishing-journal.{fish_digest}.json"
)
assert fish_archive.read_bytes() == fish_source.read_bytes()

with sqlite3.connect(fish_db) as connection:
    connection.row_factory = sqlite3.Row
    settings = {
        row["key"]: json.loads(row["value"])
        for row in connection.execute("SELECT key, value FROM app_settings")
    }
    profiles = settings["fishing_profiles"]
    assert profiles["activeProfileId"] is None
    assert len(profiles["profiles"]) == 1
    profile = profiles["profiles"][0]
    assert profile["id"] == "synthetic-fishing-profile-1"
    assert profile["name"] == "Synthetic AFK Balenos"
    assert profile["method"] == "rod"
    assert profile["equipment"] == "Balenos Fishing Rod"
    assert profile["mastery"] == 2230
    assert profile["notes"] == "Synthetic lifecycle profile"
    assert profile["fishingRank"] is None
    assert profile["fishingLevel"] is None
    assert profile["autoFishingReductionPercent"] is None
    assert profile["tradingRank"] is None
    assert profile["tradingLevel"] is None
    marker = settings[f"{migration_key_prefix}.fishing"]
    assert marker["migrationVersion"] == f"stable-v{args.migration_source_version}-fishing-v2"
    assert marker["sourceSha256"] == fish_digest
    assert marker["loadoutCount"] == 1
    assert marker["importedProfileCount"] == 1
    assert marker["preservedDeletedProfileCount"] == 0
    assert marker["sessionCount"] == 1
    fish_session = connection.execute(
        """
        SELECT id, created_at, started_at, ended_at, location_name, method,
               style, equipment, setup_id, setup_name, mastery,
               duration_minutes, total_fish, entry_source,
               verification_status, notes, legacy_received_silver,
               legacy_aggregate_only
          FROM sessions
        """
    ).fetchone()
    assert fish_session is not None
    fish_session = dict(fish_session)
    assert fish_session == {
        "id": "synthetic-fishing-haul-1",
        "created_at": "2026-09-14T16:15:00.000Z",
        "started_at": "2026-09-14T08:15:00.000Z",
        "ended_at": "2026-09-14T16:15:00Z",
        "location_name": "Velia Beach",
        "method": "rod",
        "style": "afk",
        "equipment": "Balenos Fishing Rod",
        "setup_id": "synthetic-fishing-profile-1",
        "setup_name": "Synthetic AFK Balenos",
        "mastery": 2230,
        "duration_minutes": 480,
        "total_fish": 81,
        "entry_source": "legacy-v017",
        "verification_status": "legacy-aggregate-only",
        "notes": "Synthetic journal/haul preservation record",
        "legacy_received_silver": 2240000000,
        "legacy_aggregate_only": 1,
    }

gather_digest = sha256(gather_source)
gather_archive = (
    root
    / "migration-archive"
    / migration_archive_version
    / f"gathering-state.{gather_digest}.json"
)
assert gather_archive.read_bytes() == gather_source.read_bytes()
gather = json.loads(gather_destination.read_text(encoding="utf-8"))
assert gather["schemaVersion"] == 1
assert len(gather["sessions"]) == 1
session = gather["sessions"][0]
assert session["id"] == "synthetic-gathering-session-1"
assert session["createdAt"] == "2026-09-14T10:30:00.000Z"
assert session["methodId"] == "butcher"
assert session["methodLabel"] == "Butchering"
assert session["spotId"] == "custom"
assert session["spotName"] == "Behr"
assert session["stableV017Location"] == "Behr"
assert session["durationSeconds"] == 3600
assert session["mastery"] == 2111
assert session["notes"] == "Synthetic lifecycle preservation record"
assert session["loot"] == []
assert session["buffs"] == []
assert session["pets"] == []
assert session["buffTotals"] == {}
preferences = gather["preferences"]
preparation = preferences["gatheringPreparation"]
assert preparation["statsConfirmed"] is True
assert preparation["baseSettings"]["mastery"] == 2111
assert preparation["baseSettings"]["additionalDroprateBonus"] == 0.0
assert preparation["baseSettings"]["minigameMode"] == "none"
assert preparation["baseSettings"]["hedgehogTier"] == 0
assert preparation["baseSettings"]["agrisEnabled"] is False
assert preferences[f"{migration_key_prefix}.gathering.loadoutNotes"] == (
    "Synthetic Manos gathering loadout"
)
gather_marker = preferences[f"{migration_key_prefix}.gathering"]
assert gather_marker["migrationVersion"] == f"stable-v{args.migration_source_version}-gathering-v1"
assert gather_marker["sourceSha256"] == gather_digest
assert gather_marker["sessionCount"] == 1

result = {
    "planner": {
        "applicationVersion": planner["applicationVersion"],
        "masteries": [1234, 1567, 1789],
        "inventory": {
            "Weeds": 37,
            "Wheat": 4242,
            "Iron Ore": 987,
        },
        "merchantRing": True,
        "fairy": planner["extensions"]["syntheticFairyProfile"],
    },
    "fishing": {
        "sourceSha256": fish_digest,
        "archiveSha256": sha256(fish_archive),
        "profiles": 1,
        "activeProfileId": None,
        "sessions": 1,
        "legacyAggregateOnly": True,
        "receivedSilver": 2240000000,
    },
    "gathering": {
        "sourceSha256": gather_digest,
        "archiveSha256": sha256(gather_archive),
        "mastery": 2111,
        "loadoutNotes": "Synthetic Manos gathering loadout",
        "sessions": 1,
        "legacyLocation": "Behr",
    },
}
output.write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps(result, separators=(",", ":")))
