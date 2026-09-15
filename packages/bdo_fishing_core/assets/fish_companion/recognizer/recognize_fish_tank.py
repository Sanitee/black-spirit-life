#!/usr/bin/env python3
"""Local-only recognizer for BDO Miraculous Fish Tank screenshots.

Runtime privacy invariant:
  * input images are decoded into memory only;
  * no input path/filename, screenshot, thumbnail, or crop is emitted or saved;
  * the runtime performs no network requests;
  * only structured catch data is printed or optionally written.

This is a concrete proof-of-concept for the current 8-column, 100-slot tank UI.
It deliberately fails closed when grid geometry or an icon match is uncertain.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np
from PIL import Image


TOOL_VERSION = "0.3.0"
PROFILE_ID = "miraculous-fish-tank-100"
CAPACITY = 100
COLUMNS = 8
CELL_SIZE = 45
CELL_PITCH_Y = 54
REFERENCE_BG = np.array([22.0, 22.0, 24.0], dtype=np.float32)
TEMPLATE_SIZES = (39, 40, 41, 42, 43)


class RecognitionError(RuntimeError):
    """Raised when a screenshot cannot be handled safely."""


@dataclass(frozen=True)
class GridGeometry:
    x_starts: tuple[int, ...]
    y_starts: tuple[int, ...]
    scrollbar_fraction: float
    logical_row_offset: int


@dataclass(frozen=True)
class IconMatch:
    item_id: int
    name: str
    similarity_score: float
    runner_up_gap: float
    verified: bool
    # Pixel confidence before resolving game items that share one template.
    # A caller may promote an ambiguous identity only when exact spot/method
    # context leaves one candidate and this visual-group check also passed.
    visual_group_verified: bool = False
    # Multiple game items can deliberately reuse exactly the same artwork.
    # Keep the legacy representative item_id/name fields above, but expose all
    # identities that the pixels could mean so callers never have to guess.
    identity_candidates: tuple[tuple[int, str], ...] = ()


@dataclass(frozen=True)
class SlotObservation:
    logical_slot: int
    match: IconMatch


def _runs(values: Iterable[int]) -> list[tuple[int, int]]:
    ordered = list(values)
    if not ordered:
        return []
    result: list[tuple[int, int]] = []
    start = previous = int(ordered[0])
    for value in ordered[1:]:
        value = int(value)
        if value != previous + 1:
            result.append((start, previous))
            start = value
        previous = value
    result.append((start, previous))
    return result


def _neutral_border_mask(rgb: np.ndarray) -> np.ndarray:
    minimum = rgb.min(axis=2)
    maximum = rgb.max(axis=2)
    mean = rgb.mean(axis=2)
    return (maximum - minimum <= 5) & (mean >= 50) & (mean <= 70)


def _colored_border_mask(rgb: np.ndarray) -> np.ndarray:
    """Return pixels belonging to saturated item-grade slot outlines."""

    minimum = rgb.min(axis=2).astype(np.int16)
    maximum = rgb.max(axis=2).astype(np.int16)
    return (maximum - minimum >= 12) & (maximum >= 70)


def _slot_line_runs(mask_row: np.ndarray) -> list[tuple[int, int]]:
    candidates = _runs(np.flatnonzero(mask_row))
    return [run for run in candidates if 42 <= run[1] - run[0] + 1 <= 46]


def _matching_top_runs(
    line_rows: dict[int, list[tuple[int, int]]], y: int
) -> list[tuple[int, int]]:
    """Keep horizontal slot lines that have a matching lower border."""

    top = line_rows.get(y, [])
    best: list[tuple[int, int]] = []
    for delta in (42, 43, 44):
        bottom = line_rows.get(y + delta, [])
        matched = [
            run
            for run in top
            if any(
                abs(run[0] - candidate[0]) <= 2 and abs(run[1] - candidate[1]) <= 2
                for candidate in bottom
            )
        ]
        if len(matched) > len(best):
            best = matched
    return best


def _longest_column_sequence(values: Iterable[int]) -> list[int]:
    candidates = sorted(set(int(value) for value in values))
    candidate_set = set(candidates)
    best: list[int] = []
    for start in candidates:
        chain = [start]
        current = start
        while True:
            next_value = next(
                (current + delta for delta in (52, 53, 54, 55, 56) if current + delta in candidate_set),
                None,
            )
            if next_value is None:
                break
            chain.append(next_value)
            current = next_value
        if len(chain) > len(best):
            best = chain
    return best


def _longest_top_sequence(top_candidates: Sequence[int]) -> list[int]:
    candidates = sorted(set(int(value) for value in top_candidates))
    candidate_set = set(candidates)
    best: list[int] = []
    for start in candidates:
        chain = [start]
        current = start
        while True:
            next_value = next(
                (current + delta for delta in (53, 54, 55) if current + delta in candidate_set),
                None,
            )
            if next_value is None:
                break
            chain.append(next_value)
            current = next_value
        if len(chain) > len(best):
            best = chain
    return best


def _detect_scrollbar_fraction(rgb: np.ndarray, geometry_rows: Sequence[int]) -> float:
    if not geometry_rows:
        return 0.0
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    tan = (
        (red >= 150)
        & (green >= 90)
        & (green <= 220)
        & (blue <= 160)
        & (red - green >= 20)
        & (green - blue >= 20)
    )
    right_edge = tan[:, max(0, rgb.shape[1] - 25) :].sum(axis=1)
    runs = [run for run in _runs(np.flatnonzero(right_edge >= 3)) if run[1] - run[0] + 1 >= 20]
    if not runs:
        return 0.0
    thumb_top, thumb_bottom = max(runs, key=lambda run: run[1] - run[0])
    track_top = int(geometry_rows[0])
    track_bottom = int(geometry_rows[-1] + CELL_SIZE - 1)
    thumb_length = thumb_bottom - thumb_top + 1
    travel = (track_bottom - track_top + 1) - thumb_length
    if travel <= 0:
        return 0.0
    return float(np.clip((thumb_top - track_top) / travel, 0.0, 1.0))


def detect_grid(rgb: np.ndarray) -> GridGeometry:
    if rgb.ndim != 3 or rgb.shape[2] != 3:
        raise RecognitionError("Expected an RGB screenshot")
    if rgb.shape[0] < 300 or rgb.shape[1] < 300:
        raise RecognitionError("Screenshot is too small for the tank profile")

    neutral = _neutral_border_mask(rgb)
    colored = _colored_border_mask(rgb)
    neutral_rows: dict[int, list[tuple[int, int]]] = {}
    colored_rows: dict[int, list[tuple[int, int]]] = {}
    for y in range(45, max(45, rgb.shape[0] - 40)):
        neutral_runs = _slot_line_runs(neutral[y])
        colored_runs = _slot_line_runs(colored[y])
        if neutral_runs:
            neutral_rows[y] = neutral_runs
        if colored_runs:
            colored_rows[y] = colored_runs

    # Empty slots expose neutral borders at the crop's y coordinate. Occupied
    # slots replace that frame with a colored grade border one pixel above it.
    # Normalize both kinds of evidence to the same logical cell origin so full
    # rows are first-class grid evidence rather than an afterthought.
    row_columns: dict[int, set[int]] = {}
    for y in neutral_rows:
        for run in _matching_top_runs(neutral_rows, y):
            row_columns.setdefault(y, set()).add(run[0] - 1)
    for y in colored_rows:
        logical_y = y + 1
        for run in _matching_top_runs(colored_rows, y):
            row_columns.setdefault(logical_y, set()).add(run[0])

    sequence = _longest_top_sequence(sorted(row_columns))
    if len(sequence) < 5:
        raise RecognitionError("Could not find a stable Fish Tank slot grid")

    pitch = int(round(float(np.median(np.diff(sequence))))) if len(sequence) > 1 else CELL_PITCH_Y
    if pitch not in (53, 54, 55):
        raise RecognitionError(f"Unexpected slot-row pitch: {pitch}")

    column_sequences = [_longest_column_sequence(row_columns.get(y, set())) for y in sequence]
    columns = max(column_sequences, key=len, default=[])
    if len(columns) < COLUMNS:
        raise RecognitionError("Could not locate all eight Fish Tank columns")
    x_starts = tuple(columns[:COLUMNS])

    if any(x < 0 or x + CELL_SIZE > rgb.shape[1] for x in x_starts):
        raise RecognitionError("Detected slot grid extends outside screenshot")
    if any(y < 0 or y + CELL_SIZE > rgb.shape[0] for y in sequence):
        raise RecognitionError("Detected slot row extends outside screenshot")

    scroll_fraction = _detect_scrollbar_fraction(rgb, sequence)
    total_rows = math.ceil(CAPACITY / COLUMNS)
    max_offset = max(0, total_rows - len(sequence))
    logical_offset = int(round(scroll_fraction * max_offset))
    return GridGeometry(
        x_starts=x_starts,
        y_starts=tuple(sequence),
        scrollbar_fraction=scroll_fraction,
        logical_row_offset=logical_offset,
    )


class IconCatalog:
    def __init__(self, reference_dir: Path):
        manifest_path = reference_dir / "catalog.json"
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise RecognitionError("Local icon reference catalog is unavailable") from exc

        entries = manifest.get("items", [])
        if len(entries) < 250:
            raise RecognitionError("Local icon reference catalog is incomplete")

        self.entries: list[tuple[int, str]] = []
        entry_candidates: list[tuple[tuple[int, str], ...]] = []
        artwork_fingerprints: list[tuple[tuple[int, int], bytes]] = []
        variants: list[np.ndarray] = []
        for entry in entries:
            icon_path = reference_dir / str(entry["file"])
            try:
                with Image.open(icon_path) as image:
                    source = image.convert("RGBA")
                    fingerprint = (
                        source.size,
                        hashlib.sha256(source.tobytes()).digest(),
                    )
                    item_variants = [self._render(source, size) for size in TEMPLATE_SIZES]
            except OSError as exc:
                raise RecognitionError("A local icon reference is unreadable") from exc
            item_id, name = int(entry["itemId"]), str(entry["name"])
            self.entries.append((item_id, name))
            raw_candidates = entry.get("visualCandidates")
            if not isinstance(raw_candidates, list):
                raw_candidates = [{"itemId": item_id, "name": name}]
            candidates: list[tuple[int, str]] = []
            for candidate in raw_candidates:
                if not isinstance(candidate, dict):
                    continue
                try:
                    candidate_id = int(candidate["itemId"])
                    candidate_name = str(candidate["name"]).strip()
                except (KeyError, TypeError, ValueError):
                    continue
                identity = (candidate_id, candidate_name)
                if candidate_id > 0 and candidate_name and identity not in candidates:
                    candidates.append(identity)
            if (item_id, name) not in candidates:
                candidates.insert(0, (item_id, name))
            entry_candidates.append(tuple(candidates))
            artwork_fingerprints.append(fingerprint)
            variants.extend(item_variants)

        # Collapse byte-for-byte decoded artwork before calculating the
        # runner-up gap. Two identical icons are one visual answer with several
        # possible identities, not two visually distinct model predictions.
        grouped_indices: dict[tuple[tuple[int, int], bytes], list[int]] = {}
        for index, fingerprint in enumerate(artwork_fingerprints):
            grouped_indices.setdefault(fingerprint, []).append(index)
        self.artwork_groups = tuple(tuple(indices) for indices in grouped_indices.values())
        group_candidates: list[tuple[tuple[int, str], ...]] = []
        self._candidates_by_item: dict[int, tuple[tuple[int, str], ...]] = {}
        for indices in self.artwork_groups:
            combined: list[tuple[int, str]] = []
            for index in indices:
                for candidate in entry_candidates[index]:
                    if candidate not in combined:
                        combined.append(candidate)
            identities = tuple(combined)
            group_candidates.append(identities)
            for index in indices:
                self._candidates_by_item[self.entries[index][0]] = identities
            for candidate_id, _ in identities:
                self._candidates_by_item[candidate_id] = identities
        self.group_candidates = tuple(group_candidates)

        self.variant_pixels = np.stack(variants).astype(np.float32, copy=False)
        self.variant_sq_sum = np.einsum(
            "ij,ij->i", self.variant_pixels, self.variant_pixels, optimize=True
        )
        centered = self.variant_pixels - self.variant_pixels.mean(axis=1, keepdims=True)
        norms = np.linalg.norm(centered, axis=1, keepdims=True)
        self.variant_normalized = centered / np.maximum(norms, 1e-6)

    def candidates_for_item(self, item_id: int) -> tuple[tuple[int, str], ...]:
        """Return identities sharing an item's indistinguishable artwork."""

        return self._candidates_by_item.get(int(item_id), ())

    @staticmethod
    def _render(source: Image.Image, size: int) -> np.ndarray:
        resized = np.asarray(
            source.resize((size, size), Image.Resampling.LANCZOS), dtype=np.float32
        )
        offset = (CELL_SIZE - size) // 2
        rendered = np.empty((CELL_SIZE, CELL_SIZE, 3), dtype=np.float32)
        rendered[:] = REFERENCE_BG
        alpha = resized[:, :, 3:4] / 255.0
        target = rendered[offset : offset + size, offset : offset + size]
        target[:] = resized[:, :, :3] * alpha + target * (1.0 - alpha)
        return rendered[1:44, 1:44].reshape(-1)

    def match(self, slot_rgb: np.ndarray) -> IconMatch:
        target = slot_rgb[1:44, 1:44].astype(np.float32, copy=False).reshape(-1)
        target_centered = target - target.mean()
        target_normalized = target_centered / max(float(np.linalg.norm(target_centered)), 1e-6)
        correlation = self.variant_normalized @ target_normalized

        target_sq = float(target @ target)
        squared_error = np.maximum(
            self.variant_sq_sum - 2.0 * (self.variant_pixels @ target) + target_sq,
            0.0,
        )
        rmse = np.sqrt(squared_error / target.size)
        variant_score = rmse / 255.0 + (1.0 - correlation) * 0.3
        item_score = variant_score.reshape(len(self.entries), len(TEMPLATE_SIZES)).min(axis=1)
        group_score = np.asarray(
            [min(float(item_score[index]) for index in indices) for indices in self.artwork_groups],
            dtype=np.float32,
        )
        order = np.argsort(group_score)
        best_group, second_group = int(order[0]), int(order[1])
        best = float(group_score[best_group])
        second = float(group_score[second_group])
        indices = self.artwork_groups[best_group]
        best_index = min(indices, key=lambda index: (float(item_score[index]), index))
        item_id, name = self.entries[best_index]
        candidates = self.group_candidates[best_group]
        if len(candidates) > 1:
            name = " / ".join(candidate_name for _, candidate_name in candidates)
        gap = max(0.0, second - best)
        visual_group_verified = best <= 0.20 and gap >= 0.08
        verified = visual_group_verified and len(candidates) == 1
        return IconMatch(
            item_id=item_id,
            name=name,
            similarity_score=round(max(0.0, 1.0 - best), 6),
            runner_up_gap=round(gap, 6),
            verified=verified,
            visual_group_verified=visual_group_verified,
            identity_candidates=candidates,
        )


def _is_occupied(slot_rgb: np.ndarray) -> bool:
    interior = slot_rgb[2:43, 2:43].astype(np.float32, copy=False)
    return float(interior.std()) >= 10.0


def _colored_outline_above(rgb: np.ndarray, x: int, y: int) -> bool:
    if y <= 0:
        return False
    row = rgb[y - 1, x : x + CELL_SIZE]
    saturation = row.max(axis=1).astype(np.int16) - row.min(axis=1).astype(np.int16)
    return float(np.mean((saturation >= 12) & (row.max(axis=1) >= 70))) >= 0.50


def observe_frame(rgb: np.ndarray, catalog: IconCatalog) -> tuple[GridGeometry, list[SlotObservation], int]:
    geometry = detect_grid(rgb)
    observations: list[SlotObservation] = []
    observed_slot_count = 0

    for local_row, y in enumerate(geometry.y_starts):
        logical_row = geometry.logical_row_offset + local_row
        for column, x in enumerate(geometry.x_starts):
            logical_slot = logical_row * COLUMNS + column
            if logical_slot >= CAPACITY:
                continue
            observed_slot_count += 1
            crop_y = y - 1 if _colored_outline_above(rgb, x, y) else y
            slot = rgb[crop_y : crop_y + CELL_SIZE, x : x + CELL_SIZE]
            if slot.shape != (CELL_SIZE, CELL_SIZE, 3):
                raise RecognitionError("A detected slot is clipped")
            if not _is_occupied(slot):
                continue
            match = catalog.match(slot)
            observations.append(SlotObservation(logical_slot=logical_slot, match=match))
    return geometry, observations, observed_slot_count


def recognize_images(images: Sequence[np.ndarray], catalog: IconCatalog) -> dict[str, object]:
    if not images:
        raise RecognitionError("At least one screenshot is required")

    unique_slots_seen: set[int] = set()
    catches_by_slot: dict[int, IconMatch] = {}
    duplicate_catches_suppressed = 0
    conflicting_observations = 0
    conflicting_slots: set[int] = set()
    frame_results: list[dict[str, object]] = []

    for frame_index, rgb in enumerate(images, start=1):
        geometry, observations, observed_slots = observe_frame(rgb, catalog)
        frame_slot_ids: set[int] = set()
        for local_row in range(len(geometry.y_starts)):
            logical_row = geometry.logical_row_offset + local_row
            for column in range(COLUMNS):
                logical_slot = logical_row * COLUMNS + column
                if logical_slot < CAPACITY:
                    frame_slot_ids.add(logical_slot)
        overlap = len(unique_slots_seen & frame_slot_ids)
        unique_slots_seen.update(frame_slot_ids)

        for observation in observations:
            existing = catches_by_slot.get(observation.logical_slot)
            if existing is None:
                catches_by_slot[observation.logical_slot] = observation.match
            elif existing.item_id == observation.match.item_id:
                duplicate_catches_suppressed += 1
                if observation.match.similarity_score > existing.similarity_score:
                    catches_by_slot[observation.logical_slot] = observation.match
            else:
                conflicting_observations += 1
                conflicting_slots.add(observation.logical_slot)
                # Retain the stronger observation as the review suggestion,
                # while the logical slot itself remains unverified regardless
                # of either match's individual confidence.
                if observation.match.similarity_score > existing.similarity_score:
                    catches_by_slot[observation.logical_slot] = observation.match

        frame_results.append(
            {
                "frame": frame_index,
                "scrollFraction": round(geometry.scrollbar_fraction, 6),
                "logicalRowOffset": geometry.logical_row_offset,
                "visibleRows": len(geometry.y_starts),
                "observedSlots": observed_slots,
                "occupiedSlots": len(observations),
                "overlapWithEarlierFrames": overlap,
            }
        )

    counts = Counter(match.item_id for match in catches_by_slot.values())
    exemplar = {match.item_id: match for match in catches_by_slot.values()}
    catches = [
        {
            "itemId": item_id,
            "name": exemplar[item_id].name,
            "count": counts[item_id],
            "minimumSimilarityScore": min(
                match.similarity_score
                for match in catches_by_slot.values()
                if match.item_id == item_id
            ),
            "allSlotsVerified": all(
                match.verified and slot not in conflicting_slots
                for slot, match in catches_by_slot.items()
                if match.item_id == item_id
            ),
            "conflictingSlotCount": sum(
                slot in conflicting_slots
                for slot, match in catches_by_slot.items()
                if match.item_id == item_id
            ),
            "visualTemplateVerified": all(
                match.visual_group_verified and slot not in conflicting_slots
                for slot, match in catches_by_slot.items()
                if match.item_id == item_id
            ),
            "identityStatus": (
                "ambiguous"
                if len(exemplar[item_id].identity_candidates) > 1
                else "identified"
            ),
            "candidateItems": [
                {"itemId": candidate_id, "name": candidate_name}
                for candidate_id, candidate_name in (
                    exemplar[item_id].identity_candidates
                    or ((exemplar[item_id].item_id, exemplar[item_id].name),)
                )
            ],
            "resolvedItemId": (
                item_id if len(exemplar[item_id].identity_candidates) <= 1 else None
            ),
            "resolvedName": (
                exemplar[item_id].name
                if len(exemplar[item_id].identity_candidates) <= 1
                else None
            ),
            # For ambiguous identities, itemId remains this stable visual
            # template ID for backwards compatibility. candidateItems is the
            # authoritative set until spot/method context resolves it.
            "visualTemplateItemId": item_id,
        }
        for item_id in sorted(counts, key=lambda value: exemplar[value].name.casefold())
    ]
    observed_count = sum(counts.values())
    uncertain = sum(
        (not match.verified) or slot in conflicting_slots
        for slot, match in catches_by_slot.items()
    )
    ambiguous_identity_slots = sum(
        len(match.identity_candidates) > 1 for match in catches_by_slot.values()
    )

    return {
        "schemaVersion": 1,
        "recognizerVersion": TOOL_VERSION,
        "privacy": {
            "runtimeNetworkRequests": 0,
            "screenshotsOrCropsSaved": 0,
            "inputPathsPersisted": False,
            "outputContainsStructuredCatchDataOnly": True,
        },
        "tank": {
            "profile": PROFILE_ID,
            "displayCount": f"{observed_count}/{CAPACITY}",
            "observedCount": observed_count,
            "capacity": CAPACITY,
            "countSource": "deduplicated occupied slots",
            "capacitySource": "selected Miraculous Fish Tank profile",
            "headerOcrUsed": False,
        },
        "scan": {
            "frames": frame_results,
            "uniqueSlotsObserved": len(unique_slots_seen),
            "completeTankCoverage": len(unique_slots_seen) == CAPACITY,
            "duplicateCatchObservationsSuppressed": duplicate_catches_suppressed,
            "conflictingSlotObservations": conflicting_observations,
            "conflictingLogicalSlots": len(conflicting_slots),
        },
        "review": {
            "status": "verified" if uncertain == 0 and conflicting_observations == 0 else "needs-review",
            "verifiedCatchSlots": observed_count - uncertain,
            "uncertainCatchSlots": uncertain,
            "conflictingCatchSlots": len(conflicting_slots),
            "ambiguousIdentityCatchSlots": ambiguous_identity_slots,
        },
        "catches": catches,
    }


def _load_rgb(path: Path) -> np.ndarray:
    try:
        with Image.open(path) as image:
            return np.asarray(image.convert("RGB"), dtype=np.uint8)
    except OSError as exc:
        raise RecognitionError("An input screenshot could not be decoded") from exc


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Recognize and deduplicate a local sequence of Miraculous Fish Tank screenshots."
    )
    parser.add_argument("screenshots", nargs="+", type=Path)
    parser.add_argument(
        "--reference-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "reference-icons",
    )
    parser.add_argument(
        "--result",
        type=Path,
        help="Optional path for structured JSON only; screenshots are never copied.",
    )
    args = parser.parse_args()

    try:
        catalog = IconCatalog(args.reference_dir)
        images = [_load_rgb(path) for path in args.screenshots]
        result = recognize_images(images, catalog)
    except RecognitionError as exc:
        print(json.dumps({"status": "error", "message": str(exc)}), file=sys.stderr)
        return 2

    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.result:
        args.result.write_text(encoded, encoding="utf-8")
    else:
        sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
