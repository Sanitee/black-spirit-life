"""Privacy-minimal SQLite fishing journal and personal statistics."""

from __future__ import annotations

import json
import sqlite3
import uuid
from collections import defaultdict
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


class SessionValidationError(ValueError):
    """Raised when structured journal input is incomplete or unsafe."""


FORBIDDEN_FIELD_PARTS = (
    "screenshot",
    "thumbnail",
    "filename",
    "file_path",
    "filepath",
    "image_data",
    "imagepath",
    "image_path",
    "rawocr",
    "raw_ocr",
    "cropdata",
    "crop_data",
)

DEFAULT_VALUE_SETTINGS: dict[str, float] = {
    "distanceBonusPercent": 0.0,
}

LEGACY_VALUE_SETTING_FIELDS = {
    "freshnessPercent",
    "quotationPercent",
    "bargainBonusPercent",
}

MAX_FISHING_SETUPS = 12
# A v0.1.7 journal can contain 1,000 loadouts. The unpublished first migration
# could also leave up to 16 user-created current profiles alongside loadouts it
# could not represent, so the durable store must accommodate their lossless v2
# merge. Fresh legacy input remains capped separately by MAX_LEGACY_LOADOUTS.
MAX_FISHING_PROFILES = 1_016
LIFE_SKILL_RANKS = (
    "Beginner",
    "Apprentice",
    "Skilled",
    "Professional",
    "Artisan",
    "Master",
    "Guru",
)
LIFE_SKILL_RANK_OFFSETS = {
    "Beginner": 0,
    "Apprentice": 10,
    "Skilled": 20,
    "Professional": 30,
    "Artisan": 40,
    "Master": 50,
    "Guru": 80,
}
FISHING_RESOURCE_LEVELS = {
    "abundant": "abundant",
    "average": "average",
    "not enough": "not-enough",
    "not-enough": "not-enough",
    "notenough": "not-enough",
    "exhausted": "exhausted",
}
MAX_AUTO_FISHING_REDUCTION = 66.67


def _assert_structured_only(value: Any) -> None:
    if isinstance(value, dict):
        for key, nested in value.items():
            normalized = str(key).casefold().replace("-", "_")
            safe_profile_fields = {"profileid", "profilename"}
            if normalized not in safe_profile_fields and any(
                part in normalized for part in FORBIDDEN_FIELD_PARTS
            ):
                raise SessionValidationError(
                    "Screenshots, crops, filenames, paths, and raw OCR data cannot be stored"
                )
            _assert_structured_only(nested)
    elif isinstance(value, list):
        for nested in value:
            _assert_structured_only(nested)


def _int(value: Any, *, minimum: int | None = None, maximum: int | None = None) -> int | None:
    if value in (None, ""):
        return None
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise SessionValidationError("A numeric journal field is invalid") from exc
    if minimum is not None and parsed < minimum:
        raise SessionValidationError("A numeric journal field is below its allowed range")
    if maximum is not None and parsed > maximum:
        raise SessionValidationError("A numeric journal field is above its allowed range")
    return parsed


def _text(value: Any, *, maximum: int = 160) -> str | None:
    if value is None:
        return None
    parsed = str(value).strip()
    if not parsed:
        return None
    if len(parsed) > maximum:
        raise SessionValidationError("A journal text field is too long")
    return parsed


def _profile_text(
    value: Any,
    *,
    field: str,
    maximum: int,
    allow_empty: bool = False,
    allow_none: bool = False,
) -> str | None:
    """Validate durable profile text without changing its stored identity."""

    if value is None:
        if allow_none:
            return None
        raise SessionValidationError(f"{field} is required")
    if not isinstance(value, str) or len(value) > maximum:
        raise SessionValidationError(f"{field} is invalid")
    if not allow_empty and not value.strip():
        raise SessionValidationError(f"{field} is required")
    return value


def _profile_timestamp(value: Any, *, field: str) -> tuple[str, datetime] | None:
    """Validate an optional timestamp while retaining its exact source string."""

    if value is None:
        return None
    if not isinstance(value, str) or len(value) > 80:
        raise SessionValidationError(f"{field} is invalid")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SessionValidationError(f"{field} must be an ISO-8601 timestamp") from exc
    if parsed.tzinfo is None:
        raise SessionValidationError(f"{field} must include a UTC offset")
    return value, parsed.astimezone(timezone.utc)


def _number(value: Any, *, minimum: float, maximum: float) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise SessionValidationError("A sale-estimate percentage is invalid") from exc
    if not minimum <= parsed <= maximum:
        raise SessionValidationError("A sale-estimate percentage is outside its allowed range")
    return round(parsed, 2)


def _optional_number(
    value: Any, *, minimum: float, maximum: float
) -> float | None:
    if value in (None, ""):
        return None
    return _number(value, minimum=minimum, maximum=maximum)


def _life_skill_rank(value: Any, *, field: str) -> str | None:
    text = _text(value, maximum=24)
    if text is None:
        return None
    match = next((rank for rank in LIFE_SKILL_RANKS if rank.casefold() == text.casefold()), None)
    if match is None:
        raise SessionValidationError(f"{field} rank is invalid")
    return match


def _life_skill_level(rank: str | None, value: Any, *, field: str) -> int | None:
    level = _int(value, minimum=1, maximum=100)
    if rank is None or level is None:
        return level
    maximum = 100 if rank == "Guru" else 30 if rank == "Master" else 10
    if level > maximum:
        raise SessionValidationError(f"{field} {rank} level must be between 1 and {maximum}")
    return level


def _bargain_bonus_percent(rank: str | None, level: int | None) -> float:
    if rank is None or level is None:
        return 0.0
    absolute_level = LIFE_SKILL_RANK_OFFSETS[rank] + level
    return round(5.0 + absolute_level * 0.5, 2)


def _auto_fishing_delay(reduction_percent: float | None) -> float | None:
    if reduction_percent is None:
        return None
    return round(max(60.0, 180.0 * (1.0 - reduction_percent / 100.0)), 1)


def _auto_fishing_reduction_from_delay(value: Any) -> float | None:
    if value in (None, ""):
        return None
    delay = _number(value, minimum=60.0, maximum=180.0)
    return round(
        max(0.0, min(MAX_AUTO_FISHING_REDUCTION, (1.0 - delay / 180.0) * 100.0)),
        2,
    )


def _fishing_resource_level(value: Any) -> str | None:
    text = _text(value, maximum=32)
    if text is None or text.casefold() in {"unknown", "not recorded", "not-recorded"}:
        return None
    normalized = FISHING_RESOURCE_LEVELS.get(text.casefold())
    if normalized is None:
        raise SessionValidationError("Fishing resource level is invalid")
    return normalized


def _iso_time(value: Any) -> str:
    if value in (None, ""):
        return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    text = str(value).strip()
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SessionValidationError("caughtAt must be an ISO-8601 timestamp") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _optional_iso_time(value: Any, *, field: str) -> str | None:
    if value in (None, ""):
        return None
    text = str(value).strip()
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SessionValidationError(f"{field} must be an ISO-8601 timestamp") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


class SessionStore:
    """Stores only normalized fields needed by the journal and its aggregates."""

    def __init__(self, path: Path):
        self.path = path
        path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 5000")
        return connection

    @contextmanager
    def _connection(self):
        """Commit or roll back each short operation and always release the file handle."""

        connection = self._connect()
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self._connection() as connection:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY,
                    created_at TEXT NOT NULL,
                    caught_at TEXT NOT NULL,
                    started_at TEXT,
                    ended_at TEXT,
                    zone_rgb TEXT,
                    zone_name TEXT NOT NULL,
                    location_name TEXT,
                    point_x INTEGER,
                    point_y INTEGER,
                    depth TEXT,
                    method TEXT NOT NULL CHECK (method IN ('rod', 'harpoon')),
                    style TEXT NOT NULL CHECK (style IN ('afk', 'active')),
                    rod TEXT,
                    float_name TEXT,
                    equipment TEXT,
                    setup_id TEXT,
                    setup_name TEXT,
                    keep_from TEXT,
                    mastery INTEGER,
                    fishing_speed INTEGER,
                    auto_fishing_delay_seconds INTEGER,
                    fishing_rank TEXT,
                    fishing_level INTEGER,
                    trading_mastery INTEGER,
                    trading_rank TEXT,
                    trading_level INTEGER,
                    freshness_percent REAL,
                    quotation_percent REAL,
                    distance_bonus_percent REAL,
                    bargain_bonus_percent REAL,
                    resource_level TEXT,
                    auto_fishing_reduction_percent REAL,
                    excluded_minutes INTEGER NOT NULL DEFAULT 0,
                    duration_minutes INTEGER,
                    total_fish INTEGER NOT NULL,
                    total_value INTEGER NOT NULL,
                    entry_source TEXT NOT NULL,
                    verification_status TEXT,
                    updated_at TEXT,
                    notes TEXT,
                    legacy_received_silver INTEGER,
                    legacy_aggregate_only INTEGER NOT NULL DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS session_items (
                    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                    item_id INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    grade TEXT,
                    count INTEGER NOT NULL CHECK (count > 0),
                    unit_price INTEGER,
                    PRIMARY KEY (session_id, item_id)
                );

                CREATE TABLE IF NOT EXISTS session_sales (
                    session_id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
                    sold_at TEXT NOT NULL,
                    destination TEXT NOT NULL,
                    current_tank_value INTEGER NOT NULL CHECK (current_tank_value >= 0),
                    market_percent REAL NOT NULL,
                    distance_bonus_percent REAL NOT NULL,
                    bargain_bonus_percent REAL NOT NULL,
                    final_amount INTEGER NOT NULL CHECK (final_amount >= 0)
                );

                CREATE TABLE IF NOT EXISTS app_settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS sessions_zone_idx ON sessions(zone_rgb, zone_name);
                CREATE INDEX IF NOT EXISTS sessions_filter_idx ON sessions(method, style, mastery);
                CREATE INDEX IF NOT EXISTS session_items_item_idx ON session_items(item_id);
                CREATE INDEX IF NOT EXISTS session_sales_sold_idx ON session_sales(sold_at);
                """
            )
            columns = {row[1] for row in connection.execute("PRAGMA table_info(sessions)")}
            if "depth" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN depth TEXT")
            if "keep_from" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN keep_from TEXT")
            if "location_name" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN location_name TEXT")
            if "point_x" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN point_x INTEGER")
            if "point_y" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN point_y INTEGER")
            if "started_at" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN started_at TEXT")
            if "ended_at" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN ended_at TEXT")
            if "excluded_minutes" not in columns:
                connection.execute(
                    "ALTER TABLE sessions ADD COLUMN excluded_minutes INTEGER NOT NULL DEFAULT 0"
                )
            if "setup_id" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN setup_id TEXT")
            if "setup_name" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN setup_name TEXT")
            if "fishing_speed" not in columns:
                connection.execute("ALTER TABLE sessions ADD COLUMN fishing_speed INTEGER")
            if "auto_fishing_delay_seconds" not in columns:
                connection.execute(
                    "ALTER TABLE sessions ADD COLUMN auto_fishing_delay_seconds INTEGER"
                )
            profile_columns = {
                "fishing_rank": "TEXT",
                "fishing_level": "INTEGER",
                "trading_mastery": "INTEGER",
                "trading_rank": "TEXT",
                "trading_level": "INTEGER",
                "freshness_percent": "REAL",
                "quotation_percent": "REAL",
                "distance_bonus_percent": "REAL",
                "bargain_bonus_percent": "REAL",
                "resource_level": "TEXT",
                "auto_fishing_reduction_percent": "REAL",
                "updated_at": "TEXT",
                "notes": "TEXT",
                "legacy_received_silver": "INTEGER",
                "legacy_aggregate_only": "INTEGER NOT NULL DEFAULT 0",
            }
            for column, kind in profile_columns.items():
                if column not in columns:
                    connection.execute(f"ALTER TABLE sessions ADD COLUMN {column} {kind}")

    @staticmethod
    def _normalize_value_settings(payload: dict[str, Any]) -> dict[str, float]:
        if not isinstance(payload, dict):
            raise SessionValidationError("Sale-estimate settings must be a JSON object")
        _assert_structured_only(payload)
        unknown = set(payload) - set(DEFAULT_VALUE_SETTINGS) - LEGACY_VALUE_SETTING_FIELDS
        if unknown:
            raise SessionValidationError("Sale-estimate settings contain an unknown field")
        return {
            "distanceBonusPercent": _number(
                payload.get("distanceBonusPercent", 0.0), minimum=0.0, maximum=150.0
            )
        }

    def value_settings(self) -> dict[str, float]:
        with self._connection() as connection:
            row = connection.execute(
                "SELECT value FROM app_settings WHERE key='journal_value_settings'"
            ).fetchone()
        if row is None:
            return dict(DEFAULT_VALUE_SETTINGS)
        try:
            value = json.loads(row["value"])
            return self._normalize_value_settings(value)
        except (json.JSONDecodeError, SessionValidationError, TypeError):
            return dict(DEFAULT_VALUE_SETTINGS)

    def update_value_settings(self, payload: dict[str, Any]) -> dict[str, float]:
        settings = self._normalize_value_settings(payload)
        encoded = json.dumps(settings, separators=(",", ":"), sort_keys=True)
        with self._connection() as connection:
            connection.execute(
                """
                INSERT INTO app_settings(key, value) VALUES ('journal_value_settings', ?)
                ON CONFLICT(key) DO UPDATE SET value=excluded.value
                """,
                (encoded,),
            )
        return settings

    @staticmethod
    def _normalize_fishing_setups(payload: dict[str, Any]) -> list[dict[str, Any]]:
        if not isinstance(payload, dict):
            raise SessionValidationError("Fishing setups must be a JSON object")
        _assert_structured_only(payload)
        if set(payload) - {"setups"}:
            raise SessionValidationError("Fishing setups contain an unknown field")
        raw_setups = payload.get("setups")
        if not isinstance(raw_setups, list):
            raise SessionValidationError("Fishing setups must be a list")
        if len(raw_setups) > MAX_FISHING_SETUPS:
            raise SessionValidationError(
                f"No more than {MAX_FISHING_SETUPS} fishing setups can be saved"
            )

        allowed = {
            "id",
            "name",
            "method",
            "equipment",
            "mastery",
            "fishingSpeed",
            "autoFishingDelaySeconds",
        }
        normalized: list[dict[str, Any]] = []
        ids: set[str] = set()
        names: set[tuple[str, str]] = set()
        for raw in raw_setups:
            if not isinstance(raw, dict):
                raise SessionValidationError("Each fishing setup must be an object")
            if set(raw) - allowed:
                raise SessionValidationError("A fishing setup contains an unknown field")

            setup_id = _text(raw.get("id"), maximum=64) or str(uuid.uuid4())
            if setup_id in ids:
                raise SessionValidationError("Fishing setup ids must be unique")
            ids.add(setup_id)

            name = _text(raw.get("name"), maximum=40)
            if not name:
                raise SessionValidationError("Each fishing setup needs a name")
            method_value = str(raw.get("method") or "rod").casefold().strip()
            method = {
                "fishing": "rod",
                "rod": "rod",
                "harpoon": "harpoon",
                "harpooning": "harpoon",
            }.get(method_value)
            if method is None:
                raise SessionValidationError("A fishing setup method is invalid")
            name_key = (method, name.casefold())
            if name_key in names:
                raise SessionValidationError("Fishing setup names must be unique per method")
            names.add(name_key)

            equipment = _text(raw.get("equipment"), maximum=180)
            if not equipment:
                raise SessionValidationError("Each fishing setup needs a rod or harpoon")
            mastery = _int(raw.get("mastery"), minimum=0, maximum=5000)
            if mastery is None:
                raise SessionValidationError("Each fishing setup needs an exact mastery value")

            fishing_speed = _int(raw.get("fishingSpeed"), minimum=0, maximum=5)
            auto_delay = _int(
                raw.get("autoFishingDelaySeconds"), minimum=60, maximum=180
            )
            if method == "rod" and fishing_speed is None:
                raise SessionValidationError("Fishing setups need a Fishing Speed level from 0 to 5")
            if method == "harpoon":
                fishing_speed = None
                auto_delay = None

            normalized.append(
                {
                    "id": setup_id,
                    "name": name,
                    "method": method,
                    "equipment": equipment,
                    "mastery": mastery,
                    "fishingSpeed": fishing_speed,
                    "autoFishingDelaySeconds": auto_delay,
                }
            )
        return normalized

    def fishing_setups(self) -> list[dict[str, Any]]:
        with self._connection() as connection:
            row = connection.execute(
                "SELECT value FROM app_settings WHERE key='fishing_setups'"
            ).fetchone()
        if row is None:
            return []
        try:
            value = json.loads(row["value"])
            return self._normalize_fishing_setups({"setups": value})
        except (json.JSONDecodeError, SessionValidationError, TypeError):
            return []

    def update_fishing_setups(self, payload: dict[str, Any]) -> list[dict[str, Any]]:
        setups = self._normalize_fishing_setups(payload)
        encoded = json.dumps(setups, separators=(",", ":"), sort_keys=True)
        with self._connection() as connection:
            connection.execute(
                """
                INSERT INTO app_settings(key, value) VALUES ('fishing_setups', ?)
                ON CONFLICT(key) DO UPDATE SET value=excluded.value
                """,
                (encoded,),
            )
        return setups

    @staticmethod
    def _normalize_fishing_profiles(payload: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise SessionValidationError("Fishing profiles must be a JSON object")
        _assert_structured_only(payload)
        if set(payload) - {"profiles", "activeProfileId"}:
            raise SessionValidationError("Fishing profiles contain an unknown field")
        raw_profiles = payload.get("profiles")
        if not isinstance(raw_profiles, list):
            raise SessionValidationError("Fishing profiles must be a list")
        if len(raw_profiles) > MAX_FISHING_PROFILES:
            raise SessionValidationError(
                f"No more than {MAX_FISHING_PROFILES} fishing profiles can be saved"
            )

        allowed = {
            "id",
            "legacySourceId",
            "name",
            "method",
            "equipment",
            "mastery",
            "fishingRank",
            "fishingLevel",
            "autoFishingReductionPercent",
            # Accepted only to migrate profiles saved by earlier builds.
            "fishingSpeed",
            "autoFishingDelaySeconds",
            "tradingMastery",
            "tradingRank",
            "tradingLevel",
            "freshnessPercent",
            "quotationPercent",
            "distanceBonusPercent",
            "bargainBonusPercent",
            "notes",
            "createdAtUtc",
            "updatedAtUtc",
        }
        normalized: list[dict[str, Any]] = []
        ids: set[str] = set()
        legacy_source_ids: set[str] = set()
        for raw in raw_profiles:
            if not isinstance(raw, dict):
                raise SessionValidationError("Each fishing profile must be an object")
            if set(raw) - allowed:
                raise SessionValidationError("A fishing profile contains an unknown field")

            profile_id = (
                str(uuid.uuid4())
                if raw.get("id") in (None, "")
                else _profile_text(
                    raw.get("id"), field="Fishing profile id", maximum=160
                )
            )
            assert profile_id is not None
            if profile_id in ids:
                raise SessionValidationError("Fishing profile ids must be unique")
            ids.add(profile_id)

            legacy_source_id = _profile_text(
                raw.get("legacySourceId"),
                field="Legacy Fishing profile id",
                maximum=160,
                allow_none=True,
            )
            if legacy_source_id is not None:
                if legacy_source_id in legacy_source_ids:
                    raise SessionValidationError(
                        "Legacy Fishing profile ids must be unique"
                    )
                legacy_source_ids.add(legacy_source_id)

            name = _profile_text(
                raw.get("name"), field="Fishing profile name", maximum=120
            )
            assert name is not None

            method_value = str(raw.get("method") or "rod").casefold().strip()
            method = {
                "fishing": "rod",
                "rod": "rod",
                "harpoon": "harpoon",
                "harpooning": "harpoon",
            }.get(method_value)
            if method is None:
                raise SessionValidationError("A fishing profile method is invalid")

            equipment = _profile_text(
                raw.get("equipment"),
                field="Fishing profile tool",
                maximum=200,
                allow_empty=True,
            )
            assert equipment is not None
            mastery = _int(raw.get("mastery"), minimum=0, maximum=5000)
            if mastery is None:
                raise SessionValidationError("Each fishing profile needs an exact mastery value")

            fishing_rank = _life_skill_rank(raw.get("fishingRank"), field="Fishing")
            fishing_level = _life_skill_level(
                fishing_rank, raw.get("fishingLevel"), field="Fishing"
            )
            if (fishing_rank is None) != (fishing_level is None):
                raise SessionValidationError("Fishing rank and level must be saved together")
            auto_reduction = _optional_number(
                raw.get("autoFishingReductionPercent"),
                minimum=0.0,
                maximum=MAX_AUTO_FISHING_REDUCTION,
            )
            if auto_reduction is None:
                auto_reduction = _auto_fishing_reduction_from_delay(
                    raw.get("autoFishingDelaySeconds")
                )
            if method == "harpoon":
                auto_reduction = None
            auto_delay = _auto_fishing_delay(auto_reduction)

            trading_rank = _life_skill_rank(raw.get("tradingRank"), field="Trading")
            trading_level = _life_skill_level(
                trading_rank, raw.get("tradingLevel"), field="Trading"
            )
            if (trading_rank is None) != (trading_level is None):
                raise SessionValidationError("Trading rank and level must be saved together")

            notes = _profile_text(
                raw.get("notes", ""),
                field="Fishing profile notes",
                maximum=4_000,
                allow_empty=True,
            )
            created = _profile_timestamp(
                raw.get("createdAtUtc"), field="Fishing profile creation timestamp"
            )
            updated = _profile_timestamp(
                raw.get("updatedAtUtc"), field="Fishing profile update timestamp"
            )
            if (created is None) != (updated is None):
                raise SessionValidationError(
                    "Fishing profile timestamps must be saved together"
                )
            if created is not None and updated is not None and updated[1] < created[1]:
                raise SessionValidationError(
                    "Fishing profile update timestamp precedes its creation timestamp"
                )
            normalized.append(
                {
                    "id": profile_id,
                    "legacySourceId": legacy_source_id,
                    "name": name,
                    "method": method,
                    "equipment": equipment,
                    "mastery": mastery,
                    "fishingRank": fishing_rank,
                    "fishingLevel": fishing_level,
                    "autoFishingReductionPercent": auto_reduction,
                    "autoFishingDelaySeconds": auto_delay,
                    "tradingRank": trading_rank,
                    "tradingLevel": trading_level,
                    "bargainBonusPercent": _bargain_bonus_percent(
                        trading_rank, trading_level
                    ),
                    "notes": notes,
                    "createdAtUtc": None if created is None else created[0],
                    "updatedAtUtc": None if updated is None else updated[0],
                }
            )

        active_value = payload.get("activeProfileId")
        active_profile_id = (
            None
            if active_value in (None, "")
            else _profile_text(
                active_value,
                field="Active fishing profile id",
                maximum=160,
            )
        )
        if active_profile_id and active_profile_id not in ids:
            raise SessionValidationError("The active fishing profile does not exist")
        return {"profiles": normalized, "activeProfileId": active_profile_id}

    def fishing_profiles(self) -> dict[str, Any]:
        with self._connection() as connection:
            row = connection.execute(
                "SELECT value FROM app_settings WHERE key='fishing_profiles'"
            ).fetchone()
        if row is not None:
            try:
                return self._normalize_fishing_profiles(json.loads(row["value"]))
            except (json.JSONDecodeError, SessionValidationError, TypeError):
                pass

        legacy = self.fishing_setups()
        if not legacy:
            return {"profiles": [], "activeProfileId": None}
        migrated: list[dict[str, Any]] = []
        for setup in legacy:
            migrated.append(
                {
                    **setup,
                    "fishingRank": None,
                    "fishingLevel": None,
                    "tradingRank": None,
                    "tradingLevel": None,
                }
            )
        return self._normalize_fishing_profiles(
            {"profiles": migrated, "activeProfileId": migrated[0]["id"]}
        )

    def update_fishing_profiles(self, payload: dict[str, Any]) -> dict[str, Any]:
        profiles = self._normalize_fishing_profiles(payload)
        encoded = json.dumps(profiles, separators=(",", ":"), sort_keys=True)
        with self._connection() as connection:
            connection.execute(
                """
                INSERT INTO app_settings(key, value) VALUES ('fishing_profiles', ?)
                ON CONFLICT(key) DO UPDATE SET value=excluded.value
                """,
                (encoded,),
            )
        return profiles

    def migration_status(self) -> dict[str, Any]:
        """Return privacy-safe migration metadata without exposing local paths."""

        with self._connection() as connection:
            row = connection.execute(
                "SELECT value FROM app_settings WHERE key='migration.stable-v0.1.7.fishing'"
            ).fetchone()
        if row is None:
            return {"legacyV017": None}
        try:
            value = json.loads(row["value"])
        except (json.JSONDecodeError, TypeError):
            return {"legacyV017": None}
        if not isinstance(value, dict):
            return {"legacyV017": None}
        allowed = {
            "schemaVersion",
            "migrationVersion",
            "sourceSchemaVersion",
            "sourceSha256",
            "backupRelativePath",
            "loadoutCount",
            "importedProfileCount",
            "preservedDeletedProfileCount",
            "archiveOnlyLoadoutCount",
            "sessionCount",
            "completedAtUtc",
        }
        return {"legacyV017": {key: value[key] for key in allowed if key in value}}

    def checkpoint(self) -> None:
        """Flush SQLite WAL state before the host moves or closes personal data."""

        with self._connection() as connection:
            connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()

    @staticmethod
    def _normalize(
        payload: dict[str, Any],
        catalog_lookup: Callable[[int], dict[str, Any] | None],
        existing_id: str | None = None,
    ) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise SessionValidationError("Session body must be a JSON object")
        _assert_structured_only(payload)

        zone = payload.get("zone") or payload.get("spot") or {}
        if not isinstance(zone, dict):
            zone = {}
        zone_rgb = _text(
            payload.get("zoneRgb") or payload.get("rgb") or zone.get("rgb"), maximum=11
        )
        zone_name = _text(
            payload.get("zoneName") or payload.get("spotName") or zone.get("name"), maximum=180
        )
        if not zone_name:
            raise SessionValidationError("A fishing spot is required")
        node = payload.get("node") or {}
        if not isinstance(node, dict):
            node = {}
        location_name = _text(
            payload.get("locationName") or payload.get("nodeName") or node.get("name"),
            maximum=180,
        )
        point = payload.get("point") or payload.get("mapPoint") or {}
        if point is None:
            point = {}
        if not isinstance(point, dict):
            raise SessionValidationError("The saved map point must contain x and y coordinates")
        point_x = _int(
            point.get("x") if point.get("x") is not None else payload.get("pointX"),
            minimum=0,
            maximum=11_559,
        )
        point_y = _int(
            point.get("y") if point.get("y") is not None else payload.get("pointY"),
            minimum=0,
            maximum=10_539,
        )
        if (point_x is None) != (point_y is None):
            raise SessionValidationError("A saved map point requires both x and y coordinates")
        depth = _text(payload.get("depth"), maximum=40)

        method_value = str(payload.get("method") or "rod").casefold().strip()
        method = {"fishing": "rod", "rod": "rod", "harpoon": "harpoon", "harpooning": "harpoon"}.get(
            method_value
        )
        if method is None:
            raise SessionValidationError("Method must be fishing or harpooning")
        style = str(payload.get("style") or payload.get("activity") or "afk").casefold().strip()
        if style not in {"afk", "active"}:
            raise SessionValidationError("Style must be AFK or active")

        rod = _text(payload.get("rod"), maximum=100)
        float_name = _text(payload.get("float") or payload.get("floatName"), maximum=100)
        equipment = _profile_text(
            payload.get("equipment"),
            field="Fishing equipment",
            maximum=200,
            allow_empty=True,
            allow_none=True,
        )
        if equipment is None:
            equipment = " / ".join(value for value in (rod, float_name) if value) or None
        keep_from = _text(payload.get("keepFrom"), maximum=40)
        resource_level = _fishing_resource_level(payload.get("resourceLevel"))
        mastery = _int(payload.get("mastery"), minimum=0, maximum=5000)
        setup_id = _profile_text(
            payload.get("profileId") if "profileId" in payload else payload.get("setupId"),
            field="Fishing profile id",
            maximum=160,
            allow_none=True,
        )
        setup_name = _profile_text(
            payload.get("profileName") if "profileName" in payload else payload.get("setupName"),
            field="Fishing profile name",
            maximum=120,
            allow_empty=True,
            allow_none=True,
        )
        fishing_rank = _life_skill_rank(payload.get("fishingRank"), field="Fishing")
        fishing_level = _life_skill_level(
            fishing_rank, payload.get("fishingLevel"), field="Fishing"
        )
        if (fishing_rank is None) != (fishing_level is None):
            raise SessionValidationError("Fishing rank and level must be saved together")
        legacy_fishing_speed = _int(payload.get("fishingSpeed"), minimum=0, maximum=5)
        auto_fishing_reduction = _optional_number(
            payload.get("autoFishingReductionPercent"),
            minimum=0.0,
            maximum=MAX_AUTO_FISHING_REDUCTION,
        )
        if auto_fishing_reduction is None:
            auto_fishing_reduction = _auto_fishing_reduction_from_delay(
                payload.get("autoFishingDelaySeconds")
            )
        if method == "rod" and auto_fishing_reduction is None:
            auto_fishing_reduction = 0.0
        auto_fishing_delay = _auto_fishing_delay(auto_fishing_reduction)
        trading_rank = _life_skill_rank(payload.get("tradingRank"), field="Trading")
        trading_level = _life_skill_level(
            trading_rank, payload.get("tradingLevel"), field="Trading"
        )
        if (trading_rank is None) != (trading_level is None):
            raise SessionValidationError("Trading rank and level must be saved together")
        legacy_trading_mastery = _int(
            payload.get("tradingMastery"), minimum=0, maximum=5000
        )
        legacy_freshness = _optional_number(
            payload.get("freshnessPercent"), minimum=30.0, maximum=100.0
        )
        legacy_quotation = _optional_number(
            payload.get("quotationPercent"), minimum=80.0, maximum=130.0
        )
        legacy_distance = _optional_number(
            payload.get("distanceBonusPercent"), minimum=0.0, maximum=150.0
        )
        if method != "rod":
            resource_level = None
            legacy_fishing_speed = None
            auto_fishing_reduction = None
            auto_fishing_delay = None
        elif style != "afk":
            auto_fishing_delay = None
        bargain_bonus_percent = _bargain_bonus_percent(trading_rank, trading_level)
        duration = _int(
            payload.get("durationMinutes") or payload.get("timeMinutes"), minimum=1, maximum=10080
        )
        excluded_minutes = _int(
            payload.get("excludedMinutes"), minimum=0, maximum=10079
        ) or 0
        started_at = _optional_iso_time(payload.get("startedAt"), field="startedAt")
        ended_at = _optional_iso_time(payload.get("endedAt"), field="endedAt")
        if (started_at is None) != (ended_at is None):
            raise SessionValidationError("Fishing start and end times must be saved together")
        if started_at and ended_at:
            started_value = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
            ended_value = datetime.fromisoformat(ended_at.replace("Z", "+00:00"))
            elapsed_seconds = (ended_value - started_value).total_seconds()
            if elapsed_seconds <= 0:
                raise SessionValidationError("Fishing end time must be later than its start time")
            if elapsed_seconds > 10080 * 60:
                raise SessionValidationError("A fishing session cannot be longer than 7 days")
            gross_minutes = max(1, round(elapsed_seconds / 60))
            if excluded_minutes >= gross_minutes:
                raise SessionValidationError(
                    "Time away must be shorter than the full start-to-end period"
                )
            duration = gross_minutes - excluded_minutes
        elif excluded_minutes:
            raise SessionValidationError(
                "Time away can only be subtracted from a saved start and end time"
            )
        caught_at = _iso_time(payload.get("caughtAt") or payload.get("date") or ended_at)
        source = _text(payload.get("source") or payload.get("entrySource") or "manual", maximum=40)
        verification = (
            payload.get("verification")
            or payload.get("verificationStatus")
            or payload.get("recognition")
        )
        if isinstance(verification, dict):
            uncertain = _int(verification.get("uncertainCatchSlots"), minimum=0, maximum=1000)
            verification = verification.get("status") or ("verified" if uncertain == 0 else "needs-review")
        verification_text = _text(verification, maximum=40)

        raw_items = payload.get("items") or payload.get("fish") or payload.get("catches")
        if not isinstance(raw_items, list) or not raw_items:
            raise SessionValidationError("At least one recognized or manually entered fish is required")
        by_id: dict[int, dict[str, Any]] = {}
        for raw in raw_items:
            if not isinstance(raw, dict):
                raise SessionValidationError("Each fish entry must be an object")
            item_id = _int(raw.get("itemId") or raw.get("item_id"), minimum=1, maximum=99_999_999)
            count = _int(raw.get("count"), minimum=1, maximum=1000)
            if item_id is None or count is None:
                raise SessionValidationError("Every fish needs an item id and count")
            catalog = catalog_lookup(item_id) or {}
            name = _text(raw.get("name") or catalog.get("name"), maximum=160)
            if not name:
                raise SessionValidationError(f"Fish item {item_id} has no known name")
            grade = _text(raw.get("grade") or catalog.get("grade"), maximum=40)
            price = _int(
                raw.get("unitPrice")
                if raw.get("unitPrice") is not None
                else raw.get("price")
                if raw.get("price") is not None
                else catalog.get("price"),
                minimum=0,
                maximum=10_000_000_000,
            )
            existing = by_id.get(item_id)
            if existing:
                existing["count"] += count
            else:
                by_id[item_id] = {
                    "itemId": item_id,
                    "name": name,
                    "grade": grade,
                    "count": count,
                    "unitPrice": price,
                    "price": price,
                    "iconUrl": f"/icon/{item_id}.webp",
                }

        items = sorted(by_id.values(), key=lambda item: item["name"].casefold())
        total_fish = sum(item["count"] for item in items)
        if total_fish > 1000:
            raise SessionValidationError("A single journal entry cannot contain more than 1,000 fish")
        total_value = sum((item["unitPrice"] or 0) * item["count"] for item in items)
        return {
            "id": existing_id or str(uuid.uuid4()),
            "createdAt": datetime.now(timezone.utc)
            .isoformat(timespec="seconds")
            .replace("+00:00", "Z"),
            "caughtAt": caught_at,
            "startedAt": started_at,
            "endedAt": ended_at,
            "zoneRgb": zone_rgb,
            "zoneName": zone_name,
            "locationName": location_name,
            "pointX": point_x,
            "pointY": point_y,
            "point": {"x": point_x, "y": point_y}
            if point_x is not None and point_y is not None
            else None,
            "depth": depth,
            "method": method,
            "style": style,
            "rod": rod,
            "float": float_name,
            "equipment": equipment,
            "setupId": setup_id,
            "setupName": setup_name,
            "profileId": setup_id,
            "profileName": setup_name,
            "keepFrom": keep_from,
            "mastery": mastery,
            "fishingRank": fishing_rank,
            "fishingLevel": fishing_level,
            "fishingSpeed": legacy_fishing_speed,
            "resourceLevel": resource_level,
            "autoFishingReductionPercent": auto_fishing_reduction,
            "autoFishingDelaySeconds": auto_fishing_delay,
            "tradingMastery": legacy_trading_mastery,
            "tradingRank": trading_rank,
            "tradingLevel": trading_level,
            "freshnessPercent": legacy_freshness,
            "quotationPercent": legacy_quotation,
            "distanceBonusPercent": legacy_distance,
            "bargainBonusPercent": bargain_bonus_percent,
            "excludedMinutes": excluded_minutes,
            "durationMinutes": duration,
            "totalFish": total_fish,
            "totalValue": total_value,
            "source": source or "manual",
            "verificationStatus": verification_text,
            "items": items,
        }

    def create(
        self,
        payload: dict[str, Any],
        catalog_lookup: Callable[[int], dict[str, Any] | None],
    ) -> dict[str, Any]:
        session = self._normalize(payload, catalog_lookup)
        self._write(session, preserve_created=False)
        session["catches"] = session["items"]
        return session

    def update(
        self,
        session_id: str,
        payload: dict[str, Any],
        catalog_lookup: Callable[[int], dict[str, Any] | None],
    ) -> dict[str, Any]:
        existing = self.get(session_id)
        if existing is None:
            raise KeyError(session_id)
        if existing.get("legacyAggregateOnly"):
            raise SessionValidationError(
                "Preserved legacy aggregate sessions are read-only"
            )
        session = self._normalize(payload, catalog_lookup, existing_id=session_id)
        session["createdAt"] = existing["createdAt"]
        self._write(session, preserve_created=True)
        session["catches"] = session["items"]
        return session

    def _write(self, session: dict[str, Any], *, preserve_created: bool) -> None:
        with self._connection() as connection:
            if preserve_created:
                connection.execute(
                    """
                    UPDATE sessions SET
                        caught_at=?, started_at=?, ended_at=?, zone_rgb=?, zone_name=?, location_name=?, point_x=?, point_y=?, depth=?, method=?, style=?, rod=?, float_name=?,
                        equipment=?, setup_id=?, setup_name=?, keep_from=?, mastery=?, fishing_speed=?, auto_fishing_delay_seconds=?,
                        fishing_rank=?, fishing_level=?, trading_mastery=?, trading_rank=?, trading_level=?, freshness_percent=?, quotation_percent=?, distance_bonus_percent=?, bargain_bonus_percent=?,
                        resource_level=?, auto_fishing_reduction_percent=?,
                        excluded_minutes=?, duration_minutes=?, total_fish=?, total_value=?,
                        entry_source=?, verification_status=?
                    WHERE id=?
                    """,
                    (
                        session["caughtAt"],
                        session["startedAt"],
                        session["endedAt"],
                        session["zoneRgb"],
                        session["zoneName"],
                        session["locationName"],
                        session["pointX"],
                        session["pointY"],
                        session["depth"],
                        session["method"],
                        session["style"],
                        session["rod"],
                        session["float"],
                        session["equipment"],
                        session["setupId"],
                        session["setupName"],
                        session["keepFrom"],
                        session["mastery"],
                        session["fishingSpeed"],
                        session["autoFishingDelaySeconds"],
                        session["fishingRank"],
                        session["fishingLevel"],
                        session["tradingMastery"],
                        session["tradingRank"],
                        session["tradingLevel"],
                        session["freshnessPercent"],
                        session["quotationPercent"],
                        session["distanceBonusPercent"],
                        session["bargainBonusPercent"],
                        session["resourceLevel"],
                        session["autoFishingReductionPercent"],
                        session["excludedMinutes"],
                        session["durationMinutes"],
                        session["totalFish"],
                        session["totalValue"],
                        session["source"],
                        session["verificationStatus"],
                        session["id"],
                    ),
                )
                connection.execute("DELETE FROM session_items WHERE session_id=?", (session["id"],))
            else:
                connection.execute(
                    """
                    INSERT INTO sessions (
                        id, created_at, caught_at, started_at, ended_at, zone_rgb, zone_name, location_name, point_x, point_y, depth, method, style, rod,
                        float_name, equipment, setup_id, setup_name, keep_from, mastery, fishing_speed, auto_fishing_delay_seconds,
                        fishing_rank, fishing_level, trading_mastery, trading_rank, trading_level, freshness_percent, quotation_percent, distance_bonus_percent, bargain_bonus_percent,
                        resource_level, auto_fishing_reduction_percent,
                        excluded_minutes, duration_minutes, total_fish,
                        total_value, entry_source, verification_status
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        session["id"],
                        session["createdAt"],
                        session["caughtAt"],
                        session["startedAt"],
                        session["endedAt"],
                        session["zoneRgb"],
                        session["zoneName"],
                        session["locationName"],
                        session["pointX"],
                        session["pointY"],
                        session["depth"],
                        session["method"],
                        session["style"],
                        session["rod"],
                        session["float"],
                        session["equipment"],
                        session["setupId"],
                        session["setupName"],
                        session["keepFrom"],
                        session["mastery"],
                        session["fishingSpeed"],
                        session["autoFishingDelaySeconds"],
                        session["fishingRank"],
                        session["fishingLevel"],
                        session["tradingMastery"],
                        session["tradingRank"],
                        session["tradingLevel"],
                        session["freshnessPercent"],
                        session["quotationPercent"],
                        session["distanceBonusPercent"],
                        session["bargainBonusPercent"],
                        session["resourceLevel"],
                        session["autoFishingReductionPercent"],
                        session["excludedMinutes"],
                        session["durationMinutes"],
                        session["totalFish"],
                        session["totalValue"],
                        session["source"],
                        session["verificationStatus"],
                    ),
                )
            connection.executemany(
                """
                INSERT INTO session_items (session_id, item_id, name, grade, count, unit_price)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        session["id"],
                        item["itemId"],
                        item["name"],
                        item["grade"],
                        item["count"],
                        item["unitPrice"],
                    )
                    for item in session["items"]
                ],
            )

    @staticmethod
    def _row_base(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": row["id"],
            "createdAt": row["created_at"],
            "caughtAt": row["caught_at"],
            "startedAt": row["started_at"],
            "endedAt": row["ended_at"],
            "zoneRgb": row["zone_rgb"],
            "zoneName": row["zone_name"],
            "locationName": row["location_name"],
            "pointX": row["point_x"],
            "pointY": row["point_y"],
            "point": {"x": row["point_x"], "y": row["point_y"]}
            if row["point_x"] is not None and row["point_y"] is not None
            else None,
            "depth": row["depth"],
            "method": row["method"],
            "style": None if row["legacy_aggregate_only"] else row["style"],
            "rod": row["rod"],
            "float": row["float_name"],
            "equipment": row["equipment"],
            "setupId": row["setup_id"],
            "setupName": row["setup_name"],
            "profileId": row["setup_id"],
            "profileName": row["setup_name"],
            "keepFrom": row["keep_from"],
            "mastery": row["mastery"],
            "fishingRank": row["fishing_rank"],
            "fishingLevel": row["fishing_level"],
            "fishingSpeed": row["fishing_speed"],
            "autoFishingDelaySeconds": row["auto_fishing_delay_seconds"],
            "autoFishingReductionPercent": row["auto_fishing_reduction_percent"],
            "resourceLevel": row["resource_level"],
            "tradingMastery": row["trading_mastery"],
            "tradingRank": row["trading_rank"],
            "tradingLevel": row["trading_level"],
            "freshnessPercent": row["freshness_percent"],
            "quotationPercent": row["quotation_percent"],
            "distanceBonusPercent": row["distance_bonus_percent"],
            "bargainBonusPercent": row["bargain_bonus_percent"],
            "excludedMinutes": row["excluded_minutes"],
            "durationMinutes": row["duration_minutes"],
            "totalFish": row["total_fish"],
            "totalValue": row["total_value"],
            "source": row["entry_source"],
            "verificationStatus": row["verification_status"],
            "updatedAt": row["updated_at"],
            "notes": row["notes"],
            "legacyReceivedSilver": row["legacy_received_silver"],
            "legacyAggregateOnly": bool(row["legacy_aggregate_only"]),
        }

    @staticmethod
    def _items(connection: sqlite3.Connection, session_ids: list[str]) -> dict[str, list[dict[str, Any]]]:
        output: dict[str, list[dict[str, Any]]] = defaultdict(list)
        if not session_ids:
            return output
        placeholders = ",".join("?" for _ in session_ids)
        rows = connection.execute(
            f"""
            SELECT session_id, item_id, name, grade, count, unit_price
            FROM session_items WHERE session_id IN ({placeholders})
            ORDER BY name COLLATE NOCASE
            """,
            session_ids,
        ).fetchall()
        for row in rows:
            output[row["session_id"]].append(
                {
                    "itemId": row["item_id"],
                    "name": row["name"],
                    "grade": row["grade"],
                    "count": row["count"],
                    "unitPrice": row["unit_price"],
                    "price": row["unit_price"],
                    "iconUrl": f"/icon/{row['item_id']}.webp",
                }
            )
        return output

    @staticmethod
    def _sales(connection: sqlite3.Connection, session_ids: list[str]) -> dict[str, dict[str, Any]]:
        if not session_ids:
            return {}
        placeholders = ",".join("?" for _ in session_ids)
        rows = connection.execute(
            f"""
            SELECT session_id, sold_at, destination, current_tank_value,
                   market_percent, distance_bonus_percent, bargain_bonus_percent,
                   final_amount
            FROM session_sales WHERE session_id IN ({placeholders})
            """,
            session_ids,
        ).fetchall()
        return {
            row["session_id"]: {
                "soldAt": row["sold_at"],
                "destination": row["destination"],
                "currentTankValue": row["current_tank_value"],
                "marketPercent": row["market_percent"],
                "distanceBonusPercent": row["distance_bonus_percent"],
                "bargainBonusPercent": row["bargain_bonus_percent"],
                "finalAmount": row["final_amount"],
            }
            for row in rows
        }

    def get(self, session_id: str) -> dict[str, Any] | None:
        with self._connection() as connection:
            row = connection.execute("SELECT * FROM sessions WHERE id=?", (session_id,)).fetchone()
            if row is None:
                return None
            result = self._row_base(row)
            result["items"] = self._items(connection, [session_id]).get(session_id, [])
            result["catches"] = result["items"]
            result["sale"] = self._sales(connection, [session_id]).get(session_id)
            return result

    def list(self, filters: dict[str, str]) -> list[dict[str, Any]]:
        where, parameters = self._where(filters)
        # The local journal is the source of truth, so an omitted limit must return it in full.
        requested_limit = _int(filters.get("limit"), minimum=1)
        limit = min(requested_limit, 500) if requested_limit is not None else None
        offset = _int(filters.get("offset"), minimum=0, maximum=100_000) or 0
        pagination = ""
        pagination_parameters: list[int] = []
        if limit is not None:
            pagination = " LIMIT ? OFFSET ?"
            pagination_parameters = [limit, offset]
        elif offset:
            pagination = " LIMIT -1 OFFSET ?"
            pagination_parameters = [offset]
        with self._connection() as connection:
            rows = connection.execute(
                f"SELECT * FROM sessions {where} ORDER BY caught_at DESC, created_at DESC{pagination}",
                [*parameters, *pagination_parameters],
            ).fetchall()
            session_ids = [row["id"] for row in rows]
            items = self._items(connection, session_ids)
            sales = self._sales(connection, session_ids)
            result = []
            for row in rows:
                session = self._row_base(row)
                session["items"] = items.get(row["id"], [])
                session["catches"] = session["items"]
                session["sale"] = sales.get(row["id"])
                result.append(session)
            return result

    @staticmethod
    def _normalize_sale(payload: dict[str, Any], *, default_tank_value: int) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise SessionValidationError("A recorded sale must be a JSON object")
        _assert_structured_only(payload)
        allowed = {
            "soldAt",
            "destination",
            "currentTankValue",
            "marketPercent",
            "distanceBonusPercent",
            "bargainBonusPercent",
            "finalAmount",
        }
        if set(payload) - allowed:
            raise SessionValidationError("A recorded sale contains an unknown field")
        destination = _text(payload.get("destination"), maximum=80)
        if destination is None:
            raise SessionValidationError("A trade manager or selling destination is required")
        current_tank_value = _int(
            payload.get("currentTankValue", default_tank_value),
            minimum=0,
            maximum=100_000_000_000_000,
        )
        final_amount = _int(
            payload.get("finalAmount"),
            minimum=1,
            maximum=100_000_000_000_000,
        )
        if final_amount is None:
            raise SessionValidationError("The silver actually received is required")
        return {
            "soldAt": _iso_time(payload.get("soldAt")),
            "destination": destination,
            "currentTankValue": current_tank_value or 0,
            "marketPercent": _number(
                payload.get("marketPercent", 100), minimum=30.0, maximum=130.0
            ),
            "distanceBonusPercent": _number(
                payload.get("distanceBonusPercent", 0), minimum=0.0, maximum=150.0
            ),
            "bargainBonusPercent": _number(
                payload.get("bargainBonusPercent", 0), minimum=0.0, maximum=100.0
            ),
            "finalAmount": final_amount,
        }

    def record_sale(self, session_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        with self._connection() as connection:
            session = connection.execute(
                "SELECT total_value, legacy_aggregate_only FROM sessions WHERE id=?",
                (session_id,),
            ).fetchone()
            if session is None:
                raise KeyError(session_id)
            if session["legacy_aggregate_only"]:
                raise SessionValidationError(
                    "Preserved legacy aggregate sessions cannot record sales"
                )
            sale = self._normalize_sale(payload, default_tank_value=session["total_value"])
            connection.execute(
                """
                INSERT INTO session_sales (
                    session_id, sold_at, destination, current_tank_value,
                    market_percent, distance_bonus_percent, bargain_bonus_percent,
                    final_amount
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                    sold_at=excluded.sold_at,
                    destination=excluded.destination,
                    current_tank_value=excluded.current_tank_value,
                    market_percent=excluded.market_percent,
                    distance_bonus_percent=excluded.distance_bonus_percent,
                    bargain_bonus_percent=excluded.bargain_bonus_percent,
                    final_amount=excluded.final_amount
                """,
                (
                    session_id,
                    sale["soldAt"],
                    sale["destination"],
                    sale["currentTankValue"],
                    sale["marketPercent"],
                    sale["distanceBonusPercent"],
                    sale["bargainBonusPercent"],
                    sale["finalAmount"],
                ),
            )
        return sale

    def delete_sale(self, session_id: str) -> bool:
        with self._connection() as connection:
            if connection.execute(
                "SELECT 1 FROM sessions WHERE id=?", (session_id,)
            ).fetchone() is None:
                raise KeyError(session_id)
            cursor = connection.execute(
                "DELETE FROM session_sales WHERE session_id=?", (session_id,)
            )
            return cursor.rowcount > 0

    def delete(self, session_id: str) -> bool:
        with self._connection() as connection:
            cursor = connection.execute("DELETE FROM sessions WHERE id=?", (session_id,))
            return cursor.rowcount > 0

    @staticmethod
    def _where(
        filters: dict[str, str], *, exclude_legacy_aggregates: bool = False
    ) -> tuple[str, list[Any]]:
        clauses: list[str] = (
            ["legacy_aggregate_only=0"] if exclude_legacy_aggregates else []
        )
        values: list[Any] = []
        for parameter, column, allowed in (
            ("method", "method", {"rod", "harpoon"}),
            ("style", "style", {"afk", "active"}),
        ):
            value = filters.get(parameter)
            if value in allowed:
                clauses.append(f"{column}=?")
                values.append(value)
                if parameter == "style" and not exclude_legacy_aggregates:
                    clauses.append("legacy_aggregate_only=0")
        if filters.get("equipment") and filters["equipment"] != "all":
            clauses.append("equipment=?")
            values.append(filters["equipment"])
        if filters.get("rgb"):
            clauses.append("zone_rgb=?")
            values.append(filters["rgb"])
        if filters.get("depth") and filters["depth"] != "all":
            clauses.append("depth=?")
            values.append(filters["depth"])
        mastery = filters.get("mastery")
        if mastery and mastery != "all":
            if "-" in mastery:
                lower, upper = mastery.split("-", 1)
                minimum = _int(lower, minimum=0, maximum=5000)
                maximum = _int(upper, minimum=0, maximum=5000)
                if minimum is not None and maximum is not None:
                    clauses.append("mastery BETWEEN ? AND ?")
                    values.extend([minimum, maximum])
            elif mastery.endswith("+"):
                minimum = _int(mastery[:-1], minimum=0, maximum=5000)
                if minimum is not None:
                    clauses.append("mastery>=?")
                    values.append(minimum)
            else:
                exact = _int(mastery, minimum=0, maximum=5000)
                if exact is not None:
                    clauses.append("mastery=?")
                    values.append(exact)
        minimum = _int(filters.get("minMastery"), minimum=0, maximum=5000)
        maximum = _int(filters.get("maxMastery"), minimum=0, maximum=5000)
        if minimum is not None:
            clauses.append("mastery>=?")
            values.append(minimum)
        if maximum is not None:
            clauses.append("mastery<=?")
            values.append(maximum)
        return ("WHERE " + " AND ".join(clauses) if clauses else "", values)

    def stats(self, filters: dict[str, str]) -> dict[str, Any]:
        # Aggregate-only v0.1.7 journal rows preserve totals whose species and
        # tank value are unknowable. They remain visible through /api/sessions,
        # but must never be reinterpreted as zero-value modern stats.
        where, parameters = self._where(
            filters, exclude_legacy_aggregates=True
        )
        with self._connection() as connection:
            sessions = connection.execute(
                f"SELECT * FROM sessions {where} ORDER BY caught_at DESC", parameters
            ).fetchall()
            session_ids = [row["id"] for row in sessions]
            items_by_session = self._items(connection, session_ids)

        spots: dict[tuple[str | None, str], dict[str, Any]] = {}
        total_duration = 0
        duration_sessions = 0
        timed_fish = 0
        timed_value = 0
        total_value = 0
        total_fish = 0
        for row in sessions:
            key = (row["zone_rgb"], row["zone_name"])
            spot = spots.setdefault(
                key,
                {
                    "rgb": row["zone_rgb"],
                    "name": row["zone_name"],
                    "sessions": 0,
                    "totalFish": 0,
                    "totalValue": 0,
                    "durationMinutes": 0,
                    "durationSessions": 0,
                    "timedFish": 0,
                    "timedValue": 0,
                    "items": {},
                },
            )
            spot["sessions"] += 1
            spot["totalFish"] += row["total_fish"]
            spot["totalValue"] += row["total_value"]
            total_fish += row["total_fish"]
            total_value += row["total_value"]
            # Rates use only catches belonging to sessions that supplied a positive duration.
            if row["duration_minutes"] is not None and row["duration_minutes"] > 0:
                spot["durationMinutes"] += row["duration_minutes"]
                spot["durationSessions"] += 1
                spot["timedFish"] += row["total_fish"]
                spot["timedValue"] += row["total_value"]
                total_duration += row["duration_minutes"]
                duration_sessions += 1
                timed_fish += row["total_fish"]
                timed_value += row["total_value"]
            for item in items_by_session.get(row["id"], []):
                aggregate = spot["items"].setdefault(
                    item["itemId"],
                    {
                        "itemId": item["itemId"],
                        "name": item["name"],
                        "grade": item["grade"],
                        "count": 0,
                        "unitPrice": item["unitPrice"],
                        "iconUrl": item["iconUrl"],
                    },
                )
                aggregate["count"] += item["count"]

        output_spots: list[dict[str, Any]] = []
        for spot in spots.values():
            denominator = spot["totalFish"]
            normalized_items = []
            for item in spot["items"].values():
                item = dict(item)
                item["percentage"] = round(item["count"] / denominator * 100, 3) if denominator else 0
                item["averagePer100"] = round(item["count"] / denominator * 100, 2) if denominator else 0
                normalized_items.append(item)
            normalized_items.sort(key=lambda item: (-item["count"], item["name"].casefold()))
            duration_hours = spot["durationMinutes"] / 60 if spot["durationMinutes"] else 0
            output_spots.append(
                {
                    "rgb": spot["rgb"],
                    "name": spot["name"],
                    "sessions": spot["sessions"],
                    "totalFish": denominator,
                    "totalValue": spot["totalValue"],
                    "averageValuePer100": round(spot["totalValue"] / denominator * 100)
                    if denominator
                    else 0,
                    "durationMinutes": spot["durationMinutes"] if spot["durationSessions"] else None,
                    "durationSessions": spot["durationSessions"],
                    "fishPerHour": round(spot["timedFish"] / duration_hours, 2)
                    if duration_hours
                    else None,
                    "valuePerHour": round(spot["timedValue"] / duration_hours)
                    if duration_hours
                    else None,
                    "items": normalized_items,
                }
            )
        output_spots.sort(key=lambda spot: (-spot["totalFish"], spot["name"].casefold()))
        duration_hours = total_duration / 60 if total_duration else 0
        return {
            "scope": "personal",
            "filters": {
                key: value
                for key, value in filters.items()
                if key
                in {
                    "method",
                    "style",
                    "equipment",
                    "mastery",
                    "minMastery",
                    "maxMastery",
                    "depth",
                }
                and value
            },
            "totals": {
                "sessions": len(sessions),
                "fish": total_fish,
                "value": total_value,
                "durationMinutes": total_duration if duration_sessions else None,
                "durationSessions": duration_sessions,
                "fishPerHour": round(timed_fish / duration_hours, 2) if duration_hours else None,
                "valuePerHour": round(timed_value / duration_hours) if duration_hours else None,
            },
            "spots": output_spots,
        }
