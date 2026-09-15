#!/usr/bin/env python3
"""Focused regressions for conflict and indistinguishable-icon integrity."""

from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

import recognize_fish_tank as recognizer


GEOMETRY = recognizer.GridGeometry(
    x_starts=(0, 45, 90, 135, 180, 225, 270, 315),
    y_starts=(0,),
    scrollbar_fraction=0.0,
    logical_row_offset=0,
)


FULL_TANK_ROW_ITEMS = (
    (1001, "Footballfish"),
    (1004, "Nibbler"),
    (1004, "Nibbler"),
    (1004, "Nibbler"),
    (1003, "Blue Bat Star"),
    (1003, "Blue Bat Star"),
    (1002, "Yellow Corvina"),
    (1004, "Nibbler"),
    (1003, "Blue Bat Star"),
    (1003, "Blue Bat Star"),
    (1004, "Nibbler"),
    (1001, "Footballfish"),
    (1004, "Nibbler"),
    (1002, "Yellow Corvina"),
    (1004, "Nibbler"),
    (1002, "Yellow Corvina"),
)


class SyntheticCatalog:
    """Resolve the deterministic item-color markers in a synthetic tank."""

    def __init__(self, items_by_red: dict[int, tuple[int, str]]) -> None:
        self.items_by_red = items_by_red

    def match(self, slot_rgb: np.ndarray) -> recognizer.IconMatch:
        marker = int(np.median(slot_rgb[2:43, 2:43, 0]))
        item_id, name = self.items_by_red[marker]
        return match(item_id, name)


def two_full_row_tank() -> tuple[np.ndarray, SyntheticCatalog]:
    """Build two occupied grade-border rows over five neutral empty rows."""

    frame = np.full((520, 500, 3), (22, 22, 24), dtype=np.uint8)
    x_starts = tuple(20 + column * 54 for column in range(8))
    y_starts = tuple(70 + row * 54 for row in range(7))
    marker_by_item = {
        1001: 90,
        1002: 120,
        1003: 150,
        1004: 180,
    }
    items_by_red = {
        marker_by_item[item_id]: (item_id, name)
        for item_id, name in FULL_TANK_ROW_ITEMS
    }

    for slot, (item_id, _name) in enumerate(FULL_TANK_ROW_ITEMS):
        row, column = divmod(slot, 8)
        x = x_starts[column]
        y = y_starts[row]
        frame[y - 1, x : x + 45] = (230, 40, 80)
        frame[y + 43, x : x + 45] = (230, 40, 80)
        frame[y + 1 : y + 42, x + 2 : x + 43] = (
            marker_by_item[item_id],
            20,
            30,
        )

    for y in y_starts[2:]:
        for x in x_starts:
            frame[y, x + 1 : x + 45] = (60, 60, 60)
            frame[y + 44, x + 1 : x + 45] = (60, 60, 60)

    return frame, SyntheticCatalog(items_by_red)


def match(
    item_id: int,
    name: str,
    *,
    verified: bool = True,
    score: float = 0.95,
    candidates: tuple[tuple[int, str], ...] = (),
) -> recognizer.IconMatch:
    return recognizer.IconMatch(
        item_id=item_id,
        name=name,
        similarity_score=score,
        runner_up_gap=0.1,
        verified=verified,
        identity_candidates=candidates,
    )


class RecognitionIntegrityTests(unittest.TestCase):
    def test_full_colored_rows_are_detected_and_duplicate_frames_are_deduplicated(
        self,
    ) -> None:
        frame, catalog = two_full_row_tank()

        result = recognizer.recognize_images(
            [frame, frame.copy(), frame.copy()], catalog
        )

        self.assertEqual(result["tank"]["observedCount"], 16)
        self.assertEqual(result["tank"]["displayCount"], "16/100")
        self.assertEqual(result["review"]["status"], "verified")
        self.assertEqual(
            {catch["name"]: catch["count"] for catch in result["catches"]},
            {
                "Footballfish": 2,
                "Yellow Corvina": 3,
                "Blue Bat Star": 4,
                "Nibbler": 7,
            },
        )
        self.assertEqual(result["scan"]["duplicateCatchObservationsSuppressed"], 32)
        self.assertEqual(result["scan"]["uniqueSlotsObserved"], 56)
        self.assertEqual(
            [frame_result["occupiedSlots"] for frame_result in result["scan"]["frames"]],
            [16, 16, 16],
        )

    def test_conflicting_overlap_never_counts_as_verified(self) -> None:
        first = recognizer.SlotObservation(0, match(100, "First"))
        second = recognizer.SlotObservation(0, match(200, "Second", score=0.96))
        with patch.object(
            recognizer,
            "observe_frame",
            side_effect=[(GEOMETRY, [first], 8), (GEOMETRY, [second], 8)],
        ):
            result = recognizer.recognize_images(
                [np.zeros((1, 1, 3)), np.zeros((1, 1, 3))], object()
            )

        self.assertEqual(result["review"]["status"], "needs-review")
        self.assertEqual(result["review"]["verifiedCatchSlots"], 0)
        self.assertEqual(result["review"]["uncertainCatchSlots"], 1)
        self.assertEqual(result["review"]["conflictingCatchSlots"], 1)
        self.assertEqual(result["scan"]["conflictingSlotObservations"], 1)
        self.assertEqual(result["scan"]["conflictingLogicalSlots"], 1)
        self.assertFalse(result["catches"][0]["allSlotsVerified"])
        self.assertEqual(result["catches"][0]["conflictingSlotCount"], 1)

    def test_ambiguous_artwork_requires_review_and_exposes_candidates(self) -> None:
        candidates = ((8307, "Mako Shark"), (8477, "Blue Shark"))
        observation = recognizer.SlotObservation(
            0,
            match(
                8307,
                "Mako Shark / Blue Shark",
                verified=False,
                candidates=candidates,
            ),
        )
        with patch.object(
            recognizer, "observe_frame", return_value=(GEOMETRY, [observation], 8)
        ):
            result = recognizer.recognize_images([np.zeros((1, 1, 3))], object())

        catch = result["catches"][0]
        self.assertEqual(result["review"]["status"], "needs-review")
        self.assertEqual(result["review"]["ambiguousIdentityCatchSlots"], 1)
        self.assertEqual(catch["identityStatus"], "ambiguous")
        self.assertIsNone(catch["resolvedItemId"])
        self.assertFalse(catch["allSlotsVerified"])
        self.assertEqual(
            {row["itemId"] for row in catch["candidateItems"]}, {8307, 8477}
        )

    def test_catalog_groups_known_indistinguishable_artwork(self) -> None:
        catalog = recognizer.IconCatalog(Path(__file__).parent / "reference-icons")
        self.assertEqual(
            set(catalog.candidates_for_item(8227)),
            {(8227, "Swordfish"), (8324, "Yellow Swordfish")},
        )
        self.assertEqual(
            set(catalog.candidates_for_item(8307)),
            {(8307, "Mako Shark"), (8477, "Blue Shark")},
        )
        self.assertEqual(
            set(catalog.candidates_for_item(8431)),
            {(8236, "Mullet"), (8431, "Balenos Mullet")},
        )

    def test_new_red_fish_have_verified_local_references(self) -> None:
        import hashlib
        import json
        root = Path(__file__).parent / "reference-icons"
        manifest = json.loads((root / "catalog.json").read_text(encoding="utf-8"))
        indexed = {entry["itemId"]: entry for entry in manifest["items"]}
        for item_id, name in ((821373, "Edania Gar"), (821374, "Cano Toadfish")):
            entry = indexed[item_id]
            self.assertEqual(entry["name"], name)
            self.assertEqual(hashlib.sha256((root / entry["file"]).read_bytes()).hexdigest(), entry["sha256"])


if __name__ == "__main__":
    unittest.main()
