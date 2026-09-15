"""Focused source-level regression tests for the v0.1.7 Fishing upgrade."""

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PACKAGE_ROOT / "assets" / "fish_companion"))

from backend.migration import (  # noqa: E402
    MIGRATION_MARKER_KEY,
    PREVIOUS_MIGRATION_VERSION,
    _insert_session,
    _upgrade_v1_profiles,
    _validate_document,
    _v1_imported_profile_ids,
    migrate_v017_json,
)
from backend.store import SessionStore  # noqa: E402


class StableV017MigrationTest(unittest.TestCase):
    def test_v1_subset_reproduction_keeps_its_exact_global_filters_and_cap(self) -> None:
        first = self._loadout("first", "Shared")
        duplicate_other_method = self._loadout("duplicate", "shared")
        duplicate_other_method["method"] = "harpoon"
        spaced_id = self._loadout(" spaced ", "Spaced id")
        spaced_name = self._loadout("spaced-name", " Spaced name ")
        spaced_tool = self._loadout("spaced-tool", "Spaced tool")
        spaced_tool["tool"] = " Balenos Rod "
        empty_tool = self._loadout("empty-tool", "Empty tool")
        empty_tool["tool"] = ""
        long_id = self._loadout("i" * 65, "Long id")
        long_name = self._loadout("long-name", "n" * 41)
        long_tool = self._loadout("long-tool", "Long tool")
        long_tool["tool"] = "t" * 181
        capped = [self._loadout(f"cap-{index}", f"Cap {index}") for index in range(17)]

        imported = _v1_imported_profile_ids(
            [
                first,
                duplicate_other_method,
                spaced_id,
                spaced_name,
                spaced_tool,
                empty_tool,
                long_id,
                long_name,
                long_tool,
                *capped,
            ]
        )

        self.assertEqual(imported, {"first", *(f"cap-{index}" for index in range(15))})

    def test_v1_upgrade_does_not_invent_an_active_profile(self) -> None:
        with tempfile.TemporaryDirectory(prefix="fish-v017-null-active-") as root_text:
            store = SessionStore(Path(root_text) / "fish-journal.sqlite3")
            existing = {
                "profiles": [
                    {
                        "id": "kept",
                        "name": "Kept",
                        "method": "rod",
                        "equipment": "Balenos Rod",
                        "mastery": 1,
                        "fishingRank": None,
                        "fishingLevel": None,
                        "autoFishingReductionPercent": None,
                        "tradingRank": None,
                        "tradingLevel": None,
                    }
                ],
                "activeProfileId": None,
            }
            connection = store._connect()
            try:
                connection.execute(
                    "INSERT INTO app_settings(key,value) VALUES ('fishing_profiles',?)",
                    (json.dumps(existing, separators=(",", ":")),),
                )
                upgraded = _upgrade_v1_profiles(
                    connection,
                    loadouts=[self._loadout("kept", "Kept")],
                )
            finally:
                connection.close()
            self.assertIsNone(upgraded["activeProfileId"])

    def test_v1_upgrade_fits_all_legacy_and_current_only_profiles(self) -> None:
        with tempfile.TemporaryDirectory(prefix="fish-v017-capacity-") as root_text:
            store = SessionStore(Path(root_text) / "fish-journal.sqlite3")
            current_profiles = [
                {
                    "id": f"current-{index}",
                    "name": f"Current {index}",
                    "method": "rod",
                    "equipment": "",
                    "mastery": index,
                    "fishingRank": None,
                    "fishingLevel": None,
                    "autoFishingReductionPercent": None,
                    "tradingRank": None,
                    "tradingLevel": None,
                }
                for index in range(16)
            ]
            # Every old loadout is valid under v0.1.7's limits but has an id
            # longer than v1 accepted, so v1 could have omitted all 1,000.
            legacy_loadouts = [
                self._loadout(
                    f"legacy-{index:04d}-" + "x" * 60,
                    f"Legacy {index}",
                )
                for index in range(1_000)
            ]
            connection = store._connect()
            try:
                connection.execute(
                    "INSERT INTO app_settings(key,value) VALUES ('fishing_profiles',?)",
                    (
                        json.dumps(
                            {
                                "profiles": current_profiles,
                                "activeProfileId": "current-15",
                            },
                            separators=(",", ":"),
                        ),
                    ),
                )
                upgraded = _upgrade_v1_profiles(
                    connection,
                    loadouts=legacy_loadouts,
                )
            finally:
                connection.close()

            self.assertEqual(len(upgraded["profiles"]), 1_016)
            self.assertEqual(upgraded["activeProfileId"], "current-15")
            self.assertEqual(
                [profile["id"] for profile in upgraded["profiles"][:16]],
                [profile["id"] for profile in current_profiles],
            )
            self.assertEqual(upgraded["profiles"][15]["name"], "Current 15")
            self.assertEqual(upgraded["profiles"][15]["mastery"], 15)
            self.assertEqual(
                upgraded["profiles"][-1]["id"],
                "legacy-0999-" + "x" * 60,
            )

    def test_v1_upgrade_recovers_only_profiles_v1_necessarily_omitted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="fish-v017-upgrade-") as root_text:
            personal_root = Path(root_text)
            fishing_root = personal_root / "fishing"
            fishing_root.mkdir()
            source = fishing_root / "fishing-journal.json"
            long_identifier = "profile-" + "x" * 80
            journal = {
                "version": 1,
                "loadouts": [
                    self._loadout("kept", "Duplicate", notes="source note"),
                    self._loadout("deleted", "Deleted profile"),
                    self._loadout(long_identifier, "Long identity"),
                    self._loadout("duplicate-name", "duplicate"),
                ],
                "sessions": [self._session()],
            }
            source_bytes = json.dumps(
                journal, ensure_ascii=False, separators=(",", ":")
            ).encode("utf-8")
            source.write_bytes(source_bytes)
            source_digest = hashlib.sha256(source_bytes).hexdigest()
            _, _, sessions = _validate_document(source_bytes)

            database = fishing_root / "fish-journal.sqlite3"
            store = SessionStore(database)
            connection = store._connect()
            try:
                # `deleted` was representable in v1 but is absent now: that is a
                # user deletion. Long/duplicate identities were never imported.
                existing = {
                    "profiles": [
                        {
                            "id": "kept",
                            "name": "User-edited name",
                            "method": "rod",
                            "equipment": "User-edited rod",
                            "mastery": 2222,
                            "fishingRank": "Master",
                            "fishingLevel": 5,
                            "autoFishingReductionPercent": 12.5,
                            "tradingRank": None,
                            "tradingLevel": None,
                        },
                        {
                            "id": "current-only",
                            "name": "Current-only profile",
                            "method": "harpoon",
                            "equipment": "",
                            "mastery": 4,
                            "fishingRank": None,
                            "fishingLevel": None,
                            "autoFishingReductionPercent": None,
                            "tradingRank": None,
                            "tradingLevel": None,
                        },
                    ],
                    "activeProfileId": "kept",
                }
                connection.execute(
                    "INSERT INTO app_settings(key,value) VALUES ('fishing_profiles',?)",
                    (json.dumps(existing, separators=(",", ":")),),
                )
                connection.execute(
                    "INSERT INTO app_settings(key,value) VALUES (?,?)",
                    (
                        MIGRATION_MARKER_KEY,
                        json.dumps(
                            {
                                "migrationVersion": PREVIOUS_MIGRATION_VERSION,
                                "sourceSha256": source_digest,
                                "sessionCount": 1,
                            },
                            separators=(",", ":"),
                        ),
                    ),
                )
                for migrated_session in sessions:
                    _insert_session(connection, migrated_session)
                connection.commit()
            finally:
                connection.close()

            first = migrate_v017_json(source, database)
            self.assertEqual(first["status"], "upgraded")
            self.assertEqual(first["importedProfileCount"], 3)
            self.assertEqual(first["preservedDeletedProfileCount"], 1)
            self.assertEqual(first["archiveOnlyLoadoutCount"], 0)

            stored = store.fishing_profiles()
            self.assertEqual(stored["activeProfileId"], "kept")
            profiles = {profile["id"]: profile for profile in stored["profiles"]}
            self.assertEqual(
                set(profiles),
                {"kept", "current-only", long_identifier, "duplicate-name"},
            )
            self.assertNotIn("deleted", profiles)
            self.assertEqual(profiles["kept"]["name"], "User-edited name")
            self.assertEqual(profiles["kept"]["mastery"], 2222)
            self.assertEqual(profiles["kept"]["notes"], "source note")
            self.assertEqual(profiles[long_identifier]["name"], "Long identity")
            self.assertEqual(profiles["duplicate-name"]["name"], "duplicate")

            with store._connection() as connection:
                session_count = connection.execute(
                    "SELECT COUNT(*) FROM sessions"
                ).fetchone()[0]
            self.assertEqual(session_count, 1)

            second = migrate_v017_json(source, database)
            self.assertEqual(second["status"], "already-migrated")
            with store._connection() as connection:
                repeated_count = connection.execute(
                    "SELECT COUNT(*) FROM sessions"
                ).fetchone()[0]
            self.assertEqual(repeated_count, 1)

    def test_v1_omitted_id_collision_keeps_both_profiles_and_session_identity(self) -> None:
        with tempfile.TemporaryDirectory(prefix="fish-v017-collision-") as root_text:
            personal_root = Path(root_text)
            fishing_root = personal_root / "fishing"
            fishing_root.mkdir()
            source = fishing_root / "fishing-journal.json"
            colliding_id = "omitted-" + "x" * 80
            legacy = self._loadout(colliding_id, "Legacy loadout", notes="legacy note")
            alias_shaped_id = (
                "legacy-v017-"
                + hashlib.sha256(colliding_id.encode("utf-8")).hexdigest()
            )
            alias_shaped = self._loadout(
                alias_shaped_id,
                "Alias-shaped legacy loadout",
                notes="second legacy note",
            )
            session = self._session()
            session["loadoutId"] = colliding_id
            session["loadoutName"] = "Legacy loadout"
            second_session = self._session()
            second_session["id"] = "session-2"
            second_session["loadoutId"] = alias_shaped_id
            second_session["loadoutName"] = "Alias-shaped legacy loadout"
            journal = {
                "version": 1,
                "loadouts": [legacy, alias_shaped],
                "sessions": [session, second_session],
            }
            source_bytes = json.dumps(
                journal, ensure_ascii=False, separators=(",", ":")
            ).encode("utf-8")
            source.write_bytes(source_bytes)
            source_digest = hashlib.sha256(source_bytes).hexdigest()
            _, _, sessions = _validate_document(source_bytes)

            database = fishing_root / "fish-journal.sqlite3"
            store = SessionStore(database)
            connection = store._connect()
            try:
                current_only = {
                    "profiles": [
                        {
                            "id": colliding_id,
                            "name": "Current profile",
                            "method": "harpoon",
                            "equipment": "Current harpoon",
                            "mastery": 2345,
                            "fishingRank": None,
                            "fishingLevel": None,
                            "autoFishingReductionPercent": None,
                            "tradingRank": None,
                            "tradingLevel": None,
                            "notes": "current note",
                        }
                    ],
                    "activeProfileId": colliding_id,
                }
                connection.execute(
                    "INSERT INTO app_settings(key,value) VALUES ('fishing_profiles',?)",
                    (json.dumps(current_only, separators=(",", ":")),),
                )
                connection.execute(
                    "INSERT INTO app_settings(key,value) VALUES (?,?)",
                    (
                        MIGRATION_MARKER_KEY,
                        json.dumps(
                            {
                                "migrationVersion": PREVIOUS_MIGRATION_VERSION,
                                "sourceSha256": source_digest,
                                "sessionCount": 2,
                            },
                            separators=(",", ":"),
                        ),
                    ),
                )
                for migrated_session in sessions:
                    _insert_session(connection, migrated_session)
                connection.commit()
            finally:
                connection.close()

            first = migrate_v017_json(source, database)
            self.assertEqual(first["status"], "upgraded")
            self.assertEqual(first["importedProfileCount"], 2)
            self.assertEqual(first["preservedDeletedProfileCount"], 0)
            stored = store.fishing_profiles()
            self.assertEqual(stored["activeProfileId"], colliding_id)
            self.assertEqual(len(stored["profiles"]), 3)
            current = next(
                profile for profile in stored["profiles"] if profile["id"] == colliding_id
            )
            migrated = next(
                profile
                for profile in stored["profiles"]
                if profile["legacySourceId"] == colliding_id
            )
            alias_shaped_profile = next(
                profile for profile in stored["profiles"] if profile["id"] == alias_shaped_id
            )
            self.assertEqual(current["name"], "Current profile")
            self.assertEqual(current["method"], "harpoon")
            self.assertEqual(current["mastery"], 2345)
            self.assertEqual(current["notes"], "current note")
            self.assertIsNone(current["legacySourceId"])
            self.assertEqual(migrated["legacySourceId"], colliding_id)
            self.assertEqual(migrated["id"], f"{alias_shaped_id}-2")
            self.assertEqual(migrated["name"], "Legacy loadout")
            self.assertEqual(migrated["notes"], "legacy note")
            self.assertIsNone(alias_shaped_profile["legacySourceId"])
            self.assertEqual(
                alias_shaped_profile["name"], "Alias-shaped legacy loadout"
            )
            with store._connection() as connection:
                session_profiles = {
                    row["id"]: row["setup_id"]
                    for row in connection.execute(
                        "SELECT id, setup_id FROM sessions ORDER BY id"
                    )
                }
            self.assertEqual(session_profiles["session-1"], migrated["id"])
            self.assertEqual(session_profiles["session-2"], alias_shaped_id)
            self.assertEqual(len(store.list({})), 2)
            unfiltered_stats = store.stats({})
            self.assertEqual(unfiltered_stats["spots"], [])
            self.assertEqual(
                unfiltered_stats["totals"],
                {
                    "sessions": 0,
                    "fish": 0,
                    "value": 0,
                    "durationMinutes": None,
                    "durationSessions": 0,
                    "fishPerHour": None,
                    "valuePerHour": None,
                },
            )

            # This is the same normalization/persistence path used by the
            # profiles PUT endpoint after the frontend edits a profile.
            first_profiles = store.update_fishing_profiles(stored)
            round_tripped_alias = next(
                profile
                for profile in first_profiles["profiles"]
                if profile["legacySourceId"] == colliding_id
            )
            self.assertEqual(round_tripped_alias["id"], migrated["id"])
            second = migrate_v017_json(source, database)
            self.assertEqual(second["status"], "already-migrated")
            self.assertEqual(store.fishing_profiles(), first_profiles)

    @staticmethod
    def _loadout(identifier: str, name: str, *, notes: str = "") -> dict[str, object]:
        return {
            "id": identifier,
            "name": name,
            "method": "fishing",
            "mastery": 123,
            "tool": "Balenos Rod",
            "notes": notes,
            "createdAtUtc": "2026-01-01T00:00:00Z",
            "updatedAtUtc": "2026-01-02T00:00:00Z",
        }

    @staticmethod
    def _session() -> dict[str, object]:
        return {
            "id": "session-1",
            "startedAtUtc": "2026-02-01T00:00:00Z",
            "durationMinutes": 60,
            "location": "Test coast",
            "method": "fishing",
            "loadoutId": "kept",
            "loadoutName": "Duplicate",
            "mastery": 123,
            "tool": "Balenos Rod",
            "retainedFishCount": 4,
            "silverReceived": 5,
            "notes": "session note",
            "createdAtUtc": "2026-02-01T00:00:01Z",
            "updatedAtUtc": "2026-02-01T01:00:01Z",
        }


if __name__ == "__main__":
    unittest.main()
