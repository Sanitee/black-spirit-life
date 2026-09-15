from __future__ import annotations

import hashlib
import json
import shutil
import sys
import tempfile
import threading
import unittest
from datetime import datetime as SystemDateTime
from datetime import timedelta, timezone
from pathlib import Path
from unittest import mock


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
PAYLOAD_ROOT = PACKAGE_ROOT / "assets" / "fish_companion"
sys.path.insert(0, str(PAYLOAD_ROOT))

import backend.data as data_module  # noqa: E402
from backend.data import (  # noqa: E402
    DERIVED_INDEX_ALGORITHM_CONTRACT,
    DERIVED_INDEX_CACHE_NAME,
    DERIVED_INDEX_CACHE_SCHEMA_VERSION,
    RUNTIME_SNAPSHOT_CRITICAL_PATHS,
    RUNTIME_SNAPSHOT_RECEIPT_NAME,
    RUNTIME_SNAPSHOT_RECEIPT_SCHEMA_VERSION,
    SOURCE_REFRESH_SECONDS,
    FishDataRepository,
)


SOURCE_FILES = (
    "fish.json",
    "zone-loot-facts.json",
    "zones.json",
    "meta.json",
    "tileset.json",
    "zone_mask.v8.bin",
    "zone-evidence-points.json",
    "regions.bin",
    "regions.meta.json",
    "region-groups.bin",
    "region-groups.meta.json",
    "region-nodes.geojson",
)


def normalized(value: object) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def fixed_datetime(now: SystemDateTime) -> type[SystemDateTime]:
    class FixedDateTime(SystemDateTime):
        @classmethod
        def now(cls, tz: object = None) -> SystemDateTime:
            if tz is None:
                return now.replace(tzinfo=None)
            return now.astimezone(tz)

    return FixedDateTime


class DerivedIndexCacheTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory(
            prefix="fish-derived-index-test-"
        )
        self.root = Path(self._temporary.name) / "fish-companion"
        shutil.copytree(PAYLOAD_ROOT / "backend", self.root / "backend")
        cache = self.root / "data" / "cache"
        cache.mkdir(parents=True)
        source_cache = PAYLOAD_ROOT / "data" / "cache"
        for name in SOURCE_FILES:
            shutil.copy2(source_cache / name, cache / name)
        shutil.copytree(source_cache / "zone-details", cache / "zone-details")

    def tearDown(self) -> None:
        self._temporary.cleanup()

    def test_cached_and_uncached_bootstrap_are_exactly_equal(self) -> None:
        uncached = FishDataRepository(self.root)
        uncached_output = normalized(uncached.bootstrap())
        cache_path = uncached.cache_root / DERIVED_INDEX_CACHE_NAME

        self.assertTrue(cache_path.is_file())
        document = json.loads(cache_path.read_text(encoding="utf-8"))
        self.assertEqual(
            document["schemaVersion"], DERIVED_INDEX_CACHE_SCHEMA_VERSION
        )
        self.assertEqual(
            document["payloadSha256"],
            hashlib.sha256(normalized(document["payload"]).encode("utf-8")).hexdigest(),
        )
        self.assertEqual(len(document["algorithmFingerprint"]), 64)
        self.assertEqual(len(document["sourceFingerprint"]), 64)
        self.assertTrue(DERIVED_INDEX_ALGORITHM_CONTRACT)

        with mock.patch.object(
            FishDataRepository,
            "_rebuild_indexes",
            side_effect=AssertionError("a valid derived cache must skip rebuilding"),
        ):
            cached = FishDataRepository(self.root)

        self.assertEqual(normalized(cached.bootstrap()), uncached_output)

    def test_runtime_snapshot_receipt_hashes_one_coherent_cache(self) -> None:
        repository = FishDataRepository(self.root)
        receipt_path = repository.cache_root / RUNTIME_SNAPSHOT_RECEIPT_NAME
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))

        self.assertEqual(
            receipt["schemaVersion"], RUNTIME_SNAPSHOT_RECEIPT_SCHEMA_VERSION
        )
        records = receipt["files"]
        self.assertEqual(
            [record["path"] for record in records],
            sorted(RUNTIME_SNAPSHOT_CRITICAL_PATHS),
        )
        for record in records:
            payload = (self.root / record["path"]).read_bytes()
            self.assertEqual(record["byteCount"], len(payload))
            self.assertEqual(record["sha256"], hashlib.sha256(payload).hexdigest())
        self.assertEqual(
            receipt["snapshotSha256"],
            repository._runtime_snapshot_digest(records),
        )

    def test_invalid_cache_fingerprints_rebuild_and_replace_atomically(self) -> None:
        initial = FishDataRepository(self.root)
        cache_path = initial.cache_root / DERIVED_INDEX_CACHE_NAME
        original_rebuild = FishDataRepository._rebuild_indexes

        def assert_rebuild_after(mutator: object) -> None:
            document = json.loads(cache_path.read_text(encoding="utf-8"))
            mutator(document)
            cache_path.write_text(normalized(document), encoding="utf-8")
            rebuild_count = 0

            def counted_rebuild(repository: FishDataRepository) -> None:
                nonlocal rebuild_count
                rebuild_count += 1
                original_rebuild(repository)

            with mock.patch.object(
                FishDataRepository,
                "_rebuild_indexes",
                autospec=True,
                side_effect=counted_rebuild,
            ):
                FishDataRepository(self.root)
            self.assertEqual(rebuild_count, 1)
            replacement = json.loads(cache_path.read_text(encoding="utf-8"))
            self.assertEqual(
                replacement["schemaVersion"], DERIVED_INDEX_CACHE_SCHEMA_VERSION
            )
            self.assertNotEqual(replacement["algorithmFingerprint"], "invalid")
            self.assertNotEqual(replacement["sourceFingerprint"], "invalid")

        assert_rebuild_after(
            lambda document: document.__setitem__("schemaVersion", -1)
        )
        assert_rebuild_after(
            lambda document: document.__setitem__(
                "algorithmFingerprint", "invalid"
            )
        )
        assert_rebuild_after(
            lambda document: document.__setitem__("sourceFingerprint", "invalid")
        )

        cache_path.write_bytes(b"{not-json")
        with mock.patch.object(
            FishDataRepository,
            "_rebuild_indexes",
            autospec=True,
            wraps=original_rebuild,
        ) as rebuild:
            recovered = FishDataRepository(self.root)
        self.assertEqual(rebuild.call_count, 1)
        self.assertEqual(
            normalized(recovered.bootstrap()), normalized(initial.bootstrap())
        )
        self.assertFalse(any(cache_path.parent.glob(f"{cache_path.name}.*.part")))

    def test_cached_detail_freshness_is_rederived_after_expiry(self) -> None:
        detail_path = next(
            iter(sorted((self.root / "data" / "cache" / "zone-details").glob("*.json")))
        )
        detail = json.loads(detail_path.read_text(encoding="utf-8"))
        retrieved_at = SystemDateTime.fromisoformat(
            detail["companionCache"]["retrievedAt"].replace("Z", "+00:00")
        )
        current_time = retrieved_at + timedelta(minutes=1)
        expired_time = retrieved_at + timedelta(
            seconds=SOURCE_REFRESH_SECONDS + 1
        )
        zone_rgb = int(detail_path.stem, 16)

        with mock.patch.object(
            data_module, "datetime", fixed_datetime(current_time)
        ):
            fresh = FishDataRepository(self.root)
        fresh_zone = next(
            zone for zone in fresh._zones if zone.get("rgbU32") == zone_rgb
        )
        self.assertEqual(fresh_zone["tableSource"]["status"], "current")

        with (
            mock.patch.object(
                data_module, "datetime", fixed_datetime(expired_time)
            ),
            mock.patch.object(
                FishDataRepository,
                "_rebuild_indexes",
                side_effect=AssertionError(
                    "wall-clock expiry must not require a static index rebuild"
                ),
            ),
        ):
            cached = FishDataRepository(self.root)
        cached_zone = next(
            zone for zone in cached._zones if zone.get("rgbU32") == zone_rgb
        )
        self.assertEqual(
            cached_zone["tableSource"]["status"], "stale-or-unversioned"
        )

        cached_output = normalized(cached.bootstrap())
        (cached.cache_root / DERIVED_INDEX_CACHE_NAME).unlink()
        with mock.patch.object(
            data_module, "datetime", fixed_datetime(expired_time)
        ):
            rebuilt = FishDataRepository(self.root)
        self.assertEqual(normalized(rebuilt.bootstrap()), cached_output)

    def test_source_change_during_serialization_keeps_last_good_cache(self) -> None:
        repository = FishDataRepository(self.root)
        cache_path = repository.cache_root / DERIVED_INDEX_CACHE_NAME
        receipt_path = repository.cache_root / RUNTIME_SNAPSHOT_RECEIPT_NAME
        last_good = cache_path.read_bytes()
        last_good_receipt = receipt_path.read_bytes()

        with mock.patch.object(
            repository,
            "_derived_index_source_fingerprint",
            side_effect=("source-before", "source-after"),
        ):
            repository._write_derived_index_cache(
                expected_source_fingerprint="source-before"
            )

        self.assertEqual(cache_path.read_bytes(), last_good)
        self.assertEqual(receipt_path.read_bytes(), last_good_receipt)


class BackgroundRefreshStartTest(unittest.TestCase):
    def test_start_is_idempotent(self) -> None:
        repository = object.__new__(FishDataRepository)
        repository._background_refresh_lock = threading.Lock()
        repository._background_refresh_started = False

        with mock.patch("backend.data.threading.Thread") as thread:
            self.assertTrue(repository.start_background_refresh())
            self.assertFalse(repository.start_background_refresh())

        thread.assert_called_once()
        thread.return_value.start.assert_called_once()


if __name__ == "__main__":
    unittest.main()
