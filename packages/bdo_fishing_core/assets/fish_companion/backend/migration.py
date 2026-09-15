"""Lossless, seed-free migration from the public v0.1.7 Fishing journal."""

from __future__ import annotations

import hashlib
import json
import os
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .store import SessionStore, SessionValidationError


MIGRATION_VERSION = "stable-v0.1.7-fishing-v2"
PREVIOUS_MIGRATION_VERSION = "stable-v0.1.7-fishing-v1"
MIGRATION_MARKER_KEY = "migration.stable-v0.1.7.fishing"
LOADOUT_ARCHIVE_KEY = "migration.stable-v0.1.7.fishing.loadouts"
SOURCE_FILE_NAME = "fishing-journal.json"
DATABASE_FILE_NAME = "fish-journal.sqlite3"
MAX_LEGACY_LOADOUTS = 1_000
MAX_LEGACY_SESSIONS = 10_000


class LegacyV017MigrationError(ValueError):
    """Raised when a legacy journal cannot be migrated without data loss."""


def _object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise LegacyV017MigrationError(f"{label} must be an object")
    return value


def _text(
    value: Any,
    label: str,
    *,
    maximum: int,
    allow_empty: bool = False,
) -> str:
    if not isinstance(value, str) or len(value) > maximum:
        raise LegacyV017MigrationError(f"{label} is invalid")
    if not allow_empty and not value.strip():
        raise LegacyV017MigrationError(f"{label} is invalid")
    return value


def _integer(value: Any, label: str, *, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise LegacyV017MigrationError(f"{label} is invalid")
    if value < minimum or value > maximum:
        raise LegacyV017MigrationError(f"{label} is invalid")
    return value


def _timestamp(value: Any, label: str) -> tuple[str, datetime]:
    if not isinstance(value, str):
        raise LegacyV017MigrationError(f"{label} is invalid")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise LegacyV017MigrationError(f"{label} is invalid") from exc
    if parsed.tzinfo is None:
        raise LegacyV017MigrationError(f"{label} must include a UTC offset")
    return value, parsed.astimezone(timezone.utc)


def _method(value: Any) -> str:
    if not isinstance(value, str):
        raise LegacyV017MigrationError("Fishing method is invalid")
    mapped = {
        "fishing": "rod",
        "harpooning": "harpoon",
    }.get(value)
    if mapped is None:
        raise LegacyV017MigrationError("Fishing method is invalid")
    return mapped


def _validate_loadout(value: Any) -> dict[str, Any]:
    raw = _object(value, "Fishing loadout")
    created_text, created = _timestamp(
        raw.get("createdAtUtc"), "Loadout creation timestamp"
    )
    updated_text, updated = _timestamp(
        raw.get("updatedAtUtc"), "Loadout update timestamp"
    )
    if updated < created:
        raise LegacyV017MigrationError(
            "Loadout update timestamp precedes its creation timestamp"
        )
    return {
        "id": _text(raw.get("id"), "Loadout id", maximum=160),
        "name": _text(raw.get("name"), "Loadout name", maximum=120),
        "method": _method(raw.get("method")),
        "mastery": _integer(
            raw.get("mastery"), "Fishing mastery", minimum=0, maximum=3_000
        ),
        "tool": _text(
            raw.get("tool"), "Fishing tool", maximum=200, allow_empty=True
        ),
        "notes": _text(
            raw.get("notes"), "Loadout notes", maximum=4_000, allow_empty=True
        ),
        "createdAtUtc": created_text,
        "updatedAtUtc": updated_text,
    }


def _validate_session(value: Any) -> dict[str, Any]:
    raw = _object(value, "Fishing session")
    started_text, started = _timestamp(
        raw.get("startedAtUtc"), "Session start timestamp"
    )
    created_text, created = _timestamp(
        raw.get("createdAtUtc"), "Session creation timestamp"
    )
    updated_text, updated = _timestamp(
        raw.get("updatedAtUtc"), "Session update timestamp"
    )
    if updated < created:
        raise LegacyV017MigrationError(
            "Session update timestamp precedes its creation timestamp"
        )
    duration = _integer(
        raw.get("durationMinutes"),
        "Session duration",
        minimum=1,
        maximum=10_080,
    )
    loadout_id = raw.get("loadoutId")
    if loadout_id is not None:
        loadout_id = _text(loadout_id, "Session loadout id", maximum=160)
    ended = started + timedelta(minutes=duration)
    return {
        "id": _text(raw.get("id"), "Session id", maximum=160),
        "startedAtUtc": started_text,
        "endedAtUtc": ended.isoformat(timespec="seconds").replace("+00:00", "Z"),
        "durationMinutes": duration,
        "location": _text(
            raw.get("location"),
            "Session location",
            maximum=160,
            allow_empty=True,
        ),
        "method": _method(raw.get("method")),
        "loadoutId": loadout_id,
        "loadoutName": _text(
            raw.get("loadoutName"),
            "Session loadout name",
            maximum=120,
            allow_empty=True,
        ),
        "mastery": _integer(
            raw.get("mastery"), "Session mastery", minimum=0, maximum=3_000
        ),
        "tool": _text(
            raw.get("tool"), "Session tool", maximum=200, allow_empty=True
        ),
        "retainedFishCount": _integer(
            raw.get("retainedFishCount"),
            "Retained fish count",
            minimum=0,
            maximum=1_000_000_000,
        ),
        "silverReceived": _integer(
            raw.get("silverReceived"),
            "Silver received",
            minimum=0,
            maximum=9_007_199_254_740_991,
        ),
        "notes": _text(
            raw.get("notes"), "Session notes", maximum=12_000, allow_empty=True
        ),
        "createdAtUtc": created_text,
        "updatedAtUtc": updated_text,
    }


def _validate_document(
    source_bytes: bytes,
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    try:
        document = json.loads(source_bytes.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise LegacyV017MigrationError("Legacy Fishing journal JSON is invalid") from exc
    root = _object(document, "Fishing journal")
    if root.get("version") != 1:
        raise LegacyV017MigrationError("Legacy Fishing journal version is unsupported")
    raw_loadouts = root.get("loadouts")
    raw_sessions = root.get("sessions")
    if (
        not isinstance(raw_loadouts, list)
        or len(raw_loadouts) > MAX_LEGACY_LOADOUTS
    ):
        raise LegacyV017MigrationError("Fishing loadouts must be a valid list")
    if (
        not isinstance(raw_sessions, list)
        or len(raw_sessions) > MAX_LEGACY_SESSIONS
    ):
        raise LegacyV017MigrationError("Fishing sessions must be a valid list")
    loadouts = [_validate_loadout(value) for value in raw_loadouts]
    sessions = [_validate_session(value) for value in raw_sessions]
    if len({value["id"] for value in loadouts}) != len(loadouts):
        raise LegacyV017MigrationError("Fishing loadout ids must be unique")
    if len({value["id"] for value in sessions}) != len(sessions):
        raise LegacyV017MigrationError("Fishing session ids must be unique")
    return root, loadouts, sessions


def _profile_from_loadout(loadout: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": loadout["id"],
        "name": loadout["name"],
        "method": loadout["method"],
        "equipment": loadout["tool"],
        "mastery": loadout["mastery"],
        "notes": loadout["notes"],
        "createdAtUtc": loadout["createdAtUtc"],
        "updatedAtUtc": loadout["updatedAtUtc"],
    }


def _profiles_from_loadouts(loadouts: list[dict[str, Any]]) -> dict[str, Any]:
    candidates = [_profile_from_loadout(loadout) for loadout in loadouts]
    try:
        return SessionStore._normalize_fishing_profiles(
            {"profiles": candidates, "activeProfileId": None}
        )
    except SessionValidationError as exc:
        raise LegacyV017MigrationError(
            "Legacy Fishing profiles failed lossless validation"
        ) from exc


def _v1_imported_profile_ids(loadouts: list[dict[str, Any]]) -> set[str]:
    """Reproduce the unpublished v1 subset so later user deletions stay deleted."""

    identifiers: set[str] = set()
    names: set[str] = set()
    for loadout in loadouts:
        if len(identifiers) >= 16:
            break
        identifier = loadout["id"]
        name = loadout["name"]
        equipment = loadout["tool"]
        if (
            len(identifier) > 64
            or identifier != identifier.strip()
            or len(name) > 40
            or name != name.strip()
            or len(equipment) > 180
            or not equipment.strip()
            or equipment != equipment.strip()
            or name.casefold() in names
        ):
            continue
        identifiers.add(identifier)
        names.add(name.casefold())
    return identifiers


def _collision_profile_id(source_id: str, occupied_ids: set[str]) -> str:
    """Derive a stable current id while retaining the exact legacy id separately."""

    digest = hashlib.sha256(source_id.encode("utf-8")).hexdigest()
    base = f"legacy-v017-{digest}"
    candidate = base
    suffix = 2
    while candidate in occupied_ids:
        candidate = f"{base}-{suffix}"
        suffix += 1
    return candidate


def _upgrade_v1_profiles(
    connection: Any,
    *,
    loadouts: list[dict[str, Any]],
) -> dict[str, Any]:
    """Merge profiles omitted by v1 without replaying its migrated sessions."""

    existing = _decode_setting(_setting(connection, "fishing_profiles"))
    if existing is None or not isinstance(existing.get("profiles"), list):
        raise LegacyV017MigrationError(
            "The earlier Fishing profile migration cannot be upgraded safely"
        )

    source_profiles = [_profile_from_loadout(loadout) for loadout in loadouts]
    source_by_id = {profile["id"]: profile for profile in source_profiles}
    v1_imported_ids = _v1_imported_profile_ids(loadouts)
    merged: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    represented_source_ids: set[str] = set()
    for value in existing["profiles"]:
        if not isinstance(value, dict):
            raise LegacyV017MigrationError(
                "The earlier Fishing profile migration cannot be upgraded safely"
            )
        identifier = value.get("id")
        if not isinstance(identifier, str) or identifier in seen_ids:
            raise LegacyV017MigrationError(
                "The earlier Fishing profile migration cannot be upgraded safely"
            )
        source_profile = source_by_id.get(identifier)
        candidate = dict(value)
        legacy_source_id = candidate.get("legacySourceId")
        if legacy_source_id is not None:
            if not isinstance(legacy_source_id, str):
                raise LegacyV017MigrationError(
                    "The earlier Fishing profile migration cannot be upgraded safely"
                )
            represented_source_ids.add(legacy_source_id)
        if source_profile is not None and identifier in v1_imported_ids:
            # v1 did not retain these durable fields in the editable profile.
            # Enrich the existing profile without undoing any later user edits.
            for key in ("notes", "createdAtUtc", "updatedAtUtc"):
                if key not in candidate or candidate[key] is None:
                    candidate[key] = source_profile[key]
            represented_source_ids.add(identifier)
        merged.append(candidate)
        seen_ids.add(identifier)

    for profile in source_profiles:
        source_id = profile["id"]
        if source_id in represented_source_ids or source_id in v1_imported_ids:
            continue
        candidate = profile
        if source_id in seen_ids:
            # v1 could not have imported this loadout, so an existing profile
            # with the same id is current-only. Keep it untouched and give the
            # legacy profile a deterministic current id while retaining its
            # exact source identity for durable round-tripping and status.
            candidate = dict(profile)
            # Reserve every exact source id, including profiles still pending,
            # so an alias cannot steal a later profile's identity or cascade
            # its session-reference rewrite.
            candidate["id"] = _collision_profile_id(
                source_id, seen_ids | set(source_by_id)
            )
            candidate["legacySourceId"] = source_id
            connection.execute(
                """
                UPDATE sessions SET setup_id=?
                WHERE legacy_aggregate_only=1 AND setup_id=?
                """,
                (candidate["id"], source_id),
            )
        merged.append(candidate)
        seen_ids.add(candidate["id"])
        represented_source_ids.add(source_id)

    active = existing.get("activeProfileId")
    if active is not None and active not in seen_ids:
        active = None
    try:
        return SessionStore._normalize_fishing_profiles(
            {"profiles": merged, "activeProfileId": active}
        )
    except SessionValidationError as exc:
        raise LegacyV017MigrationError(
            "The earlier Fishing profile migration cannot be upgraded safely"
        ) from exc


def _write_backup(source: Path, source_bytes: bytes, digest: str) -> tuple[Path, str]:
    if (
        source.name.casefold() != SOURCE_FILE_NAME
        or source.parent.name.casefold() != "fishing"
    ):
        raise LegacyV017MigrationError(
            "Legacy source must be the selected root's fishing/fishing-journal.json"
        )
    personal_root = source.parent.parent
    backup_directory = personal_root / "migration-archive" / "v0.1.7"
    backup_directory.mkdir(parents=True, exist_ok=True)
    backup = backup_directory / f"fishing-journal.{digest}.json"
    if backup.exists():
        if hashlib.sha256(backup.read_bytes()).hexdigest() != digest:
            raise LegacyV017MigrationError(
                "Existing legacy backup does not match its name"
            )
    else:
        temporary = backup.with_name(f".{backup.name}.{uuid.uuid4().hex}.tmp")
        try:
            with temporary.open("xb") as output:
                output.write(source_bytes)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, backup)
        finally:
            temporary.unlink(missing_ok=True)
    return backup, backup.relative_to(personal_root).as_posix()


def _decode_setting(value: str | None) -> dict[str, Any] | None:
    if value is None:
        return None
    try:
        decoded = json.loads(value)
    except (json.JSONDecodeError, TypeError):
        return None
    return decoded if isinstance(decoded, dict) else None


def _setting(connection: Any, key: str) -> str | None:
    row = connection.execute(
        "SELECT value FROM app_settings WHERE key=?", (key,)
    ).fetchone()
    return None if row is None else str(row["value"])


def _database_has_personal_content(connection: Any) -> bool:
    for table in ("sessions", "session_items", "session_sales", "app_settings"):
        count = connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        if int(count) > 0:
            return True
    return False


def _insert_session(connection: Any, session: dict[str, Any]) -> None:
    connection.execute(
        """
        INSERT INTO sessions (
            id, created_at, caught_at, started_at, ended_at,
            zone_rgb, zone_name, location_name, method, style, equipment,
            setup_id, setup_name, mastery, duration_minutes, total_fish,
            total_value, entry_source, verification_status, updated_at,
            notes, legacy_received_silver, legacy_aggregate_only
        ) VALUES (
            :id, :createdAtUtc, :startedAtUtc, :startedAtUtc, :endedAtUtc,
            NULL, :location, :locationOrNull, :method, 'afk', :tool,
            :loadoutId, :loadoutName, :mastery, :durationMinutes,
            :retainedFishCount, 0, 'legacy-v017', 'legacy-aggregate-only',
            :updatedAtUtc, :notes, :silverReceived, 1
        )
        """,
        {**session, "locationOrNull": session["location"] or None},
    )


def migrate_v017_json(source_path: Path, database_path: Path) -> dict[str, Any]:
    """Migrate one selected-root v0.1.7 journal without merging or invention."""

    source = source_path.resolve(strict=True)
    database = database_path.resolve(strict=False)
    if database.name.casefold() != DATABASE_FILE_NAME:
        raise LegacyV017MigrationError(
            "Migration destination must be fish-journal.sqlite3"
        )
    source_bytes = source.read_bytes()
    digest = hashlib.sha256(source_bytes).hexdigest()
    raw_document, loadouts, sessions = _validate_document(source_bytes)
    _, backup_relative = _write_backup(source, source_bytes, digest)
    profiles = _profiles_from_loadouts(loadouts)

    store = SessionStore(database)
    connection = store._connect()
    try:
        connection.execute("BEGIN IMMEDIATE")
        existing_marker = _decode_setting(
            _setting(connection, MIGRATION_MARKER_KEY)
        )
        if (
            existing_marker is not None
            and existing_marker.get("migrationVersion") == MIGRATION_VERSION
            and existing_marker.get("sourceSha256") == digest
        ):
            connection.rollback()
            return {"status": "already-migrated", **existing_marker}
        upgrading_v1 = bool(
            existing_marker is not None
            and existing_marker.get("migrationVersion")
            == PREVIOUS_MIGRATION_VERSION
            and existing_marker.get("sourceSha256") == digest
        )
        if upgrading_v1:
            profiles = _upgrade_v1_profiles(connection, loadouts=loadouts)
        elif _database_has_personal_content(connection):
            connection.rollback()
            return {
                "status": "skipped-nonempty",
                "migrationVersion": MIGRATION_VERSION,
                "sourceSha256": digest,
            }

        profile_json = json.dumps(
            profiles, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        )
        archive = {
            "schemaVersion": 1,
            "migrationVersion": MIGRATION_VERSION,
            "sourceSchemaVersion": raw_document["version"],
            "sourceSha256": digest,
            "loadouts": raw_document["loadouts"],
        }
        archive_json = json.dumps(
            archive, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        )
        connection.execute(
            """
            INSERT INTO app_settings(key, value) VALUES ('fishing_profiles', ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value
            """,
            (profile_json,),
        )
        connection.execute(
            """
            INSERT INTO app_settings(key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value
            """,
            (LOADOUT_ARCHIVE_KEY, archive_json),
        )
        if not upgrading_v1:
            for session in sessions:
                _insert_session(connection, session)

        stored_profile_ids = {
            profile.get("legacySourceId") or profile["id"]
            for profile in profiles["profiles"]
        }
        available_source_profiles = sum(
            1 for loadout in loadouts if loadout["id"] in stored_profile_ids
        )
        preserved_deleted_profiles = len(loadouts) - available_source_profiles

        marker = {
            "schemaVersion": 1,
            "migrationVersion": MIGRATION_VERSION,
            "sourceSchemaVersion": raw_document["version"],
            "sourceSha256": digest,
            "backupRelativePath": backup_relative,
            "loadoutCount": len(loadouts),
            "importedProfileCount": available_source_profiles,
            "preservedDeletedProfileCount": preserved_deleted_profiles,
            "archiveOnlyLoadoutCount": 0,
            "sessionCount": len(sessions),
            "completedAtUtc": datetime.now(timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z"),
        }
        connection.execute(
            """
            INSERT INTO app_settings(key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value
            """,
            (
                MIGRATION_MARKER_KEY,
                json.dumps(
                    marker,
                    ensure_ascii=False,
                    separators=(",", ":"),
                    sort_keys=True,
                ),
            ),
        )
        connection.commit()
        return {"status": "upgraded" if upgrading_v1 else "migrated", **marker}
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
