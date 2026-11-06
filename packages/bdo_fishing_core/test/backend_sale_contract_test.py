"""Synthetic-only checks for journal facts, estimates and recorded sales."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "assets/fish_companion"))
from backend.store import (  # noqa: E402
    SessionStore, SessionValidationError, _auto_fishing_delay,
    _auto_fishing_reduction_from_delay, _bargain_bonus_percent,
)


def payload(**changes):
    value = {"zoneRgb": "1,2,3", "zoneName": "Synthetic test water",
             "locationName": "Synthetic town", "method": "rod", "style": "afk",
             "mastery": 1682, "catches": [{"itemId": 1, "count": 2}]}
    value.update(changes)
    return value


def lookup(item_id):
    return {"name": "Synthetic fish", "grade": "Rare", "price": 1000} if item_id == 1 else None


class SaleContractTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="bsl-sale-contract-")
        self.store = SessionStore(Path(self.scratch.name) / "journal.sqlite3")

    def tearDown(self):
        self.scratch.cleanup()

    def test_incomplete_trading_level_has_no_invented_bonus(self):
        for rank, level in [(None, None), ("Guru", None), (None, 100)]:
            with self.subTest(rank=rank, level=level):
                self.assertEqual(_bargain_bonus_percent(rank, level), 0)
                if (rank is None) != (level is None):
                    with self.assertRaisesRegex(SessionValidationError, "must be saved together"):
                        self.store.create(payload(tradingRank=rank, tradingLevel=level), lookup)
                else:
                    saved = self.store.create(payload(tradingRank=rank, tradingLevel=level), lookup)
                    self.assertEqual(saved["bargainBonusPercent"], 0)
                    self.assertEqual(self.store.get(saved["id"])["bargainBonusPercent"], 0)

    def test_existing_rank_boundaries_match_the_ui_contract(self):
        for rank, level, bonus in [("Beginner", 1, 5.5), ("Apprentice", 10, 15),
                                   ("Skilled", 10, 20), ("Professional", 1, 20.5),
                                   ("Artisan", 10, 30), ("Master", 30, 45),
                                   ("Guru", 1, 45.5), ("Guru", 100, 95)]:
            with self.subTest(rank=rank, level=level):
                self.assertEqual(_bargain_bonus_percent(rank, level), bonus)

    def test_timer_is_wait_after_bite_not_a_full_cycle_prediction(self):
        self.assertIsNone(_auto_fishing_delay(None))
        for reduction, delay in [(0, 180), (30, 126), (66.67, 60)]:
            with self.subTest(reduction=reduction):
                self.assertEqual(_auto_fishing_delay(reduction), delay)
                self.assertAlmostEqual(_auto_fishing_reduction_from_delay(delay), reduction, places=2)

    def test_actual_sale_survives_profile_and_haul_edits(self):
        created = self.store.create(payload(tradingRank="Master", tradingLevel=1), lookup)
        for bonus in [0, 12.5, 50]:
            self.store.record_sale(created["id"], {
                "destination": "Historical custom trader", "finalAmount": 4321,
                "bargainBonusPercent": bonus, "distanceBonusPercent": 123.4,
                "marketPercent": 90, "soldAt": "2026-11-01T12:00:00Z",
            })
            self.store.update(created["id"], payload(tradingRank="Guru", tradingLevel=100), lookup)
            saved = self.store.get(created["id"])
            self.assertEqual(saved["bargainBonusPercent"], 95)
            self.assertEqual(saved["sale"]["bargainBonusPercent"], bonus)
            self.assertEqual(saved["sale"]["destination"], "Historical custom trader")
            self.assertEqual(saved["sale"]["finalAmount"], 4321)
            self.assertEqual(saved["totalValue"], 2000)

    def test_estimate_is_never_recorded_as_actual_without_input(self):
        created = self.store.create(payload(), lookup)
        for value in [None, 0, -1]:
            with self.subTest(value=value), self.assertRaises(SessionValidationError):
                self.store.record_sale(created["id"], {"destination": "Test", "finalAmount": value})
        self.assertIsNone(self.store.get(created["id"])["sale"])

    def test_unknown_duration_does_not_dilute_or_inflate_hourly_rates(self):
        self.store.create(payload(durationMinutes=60), lookup)
        self.store.create(payload(catches=[{"itemId": 1, "count": 100}]), lookup)
        stats = self.store.stats({})["totals"]
        self.assertEqual(stats["fish"], 102)
        self.assertEqual(stats["durationSessions"], 1)
        self.assertEqual(stats["fishPerHour"], 2)
        self.assertEqual(stats["valuePerHour"], 2000)

    def test_unknown_price_never_becomes_a_complete_value(self):
        for price in [None, 0]:
            with self.subTest(price=price):
                catches = [{"itemId": 1, "count": 2},
                           {"itemId": 2, "name": "Unknown test fish", "count": 3,
                            "unitPrice": price}]
                saved = self.store.create(payload(catches=catches, durationMinutes=60), lookup)
                for result in [saved, self.store.get(saved["id"]), self.store.list({})[0]]:
                    self.assertEqual(result["totalValue"], 2000)  # Original storage contract.
                    self.assertEqual(result["knownValue"], 2000)
                    self.assertEqual(result["unknownPriceFish"], 3)
                    self.assertFalse(result["valueComplete"])
                    self.assertIsNone(result["baseValue"])
                self.store.record_sale(saved["id"], {"destination": "Actual trader",
                                       "finalAmount": 4321, "bargainBonusPercent": 0})
                self.assertEqual(self.store.get(saved["id"])["sale"]["finalAmount"], 4321)
                stats = self.store.stats({})
                self.assertIsNone(stats["totals"]["value"])
                self.assertIsNone(stats["totals"]["valuePerHour"])
                self.assertEqual(stats["totals"]["fishPerHour"], 5)
                spot = stats["spots"][0]
                self.assertIsNone(spot["totalValue"])
                self.assertIsNone(spot["averageValuePer100"])
                self.assertIsNone(spot["valuePerHour"])
                self.assertEqual(spot["fishPerHour"], 5)
                self.assertEqual(sum(i["count"] for i in spot["items"]), stats["totals"]["fish"])

    def test_untimed_unknown_prices_do_not_poison_known_timed_values(self):
        self.store.create(payload(durationMinutes=60), lookup)
        self.store.create(payload(catches=[{"itemId": 2, "name": "Unknown fish",
                                           "count": 3, "price": 0}]), lookup)
        stats = self.store.stats({})
        self.assertIsNone(stats["totals"]["value"])
        self.assertEqual(stats["totals"]["knownValue"], 2000)
        self.assertEqual(stats["totals"]["unknownPriceFish"], 3)
        self.assertEqual(stats["totals"]["valuePerHour"], 2000)
        self.assertEqual(stats["spots"][0]["valuePerHour"], 2000)

    def test_read_only_value_projection_does_not_rewrite_saved_history(self):
        saved = self.store.create(payload(catches=[{"itemId": 2, "name": "Unknown fish",
                                                   "count": 3, "price": 0}]), lookup)
        self.store.record_sale(saved["id"], {"destination": "Actual trader", "finalAmount": 99})
        database = Path(self.scratch.name) / "journal.sqlite3"
        before = database.read_bytes()
        self.store.get(saved["id"])
        self.store.list({})
        self.store.stats({})
        self.assertEqual(database.read_bytes(), before)

    def test_empty_stats_remain_zero_and_known_hauls_keep_exact_values(self):
        empty = self.store.stats({})["totals"]
        self.assertEqual(empty["value"], 0)
        self.assertEqual(empty["unknownPriceFish"], 0)
        saved = self.store.create(payload(durationMinutes=60), lookup)
        self.assertTrue(saved["valueComplete"])
        self.assertEqual(saved["baseValue"], 2000)
        self.assertEqual(self.store.stats({})["spots"][0]["averageValuePer100"], 100000)


if __name__ == "__main__":
    unittest.main()
