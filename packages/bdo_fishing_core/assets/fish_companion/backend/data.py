"""Real map, fishing-table, tile, and icon data for the local companion.

FishyStuff remains the source of the curated map/table data served here. The
repository prefers a fresh public API response and uses only the caller's
explicit, disposable cache for offline starts. Unknown source facts remain
``null``; this module never fills a data gap with an illustrative value.
"""

from __future__ import annotations

import io
import hashlib
import json
import math
import os
import re
import threading
import time
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlsplit

from .mask import (
    ZoneMask,
    ZoneMaskError,
    extract_zone_lookup,
    rgb_key_to_u32,
    rgb_u32_to_key,
)
from .fish_supplement import apply_catalog_supplement


API_ROOT = "https://fishystuff.fish"
CDN_ROOT = "https://cdn.fishystuff.fish"
SITE_ROOT = "https://fishystuff.fish"
ZONE_MASK_ENDPOINT = f"{API_ROOT}/api/v1/map/zone_mask/lineage/artifact"
USER_AGENT = "Black-Spirit-Life/0.1.8 (Fish Companion; FishyStuff credited)"
EVIDENCE_CACHE_VERSION = 4
SOURCE_REFRESH_SECONDS = 6 * 60 * 60
DETAIL_CACHE_VERSION = 1
# The normalized bootstrap graph is expensive because it derives exact bounds
# and representative points from the full-resolution zone mask.  Keep this
# cache contract independent from source/API cache versions so either can be
# invalidated without weakening the other.
DERIVED_INDEX_CACHE_SCHEMA_VERSION = 1
DERIVED_INDEX_CACHE_NAME = "derived-index.v1.json"
DERIVED_INDEX_ALGORITHM_CONTRACT = (
    "fish-companion-derived-index-v1:exact-zone-bounds-centers:"
    "catalog-supplement:location-node-resolution"
)
# The Flutter host uses this receipt to distinguish a coherent live refresh
# from random damage in the writable runtime copy.  It is published only after
# the derived index and every critical source below describe the same snapshot.
RUNTIME_SNAPSHOT_RECEIPT_SCHEMA_VERSION = 1
RUNTIME_SNAPSHOT_RECEIPT_NAME = "runtime-snapshot-integrity.v1.json"
RUNTIME_SNAPSHOT_CRITICAL_PATHS = (
    "data/cache/fish.json",
    "data/cache/zones.json",
    "data/cache/meta.json",
    "data/cache/zone_mask.v8.bin",
    "data/cache/derived-index.v1.json",
)
# Display rendering may change without changing FishyStuff's source mask.
# Keep this separate from the source revision used for exact clicks/evidence.
FISHING_REGION_DISPLAY_VERSION = 2
FISHING_REGION_DISPLAY_TRANSPARENT_RGB = frozenset({0x1E1E1E, 0xF0F0F0})
RANKING_CLUSTER_DISTANCE_PX = 4
RANKING_UNCERTAINTY_GAME_UNITS = 500
# FishyStuff's glossary describes the ranking position as a 500 game-unit
# ring.  Its minimap projection is approximately 300 game units per pixel.
RANKING_UNCERTAINTY_MAP_PX = RANKING_UNCERTAINTY_GAME_UNITS / 301.1764831542969
# A map click close to a named FishyStuff node should use that more specific
# name (for example Velia Beach).  Outside this small radius, the exact
# semantic territory below the cursor is more honest than guessing a distant
# node.
LOCATION_NODE_SNAP_RADIUS_PX = 32
# Some equipment records intentionally reuse another in-game icon.  BDO Codex
# identifies Triple-Float Fishing Rod (16153) with the original 16152 artwork.
ICON_ITEM_ALIASES = {16153: 16152}
# The earnings model is deliberately separate from ``estimatedValue``.  It is
# an experimental projection for one clearly labelled FishyStuff calculator
# profile, not a universal or official drop-rate claim.
EXPERIMENTAL_MONEY_CATCHES = 100
EXPERIMENTAL_MONEY_PERCENTILE = 25
EXPERIMENTAL_MONEY_VALUE_BIN_SILVER = 2_000
EXPERIMENTAL_MONEY_APPROXIMATION_ERROR_SILVER = (
    EXPERIMENTAL_MONEY_CATCHES * EXPERIMENTAL_MONEY_VALUE_BIN_SILVER // 2
)
EXPERIMENTAL_MONEY_RATE_TOLERANCE_PERCENT = 0.5


class DataUnavailable(RuntimeError):
    """Raised when a real source asset is not available online or in cache."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _fishing_region_display_revision(mask_revision: str) -> str:
    return f"{mask_revision}-display{FISHING_REGION_DISPLAY_VERSION}"


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _integer(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _fft_convolve_truncated(left: Any, right: Any, cap_index: int) -> Any:
    """Return the nonnegative, alias-free convolution through ``cap_index``."""

    import numpy as np

    full_length = len(left) + len(right) - 1
    fft_length = 1 << max(0, (full_length - 1).bit_length())
    transformed = np.fft.rfft(left, fft_length) * np.fft.rfft(right, fft_length)
    result = np.fft.irfft(transformed, fft_length)[
        : min(full_length, cap_index + 1)
    ]
    # Exact coefficients are nonnegative.  Reject anything larger than known
    # FFT roundoff, then clamp only negative machine noise; retain every
    # positive coefficient, however small.
    if float(result.min(initial=0.0)) < -1e-10:
        raise ArithmeticError("FFT convolution produced material negative mass")
    result[result < 0.0] = 0.0
    return result


@lru_cache(maxsize=512)
def _binned_total_value_percentile_index(
    probability_by_index: tuple[tuple[int, float], ...],
    catches: int,
    percentile: int,
    value_bin_silver: int,
) -> int:
    """Convolve a rounded nonnegative value distribution deterministically."""

    import numpy as np

    if value_bin_silver <= 0:
        raise ValueError("Value bin must be positive")
    target_probability = percentile / 100.0
    expected_index = sum(
        index * probability for index, probability in probability_by_index
    )
    # For the nonnegative rounded total S, Markov gives
    # P(S > E[S] / (1 - target)) <= 1 - target.  The extra bin makes the
    # inequality strict despite integer rounding, so the requested quantile
    # is guaranteed to be at or below this cap.
    cap_index = (
        math.ceil(catches * expected_index / (1.0 - target_probability)) + 1
    )
    maximum_index = max(index for index, _ in probability_by_index)
    base = np.zeros(min(cap_index, maximum_index) + 1, dtype=np.float64)
    for index, probability in probability_by_index:
        if index <= cap_index:
            base[index] += probability

    distribution = np.asarray([1.0], dtype=np.float64)
    exponent = catches
    while exponent:
        if exponent & 1:
            distribution = _fft_convolve_truncated(
                distribution, base, cap_index
            )
        exponent >>= 1
        if exponent:
            base = _fft_convolve_truncated(base, base, cap_index)

    cumulative = np.cumsum(distribution)
    if cumulative[-1] < target_probability - 1e-9:
        raise ArithmeticError("Rounded percentile cap lost required probability mass")
    return int(np.searchsorted(cumulative, target_probability, side="left"))


def _deterministic_total_value_percentile(
    outcomes: Iterable[tuple[float, float]],
    *,
    catches: int = EXPERIMENTAL_MONEY_CATCHES,
    percentile: int = EXPERIMENTAL_MONEY_PERCENTILE,
    value_bin_silver: int = EXPERIMENTAL_MONEY_VALUE_BIN_SILVER,
) -> int:
    """Return a bounded deterministic approximation of a total-value quantile.

    Each per-catch value is rounded to the nearest ``value_bin_silver`` after
    subtracting the smallest outcome.  Binary polynomial exponentiation then
    calculates the rounded 100-catch distribution rather than sampling it.
    Coupling every exact session with its rounded counterpart proves an
    absolute quantile error no greater than
    ``catches * value_bin_silver / 2`` (100,000 silver for the app model).
    """

    buckets: dict[float, float] = defaultdict(float)
    for raw_probability, raw_value in outcomes:
        probability = float(raw_probability)
        value = float(raw_value)
        if not math.isfinite(probability) or not math.isfinite(value):
            raise ValueError("Outcome probabilities and values must be finite")
        if probability > 0.0:
            if value < 0.0:
                raise ValueError("Outcome values must be nonnegative")
            buckets[value] += probability
    if not buckets:
        raise ValueError("At least one positive-probability outcome is required")
    if catches <= 0 or not 0 < percentile < 100 or value_bin_silver <= 0:
        raise ValueError("Invalid deterministic percentile settings")

    probability_total = sum(buckets.values())
    if not math.isfinite(probability_total) or probability_total <= 0.0:
        raise ValueError("Outcome probability total must be positive and finite")
    baseline = min(buckets)
    probability_by_index: dict[int, float] = defaultdict(float)
    for value, probability in sorted(buckets.items()):
        # Values are nonnegative, so floor(x + 1/2) is an unambiguous
        # round-to-nearest rule with a maximum half-bin error.
        index = math.floor((value - baseline) / value_bin_silver + 0.5)
        probability_by_index[index] += probability / probability_total
    ordered = tuple(sorted(probability_by_index.items()))
    # Remove the last few ulps of source percentage drift exactly once, before
    # convolution.  Never renormalize the deliberately truncated distribution.
    ordered_list = list(ordered)
    last_index, last_probability = ordered_list[-1]
    ordered_list[-1] = (
        last_index,
        last_probability + 1.0 - sum(probability for _, probability in ordered_list),
    )
    quantile_index = _binned_total_value_percentile_index(
        tuple(ordered_list), catches, percentile, value_bin_silver
    )
    return int(round(catches * baseline + quantile_index * value_bin_silver))


def _atomic_write(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(
        f"{path.name}.{os.getpid()}.{threading.get_ident()}.part"
    )
    try:
        temporary.write_bytes(payload)
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except OSError:
            pass


def _format_percent(value: float | None) -> str:
    if value is None:
        return "Unknown"
    return f"{value:.6f}".rstrip("0").rstrip(".") + "%"


def _percent_number(value: Any) -> float | None:
    """Parse a source percentage without treating Unknown as zero."""

    if isinstance(value, str):
        text = value.strip()
        if not text or text.casefold() in {"unknown", "?", "n/a", "none"}:
            return None
        if text.endswith("%"):
            text = text[:-1].strip()
        return _number(text)
    return _number(value)


def _default_pool_methods(label: str) -> set[str]:
    """Use FishyStuff's stable pool labels only when method metadata is absent."""

    normalized = label.strip().casefold().replace("_", "-")
    if normalized == "harpoon":
        return {"harpoon"}
    if normalized in {
        "prize",
        "rare",
        "high-quality",
        "highquality",
        "general",
        "trash",
    }:
        return {"rod"}
    return set()


def _grade_tone(grade: str) -> str:
    return {
        "Prize": "red",
        "Rare": "yellow",
        "HighQuality": "blue",
        "High-Quality": "blue",
        "General": "green",
        "Trash": "white",
    }.get(grade, "white")


class FishDataRepository:
    """Thread-safe source repository shared by all local HTTP requests."""

    DATA_ENDPOINTS = {
        "zones.json": f"{API_ROOT}/api/v1/zones",
        "fish.json": f"{API_ROOT}/api/v1/fish?lang=en&",
        "zone-loot-facts.json": f"{API_ROOT}/api/v1/zone_loot_facts?lang=en&",
        "meta.json": f"{API_ROOT}/api/v1/meta",
        "tileset.json": f"{CDN_ROOT}/images/tiles/minimap_visual/v5/tileset.json",
        # FishyStuff's coloured Regions layer and its named Nodes layer are
        # separate semantic-map datasets.  They must not be conflated with the
        # fishing-table zone mask.
        "regions.meta.json": f"{CDN_ROOT}/territory/v8/regions.meta.json",
        "region-groups.meta.json": f"{CDN_ROOT}/territory/v8/region_groups.meta.json",
        "region-nodes.geojson": f"{CDN_ROOT}/territory/v8/region_nodes.geojson",
    }
    SEMANTIC_REGION_ASSETS = {
        ("regions", "field"): ("regions.bin", f"{CDN_ROOT}/territory/v8/regions.bin"),
        ("regions", "meta"): (
            "regions.meta.json",
            f"{CDN_ROOT}/territory/v8/regions.meta.json",
        ),
        ("region-groups", "field"): (
            "region-groups.bin",
            f"{CDN_ROOT}/territory/v8/region_groups.bin",
        ),
        ("region-groups", "meta"): (
            "region-groups.meta.json",
            f"{CDN_ROOT}/territory/v8/region_groups.meta.json",
        ),
    }

    def __init__(self, app_root: Path, cache_root: Path):
        self.app_root = app_root.resolve()
        self.snapshot_root = self.app_root / "data" / "cache"
        self.cache_root = cache_root.resolve()
        self.cache_root.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._refresh_lock = threading.Lock()
        self._background_refresh_lock = threading.Lock()
        self._background_refresh_started = False
        self._state: dict[str, Any] = {
            "status": "initializing",
            "revision": None,
            "fetchedAt": None,
            "message": None,
            "evidenceStatus": "loading",
            "evidenceRevision": None,
            "evidencePointCount": 0,
            "evidenceClusterCount": 0,
            "refreshInProgress": False,
            "artifacts": {},
            "tableRefresh": {"status": "not-checked", "total": 0, "checked": 0},
        }
        self._json: dict[str, dict[str, Any]] = {}
        self.mask: ZoneMask | None = None
        self._mask_revision = "legacy"
        self.tileset: dict[str, Any] = {}
        self.fish_by_id: dict[int, dict[str, Any]] = {}
        self.icon_paths_by_item: dict[int, str] = {}
        self.zones_by_key: dict[str, dict[str, Any]] = {}
        self._zones: list[dict[str, Any]] = []
        self._fish: list[dict[str, Any]] = []
        self._regions: list[dict[str, Any]] = []
        self._location_nodes: list[dict[str, Any]] = []
        self._location_nodes_by_name: dict[str, list[dict[str, Any]]] = {}
        self._location_nodes_by_label: dict[str, list[dict[str, Any]]] = {}
        self._semantic_region_masks: dict[str, ZoneMask] = {}
        self._semantic_region_names: dict[str, dict[int, str]] = {}
        self._evidence_clusters_by_rgb: dict[int, list[dict[str, Any]]] = {}
        self._accuracy_audit: dict[str, Any] = {}
        self._mask_fingerprint = "missing"
        self._load_initial()

    # ------------------------------------------------------------------
    # Initial data and refresh

    @property
    def recognizer_icon_root(self) -> Path:
        return self.app_root / "recognizer" / "reference-icons"

    def _fallback_candidates(self, name: str) -> list[Path]:
        return [self.cache_root / name, self.snapshot_root / name]

    def _snapshot_path(self, cache_path: Path) -> Path:
        """Map one writable-cache path to its immutable packaged fallback."""

        return self.snapshot_root / cache_path.relative_to(self.cache_root)

    def _cache_paths(self, cache_path: Path) -> list[Path]:
        return [cache_path, self._snapshot_path(cache_path)]

    def _read_cache_bytes(self, cache_path: Path) -> bytes:
        last_error: OSError | None = None
        for path in self._cache_paths(cache_path):
            try:
                return path.read_bytes()
            except OSError as exc:
                last_error = exc
        assert last_error is not None
        raise last_error

    @staticmethod
    def _read_json(paths: Iterable[Path]) -> tuple[dict[str, Any] | None, Path | None]:
        for path in paths:
            try:
                value = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(value, dict):
                return value, path
        return None, None

    @staticmethod
    def _canonical_json_bytes(value: Any) -> bytes:
        return json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")

    @staticmethod
    def _runtime_snapshot_digest(records: list[dict[str, Any]]) -> str:
        canonical = "".join(
            f'{record["path"]}|{record["byteCount"]}|{record["sha256"]}\n'
            for record in records
        ).encode("utf-8")
        return hashlib.sha256(canonical).hexdigest()

    def _critical_json_files_match_memory(self) -> bool:
        for name in ("fish.json", "zones.json", "meta.json"):
            expected = self._json.get(name)
            if expected is None:
                return False
            try:
                disk_value = json.loads(
                    self._read_cache_bytes(self.cache_root / name).decode("utf-8")
                )
            except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                return False
            if self._canonical_json_bytes(disk_value) != self._canonical_json_bytes(
                expected
            ):
                return False
        try:
            mask_payload = self._read_cache_bytes(
                self.cache_root / "zone_mask.v8.bin"
            )
        except OSError:
            return False
        return hashlib.sha256(mask_payload).hexdigest() == self._mask_fingerprint

    def _write_runtime_snapshot_receipt(
        self, *, expected_source_fingerprint: str
    ) -> bool:
        """Atomically publish hashes for one coherent writable snapshot."""

        try:
            if self._derived_index_source_fingerprint() != expected_source_fingerprint:
                return False
            if not self._critical_json_files_match_memory():
                return False
            derived_path = self.cache_root / DERIVED_INDEX_CACHE_NAME
            derived = json.loads(derived_path.read_text(encoding="utf-8"))
            if (
                not isinstance(derived, dict)
                or derived.get("sourceFingerprint") != expected_source_fingerprint
            ):
                return False
            records: list[dict[str, Any]] = []
            for relative in RUNTIME_SNAPSHOT_CRITICAL_PATHS:
                relative_cache = relative.removeprefix("data/cache/")
                payload = self._read_cache_bytes(
                    self.cache_root / relative_cache
                )
                records.append(
                    {
                        "path": relative,
                        "byteCount": len(payload),
                        "sha256": hashlib.sha256(payload).hexdigest(),
                    }
                )
            records.sort(key=lambda record: str(record["path"]))
            if self._derived_index_source_fingerprint() != expected_source_fingerprint:
                return False
            if not self._critical_json_files_match_memory():
                return False
            document = {
                "schemaVersion": RUNTIME_SNAPSHOT_RECEIPT_SCHEMA_VERSION,
                "snapshotSha256": self._runtime_snapshot_digest(records),
                "files": records,
            }
            _atomic_write(
                self.cache_root / RUNTIME_SNAPSHOT_RECEIPT_NAME,
                self._canonical_json_bytes(document),
            )
            return True
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
            # The receipt is repair metadata.  Failure leaves the old receipt
            # intact, so the host restores the accepted bootstrap snapshot on
            # the next launch instead of trusting an uncertain partial update.
            return False

    @staticmethod
    def _update_file_fingerprint(
        digest: Any, label: str, path: Path
    ) -> None:
        try:
            payload = path.read_bytes()
        except OSError:
            digest.update(f"{label}\0missing\n".encode("utf-8"))
            return
        digest.update(f"{label}\0{len(payload)}\0".encode("utf-8"))
        digest.update(hashlib.sha256(payload).digest())
        digest.update(b"\n")

    def _derived_index_algorithm_fingerprint(self) -> str:
        """Fingerprint the exact normalization contract and its source files."""

        digest = hashlib.sha256(DERIVED_INDEX_ALGORITHM_CONTRACT.encode("utf-8"))
        for name in ("data.py", "fish_supplement.py", "mask.py"):
            self._update_file_fingerprint(
                digest,
                f"backend/{name}",
                self.app_root / "backend" / name,
            )
        return digest.hexdigest()

    def _derived_index_source_fingerprint(self) -> str:
        """Fingerprint every source value that can alter normalized output."""

        digest = hashlib.sha256()
        for name in sorted(self._json):
            payload = self._canonical_json_bytes(self._json[name])
            digest.update(f"json/{name}\0{len(payload)}\0".encode("utf-8"))
            digest.update(hashlib.sha256(payload).digest())
            digest.update(b"\n")
        digest.update(f"zone-mask\0{self._mask_fingerprint}\n".encode("utf-8"))

        evidence_path = self.cache_root / "zone-evidence-points.json"
        self._update_file_fingerprint(
            digest,
            "cache/zone-evidence-points.json",
            evidence_path,
        )
        detail_by_name = {
            path.name.casefold(): path
            for path in (self.snapshot_root / "zone-details").glob("*.json")
        }
        detail_by_name.update(
            {
                path.name.casefold(): path
                for path in (self.cache_root / "zone-details").glob("*.json")
            }
        )
        detail_paths = [detail_by_name[key] for key in sorted(detail_by_name)]
        for path in detail_paths:
            label = f"data/cache/zone-details/{path.name}"
            self._update_file_fingerprint(digest, label, path)
        return digest.hexdigest()

    @staticmethod
    def _validate_derived_index_payload(payload: Any) -> bool:
        if not isinstance(payload, dict):
            return False
        expected_types = {
            "fishById": dict,
            "iconPathsByItem": dict,
            "fish": list,
            "zones": list,
            "accuracyAudit": dict,
            "regions": list,
            "locationNodes": list,
        }
        if any(not isinstance(payload.get(key), kind) for key, kind in expected_types.items()):
            return False
        counts = payload.get("counts")
        if not isinstance(counts, dict):
            return False
        counted = {
            "fishById": len(payload["fishById"]),
            "iconPathsByItem": len(payload["iconPathsByItem"]),
            "fish": len(payload["fish"]),
            "zones": len(payload["zones"]),
            "regions": len(payload["regions"]),
            "locationNodes": len(payload["locationNodes"]),
        }
        if counts != counted:
            return False
        if not payload["fish"] or not payload["zones"]:
            return False
        return all(
            isinstance(item, dict)
            for key in ("fish", "zones", "regions", "locationNodes")
            for item in payload[key]
        )

    def _derived_index_payload(self) -> dict[str, Any]:
        fish_by_id = {
            str(item_id): record
            for item_id, record in sorted(self.fish_by_id.items())
        }
        icon_paths = {
            str(item_id): path
            for item_id, path in sorted(self.icon_paths_by_item.items())
        }
        payload = {
            "fishById": fish_by_id,
            "iconPathsByItem": icon_paths,
            "fish": self._fish,
            "zones": self._zones,
            "accuracyAudit": self._accuracy_audit,
            "regions": self._regions,
            "locationNodes": self._location_nodes,
        }
        payload["counts"] = {
            "fishById": len(fish_by_id),
            "iconPathsByItem": len(icon_paths),
            "fish": len(self._fish),
            "zones": len(self._zones),
            "regions": len(self._regions),
            "locationNodes": len(self._location_nodes),
        }
        return payload

    def _restore_derived_index_payload(self, payload: dict[str, Any]) -> None:
        self.fish_by_id = {
            int(item_id): dict(record)
            for item_id, record in payload["fishById"].items()
        }
        self.icon_paths_by_item = {
            int(item_id): str(path)
            for item_id, path in payload["iconPathsByItem"].items()
        }
        self._fish = list(payload["fish"])
        self._zones = list(payload["zones"])
        self._rederive_cached_detail_statuses()
        self._accuracy_audit = dict(payload["accuracyAudit"])
        self._regions = list(payload["regions"])
        self._location_nodes = list(payload["locationNodes"])
        self.zones_by_key = {
            str(zone["rgbKey"]): zone
            for zone in self._zones
            if isinstance(zone.get("rgbKey"), str)
        }
        self.tileset = self._json.get("tileset.json", {})
        self._load_semantic_region_indexes()
        self._rebuild_location_node_lookups()
        self._set_normalized_revision()

    def _load_derived_index_cache(self) -> bool:
        try:
            document, _ = self._read_json(
                self._cache_paths(self.cache_root / DERIVED_INDEX_CACHE_NAME)
            )
            if not isinstance(document, dict):
                return False
            if document.get("schemaVersion") != DERIVED_INDEX_CACHE_SCHEMA_VERSION:
                return False
            if document.get("algorithmFingerprint") != self._derived_index_algorithm_fingerprint():
                return False
            if document.get("sourceFingerprint") != self._derived_index_source_fingerprint():
                return False
            payload = document.get("payload")
            if not self._validate_derived_index_payload(payload):
                return False
            payload_bytes = self._canonical_json_bytes(payload)
            if document.get("payloadSha256") != hashlib.sha256(payload_bytes).hexdigest():
                return False
            self._restore_derived_index_payload(payload)
            return True
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
            return False

    def _write_derived_index_cache(
        self, *, expected_source_fingerprint: str | None = None
    ) -> bool:
        try:
            source_fingerprint = self._derived_index_source_fingerprint()
            if (
                expected_source_fingerprint is not None
                and source_fingerprint != expected_source_fingerprint
            ):
                return False
            payload = self._derived_index_payload()
            if not self._validate_derived_index_payload(payload):
                return False
            payload_bytes = self._canonical_json_bytes(payload)
            document = {
                "schemaVersion": DERIVED_INDEX_CACHE_SCHEMA_VERSION,
                "algorithmFingerprint": self._derived_index_algorithm_fingerprint(),
                "sourceFingerprint": source_fingerprint,
                "payloadSha256": hashlib.sha256(payload_bytes).hexdigest(),
                "payload": payload,
            }
            encoded = self._canonical_json_bytes(document)
            # Validate the exact bytes which will replace the last good cache.
            decoded = json.loads(encoded.decode("utf-8"))
            if not isinstance(decoded, dict) or decoded.get("payloadSha256") != document["payloadSha256"]:
                return False
            if self._derived_index_source_fingerprint() != source_fingerprint:
                return False
            _atomic_write(self.cache_root / DERIVED_INDEX_CACHE_NAME, encoded)
            return True
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
            # A disposable acceleration cache must never prevent exact startup.
            return False

    def _set_normalized_revision(self) -> None:
        fish_document = self._json.get("fish.json", {})
        zone_document = self._json.get("zones.json", {})
        facts_document = self._json.get("zone-loot-facts.json", {})
        self._state["revision"] = (
            self._json.get("meta.json", {}).get("release_identity")
            or fish_document.get("revision")
            or zone_document.get("revision")
            or facts_document.get("revision")
        )

    def _rebuild_location_node_lookups(self) -> None:
        by_name: dict[str, list[dict[str, Any]]] = defaultdict(list)
        by_label: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for node in self._location_nodes:
            by_name[str(node["name"]).casefold()].append(node)
            by_label[str(node["label"]).casefold()].append(node)
        self._location_nodes_by_name = dict(by_name)
        self._location_nodes_by_label = dict(by_label)

    def _load_initial(self) -> None:
        origins: list[Path] = []
        for name in self.DATA_ENDPOINTS:
            value, origin = self._read_json(self._fallback_candidates(name))
            if value is not None:
                self._json[name] = value
                if origin is not None:
                    origins.append(origin)
                    self._state["artifacts"][name] = {
                        "status": "cached",
                        "revision": value.get("revision") or value.get("release_identity"),
                        "fetchedAt": datetime.fromtimestamp(origin.stat().st_mtime, timezone.utc).isoformat(),
                    }

        mask_paths = [
            self.cache_root / "zone_mask.v8.bin",
            self.snapshot_root / "zone_mask.v8.bin",
        ]
        for path in mask_paths:
            if not path.is_file():
                continue
            try:
                self.mask = ZoneMask(path)
                self._mask_fingerprint = hashlib.sha256(path.read_bytes()).hexdigest()
                self._mask_revision = self._mask_fingerprint[:16]
                self._state["artifacts"]["zone_mask.v8.bin"] = {
                    "status": "cached", "revision": self._mask_revision,
                    "fetchedAt": datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat(),
                }
                break
            except (OSError, ZoneMaskError):
                continue

        self._load_evidence_points_cache()

        # A clean public install has no bundled reference snapshot. Fetch the
        # minimum synchronous bootstrap into the explicit cache in that case.
        if "zones.json" not in self._json or "fish.json" not in self._json:
            self.refresh(raise_on_empty=True)
        else:
            newest = max((path.stat().st_mtime for path in origins), default=time.time())
            self._state.update(
                status=(
                    "cached"
                    if any(
                        self.cache_root in p.parents
                        or self.snapshot_root in p.parents
                        for p in origins
                    )
                    else "local-fallback"
                ),
                fetchedAt=datetime.fromtimestamp(newest, timezone.utc)
                .isoformat(timespec="seconds")
                .replace("+00:00", "Z"),
            )
            if not self._load_derived_index_cache():
                self._rebuild_indexes()

        if self.mask is None:
            try:
                mask_payload = extract_zone_lookup(
                    self._fetch_bytes(ZONE_MASK_ENDPOINT, timeout=25)
                )
                mask_path = self.cache_root / "zone_mask.v8.bin"
                _atomic_write(mask_path, mask_payload)
                self.mask = ZoneMask(mask_path)
                self._mask_fingerprint = hashlib.sha256(mask_payload).hexdigest()
                self._mask_revision = self._mask_fingerprint[:16]
                self._rebuild_indexes()
            except (DataUnavailable, ZoneMaskError):
                # Map browsing remains possible; only exact-click lookup is unavailable.
                pass

    def start_background_refresh(self) -> bool:
        """Start one refresh loop after the visible page signals first paint."""

        with self._background_refresh_lock:
            if self._background_refresh_started:
                return False
            self._background_refresh_started = True
            thread = threading.Thread(
                target=self._refresh_loop,
                name="fish-data-refresh",
                daemon=True,
            )
            thread.start()
            return True

    def _refresh_loop(self) -> None:
        while True:
            self._background_refresh()
            threading.Event().wait(SOURCE_REFRESH_SECONDS)

    def _background_refresh(self) -> None:
        with self._lock:
            self._state["refreshInProgress"] = True
        try:
            self.refresh()
            self._refresh_zone_mask()
            # Exact membership is more important than optional ranking evidence.
            self._hydrate_missing_zone_summaries()
            self._refresh_evidence_points()
        except Exception as exc:
            with self._lock:
                self._state.update(status="live-partial", message=f"Refresh incomplete: {type(exc).__name__}")
        finally:
            with self._lock:
                self._state["refreshInProgress"] = False
                self._state["refreshCompletedAt"] = utc_now()

    def _source_revision(self) -> str:
        return str(self._json.get("fish.json", {}).get("revision")
                   or self._json.get("zone-loot-facts.json", {}).get("revision")
                   or self._json.get("meta.json", {}).get("release_identity") or "unknown")

    def _source_revisions_consistent(self) -> bool:
        revisions = {str(self._json.get(name, {}).get("revision"))
                     for name in ("fish.json", "zone-loot-facts.json") if self._json.get(name, {}).get("revision")}
        commit = self._json.get("meta.json", {}).get("dolt_commit")
        if commit:
            revisions.add(f"dolt:{commit}")
        return len(revisions) <= 1

    def _ranking_uncertainty_pixels(self) -> float:
        distance = _number(self._json.get("meta.json", {}).get("canonical_map", {}).get("distance_per_pixel"))
        return RANKING_UNCERTAINTY_GAME_UNITS / distance if distance and distance > 0 else RANKING_UNCERTAINTY_MAP_PX

    def _detail_receipt(self, document: dict[str, Any]) -> dict[str, Any]:
        receipt = document.get("companionCache")
        return receipt if isinstance(receipt, dict) else {}

    def _detail_is_current(self, document: dict[str, Any]) -> bool:
        receipt = self._detail_receipt(document)
        try:
            fetched = datetime.fromisoformat(str(receipt["retrievedAt"]).replace("Z", "+00:00"))
            age = (datetime.now(timezone.utc) - fetched).total_seconds()
        except (KeyError, TypeError, ValueError):
            return False
        return (receipt.get("cacheVersion") == DETAIL_CACHE_VERSION
                and receipt.get("sourceRevision") == self._source_revision()
                and 0 <= age < SOURCE_REFRESH_SECONDS)

    def _read_zone_detail(
        self, rgb_u32: int, rgb_key: str
    ) -> dict[str, Any] | None:
        detail, _ = self._read_json(
            self._cache_paths(
                self.cache_root / "zone-details" / f"{rgb_u32:06x}.json"
            )
        )
        return detail

    def _rederive_cached_detail_statuses(self) -> None:
        """Keep wall-clock freshness exact without rebuilding static indexes."""

        for zone in self._zones:
            table_source = zone.get("tableSource")
            if not isinstance(table_source, dict):
                continue
            if table_source.get("kind") != "zone-loot-summary":
                continue
            rgb_u32 = _integer(zone.get("rgbU32"))
            if rgb_u32 is None:
                rgb_u32 = _integer(zone.get("rgb"))
            if rgb_u32 is None:
                table_source["status"] = "stale-or-unversioned"
                continue
            detail = self._read_zone_detail(
                rgb_u32, str(zone.get("rgbKey") or rgb_u32_to_key(rgb_u32))
            )
            table_source["status"] = (
                "current"
                if detail is not None and self._detail_is_current(detail)
                else "stale-or-unversioned"
            )

    def _cache_detail(self, cache_path: Path, document: dict[str, Any]) -> dict[str, Any]:
        document = dict(document)
        document["companionCache"] = {
            "cacheVersion": DETAIL_CACHE_VERSION, "provider": "FishyStuff",
            "sourceRevision": self._source_revision(), "retrievedAt": utc_now(),
            "contract": "zone_loot_summary.v3",
        }
        with self._lock:
            _atomic_write(
                cache_path,
                json.dumps(document, ensure_ascii=False).encode("utf-8"),
            )
        return document

    def _refresh_zone_mask(self) -> None:
        """Validate the current published field and version derived tiles by content."""
        name = "zone_mask.v8.bin"
        candidate = self.cache_root / "zone_mask.v8.validation.bin"
        try:
            payload = extract_zone_lookup(
                self._fetch_bytes(ZONE_MASK_ENDPOINT, timeout=25)
            )
            _atomic_write(candidate, payload)
            checked = ZoneMask(candidate)
            fingerprint = hashlib.sha256(payload).hexdigest()
            revision = fingerprint[:16]
            path = self.cache_root / name
            with self._lock:
                _atomic_write(path, payload)
                checked.path = path
                if revision != self._mask_revision:
                    self._state["evidenceRevision"] = None
                    self._evidence_clusters_by_rgb = {}
                self.mask = checked
                self._mask_fingerprint = fingerprint
                self._mask_revision = revision
                self._state["artifacts"][name] = {"status": "live", "revision": revision, "fetchedAt": utc_now()}
                self._rebuild_indexes()
        except (DataUnavailable, ZoneMaskError, OSError) as exc:
            with self._lock:
                self._state["artifacts"][name] = {"status": "cached" if self.mask else "unavailable", "error": str(exc)}
                self._state["status"] = "live-partial"
        finally:
            try:
                candidate.unlink(missing_ok=True)
            except OSError:
                pass

    def _load_evidence_points_cache(self) -> None:
        """Load compact ranking-position clusters; never treat them as catches."""

        document, _ = self._read_json(
            self._cache_paths(self.cache_root / "zone-evidence-points.json")
        )
        if document is None or _integer(document.get("schemaVersion")) != EVIDENCE_CACHE_VERSION:
            self._state.update(evidenceStatus="missing", evidencePointCount=0, evidenceClusterCount=0)
            return
        clusters_by_rgb: dict[int, list[dict[str, Any]]] = defaultdict(list)
        for record in document.get("clusters", []):
            if not isinstance(record, dict):
                continue
            rgb = _integer(record.get("rgb"))
            x = _integer(record.get("x"))
            y = _integer(record.get("y"))
            observations = _integer(record.get("observations"))
            if rgb is None or x is None or y is None or observations is None or observations < 1:
                continue
            if self.mask is not None:
                try:
                    if self.mask.lookup_u32(x, y) != rgb:
                        continue
                except (IndexError, ZoneMaskError):
                    continue
            clusters_by_rgb[rgb].append(
                {
                    "x": x,
                    "y": y,
                    "observations": observations,
                    "sourceCenterCount": _integer(record.get("sourceCenterCount")) or 1,
                    "observedDayCount": _integer(record.get("observedDayCount")) or 0,
                    "observedSpeciesCount": _integer(record.get("observedSpeciesCount")) or 0,
                    "observedRedSpeciesCount": _integer(record.get("observedRedSpeciesCount")) or 0,
                    "lastObservedUtc": _integer(record.get("lastObservedUtc")),
                    "uncertaintyGameUnits": _integer(record.get("uncertaintyGameUnits")) or RANKING_UNCERTAINTY_GAME_UNITS,
                    "displayRadiusMapPixels": _number(record.get("displayRadiusMapPixels")) or self._ranking_uncertainty_pixels(),
                    "observedFish": [
                        dict(item)
                        for item in record.get("observedFish", [])
                        if isinstance(item, dict) and _integer(item.get("itemId")) is not None
                    ],
                    "sourceKind": str(record.get("sourceKind") or document.get("sourceKind") or "ranking"),
                }
            )
        clusters = {rgb: values for rgb, values in clusters_by_rgb.items() if values}
        self._evidence_clusters_by_rgb = clusters
        cluster_count = sum(len(values) for values in clusters.values())
        self._state.update(
            evidenceStatus="cached" if cluster_count else "missing",
            evidenceRevision=document.get("revision"),
            evidencePointCount=cluster_count,
            evidenceClusterCount=cluster_count,
        )

    @staticmethod
    def _cluster_coordinate_indexes(coordinates: list[tuple[int, int]]) -> list[list[int]]:
        """Return 4px connected components using a small spatial hash."""

        if not coordinates:
            return []
        parent = list(range(len(coordinates)))

        def find(index: int) -> int:
            while parent[index] != index:
                parent[index] = parent[parent[index]]
                index = parent[index]
            return index

        def union(left: int, right: int) -> None:
            left_root = find(left)
            right_root = find(right)
            if left_root != right_root:
                parent[right_root] = left_root

        distance = RANKING_CLUSTER_DISTANCE_PX
        distance_squared = distance * distance
        grid: dict[tuple[int, int], list[int]] = defaultdict(list)
        for index, (x, y) in enumerate(coordinates):
            cell_x, cell_y = x // distance, y // distance
            for neighbor_x in range(cell_x - 1, cell_x + 2):
                for neighbor_y in range(cell_y - 1, cell_y + 2):
                    for other in grid.get((neighbor_x, neighbor_y), []):
                        other_x, other_y = coordinates[other]
                        if (x - other_x) ** 2 + (y - other_y) ** 2 <= distance_squared:
                            union(index, other)
            grid[(cell_x, cell_y)].append(index)

        components: dict[int, list[int]] = defaultdict(list)
        for index in range(len(coordinates)):
            components[find(index)].append(index)
        return list(components.values())

    def _derive_evidence_points(self, events: Iterable[Any]) -> dict[int, list[dict[str, Any]]]:
        """Aggregate FishyStuff ranking positions into honest nearby-evidence clusters.

        The public snapshot currently contains ranking inputs, not direct catch
        coordinates.  Each sampled player position has a 500 game-unit
        uncertainty ring.  ``full_zone_rgbs`` only establishes that the whole
        ring belongs to one zone RGB.  It supports nearby fish-presence evidence
        and zone attribution; it cannot establish a per-pixel loot table or rate.
        """

        counts: dict[int, Counter[tuple[int, int]]] = defaultdict(Counter)
        fish_counts: dict[tuple[int, int, int], Counter[int]] = defaultdict(Counter)
        latest: dict[tuple[int, int, int], int] = {}
        days: dict[tuple[int, int, int], set[int]] = defaultdict(set)
        fish_document = self._json.get("fish.json", {})
        fish_by_key = {
            key: record
            for record in fish_document.get("fish", [])
            if isinstance(record, dict)
            and (key := _integer(record.get("encyclopedia_key"))) is not None
        }
        for event in events:
            if not isinstance(event, dict) or str(event.get("source_kind") or "ranking") != "ranking":
                continue
            x = _integer(event.get("map_px_x"))
            y = _integer(event.get("map_px_y"))
            timestamp = _integer(event.get("ts_utc")) or 0
            fish_key = _integer(event.get("fish_id"))
            full_zone_rgbs = event.get("full_zone_rgbs")
            if x is None or y is None or not isinstance(full_zone_rgbs, list):
                continue
            for raw_rgb in full_zone_rgbs:
                rgb = _integer(raw_rgb)
                if rgb is None:
                    continue
                if self.mask is not None:
                    try:
                        if self.mask.lookup_u32(x, y) != rgb:
                            continue
                    except (IndexError, ZoneMaskError):
                        continue
                key = (rgb, x, y)
                counts[rgb][(x, y)] += 1
                if fish_key is not None and fish_key in fish_by_key:
                    fish_counts[key][fish_key] += 1
                latest[key] = max(timestamp, latest.get(key, 0))
                if timestamp > 0:
                    days[key].add(timestamp // 86400)

        result: dict[int, list[dict[str, Any]]] = {}
        grade_order = {"Prize": 0, "Rare": 1, "HighQuality": 2, "General": 3}
        for rgb, coordinate_counts in counts.items():
            coordinates = list(coordinate_counts)
            clusters: list[dict[str, Any]] = []
            for indexes in self._cluster_coordinate_indexes(coordinates):
                component = [coordinates[index] for index in indexes]
                observations = sum(coordinate_counts[coordinate] for coordinate in component)
                weighted_x = sum(x * coordinate_counts[(x, y)] for x, y in component) / observations
                weighted_y = sum(y * coordinate_counts[(x, y)] for x, y in component) / observations
                anchor_x, anchor_y = min(
                    component,
                    key=lambda coordinate: (
                        (coordinate[0] - weighted_x) ** 2 + (coordinate[1] - weighted_y) ** 2,
                        -coordinate_counts[coordinate],
                        coordinate[1],
                        coordinate[0],
                    ),
                )
                observed: Counter[int] = Counter()
                observed_days: set[int] = set()
                last_observed = 0
                for x, y in component:
                    key = (rgb, x, y)
                    observed.update(fish_counts.get(key, Counter()))
                    observed_days.update(days.get(key, set()))
                    last_observed = max(last_observed, latest.get(key, 0))
                observed_fish: list[dict[str, Any]] = []
                for fish_key, fish_observations in observed.items():
                    catalog = fish_by_key[fish_key]
                    item_id = _integer(catalog.get("item_id"))
                    name = catalog.get("name")
                    if item_id is None or not isinstance(name, str) or not name:
                        continue
                    observed_fish.append(
                        {
                            "itemId": item_id,
                            "name": name,
                            "grade": catalog.get("grade") or None,
                            "price": _integer(catalog.get("vendor_price")),
                            "observations": fish_observations,
                        }
                    )
                observed_fish.sort(
                    key=lambda item: (
                        grade_order.get(str(item.get("grade")), 4),
                        str(item["name"]).casefold(),
                    )
                )
                spatial_radius = max(
                    (math.hypot(x - anchor_x, y - anchor_y) for x, y in component),
                    default=0,
                ) + self._ranking_uncertainty_pixels()
                clusters.append(
                    {
                        "x": anchor_x,
                        "y": anchor_y,
                        "observations": observations,
                        "sourceCenterCount": len(component),
                        "observedDayCount": len(observed_days),
                        "observedSpeciesCount": len(observed_fish),
                        "observedRedSpeciesCount": sum(item.get("grade") == "Prize" for item in observed_fish),
                        "lastObservedUtc": last_observed,
                        "uncertaintyGameUnits": RANKING_UNCERTAINTY_GAME_UNITS,
                        "displayRadiusMapPixels": round(spatial_radius, 3),
                        "observedFish": observed_fish,
                        "sourceKind": "ranking",
                    }
                )
            clusters.sort(
                key=lambda point: (
                    -(point["observedRedSpeciesCount"]),
                    -(point["observations"]),
                    -(point["observedSpeciesCount"]),
                    -(point["lastObservedUtc"] or 0),
                    point["y"],
                    point["x"],
                )
            )
            result[rgb] = clusters
        return result

    def _refresh_evidence_points(self) -> None:
        """Refresh compact FishyStuff ranking-position clusters in memory/cache."""

        try:
            meta_payload = self._fetch_bytes(f"{API_ROOT}/api/v1/events_snapshot_meta", timeout=18)
            meta = json.loads(meta_payload.decode("utf-8"))
            revision = str(meta.get("revision") or "").strip()
            snapshot_path = str(meta.get("snapshot_url") or "").strip()
            if not revision or not snapshot_path.startswith("/api/"):
                raise ValueError("event snapshot metadata is incomplete")

            if revision == self._state.get("evidenceRevision") and self._evidence_clusters_by_rgb:
                cluster_count = sum(len(values) for values in self._evidence_clusters_by_rgb.values())
                with self._lock:
                    self._state.update(
                        evidenceStatus="live",
                        evidenceRevision=revision,
                        evidencePointCount=cluster_count,
                        evidenceClusterCount=cluster_count,
                    )
                return

            snapshot_payload = self._fetch_bytes(f"{API_ROOT}{snapshot_path}", timeout=35)
            snapshot = json.loads(snapshot_payload.decode("utf-8"))
            events = snapshot.get("events", [])
            if not isinstance(events, list):
                raise ValueError("event snapshot has no event list")
            clusters_by_rgb = self._derive_evidence_points(events)
            if not clusters_by_rgb:
                raise ValueError("event snapshot produced no verified ranking clusters")
            source_kind = str(snapshot.get("source_kind") or meta.get("source_kind") or "ranking")
            for clusters in clusters_by_rgb.values():
                for cluster in clusters:
                    cluster["sourceKind"] = source_kind
            flattened_clusters = [
                {"rgb": rgb, **cluster}
                for rgb, clusters in sorted(clusters_by_rgb.items())
                for cluster in clusters
            ]
            document = {
                "schemaVersion": EVIDENCE_CACHE_VERSION,
                "revision": revision,
                "sourceKind": source_kind,
                "eventCount": _integer(snapshot.get("event_count")) or len(events),
                "clusterDistanceMapPixels": RANKING_CLUSTER_DISTANCE_PX,
                "uncertaintyGameUnits": RANKING_UNCERTAINTY_GAME_UNITS,
                "clusters": flattened_clusters,
            }
            with self._lock:
                _atomic_write(
                    self.cache_root / "zone-evidence-points.json",
                    json.dumps(
                        document,
                        ensure_ascii=False,
                        separators=(",", ":"),
                    ).encode("utf-8"),
                )
                self._evidence_clusters_by_rgb = clusters_by_rgb
                cluster_count = len(flattened_clusters)
                self._state.update(
                    evidenceStatus="live",
                    evidenceRevision=revision,
                    evidencePointCount=cluster_count,
                    evidenceClusterCount=cluster_count,
                )
                self._rebuild_indexes()
        except (DataUnavailable, UnicodeDecodeError, json.JSONDecodeError, ValueError):
            with self._lock:
                cluster_count = sum(len(values) for values in self._evidence_clusters_by_rgb.values())
                self._state.update(
                    evidenceStatus="cached" if cluster_count else "unavailable",
                    evidencePointCount=cluster_count,
                    evidenceClusterCount=cluster_count,
                )

    def refresh(self, raise_on_empty: bool = False) -> None:
        """Refresh public source JSON without ever replacing good data with an error."""

        if not self._refresh_lock.acquire(blocking=False):
            return
        try:
            fresh: dict[str, dict[str, Any]] = {}
            fresh_payloads: dict[str, bytes] = {}
            errors: list[str] = []
            for name, url in self.DATA_ENDPOINTS.items():
                try:
                    payload = self._fetch_bytes(url, timeout=18)
                    parsed = json.loads(payload.decode("utf-8"))
                    if not isinstance(parsed, dict):
                        raise ValueError("root is not an object")
                    required = {"fish.json": "fish", "zones.json": "zones", "zone-loot-facts.json": "elements"}.get(name)
                    if required and not isinstance(parsed.get(required), list):
                        raise ValueError(f"missing {required} list")
                    if required and not parsed[required]:
                        raise ValueError(f"empty {required} list; retaining last good source")
                    fresh[name] = parsed
                    fresh_payloads[name] = payload
                except (DataUnavailable, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
                    errors.append(f"{name}: {exc}")
                    previous = self._state["artifacts"].get(name, {})
                    self._state["artifacts"][name] = {**previous, "status": "cached" if name in self._json else "unavailable", "error": str(exc)}

            if fresh:
                with self._lock:
                    for name, payload in fresh_payloads.items():
                        _atomic_write(self.cache_root / name, payload)
                        parsed = fresh[name]
                        self._state["artifacts"][name] = {
                            "status": "live", "fetchedAt": utc_now(),
                            "revision": parsed.get("revision") or parsed.get("release_identity"),
                        }
                    self._json.update(fresh)
                    self._state.update(
                        status="live-partial",
                        jsonStatus="live" if not errors else "live-partial",
                        fetchedAt=utc_now(),
                        message="; ".join(errors) if errors else None,
                    )
                    self._rebuild_indexes()
                    state_payload = json.dumps(self._state, ensure_ascii=False, indent=2).encode("utf-8")
                    _atomic_write(self.cache_root / "source-state.json", state_payload)
            elif errors:
                self._state.update(status="cached", jsonStatus="unavailable", message="; ".join(errors))
            if raise_on_empty and ("zones.json" not in self._json or "fish.json" not in self._json):
                raise DataUnavailable("Fish map data could not be loaded")
        finally:
            self._refresh_lock.release()

    @staticmethod
    def _fetch_bytes(url: str, *, timeout: int = 15, body: bytes | None = None) -> bytes:
        headers = {
            "Accept": "application/json,image/webp,*/*;q=0.8",
            "User-Agent": USER_AGENT,
        }
        if body is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=body, headers=headers, method="POST" if body else "GET")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                if response.status != 200:
                    raise DataUnavailable(f"source returned HTTP {response.status}")
                return response.read()
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise DataUnavailable("source is currently unreachable") from exc

    # ------------------------------------------------------------------
    # Normalized indexes

    def _rebuild_indexes(self) -> None:
        source_fingerprint = self._derived_index_source_fingerprint()
        fish_document = self._json.get("fish.json", {})
        fish_records = fish_document.get("fish", [])
        fish_by_id: dict[int, dict[str, Any]] = {}
        fish_output: list[dict[str, Any]] = []
        for record in fish_records if isinstance(fish_records, list) else []:
            if not isinstance(record, dict):
                continue
            item_id = _integer(record.get("item_id"))
            name = record.get("name")
            if item_id is None or not isinstance(name, str) or not name:
                continue
            fish_by_id[item_id] = dict(record)
            if bool(record.get("is_dried")):
                continue
            icon_item_id = _integer(record.get("icon_item_id")) or item_id
            fish_output.append(
                {
                    "itemId": item_id,
                    "iconItemId": icon_item_id,
                    "name": name,
                    "grade": record.get("grade") or None,
                    "price": _integer(record.get("vendor_price")),
                    "methods": [str(value) for value in record.get("catch_methods", []) if value],
                    "iconUrl": f"/icon/{item_id}.webp",
                }
            )
        fish_output.sort(key=lambda item: item["name"].casefold())
        icon_paths: dict[int, str] = {}
        for item_id, record in fish_by_id.items():
            icon_path = record.get("icon_image")
            if isinstance(icon_path, str) and icon_path.startswith("/images/items/"):
                icon_paths[item_id] = icon_path
        detail_by_name = {
            path.name.casefold(): path
            for path in (self.snapshot_root / "zone-details").glob("*.json")
        }
        detail_by_name.update(
            {
                path.name.casefold(): path
                for path in (self.cache_root / "zone-details").glob("*.json")
            }
        )
        detail_paths = list(detail_by_name.values())
        for detail_path in detail_paths:
            detail, _ = self._read_json([detail_path])
            if detail is not None:
                self._collect_icon_paths(detail, icon_paths)

        facts_document = self._json.get("zone-loot-facts.json", {})
        facts_by_rgb: dict[int, dict[str, Any]] = {}
        for element in facts_document.get("elements", []) if isinstance(facts_document, dict) else []:
            if not isinstance(element, dict):
                continue
            match = re.fullmatch(r"zone:0x([0-9a-fA-F]{6})", str(element.get("elementId", "")))
            if match:
                facts_by_rgb[int(match.group(1), 16)] = element

        zone_document = self._json.get("zones.json", {})
        zone_records = zone_document.get("zones", [])
        active_records = [
            record
            for record in zone_records
            if isinstance(record, dict) and record.get("active") is True and isinstance(record.get("name"), str)
        ]
        active_rgb = {_integer(record.get("rgb_u32")) for record in active_records}
        centers = self.mask.representative_points(value for value in active_rgb if value is not None) if self.mask else {}
        bounds = self.mask.bounds(value for value in active_rgb if value is not None) if self.mask else {}

        zones: list[dict[str, Any]] = []
        zones_by_key: dict[str, dict[str, Any]] = {}
        for record in active_records:
            rgb_u32 = _integer(record.get("rgb_u32"))
            if rgb_u32 is None:
                continue
            rgb_key = str(record.get("rgb_key") or rgb_u32_to_key(rgb_u32))
            name = str(record["name"])
            zone_role = self._zone_role(name)
            element = facts_by_rgb.get(rgb_u32)
            fact_summary = self._summarize_facts(element, fish_by_id)
            table_source = {"kind": "zone-loot-facts", "status": "partial", "revision": facts_document.get("revision"),
                            "note": "Facts export is incomplete; absence here does not establish absence from the game."}
            detail = self._read_zone_detail(rgb_u32, rgb_key)
            if detail is not None:
                # The summary reconciles source claims and contains species omitted
                # from the sparse facts export. Never union old facts back into it.
                fact_summary = self._summarize_detail(detail, fish_by_id)
                receipt = self._detail_receipt(detail)
                table_source = {
                    "kind": "zone-loot-summary", "status": "current" if self._detail_is_current(detail) else "stale-or-unversioned",
                    "revision": receipt.get("sourceRevision"), "retrievedAt": receipt.get("retrievedAt"),
                    "available": detail.get("available"), "note": detail.get("dataQualityNote") or detail.get("note"),
                }
            point = centers.get(rgb_u32)
            evidence_clusters = self._evidence_clusters_by_rgb.get(rgb_u32, [])
            evidence_point = evidence_clusters[0] if evidence_clusters else None
            zone = {
                # Decimal packed RGB keeps the browser-side map index compact;
                # rgbKey preserves the human-readable exact source value.
                "rgb": rgb_u32,
                "rgbKey": rgb_key,
                "rgbU32": rgb_u32,
                "name": name,
                "entityType": "fishing-table-zone",
                "active": True,
                "exact": bool(record.get("exactRgbConfirmed")),
                # ``exactRgbConfirmed`` confirms the zone colour/RGB mapping;
                # it does not mean that this is a single point-sized fishing
                # spot.  Default and Unknown source labels are broad catch-all
                # mask areas and remain available for exact map clicks.
                "sourceRgbConfirmed": bool(record.get("exactRgbConfirmed")),
                "zoneRole": zone_role,
                "tableSource": table_source,
                "depth": self._depth_from_name(name),
                "center": {"x": point.x, "y": point.y} if point else None,
                # A center is only a mask-safe viewport anchor.  Ranking
                # evidence is sampled player-position data with a 500 game-unit
                # uncertainty ring; it is never presented as an exact catch.
                "evidencePoint": dict(evidence_point) if evidence_point else None,
                "evidenceClusters": [dict(cluster) for cluster in evidence_clusters],
                "pinpointRecommendationEligible": bool(
                    evidence_clusters and zone_role == "named-table"
                ),
                "tableRecommendationEligible": bool(
                    fact_summary["dataKnown"] and zone_role == "named-table"
                ),
                "bounds": bounds.get(rgb_u32),
                "index": _integer(record.get("index")),
                "biteTime": {
                    "minimumSeconds": _integer(record.get("bite_time_min")),
                    "maximumSeconds": _integer(record.get("bite_time_max")),
                },
                **fact_summary,
            }
            zones.append(zone)
            zones_by_key[rgb_key] = zone

        zones.sort(key=lambda item: item["name"].casefold())
        assignment_methods: dict[int, set[str]] = defaultdict(set)
        for zone in zones:
            for item in zone.get("items", []):
                if item.get("method") in {"rod", "harpoon"}:
                    assignment_methods[item["itemId"]].add(item["method"])
        for item in fish_output:
            item["assignmentMethods"] = sorted(assignment_methods.get(item["itemId"], set()))
            item["methods"] = sorted(set(item["methods"]) | assignment_methods.get(item["itemId"], set()))
        self._accuracy_audit = apply_catalog_supplement(fish_by_id, fish_output, zones)
        self.fish_by_id = fish_by_id
        self.icon_paths_by_item = icon_paths
        self._fish = fish_output
        self._zones = zones
        self.zones_by_key = zones_by_key
        self.tileset = self._json.get("tileset.json", {})
        self._regions = self._load_regions()
        self._location_nodes = self._load_location_nodes()
        self._load_semantic_region_indexes()
        self._rebuild_location_node_lookups()
        self._set_normalized_revision()
        if self._write_derived_index_cache(
            expected_source_fingerprint=source_fingerprint
        ):
            self._write_runtime_snapshot_receipt(
                expected_source_fingerprint=source_fingerprint
            )

    @staticmethod
    def _zone_role(name: str) -> str:
        """Classify only explicit FishyStuff source naming conventions."""

        normalized = name.casefold().strip()
        if "out-of-bounds" in normalized or "out of bounds" in normalized:
            return "out-of-bounds"
        if normalized.endswith(" - unknown") or normalized == "unknown":
            return "unknown"
        if "terrain default" in normalized or normalized.endswith(" - default"):
            return "broad-default"
        return "named-table"

    @staticmethod
    def _row_has_assignment(row: dict[str, Any]) -> bool:
        group = str(row.get("groupLabel") or row.get("group") or "").strip().casefold()
        if group in {"", "unassigned"}:
            return False
        if "presenceClaims" not in row:
            # Legacy direct table rows have no claim contract. Keep their explicit
            # group assignment, with table-level stale/partial provenance.
            return True
        claims = [claim for claim in row.get("presenceClaims", []) if isinstance(claim, dict)]
        effective = [claim for claim in claims if claim.get("status") == "effective"]
        for claim in effective:
            value = claim.get("value") or {}
            if ((claim.get("factKind") == "groupMembership" and value.get("value") in {"notMember", "absent"})
                    or (claim.get("factKind") == "itemPresence" and value.get("value") in {"absent", "notPresent"})):
                return False
        return any(claim.get("factKind") == "groupMembership"
                   and (claim.get("value") or {}).get("value") == "member"
                   and not str(claim.get("observationScope") or "").startswith("ranking")
                   for claim in effective)

    @staticmethod
    def _detail_rows(detail: dict[str, Any]) -> list[dict[str, Any]]:
        """Expose every explicit v3 membership without flattening conditions.

        Top-level conditional rows reflect a source-selected calculator profile,
        not universal membership. Replace those with their full labeled cohorts.
        """
        groups = [group for group in detail.get("groups", []) if isinstance(group, dict)]
        conditional = {str(group.get("label") or group.get("groupLabel") or "")
                       for group in groups if group.get("conditionOptions")}
        rows = [dict(row) for row in detail.get("speciesRows", [])
                if isinstance(row, dict) and str(row.get("groupLabel") or row.get("group") or "") not in conditional]
        for group in groups:
            for option in group.get("conditionOptions", []):
                if not isinstance(option, dict):
                    continue
                for original in option.get("speciesRows", []):
                    if not isinstance(original, dict):
                        continue
                    row = dict(original)
                    row["conditionId"] = option.get("conditionId") or option.get("conditionText") or "unknown-condition"
                    row["conditions"] = option.get("conditions") or {"state": "unknown"}
                    row["conditionText"] = option.get("conditionText") or "Source condition unspecified"
                    row["conditionTooltip"] = option.get("conditionTooltip") or row["conditionText"]
                    # Membership must remain explicit on the species row; do not
                    # infer a fish from a group, grade, or ranking observation.
                    if not row.get("catchMethods") and group.get("catchMethods"):
                        row["catchMethods"] = list(group["catchMethods"])
                    rows.append(row)
        return rows

    @staticmethod
    def _source_profile_methods(
        record: dict[str, Any],
        label: str,
        catalog: dict[str, Any] | None = None,
        fallback: Iterable[str] = (),
    ) -> set[str]:
        """Resolve only explicit/source-stable fishing methods for one row."""

        values = (
            record.get("catchMethods")
            or record.get("methods")
            or ([record.get("catchMethod")] if record.get("catchMethod") else [])
        )
        if isinstance(values, str):
            values = [values]
        methods = {
            str(value or "").strip().casefold()
            for value in values
            if str(value or "").strip().casefold() in {"rod", "harpoon"}
        }
        if not methods and catalog:
            catalog_methods = catalog.get("catch_methods") or []
            if isinstance(catalog_methods, str):
                catalog_methods = [catalog_methods]
            methods = {
                str(value or "").strip().casefold()
                for value in catalog_methods
                if str(value or "").strip().casefold() in {"rod", "harpoon"}
            }
        if not methods:
            methods = _default_pool_methods(label)
        if not methods:
            methods = {
                str(value or "").strip().casefold()
                for value in fallback
                if str(value or "").strip().casefold() in {"rod", "harpoon"}
            }
        return methods

    @staticmethod
    def _source_profile_percent(record: dict[str, Any]) -> float | None:
        """Read the selected profile's most precise normalized percentage.

        FishyStuff's visible text is rounded and can say ``0%`` for a known,
        tiny positive weight.  The title carries the precise percentage in
        those cases.  An explicitly unknown state always wins over either
        display field so an unknown can never silently become zero.
        """

        state = str(record.get("normalizedDropRateState") or "").strip().casefold()
        if state in {"unknown", "unavailable", "missing", "not-known"}:
            return None
        for field in ("normalizedDropRateTitle", "normalizedDropRateText"):
            rate = _percent_number(record.get(field))
            if rate is not None:
                return rate if 0.0 <= rate <= 100.0 else None
        return None

    @staticmethod
    def _experimental_money_by_method(
        detail: dict[str, Any], fish_by_id: dict[int, dict[str, Any]]
    ) -> dict[str, dict[str, Any]]:
        """Model base fish money from one source-selected calculator profile.

        This intentionally uses the top-level ``groups`` and ``speciesRows``.
        Those rows are the currently selected FishyStuff profile, while
        ``_detail_rows`` expands all conditional cohorts for universal table
        membership. Mixing those cohorts would manufacture impossible odds.

        Every positive-probability group and assigned row must have a known
        normalized rate, every group/table probability must be complete within
        source rounding tolerance, and every positive-probability fish needs a
        base vendor price. Otherwise the method remains explicitly
        ``insufficient-rate-data`` rather than using a zero placeholder.
        """

        source_data_quality_note = str(
            detail.get("dataQualityNote") or detail.get("note") or ""
        ).strip() or None
        source_data_may_be_incomplete = bool(
            source_data_quality_note
            and re.search(r"\bincomplete\b|\bmissing\b", source_data_quality_note, re.I)
        )

        def base_result(method: str) -> dict[str, Any]:
            return {
                "status": "insufficient-rate-data",
                "reasonCode": "no-source-rate-profile",
                "reason": "Not enough source rate data.",
                "method": method,
                "experimental": True,
                "catches": EXPERIMENTAL_MONEY_CATCHES,
                "expectedBaseFishValuePerCatch": None,
                "expectedBaseFishValuePer100": None,
                "consistentBaseFishValuePer100": None,
                "redFishChancePercent": None,
                "modeledProbabilityPercent": None,
                "rateProfileLabel": detail.get("profileLabel"),
                "rateBasis": "fishystuff-selected-calculator-profile",
                "sourceProfileConditions": [],
                "sourceDataQualityNote": source_data_quality_note,
                "sourceDataMayBeIncomplete": source_data_may_be_incomplete,
                "priceBasis": "base-fish-vendor-price",
                "consistencyBasis": "deterministic-binned-percentile-over-100-catches",
                "consistencyPercentile": EXPERIMENTAL_MONEY_PERCENTILE,
                "approximationBasis": "nearest-2000-silver-per-catch-value-bins",
                "approximationErrorSilver": EXPERIMENTAL_MONEY_APPROXIMATION_ERROR_SILVER,
                "rateCoverageBasis": "normalized-supplied-source-weights",
                "valueExclusions": [
                    "non-fish-items",
                    "trade-bonuses",
                    "resources",
                    "catch-speed",
                ],
                "rateIssueGroups": [],
                "missingPriceItemIds": [],
            }

        results = {method: base_result(method) for method in ("rod", "harpoon")}
        if detail.get("available") is False:
            return results

        source_rows = [
            row
            for row in detail.get("speciesRows", [])
            if isinstance(row, dict) and FishDataRepository._row_has_assignment(row)
        ]
        source_groups = [
            group
            for group in detail.get("groups", [])
            if isinstance(group, dict)
            and str(group.get("label") or group.get("groupLabel") or "").strip().casefold()
            not in {"", "unassigned"}
        ]
        if not source_rows or not source_groups:
            return results

        group_records_by_method: dict[str, list[tuple[str, dict[str, Any]]]] = {
            "rod": [],
            "harpoon": [],
        }
        group_methods_by_label: dict[str, set[str]] = defaultdict(set)
        for group in source_groups:
            label = str(group.get("label") or group.get("groupLabel") or "").strip()
            methods = FishDataRepository._source_profile_methods(group, label)
            if not methods:
                for row in source_rows:
                    if str(row.get("groupLabel") or row.get("group") or "").strip() != label:
                        continue
                    item_id = _integer(row.get("itemId"))
                    methods.update(
                        FishDataRepository._source_profile_methods(
                            row, label, fish_by_id.get(item_id or -1, {})
                        )
                    )
            group_methods_by_label[label].update(methods)
            for method in methods:
                if method in group_records_by_method:
                    group_records_by_method[method].append((label, group))

        for method, method_groups in group_records_by_method.items():
            result = results[method]
            if not method_groups:
                continue

            profile_conditions = {
                str(group.get("conditionText") or "").strip()
                for _, group in method_groups
                if str(group.get("conditionText") or "").strip()
            }

            labels = [label for label, _ in method_groups]
            duplicate_labels = sorted({label for label in labels if labels.count(label) > 1})
            if duplicate_labels:
                result.update(
                    reasonCode="ambiguous-source-groups",
                    rateIssueGroups=duplicate_labels,
                )
                continue

            group_rates: dict[str, float] = {}
            unknown_groups: list[str] = []
            for label, group in method_groups:
                rate = FishDataRepository._source_profile_percent(group)
                if rate is None:
                    unknown_groups.append(label)
                else:
                    group_rates[label] = rate
            if unknown_groups:
                result.update(
                    reasonCode="unknown-group-rates",
                    rateIssueGroups=sorted(unknown_groups),
                )
                continue

            group_probability_percent = sum(group_rates.values())
            if abs(group_probability_percent - 100.0) > EXPERIMENTAL_MONEY_RATE_TOLERANCE_PERCENT:
                result.update(
                    reasonCode="incomplete-group-probability",
                    modeledProbabilityPercent=round(group_probability_percent, 6),
                    rateIssueGroups=sorted(group_rates),
                )
                continue

            outcomes: list[tuple[float, float, bool, int]] = []
            rate_issue_groups: list[str] = []
            unknown_rate_groups: set[str] = set()
            for label, _ in method_groups:
                group_rate = group_rates[label]
                if group_rate <= 0.0:
                    continue
                group_methods = group_methods_by_label.get(label, {method})
                rows_for_group: list[dict[str, Any]] = []
                for row in source_rows:
                    if str(row.get("groupLabel") or row.get("group") or "").strip() != label:
                        continue
                    item_id = _integer(row.get("itemId"))
                    row_methods = FishDataRepository._source_profile_methods(
                        row,
                        label,
                        fish_by_id.get(item_id or -1, {}),
                        group_methods,
                    )
                    if method in row_methods:
                        rows_for_group.append(row)
                        condition_text = str(row.get("conditionText") or "").strip()
                        if condition_text:
                            profile_conditions.add(condition_text)
                if not rows_for_group:
                    rate_issue_groups.append(label)
                    unknown_rate_groups.add(label)
                    continue

                row_rates: list[tuple[dict[str, Any], float]] = []
                for row in rows_for_group:
                    rate = FishDataRepository._source_profile_percent(row)
                    if rate is None:
                        unknown_rate_groups.add(label)
                        rate_issue_groups.append(label)
                    else:
                        row_rates.append((row, rate))
                if label in unknown_rate_groups:
                    continue
                row_probability_percent = sum(rate for _, rate in row_rates)
                if abs(row_probability_percent - 100.0) > EXPERIMENTAL_MONEY_RATE_TOLERANCE_PERCENT:
                    rate_issue_groups.append(label)
                    continue

                for row, row_rate in row_rates:
                    probability = (group_rate / 100.0) * (row_rate / 100.0)
                    if probability <= 0.0:
                        continue
                    item_id = _integer(row.get("itemId"))
                    if item_id is None:
                        rate_issue_groups.append(label)
                        continue
                    catalog = fish_by_id.get(item_id, {})
                    is_fish = row.get("isFish") is True or str(row.get("isFish") or "").casefold() == "true"
                    grade = str(row.get("grade") or catalog.get("grade") or "").strip().casefold()
                    price = _number(
                        row.get("priceRaw")
                        if row.get("priceRaw") is not None
                        else row.get("price")
                    )
                    if price is None:
                        price = _number(catalog.get("vendor_price"))
                    if is_fish and (price is None or price < 0.0):
                        result["missingPriceItemIds"].append(item_id)
                        value = 0.0
                    else:
                        # Non-fish resources are real outcomes and therefore
                        # stay in the probability/variance model with zero fish
                        # value. Their market prices are intentionally outside
                        # this base-fish-value comparison.
                        value = float(price or 0.0) if is_fish else 0.0
                    outcomes.append((probability, value, is_fish and grade == "prize", item_id))

            if unknown_rate_groups or rate_issue_groups:
                result.update(
                    reasonCode=(
                        "unknown-item-rates"
                        if unknown_rate_groups
                        else "incomplete-item-probability"
                    ),
                    rateIssueGroups=sorted(set(rate_issue_groups)),
                )
                continue

            modeled_probability = sum(probability for probability, _, _, _ in outcomes)
            result["modeledProbabilityPercent"] = round(modeled_probability * 100.0, 6)
            if (
                modeled_probability <= 0.0
                or abs(modeled_probability * 100.0 - 100.0)
                > EXPERIMENTAL_MONEY_RATE_TOLERANCE_PERCENT
            ):
                result.update(
                    reasonCode="incomplete-modeled-probability",
                    rateIssueGroups=sorted(group_rates),
                )
                continue

            # The published percentages are rounded for display. Normalize
            # their tiny rounding drift only after proving near-100% coverage.
            normalized_outcomes = [
                (probability / modeled_probability, value, is_red)
                for probability, value, is_red, _ in outcomes
            ]
            red_probability = sum(
                probability for probability, _, is_red in normalized_outcomes if is_red
            )
            result["redFishChancePercent"] = round(red_probability * 100.0, 6)
            if result["missingPriceItemIds"]:
                result.update(
                    reasonCode="unknown-fish-price",
                    missingPriceItemIds=sorted(set(result["missingPriceItemIds"])),
                )
                continue

            mean = sum(probability * value for probability, value, _ in normalized_outcomes)
            catches = EXPERIMENTAL_MONEY_CATCHES
            expected_per_100 = catches * mean
            consistent_per_100 = _deterministic_total_value_percentile(
                ((probability, value) for probability, value, _ in normalized_outcomes),
                catches=catches,
            )
            result.update(
                status="modeled",
                reasonCode=None,
                reason=None,
                expectedBaseFishValuePerCatch=round(mean, 2),
                expectedBaseFishValuePer100=int(round(expected_per_100)),
                consistentBaseFishValuePer100=consistent_per_100,
                sourceProfileConditions=sorted(profile_conditions),
                missingPriceItemIds=[],
            )
        return results

    @staticmethod
    def _collect_icon_paths(detail: dict[str, Any], target: dict[int, str]) -> None:
        for row in FishDataRepository._detail_rows(detail):
            if not isinstance(row, dict):
                continue
            item_id = _integer(row.get("itemId"))
            icon_url = row.get("iconUrl")
            if item_id is None or not isinstance(icon_url, str):
                continue
            parsed = urlsplit(icon_url)
            if parsed.hostname not in {None, "cdn.fishystuff.fish"}:
                continue
            path = parsed.path
            if path.startswith("/images/items/") and path.casefold().endswith(".webp"):
                target[item_id] = path

    @staticmethod
    def _summarize_detail(
        detail: dict[str, Any], fish_by_id: dict[int, dict[str, Any]]
    ) -> dict[str, Any]:
        rows = FishDataRepository._detail_rows(detail)
        if detail.get("available") is False or not rows:
            return {
                "dataKnown": False,
                "hasRelic": None,
                "hasRelicBasis": "unknown",
                "hasRelicByMethod": {"rod": None, "harpoon": None},
                "redSpeciesCount": None,
                "redSpeciesCountByMethod": {"rod": None, "harpoon": None},
                "groupRatesByMethod": {"rod": {}, "harpoon": {}},
                "estimatedValue": None,
                "estimatedValueByMethod": {"rod": None, "harpoon": None},
                "experimentalMoneyByMethod": FishDataRepository._experimental_money_by_method(
                    {"available": False}, fish_by_id
                ),
                "methods": [],
                "items": [],
                "searchTerms": "",
            }
        items: list[dict[str, Any]] = []
        seen: set[tuple[int, str, str, str]] = set()
        methods: set[str] = set()
        red_ids: set[int] = set()
        red_ids_by_method: dict[str, set[int]] = {"rod": set(), "harpoon": set()}
        group_methods: dict[str, set[str]] = defaultdict(set)
        has_relic = False
        has_relic_by_method = {"rod": False, "harpoon": False}
        for row in rows:
            item_id = _integer(row.get("itemId"))
            if item_id is None:
                continue
            catalog = fish_by_id.get(item_id, {})
            row_methods = row.get("catchMethods") or row.get("methods") or []
            if isinstance(row_methods, str):
                row_methods = [row_methods]
            if not row_methods and row.get("catchMethod"):
                row_methods = [row.get("catchMethod")]
            if not row_methods:
                row_methods = catalog.get("catch_methods") or []
            group = str(row.get("groupLabel") or row.get("group") or "")
            assigned_to_table = FishDataRepository._row_has_assignment(row)
            name = str(row.get("label") or row.get("name") or catalog.get("name") or item_id)
            grade = str(row.get("grade") or catalog.get("grade") or "")
            is_fish = row.get("isFish") is True or str(row.get("isFish")).casefold() == "true"
            price = _integer(row.get("priceRaw") if row.get("priceRaw") is not None else row.get("price"))
            if price is None:
                price = _integer(catalog.get("vendor_price"))
            if assigned_to_table:
                for row_method in row_methods:
                    normalized_method = str(row_method or "").casefold()
                    if normalized_method in {"rod", "harpoon"}:
                        group_methods[group].add(normalized_method)
            for method in row_methods or [""]:
                method = str(method or "").strip().casefold()
                if not assigned_to_table:
                    continue
                key = (item_id, method, group, str(row.get("conditionId") or ""))
                if key in seen:
                    continue
                seen.add(key)
                if method:
                    methods.add(method)
                items.append(
                    {
                        "itemId": item_id,
                        "name": name,
                        "grade": grade or None,
                        "group": group or None,
                        "isFish": is_fish,
                        "method": method or None,
                        "price": price,
                        "ratePercentWithinGroup": None,
                        "iconUrl": f"/icon/{item_id}.webp",
                        "conditionId": row.get("conditionId"),
                        "hasConditions": bool(row.get("conditionId") or row.get("conditionText")),
                        "conditions": row.get("conditions") or {"state": "unconditional"},
                        "conditionText": row.get("conditionText") or "",
                        "presenceClaims": row.get("presenceClaims") or [],
                        "rateClaims": row.get("rateClaims") or [],
                    }
                )
            if assigned_to_table and (item_id == 40218 or name.casefold() == "ancient relic crystal shard"):
                has_relic = True
                for row_method in row_methods:
                    normalized_method = str(row_method or "").casefold()
                    if normalized_method in has_relic_by_method:
                        has_relic_by_method[normalized_method] = True
            if assigned_to_table and is_fish and grade == "Prize":
                red_ids.add(item_id)
                for row_method in row_methods:
                    normalized_method = str(row_method or "").casefold()
                    if normalized_method in red_ids_by_method:
                        red_ids_by_method[normalized_method].add(item_id)

        if not items:
            # An available response containing only Unassigned/refuted rows is
            # not a known empty table. Preserve unknown rather than false/zero.
            unknown = FishDataRepository._summarize_detail({"available": False}, fish_by_id)
            unknown["excludedSourceRows"] = [dict(row) for row in rows]
            return unknown

        group_rates_by_method: dict[str, dict[str, float]] = {
            "rod": {},
            "harpoon": {},
        }
        for group_record in detail.get("groups", []):
            if not isinstance(group_record, dict):
                continue
            if group_record.get("conditionOptions") or group_record.get("conditionText"):
                # A selected mastery cohort's rate is not the universal pool rate.
                continue
            label = str(group_record.get("label") or group_record.get("groupLabel") or "")
            if label.strip().casefold() in {"", "unassigned"}:
                continue
            rate_state = str(group_record.get("normalizedDropRateState") or "").casefold()
            if rate_state and rate_state != "known":
                continue
            rate = _percent_number(group_record.get("normalizedDropRateText"))
            if rate is None:
                continue
            group_record_methods = (
                group_record.get("catchMethods")
                or group_record.get("methods")
                or ([group_record.get("catchMethod")] if group_record.get("catchMethod") else [])
            )
            if isinstance(group_record_methods, str):
                group_record_methods = [group_record_methods]
            normalized_methods = {
                str(value or "").casefold()
                for value in group_record_methods
                if str(value or "").casefold() in {"rod", "harpoon"}
            }
            if not normalized_methods:
                normalized_methods = group_methods.get(label, set())
            if not normalized_methods:
                normalized_methods = _default_pool_methods(label)
            for normalized_method in normalized_methods:
                group_rates_by_method[normalized_method][label] = rate
        items.sort(key=lambda item: (str(item.get("group") or ""), str(item["name"]).casefold()))
        return {
            "dataKnown": bool(items),
            "hasRelic": has_relic,
            "hasRelicByMethod": has_relic_by_method,
            "hasRelicBasis": (
                "present-in-current-source-table" if has_relic else "absent-from-current-source-table"
            ),
            "redSpeciesCount": len(red_ids),
            "redSpeciesCountByMethod": {
                method: len(item_ids) for method, item_ids in red_ids_by_method.items()
            },
            "groupRatesByMethod": group_rates_by_method,
            "conditionalGroups": [
                {"label": group.get("label"), "catchMethods": group.get("catchMethods") or [],
                 "conditionOptions": [{key: value for key, value in option.items() if key != "speciesRows"}
                                      for option in group.get("conditionOptions", []) if isinstance(option, dict)]}
                for group in detail.get("groups", []) if isinstance(group, dict) and group.get("conditionOptions")
            ],
            "rateProfileLabel": detail.get("profileLabel"),
            # FishyStuff correctly marks many per-item rates unknown.  A value
            # estimate would be invented without them, so it stays null here.
            "estimatedValue": None,
            "estimatedValueByMethod": {"rod": None, "harpoon": None},
            "estimatedValueBasis": None,
            "experimentalMoneyByMethod": FishDataRepository._experimental_money_by_method(
                detail, fish_by_id
            ),
            "methods": sorted(methods),
            "items": items,
            "excludedSourceRows": [{"itemId": row.get("itemId"), "name": row.get("label") or row.get("name"),
                                    "group": row.get("groupLabel"), "presenceClaims": row.get("presenceClaims") or [],
                                    "reason": "No effective explicit table membership"}
                                   for row in rows if not FishDataRepository._row_has_assignment(row)],
            "searchTerms": " ".join(str(item["name"]) for item in items),
        }

    def _hydrate_missing_zone_summaries(self) -> None:
        """Refresh every active table; sparse facts are never a completeness test."""
        with self._lock:
            zones = list(self._zones)
            progress = {"status": "refreshing", "total": len(zones), "checked": 0,
                        "refreshed": 0, "cached": 0, "available": 0, "unavailable": 0, "errors": []}
            self._state["tableRefresh"] = progress
        failures = 0
        for zone in zones:
            packed = int(zone["rgbU32"])
            cache_path = self.cache_root / "zone-details" / f"{packed:06x}.json"
            existing, _ = self._read_json([cache_path])
            if existing is not None and self._detail_is_current(existing):
                progress["cached"] += 1
                progress["checked"] += 1
                progress["unavailable" if existing.get("available") is False else "available"] += 1
                continue
            rgb_key = str(zone["rgbKey"])
            body = json.dumps({"rgb": rgb_key, "userOverlay": None}, separators=(",", ":")).encode("utf-8")
            try:
                raw = self._fetch_bytes(
                    f"{API_ROOT}/api/v1/zone_loot_summary?lang=en&locale=en-US",
                    timeout=18,
                    body=body,
                )
                parsed = json.loads(raw.decode("utf-8"))
                if not isinstance(parsed, dict) or not isinstance(parsed.get("available"), bool):
                    raise ValueError("summary lacks explicit availability")
                if parsed.get("available") and not isinstance(parsed.get("speciesRows"), list):
                    raise ValueError("available summary lacks species rows")
                self._cache_detail(cache_path, parsed)
                progress["refreshed"] += 1
                progress["unavailable" if parsed.get("available") is False else "available"] += 1
                failures = 0
            except (DataUnavailable, UnicodeDecodeError, json.JSONDecodeError, ValueError, OSError) as exc:
                progress["errors"].append({"rgb": rgb_key, "message": str(exc)})
                failures += 1
            progress["checked"] += 1
            # Publish new memberships in batches, not just after hundreds of requests.
            if progress["checked"] % 10 == 0:
                with self._lock:
                    self._rebuild_indexes()
            if failures >= 3:
                break  # Avoid hammering an offline source; next scheduled pass retries.
            time.sleep(0.15)
        with self._lock:
            progress["allResponsesChecked"] = not progress["errors"] and progress["checked"] == progress["total"]
            progress["status"] = "complete" if progress["allResponsesChecked"] and not progress["unavailable"] else "partial"
            progress["completedAt"] = utc_now()
            self._rebuild_indexes()
            artifacts_live = all(self._state.get("artifacts", {}).get(name, {}).get("status") == "live"
                                 for name in (*self.DATA_ENDPOINTS, "zone_mask.v8.bin"))
            self._state["sourceRevisionsConsistent"] = self._source_revisions_consistent()
            self._state["status"] = "live" if artifacts_live and progress["status"] == "complete" and self._state["sourceRevisionsConsistent"] else "live-partial"
            self._state["coverageNote"] = "All source responses checked does not certify complete game coverage; source gaps remain explicit."

    @staticmethod
    def _depth_from_name(name: str) -> str:
        match = re.search(r"\bDepth\s*([0-9]+)\b", name, re.IGNORECASE)
        if match:
            return f"Depth {match.group(1)}"
        lower = name.casefold()
        inland_words = (
            "inland",
            "river",
            "lake",
            "pond",
            "swamp",
            "oasis",
            "reservoir",
            "waterfall",
            "stream",
            "creek",
        )
        if any(word in lower for word in inland_words):
            return "Inland"
        if "coast" in lower or "shore" in lower or "docks" in lower or "wharf" in lower:
            return "Coast"
        return "Unspecified"

    @staticmethod
    def _summarize_facts(
        element: dict[str, Any] | None, fish_by_id: dict[int, dict[str, Any]]
    ) -> dict[str, Any]:
        if not element:
            return {
                "dataKnown": False,
                "hasRelic": None,
                "hasRelicBasis": "unknown",
                "hasRelicByMethod": {"rod": None, "harpoon": None},
                "redSpeciesCount": None,
                "redSpeciesCountByMethod": {"rod": None, "harpoon": None},
                "groupRatesByMethod": {"rod": {}, "harpoon": {}},
                "estimatedValue": None,
                "estimatedValueByMethod": {"rod": None, "harpoon": None},
                "experimentalMoneyByMethod": FishDataRepository._experimental_money_by_method(
                    {"available": False}, fish_by_id
                ),
                "methods": [],
                "items": [],
                "searchTerms": "",
            }

        species_facts: list[dict[str, Any]] = []
        group_rates: dict[str, float] = {}
        for fact in element.get("facts", []):
            if not isinstance(fact, dict) or not isinstance(fact.get("values"), dict):
                continue
            values = fact["values"]
            if fact.get("factId") == "zone.loot.species":
                species_facts.append(values)
            elif fact.get("factId") == "zone.loot.group":
                label = str(values.get("groupLabel") or "")
                rate = _number(values.get("rawRatePercent"))
                if label.strip().casefold() not in {"", "unassigned"} and rate is not None:
                    group_rates[label] = rate

        items: list[dict[str, Any]] = []
        seen: set[tuple[int, str, str]] = set()
        methods: set[str] = set()
        red_ids: set[int] = set()
        red_ids_by_method: dict[str, set[int]] = {"rod": set(), "harpoon": set()}
        group_methods: dict[str, set[str]] = defaultdict(set)
        has_relic = False
        has_relic_by_method = {"rod": False, "harpoon": False}
        expected_value = 0.0
        expected_terms = 0
        expected_value_by_method = {"rod": 0.0, "harpoon": 0.0}
        expected_terms_by_method = {"rod": 0, "harpoon": 0}
        for values in species_facts:
            item_id = _integer(values.get("itemId"))
            if item_id is None:
                continue
            method = str(values.get("catchMethod") or "")
            group = str(values.get("groupLabel") or "")
            assigned_to_table = group.strip().casefold() not in {"", "unassigned"}
            if not assigned_to_table:
                continue
            key = (item_id, method, group)
            if key in seen:
                continue
            seen.add(key)
            if method:
                methods.add(method)
                normalized_method = method.casefold()
                if normalized_method in {"rod", "harpoon"}:
                    group_methods[group].add(normalized_method)
            catalog = fish_by_id.get(item_id, {})
            name = str(values.get("label") or catalog.get("name") or item_id)
            grade = str(values.get("grade") or catalog.get("grade") or "")
            is_fish = str(values.get("isFish", "")).casefold() == "true"
            price = _integer(values.get("priceRaw"))
            if price is None:
                price = _integer(catalog.get("vendor_price"))
            rate = _number(values.get("rawRatePercent"))
            item = {
                "itemId": item_id,
                "name": name,
                "grade": grade or None,
                "group": group or None,
                "isFish": is_fish,
                "method": method or None,
                "price": price,
                "ratePercentWithinGroup": rate,
                "iconUrl": f"/icon/{item_id}.webp",
            }
            items.append(item)
            if item_id == 40218 or name.casefold() == "ancient relic crystal shard":
                has_relic = True
                normalized_method = method.casefold()
                if normalized_method in has_relic_by_method:
                    has_relic_by_method[normalized_method] = True
            if is_fish and grade == "Prize":
                red_ids.add(item_id)
                normalized_method = method.casefold()
                if normalized_method in red_ids_by_method:
                    red_ids_by_method[normalized_method].add(item_id)
            group_rate = group_rates.get(group)
            if group_rate is not None and rate is not None and price is not None:
                contribution = (group_rate / 100.0) * (rate / 100.0) * price
                expected_value += contribution
                expected_terms += 1
                normalized_method = method.casefold()
                if normalized_method in expected_value_by_method:
                    expected_value_by_method[normalized_method] += contribution
                    expected_terms_by_method[normalized_method] += 1

        group_rates_by_method: dict[str, dict[str, float]] = {
            "rod": {},
            "harpoon": {},
        }
        for label, rate in group_rates.items():
            normalized_methods = group_methods.get(label, set()) or _default_pool_methods(label)
            for normalized_method in normalized_methods:
                group_rates_by_method[normalized_method][label] = rate

        items.sort(key=lambda item: (str(item.get("group") or ""), str(item["name"]).casefold()))
        return {
            "dataKnown": bool(items),
            "hasRelic": has_relic if items else None,
            "hasRelicByMethod": has_relic_by_method,
            "hasRelicBasis": (
                "present-in-current-source-table" if has_relic else "absent-from-current-source-table"
            )
            if items
            else "unknown",
            "redSpeciesCount": len(red_ids),
            "redSpeciesCountByMethod": {
                method: len(item_ids) for method, item_ids in red_ids_by_method.items()
            },
            "groupRatesByMethod": group_rates_by_method,
            # A sparse legacy facts export is not a complete probability model.
            # A subtotal of known fish would misrepresent expected money per cast.
            "estimatedValue": None,
            "estimatedValueByMethod": {"rod": None, "harpoon": None},
            "estimatedValueBasis": None,
            "experimentalMoneyByMethod": FishDataRepository._experimental_money_by_method(
                {"available": False}, fish_by_id
            ),
            "methods": sorted(methods),
            "items": items,
            "searchTerms": " ".join(str(item["name"]) for item in items),
        }

    def _load_regions(self) -> list[dict[str, Any]]:
        paths = [
            self.cache_root / "region-nodes.geojson",
            self.snapshot_root / "region-nodes.geojson",
        ]
        document, origin = self._read_json(paths)
        if document is None:
            return []

        canonical = self._json.get("meta.json", {}).get("canonical_map", {})
        left = _number(canonical.get("left"))
        top = _number(canonical.get("top"))
        scale = _number(canonical.get("sector_per_pixel"))
        factor = _number(canonical.get("world_position_factor"))
        if None in {left, top, scale, factor} or scale == 0 or factor == 0:
            return []

        by_name: dict[str, dict[str, Any]] = {}
        for feature in document.get("features", []):
            if not isinstance(feature, dict):
                continue
            properties = feature.get("properties", {})
            geometry = feature.get("geometry", {})
            kind = properties.get("node_type")
            name = properties.get("name")
            coords = geometry.get("coordinates")
            if kind not in {"city", "village"} or not isinstance(name, str):
                continue
            if not isinstance(coords, list) or len(coords) < 2:
                continue
            world_x, world_z = _number(coords[0]), _number(coords[1])
            if world_x is None or world_z is None:
                continue
            x = (world_x / factor - left) / scale
            y = (top - world_z / factor) / scale
            if not (0 <= x < (self.mask.width if self.mask else 11560)):
                continue
            if not (0 <= y < (self.mask.height if self.mask else 10540)):
                continue
            candidate = {"name": name, "x": round(x, 2), "y": round(y, 2), "kind": kind}
            current = by_name.get(name.casefold())
            if current is None or (current["kind"] == "village" and kind == "city"):
                by_name[name.casefold()] = candidate
        return sorted(by_name.values(), key=lambda item: item["name"].casefold())

    def _load_location_nodes(self) -> list[dict[str, Any]]:
        """Load every named FishyStuff Nodes-layer point and resolve its mask zone.

        A node marker is a deterministic map point, not proof that every body of
        water associated with the same node uses that table.  The returned
        resolution basis and confirmation flag preserve that distinction for
        haul entry.
        """

        document, _ = self._read_json(
            [
                self.cache_root / "region-nodes.geojson",
                self.snapshot_root / "region-nodes.geojson",
            ]
        )
        if document is None:
            return []

        canonical = self._json.get("meta.json", {}).get("canonical_map", {})
        left = _number(canonical.get("left"))
        top = _number(canonical.get("top"))
        scale = _number(canonical.get("sector_per_pixel"))
        factor = _number(canonical.get("world_position_factor"))
        if None in {left, top, scale, factor} or scale == 0 or factor == 0:
            return []

        width = self.mask.width if self.mask else int(canonical.get("image_size_x") or 11560)
        height = self.mask.height if self.mask else int(canonical.get("image_size_y") or 10540)
        output: list[dict[str, Any]] = []
        for feature in document.get("features", []):
            if not isinstance(feature, dict):
                continue
            properties = feature.get("properties", {})
            geometry = feature.get("geometry", {})
            if not isinstance(properties, dict) or not isinstance(geometry, dict):
                continue
            if properties.get("kind") != "region_node" or geometry.get("type") != "Point":
                continue
            name = properties.get("name")
            label = properties.get("label")
            coords = geometry.get("coordinates")
            if not isinstance(name, str) or not name.strip():
                continue
            if not isinstance(coords, list) or len(coords) < 2:
                continue
            world_x, world_z = _number(coords[0]), _number(coords[1])
            if world_x is None or world_z is None:
                continue
            x = (world_x / factor - left) / scale
            y = (top - world_z / factor) / scale
            pixel_x, pixel_y = int(math.floor(x)), int(math.floor(y))
            if not (0 <= pixel_x < width and 0 <= pixel_y < height):
                continue

            boundary_candidates: set[str] = set()
            sampled_pixels: list[dict[str, Any]] = []
            if self.mask is not None:
                for sample_y in (pixel_y, min(pixel_y + 1, height - 1)):
                    for sample_x in (pixel_x, min(pixel_x + 1, width - 1)):
                        sampled_rgb = self.mask.lookup(sample_x, sample_y)
                        boundary_candidates.add(sampled_rgb)
                        sampled_pixels.append(
                            {"x": sample_x, "y": sample_y, "rgb": sampled_rgb}
                        )
            candidate_zones: list[dict[str, Any]] = []
            for candidate_rgb in sorted(boundary_candidates):
                candidate_zone = self.zones_by_key.get(candidate_rgb)
                candidate_zones.append(
                    {
                        "rgb": candidate_rgb,
                        "name": candidate_zone.get("name") if candidate_zone else None,
                        "zoneRole": candidate_zone.get("zoneRole") if candidate_zone else None,
                        "active": bool(candidate_zone),
                        "sampledPixelCount": sum(
                            1 for sample in sampled_pixels if sample["rgb"] == candidate_rgb
                        ),
                    }
                )
            zone_ambiguous = len(candidate_zones) > 1
            resolved_candidate = candidate_zones[0] if len(candidate_zones) == 1 else None

            region_id = _integer(properties.get("r"))
            waypoint_id = _integer(properties.get("wp"))
            official_label = str(label or name).strip()
            output.append(
                {
                    "entityType": "location-node",
                    "id": (
                        f"region:{region_id}:waypoint:{waypoint_id}"
                        if region_id is not None or waypoint_id is not None
                        else f"point:{pixel_x}:{pixel_y}:{name.casefold()}"
                    ),
                    "name": name.strip(),
                    "label": official_label,
                    "nodeType": str(properties.get("node_type") or "unknown"),
                    "nodeTypeLabel": str(properties.get("node_type_label") or "Unknown"),
                    "regionId": region_id,
                    "waypointId": waypoint_id,
                    "defaultVisible": bool(properties.get("default_visible")),
                    "x": round(x, 2),
                    "y": round(y, 2),
                    "pixel": {"x": pixel_x, "y": pixel_y},
                    "world": {"x": world_x, "z": world_z},
                    # Never choose a table when the fractional node marker
                    # straddles more than one exact zone-mask pixel value.
                    "zoneRgb": resolved_candidate.get("rgb") if resolved_candidate else None,
                    "zoneName": resolved_candidate.get("name") if resolved_candidate else None,
                    "zoneRole": resolved_candidate.get("zoneRole") if resolved_candidate else None,
                    "zoneActive": bool(resolved_candidate and resolved_candidate.get("active")),
                    "resolutionBasis": "fishystuff-node-marker-through-zone-mask",
                    "ambiguous": zone_ambiguous,
                    "zoneBoundaryAmbiguous": zone_ambiguous,
                    "ambiguousZones": candidate_zones if zone_ambiguous else [],
                    "requiresExactClick": zone_ambiguous or not resolved_candidate,
                    "nearbyZoneRgbs": sorted(boundary_candidates),
                    "sampledPixels": sampled_pixels,
                }
            )

        name_counts: dict[str, int] = defaultdict(int)
        for node in output:
            name_counts[str(node["name"]).casefold()] += 1
        for node in output:
            duplicate_name = name_counts[str(node["name"]).casefold()] > 1
            node["duplicateName"] = duplicate_name
            node["requiresConfirmation"] = bool(
                duplicate_name
                or node["requiresExactClick"]
                or not node["zoneActive"]
                or node["zoneRole"] in {"broad-default", "unknown", "out-of-bounds"}
            )
        return sorted(
            output,
            key=lambda item: (
                str(item["name"]).casefold(),
                item.get("regionId") if item.get("regionId") is not None else -1,
                item.get("waypointId") if item.get("waypointId") is not None else -1,
            ),
        )

    @staticmethod
    def _semantic_entry_name(entry: Any, fact_key: str) -> str | None:
        """Extract a clean FishyStuff territory name from one metadata entry."""

        if not isinstance(entry, dict):
            return None
        for section in entry.get("detailSections", []):
            if not isinstance(section, dict):
                continue
            for fact in section.get("facts", []):
                if not isinstance(fact, dict) or fact.get("key") != fact_key:
                    continue
                value = str(fact.get("value") or "").strip()
                if value:
                    return re.sub(r"\s+\((?:R|RG|N)\d+\)$", "", value).strip() or None
        return None

    def _load_semantic_region_indexes(self) -> None:
        """Load the exact named territory fields already used by the map UI."""

        masks: dict[str, ZoneMask] = {}
        names: dict[str, dict[int, str]] = {}
        descriptors = {
            "regions": ("regions.bin", "regions.meta.json", "region"),
            "region-groups": (
                "region-groups.bin",
                "region-groups.meta.json",
                "resource_group",
            ),
        }
        for layer, (field_name, meta_name, fact_key) in descriptors.items():
            mask = None
            for path in self._cache_paths(self.cache_root / field_name):
                try:
                    mask = ZoneMask(path)
                    break
                except (OSError, ZoneMaskError):
                    continue
            if mask is None:
                continue
            entries = self._json.get(meta_name, {}).get("entries", {})
            if not isinstance(entries, dict):
                continue
            layer_names: dict[int, str] = {}
            for raw_id, entry in entries.items():
                identifier = _integer(raw_id)
                name = self._semantic_entry_name(entry, fact_key)
                if identifier is not None and name:
                    layer_names[identifier] = name
            if layer_names:
                masks[layer] = mask
                names[layer] = layer_names
        self._semantic_region_masks = masks
        self._semantic_region_names = names

    # ------------------------------------------------------------------
    # Public normalized data

    def bootstrap(self) -> dict[str, Any]:
        with self._lock:
            display_revision = _fishing_region_display_revision(self._mask_revision)
            width = self.mask.width if self.mask else int(self.tileset.get("map_size_px", [11560, 10540])[0])
            height = self.mask.height if self.mask else int(self.tileset.get("map_size_px", [11560, 10540])[1])
            canonical = self._json.get("meta.json", {}).get("canonical_map", {})
            levels = []
            for value in self.tileset.get("levels", []):
                if not isinstance(value, dict):
                    continue
                levels.append(
                    {
                        "z": _integer(value.get("z")),
                        "width": _integer(value.get("width")),
                        "height": _integer(value.get("height")),
                        "minX": _integer(value.get("min_x")) or 0,
                        "minY": _integer(value.get("min_y")) or 0,
                    }
                )
            return {
                "map": {
                    "width": width,
                    "height": height,
                    "tileSize": int(self.tileset.get("tile_size_px", 512)),
                    "levels": levels,
                    "exactClickAvailable": self.mask is not None,
                    "worldTransform": {
                        "left": _number(canonical.get("left")),
                        "top": _number(canonical.get("top")),
                        "sectorPerPixel": _number(canonical.get("sector_per_pixel")),
                        "positionFactor": _number(canonical.get("world_position_factor")),
                    },
                },
                "fishingRegionLayer": {
                    "id": "fishing-regions",
                    "name": "Fishing regions",
                    "entityType": "fishing-table-zone-field",
                    "format": "lossless-webp-zone-rgb",
                    "tileUrlTemplate": "/map-layer/fishing-regions/{z}/{x}_{y}.webp?v=" + display_revision,
                    "revision": self._mask_revision,
                    "displayRevision": display_revision,
                    "defaultOpacity": 0.35,
                    "sourceField": "FishyStuff zone_mask.v8.bin",
                    "highlight": {
                        "tileUrlTemplate": (
                            "/map-layer/fishing-regions-highlight/{z}/{x}_{y}.webp?rgb={rgb}&color={color}&v=" + self._mask_revision
                        ),
                        "color": "#30ff60",
                        "defaultOpacity": 0.38,
                    },
                },
                "dataModel": {
                    "fishingTables": "zones",
                    "nearbyEvidence": "ranking-position-clusters",
                    "semanticColoredRegions": "semanticRegionLayers",
                    "namedMapNodes": "locationNodes",
                    "note": (
                        "Fishing-table zones are zone-mask RGB areas, not fishable-water masks. "
                        "Ranking clusters are approximate player positions with a 500 game-unit "
                        "uncertainty ring. Semantic regions and named nodes are separate layers."
                    ),
                },
                "zones": self._zones,
                "fish": self._fish,
                "accuracyAudit": self._accuracy_audit,
                # Preserved for the current frontend: these are only the small
                # city/village label subset, not FishyStuff's coloured Regions
                # field.  New code should use semanticRegionLayers.
                "regions": self._regions,
                "mapLabels": self._regions,
                "semanticRegionLayers": [
                    {
                        "id": "regions",
                        "name": "Regions",
                        "entityType": "semantic-region-field",
                        "format": "FSZLKP01",
                        "fieldUrl": "/map-layer/regions.bin",
                        "metaUrl": "/map-layer/regions.meta.json",
                        "defaultOpacity": 0.35,
                        "sourceVersion": "v7",
                    },
                    {
                        "id": "region-groups",
                        "name": "Region Groups",
                        "entityType": "semantic-region-field",
                        "format": "FSZLKP01",
                        "fieldUrl": "/map-layer/region-groups.bin",
                        "metaUrl": "/map-layer/region-groups.meta.json",
                        "defaultOpacity": 0.35,
                        "sourceVersion": "v7",
                    },
                ],
                "locationNodes": self._location_nodes,
                "source": {
                    **self._state,
                    "name": "FishyStuff",
                    "site": SITE_ROOT,
                    "map": f"{SITE_ROOT}/map/",
                    "api": API_ROOT,
                    "creditRequired": True,
                    "scope": "Fetched directly at runtime into a disposable local cache; redistribution rights are not asserted.",
                },
            }

    def location_at(self, x: int, y: int) -> dict[str, Any] | None:
        """Return the most specific honest place name for an exact map click.

        A nearby named node is useful when the click is genuinely close to its
        marker.  Everywhere else uses FishyStuff's exact semantic Regions field
        at the clicked pixel, so a distant node is never guessed.
        """

        semantic_region: dict[str, Any] | None = None
        for layer in ("regions", "region-groups"):
            mask = self._semantic_region_masks.get(layer)
            layer_names = self._semantic_region_names.get(layer, {})
            if mask is None:
                continue
            try:
                identifier = mask.lookup_u32(x, y)
            except (IndexError, ZoneMaskError):
                continue
            name = layer_names.get(identifier)
            if name:
                semantic_region = {
                    "name": name,
                    "kind": "region" if layer == "regions" else "region-group",
                    "source": f"fishystuff-{layer}-field",
                    "regionId": identifier,
                }
                break

        nearest_node: dict[str, Any] | None = None
        nearest_distance_squared: float | None = None
        for node in self._location_nodes:
            node_x = _number(node.get("x"))
            node_y = _number(node.get("y"))
            if node_x is None or node_y is None:
                continue
            distance_squared = (node_x - x) ** 2 + (node_y - y) ** 2
            if nearest_distance_squared is None or distance_squared < nearest_distance_squared:
                nearest_node = node
                nearest_distance_squared = distance_squared

        if (
            nearest_node is not None
            and nearest_distance_squared is not None
            and nearest_distance_squared <= LOCATION_NODE_SNAP_RADIUS_PX**2
        ):
            return {
                "name": nearest_node["name"],
                "label": nearest_node.get("label") or nearest_node["name"],
                "kind": "node",
                "source": "nearest-fishystuff-node",
                "distancePixels": round(math.sqrt(nearest_distance_squared), 2),
                "node": {
                    "id": nearest_node.get("id"),
                    "name": nearest_node["name"],
                    "label": nearest_node.get("label") or nearest_node["name"],
                    "nodeType": nearest_node.get("nodeType"),
                    "nodeTypeLabel": nearest_node.get("nodeTypeLabel"),
                    "x": nearest_node.get("x"),
                    "y": nearest_node.get("y"),
                },
                "semanticRegion": semantic_region,
            }
        return semantic_region

    def zone_at(self, x: int, y: int) -> dict[str, Any]:
        if self.mask is None:
            raise DataUnavailable("Exact zone lookup is unavailable")
        rgb = self.mask.lookup(x, y)
        zone = self.zones_by_key.get(rgb)
        location = self.location_at(x, y)
        if location is None and zone is not None:
            location = {
                "name": zone["name"],
                "kind": "fishing-table",
                "source": "fishing-table-fallback",
            }
        return {
            "coordinate": {"x": x, "y": y},
            "resolutionBasis": "fishystuff-zone-mask-pixel",
            "rgb": rgb,
            "zone": zone,
            "location": location,
        }

    def resolve_location(self, query: str) -> dict[str, Any]:
        """Resolve an exact FishyStuff node name/label without unsafe guessing."""

        cleaned = str(query or "").strip()
        if not cleaned:
            raise ValueError("A FishyStuff node name is required")
        key = cleaned.casefold()
        matches = self._location_nodes_by_label.get(key) or self._location_nodes_by_name.get(key) or []
        if not matches:
            return {"status": "not-found", "query": cleaned, "matches": []}
        if len(matches) > 1:
            return {
                "status": "ambiguous",
                "query": cleaned,
                "matches": matches,
                "note": "Choose the exact FishyStuff node/region label before saving the haul.",
            }
        location = matches[0]
        return {
            "status": "resolved",
            "query": cleaned,
            "location": location,
            "aggregation": {
                "displayLocationName": location["name"],
                "zoneRgb": location.get("zoneRgb"),
                "zoneName": location.get("zoneName"),
                "ambiguous": location.get("ambiguous", False),
                "ambiguousZones": location.get("ambiguousZones", []),
                "basis": location["resolutionBasis"],
                "requiresConfirmation": location["requiresConfirmation"],
                "requiresExactClick": location.get("requiresExactClick", False),
            },
        }

    def semantic_region_asset(self, layer: str, asset: str) -> bytes:
        """Return only allow-listed canonical FishyStuff semantic-layer assets."""

        descriptor = self.SEMANTIC_REGION_ASSETS.get((layer, asset))
        if descriptor is None:
            raise ValueError("Unknown semantic map-layer asset")
        cache_name, url = descriptor
        cache_path = self.cache_root / cache_name
        try:
            return self._read_cache_bytes(cache_path)
        except OSError:
            payload = self._fetch_bytes(url, timeout=25)
            _atomic_write(cache_path, payload)
            return payload

    def catalog_item(self, item_id: int) -> dict[str, Any] | None:
        record = self.fish_by_id.get(item_id)
        if not record:
            return None
        return {
            "itemId": item_id,
            "name": record.get("name"),
            "grade": record.get("grade"),
            "price": _integer(record.get("vendor_price")),
            "iconUrl": f"/icon/{item_id}.webp",
        }

    # ------------------------------------------------------------------
    # Zone detail, tiles, and faithful local icon enhancement

    @staticmethod
    def _safe_rgb_filename(rgb: str) -> str:
        packed = rgb_key_to_u32(rgb)
        return f"{packed:06x}.json"

    def zone_detail(self, rgb: str, method: str | None = None) -> dict[str, Any]:
        rgb = rgb_u32_to_key(rgb_key_to_u32(rgb))
        cache_path = self.cache_root / "zone-details" / self._safe_rgb_filename(rgb)
        payload, _ = self._read_json(self._cache_paths(cache_path))
        source_status = "current-cache" if payload is not None and self._detail_is_current(payload) else "cache"
        request_body = json.dumps({"rgb": rgb, "userOverlay": None}, separators=(",", ":")).encode("utf-8")
        if source_status != "current-cache":
            try:
                raw = self._fetch_bytes(
                    f"{API_ROOT}/api/v1/zone_loot_summary?lang=en&locale=en-US",
                    timeout=18, body=request_body,
                )
                parsed = json.loads(raw.decode("utf-8"))
                if not isinstance(parsed, dict) or not isinstance(parsed.get("available"), bool):
                    raise ValueError("summary lacks explicit availability")
                if parsed.get("available") and not isinstance(parsed.get("speciesRows"), list):
                    raise ValueError("available summary lacks species rows")
                payload = self._cache_detail(cache_path, parsed)
                source_status = "live"
            except (DataUnavailable, UnicodeDecodeError, json.JSONDecodeError, ValueError, OSError):
                source_status = "cache"

        if payload is None:
            payload = self._facts_detail_fallback(rgb)
            source_status = "facts-fallback"

        if payload is not None:
            summary = self._summarize_detail(payload, self.fish_by_id)
            with self._lock:
                if summary["dataKnown"]:
                    self._collect_icon_paths(payload, self.icon_paths_by_item)
                zone = self.zones_by_key.get(rgb)
                if zone is not None:
                    zone.update(summary)
                    receipt = self._detail_receipt(payload)
                    zone["tableSource"] = {
                        "kind": "zone-loot-summary" if source_status != "facts-fallback" else "zone-loot-facts",
                        "status": "current" if self._detail_is_current(payload) else "stale-or-partial",
                        "revision": receipt.get("sourceRevision"), "retrievedAt": receipt.get("retrievedAt"),
                        "available": payload.get("available"), "note": payload.get("dataQualityNote") or payload.get("note"),
                    }
                    zone["tableRecommendationEligible"] = bool(
                        summary["dataKnown"] and zone.get("zoneRole") == "named-table"
                    )

        result = dict(payload)
        expanded_rows = self._detail_rows(result)
        species_rows = [row for row in expanded_rows if self._row_has_assignment(row)]
        result["excludedSourceRows"] = [row for row in expanded_rows if not self._row_has_assignment(row)]
        groups = [dict(group) for group in result.get("groups", []) if isinstance(group, dict)]
        for group in groups:
            if group.get("conditionOptions"):
                group["normalizedDropRateState"] = "conditional"
                group["normalizedDropRateText"] = "Unknown"
        for row in species_rows:
            row["hasConditions"] = bool(row.get("conditionId") or row.get("conditionText"))
            if not row.get("catchMethods"):
                row["catchMethods"] = row.get("methods") or ([row["catchMethod"]] if row.get("catchMethod") else self.fish_by_id.get(_integer(row.get("itemId")), {}).get("catch_methods", []))
        normalized_method = method if method in {"rod", "harpoon"} else None
        if normalized_method:
            species_rows = [
                row
                for row in species_rows
                if not row.get("catchMethods") or normalized_method in row.get("catchMethods", [])
            ]
            groups = [
                group
                for group in groups
                if not group.get("catchMethods") or normalized_method in group.get("catchMethods", [])
            ]
        for row in species_rows:
            item_id = _integer(row.get("itemId"))
            if item_id is not None:
                row["localIconUrl"] = f"/icon/{item_id}.webp"
                catalog = self.fish_by_id.get(item_id, {})
                catalog_grade = str(catalog.get("grade") or "").strip()
                if not str(row.get("grade") or "").strip() and catalog_grade:
                    # zone_loot_summary deliberately leaves grade null on a
                    # number of rows even though the canonical fish catalog has
                    # it.  Enrich the presentation field without changing any
                    # group/rate provenance from the table response.
                    row["grade"] = catalog_grade
                    row["gradeSource"] = "fish-catalog"
                if not str(row.get("iconGradeTone") or "").strip() and catalog_grade:
                    row["iconGradeTone"] = _grade_tone(catalog_grade)
        result["speciesRows"] = species_rows
        result["groups"] = groups
        result["accuracyNotes"] = self.zones_by_key.get(rgb, {}).get("accuracyNotes", [])
        result["companionSource"] = {
            "provider": "FishyStuff",
            "status": source_status,
            "retrievedAt": self._detail_receipt(payload).get("retrievedAt"),
            "sourceRevision": self._detail_receipt(payload).get("sourceRevision"),
            "map": f"{SITE_ROOT}/map/",
        }
        return result

    def _facts_detail_fallback(self, rgb: str) -> dict[str, Any]:
        packed = rgb_key_to_u32(rgb)
        document = self._json.get("zone-loot-facts.json", {})
        target_id = f"zone:0x{packed:06x}"
        element = next(
            (
                value
                for value in document.get("elements", [])
                if isinstance(value, dict) and str(value.get("elementId", "")).casefold() == target_id
            ),
            None,
        )
        zone = self.zones_by_key.get(rgb)
        if not element:
            return {
                "available": False,
                "zoneName": zone.get("name") if zone else rgb,
                "dataQualityNote": "No cached source table is available for this exact zone while offline.",
                "groups": [],
                "speciesRows": [],
            }

        groups: list[dict[str, Any]] = []
        species: list[dict[str, Any]] = []
        group_methods: dict[str, set[str]] = defaultdict(set)
        group_values: list[dict[str, Any]] = []
        for fact in element.get("facts", []):
            if not isinstance(fact, dict) or not isinstance(fact.get("values"), dict):
                continue
            values = fact["values"]
            if fact.get("factId") == "zone.loot.species":
                item_id = _integer(values.get("itemId"))
                if item_id is None:
                    continue
                method = str(values.get("catchMethod") or "")
                label = str(values.get("groupLabel") or "Unassigned")
                if method:
                    group_methods[label].add(method)
                rate = _number(values.get("rawRatePercent"))
                price = _number(values.get("priceRaw"))
                species.append(
                    {
                        "slotIdx": _integer(values.get("slotIdx")) or 0,
                        "itemId": item_id,
                        "groupLabel": label,
                        "label": str(values.get("label") or item_id),
                        "iconUrl": f"{CDN_ROOT}/images/items/{item_id:08d}.webp",
                        "localIconUrl": f"/icon/{item_id}.webp",
                        "iconGradeTone": _grade_tone(str(values.get("grade") or "")),
                        "isFish": str(values.get("isFish", "")).casefold() == "true",
                        "priceRaw": price,
                        "priceText": f"{int(price):,}" if price is not None else "Unknown",
                        "rawDropRateText": _format_percent(rate),
                        "rawDropRateState": "known" if rate is not None else "unknown",
                        "normalizedDropRateText": _format_percent(rate),
                        "normalizedDropRateState": "known" if rate is not None else "unknown",
                        "catchMethods": [method] if method else [],
                    }
                )
            elif fact.get("factId") == "zone.loot.group":
                group_values.append(values)
        for values in group_values:
            label = str(values.get("groupLabel") or "Unassigned")
            rate = _number(values.get("rawRatePercent"))
            groups.append(
                {
                    "slotIdx": _integer(values.get("slotIdx")) or 0,
                    "label": label,
                    "rawDropRateText": _format_percent(rate),
                    "rawDropRateState": "known" if rate is not None else "unknown",
                    "normalizedDropRateText": _format_percent(rate),
                    "normalizedDropRateState": "known" if rate is not None else "unknown",
                    "catchMethods": sorted(group_methods.get(label, set())),
                }
            )
        return {
            "available": bool(species),
            "zoneName": zone.get("name") if zone else element.get("label", rgb),
            "dataQualityNote": (
                "Offline fallback from the FishyStuff zone-loot facts snapshot. "
                "Only facts present in that source are shown."
            ),
            "groups": groups,
            "speciesRows": species,
        }

    def tile_bytes(self, z: int, x: int, y: int) -> bytes:
        level = next(
            (entry for entry in self.tileset.get("levels", []) if _integer(entry.get("z")) == z),
            None,
        )
        if not isinstance(level, dict):
            raise ValueError("Unknown map zoom level")
        width, height = _integer(level.get("width")), _integer(level.get("height"))
        if width is None or height is None or not (0 <= x < width and 0 <= y < height):
            raise ValueError("Map tile coordinate is outside this zoom level")

        cache_path = self.cache_root / "tiles" / str(z) / f"{x}_{y}.webp"
        try:
            return self._read_cache_bytes(cache_path)
        except OSError:
            pass
        payload = self._fetch_bytes(
            f"{CDN_ROOT}/images/tiles/minimap_visual/v5/{z}/{x}_{y}.webp", timeout=20
        )
        _atomic_write(cache_path, payload)
        return payload

    def fishing_region_tile_bytes(
        self,
        z: int,
        x: int,
        y: int,
        *,
        highlight_rgb: str | None = None,
        highlight_color: str | None = None,
    ) -> bytes:
        """Render one lossless tile directly from FishyStuff's exact zone mask.

        Normal tiles retain source colours except for out-of-bounds and the
        near-white Other Regions terrain-default fill, which stay transparent.
        This is display-only: exact lookup and selected-RGB highlighting still
        use every original mask pixel. Opacity is left to the frontend.
        """

        # Refresh replaces the mask and its revision together. Hold one snapshot
        # for the entire tile so neither pixels nor the cache key can mix sources.
        with self._lock:
            mask = self.mask
            mask_revision = self._mask_revision
            tileset = self.tileset
        if mask is None:
            raise DataUnavailable("Fishing-region overlay is unavailable")
        level = next(
            (entry for entry in tileset.get("levels", []) if _integer(entry.get("z")) == z),
            None,
        )
        if not isinstance(level, dict) or z < 0 or z > 20:
            raise ValueError("Unknown map zoom level")
        level_width, level_height = _integer(level.get("width")), _integer(level.get("height"))
        if (
            level_width is None
            or level_height is None
            or not (0 <= x < level_width and 0 <= y < level_height)
        ):
            raise ValueError("Map tile coordinate is outside this zoom level")

        tile_size = int(tileset.get("tile_size_px", 512))
        scale = 1 << z
        expected_width = math.ceil(mask.width / (tile_size * scale))
        expected_height = math.ceil(mask.height / (tile_size * scale))
        if (level_width, level_height) != (expected_width, expected_height):
            raise DataUnavailable("Fishing-region overlay does not match the active minimap pyramid")

        highlight_packed: int | None = None
        highlight_hex = "30ff60"
        if highlight_rgb is not None:
            highlight_packed = rgb_key_to_u32(highlight_rgb)
            candidate_color = str(highlight_color or "").strip().lstrip("#").lower()
            if candidate_color:
                if not re.fullmatch(r"[0-9a-f]{6}", candidate_color):
                    raise ValueError("Invalid fishing-region highlight colour")
                highlight_hex = candidate_color
            cache_path = (
                self.cache_root
                / "fishing-region-highlights"
                / mask_revision
                / f"{highlight_packed:06x}-{highlight_hex}"
                / str(z)
                / f"{x}_{y}.webp"
            )
        else:
            cache_path = (
                self.cache_root
                / "fishing-region-tiles"
                / _fishing_region_display_revision(mask_revision)
                / str(z)
                / f"{x}_{y}.webp"
            )
        try:
            return self._read_cache_bytes(cache_path)
        except OSError:
            pass

        rgba = bytearray(tile_size * tile_size * 4)
        source_left = x * tile_size * scale
        source_top = y * tile_size * scale
        highlight_rgba = (
            int(highlight_hex[0:2], 16),
            int(highlight_hex[2:4], 16),
            int(highlight_hex[4:6], 16),
            0xFF,
        )
        for destination_y in range(tile_size):
            source_y = source_top + destination_y * scale
            if source_y >= mask.height:
                break
            row_offset = destination_y * tile_size * 4
            for destination_x in range(tile_size):
                source_x = source_left + destination_x * scale
                if source_x >= mask.width:
                    break
                packed = mask.lookup_u32(source_x, source_y)
                offset = row_offset + destination_x * 4
                if highlight_packed is not None:
                    if packed == highlight_packed:
                        rgba[offset : offset + 4] = bytes(highlight_rgba)
                    continue
                if packed in FISHING_REGION_DISPLAY_TRANSPARENT_RGB:
                    continue
                rgba[offset] = (packed >> 16) & 0xFF
                rgba[offset + 1] = (packed >> 8) & 0xFF
                rgba[offset + 2] = packed & 0xFF
                rgba[offset + 3] = 0xFF

        try:
            from PIL import Image

            image = Image.frombytes("RGBA", (tile_size, tile_size), bytes(rgba))
            buffer = io.BytesIO()
            image.save(buffer, format="WEBP", lossless=True, method=6, exact=True)
            payload = buffer.getvalue()
        except (ImportError, OSError, ValueError) as exc:
            raise DataUnavailable("Fishing-region overlay tile could not be rendered") from exc
        _atomic_write(cache_path, payload)
        return payload

    def icon_bytes(self, item_id: int) -> bytes:
        if item_id <= 0 or item_id > 99_999_999:
            raise ValueError("Invalid item id")
        output = self.cache_root / "icons-4x" / f"{item_id:08d}.webp"
        try:
            return self._read_cache_bytes(output)
        except OSError:
            pass

        record = self.fish_by_id.get(item_id, {})
        icon_source_id = ICON_ITEM_ALIASES.get(item_id, item_id)
        icon_path = str(
            self.icon_paths_by_item.get(item_id)
            or record.get("icon_image")
            or f"/images/items/{icon_source_id:08d}.webp"
        )
        raw_cache = self.cache_root / "icons-original" / Path(icon_path).name
        try:
            raw = self._read_cache_bytes(raw_cache)
        except OSError:
            local_icon = self.recognizer_icon_root / f"{item_id:08d}.webp"
            try:
                raw = local_icon.read_bytes()
            except OSError:
                raw = self._fetch_bytes(f"{CDN_ROOT}{icon_path}", timeout=15)
                _atomic_write(raw_cache, raw)

        # This is a deterministic, faithful resample: no generative redraw, no
        # invented features, and no palette substitution.  A light unsharp mask
        # only restores edge contrast softened by the 4x Lanczos interpolation.
        try:
            from PIL import Image, ImageFilter

            with Image.open(io.BytesIO(raw)) as image:
                source = image.convert("RGBA")
                enlarged = source.resize((source.width * 4, source.height * 4), Image.Resampling.LANCZOS)
                alpha = enlarged.getchannel("A")
                rgb = enlarged.convert("RGB").filter(
                    ImageFilter.UnsharpMask(radius=0.8, percent=55, threshold=3)
                )
                enhanced = rgb.convert("RGBA")
                enhanced.putalpha(alpha)
                buffer = io.BytesIO()
                enhanced.save(buffer, format="WEBP", lossless=True, method=6, exact=True)
                payload = buffer.getvalue()
        except (ImportError, OSError, ValueError) as exc:
            raise DataUnavailable("The original icon could not be rendered faithfully") from exc
        _atomic_write(output, payload)
        return payload
