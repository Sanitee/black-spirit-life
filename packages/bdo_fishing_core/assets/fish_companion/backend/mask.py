"""Reader for FishyStuff's compact FSZLKP01 zone lookup artifact.

The artifact is a row-oriented run-length encoding.  Every row owns a slice
of the shared ``x_ends`` and ``rgb_values`` arrays; the first x-end strictly
greater than a pixel's x coordinate identifies its zone RGB value.

This module intentionally only reads the artifact.  It does not alter or
attempt to reinterpret FishyStuff's curated zone assignments.
"""

from __future__ import annotations

import array
import bisect
import hashlib
import json
import struct
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


MAGIC = b"FSZLKP01"
HEADER = struct.Struct("<8sHHHHI")
LINEAGE_MAGIC = b"FSLINE01"
LINEAGE_HEADER = struct.Struct("<8sII")


class ZoneMaskError(RuntimeError):
    """Raised when a lookup artifact is missing or malformed."""


def extract_zone_lookup(payload: bytes) -> bytes:
    """Return the current FSZLKP01 field from a public lineage artifact.

    FishyStuff's current endpoint wraps the exact lookup field in an
    FSLINE01 envelope. Older cached fields are already bare FSZLKP01 bytes.
    The wrapper lengths and published lineage-field digest are verified before
    any bytes are accepted.
    """

    if payload.startswith(MAGIC):
        return payload
    if len(payload) < LINEAGE_HEADER.size:
        raise ZoneMaskError("Zone lineage artifact is truncated")
    magic, manifest_length, lookup_length = LINEAGE_HEADER.unpack_from(payload)
    if magic != LINEAGE_MAGIC:
        raise ZoneMaskError("Zone lineage artifact has an unknown format")
    manifest_start = LINEAGE_HEADER.size
    lookup_start = manifest_start + manifest_length
    if lookup_start > len(payload) or lookup_start + lookup_length != len(payload):
        raise ZoneMaskError("Zone lineage artifact has an invalid length")
    try:
        manifest = json.loads(
            payload[manifest_start:lookup_start].decode("utf-8")
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ZoneMaskError("Zone lineage manifest is invalid") from exc
    if not isinstance(manifest, dict) or manifest.get("schemaVersion") != 1:
        raise ZoneMaskError("Zone lineage manifest has an unsupported schema")
    lookup = payload[lookup_start:]
    if not lookup.startswith(MAGIC):
        raise ZoneMaskError("Zone lineage artifact contains no zone lookup")
    expected = manifest.get("lineageFieldSha256")
    if not isinstance(expected, str) or hashlib.sha256(lookup).hexdigest() != expected:
        raise ZoneMaskError("Zone lineage field failed integrity verification")
    return lookup


def rgb_u32_to_key(value: int) -> str:
    """Return FishyStuff's canonical ``r,g,b`` key for a packed RGB value."""

    return f"{(value >> 16) & 255},{(value >> 8) & 255},{value & 255}"


def rgb_key_to_u32(value: str) -> int:
    """Parse a strict ``r,g,b`` key into the packed RGB value used by the mask."""

    parts = value.split(",")
    if len(parts) != 3:
        raise ValueError("RGB must use r,g,b notation")
    channels = [int(part.strip()) for part in parts]
    if any(channel < 0 or channel > 255 for channel in channels):
        raise ValueError("RGB channels must be between 0 and 255")
    return (channels[0] << 16) | (channels[1] << 8) | channels[2]


@dataclass(frozen=True)
class ZonePoint:
    x: int
    y: int


class ZoneMask:
    """Memory-efficient exact pixel lookup for an FSZLKP01 artifact."""

    def __init__(self, path: Path):
        self.path = path
        try:
            payload = path.read_bytes()
        except OSError as exc:
            raise ZoneMaskError("Zone lookup artifact is unavailable") from exc

        if len(payload) < HEADER.size:
            raise ZoneMaskError("Zone lookup artifact is truncated")
        magic, width, height, row_offset_count, reserved, span_count = HEADER.unpack_from(payload)
        if magic != MAGIC:
            raise ZoneMaskError("Zone lookup artifact has an unknown format")
        if reserved != 0 or row_offset_count != height + 1:
            raise ZoneMaskError("Zone lookup artifact has an invalid header")

        offsets_start = HEADER.size
        offsets_end = offsets_start + row_offset_count * 4
        ends_end = offsets_end + span_count * 2
        colors_end = ends_end + span_count * 4
        if colors_end != len(payload):
            raise ZoneMaskError("Zone lookup artifact has an invalid length")

        self.width = int(width)
        self.height = int(height)
        self.span_count = int(span_count)
        self._row_offsets = self._read_array("I", payload[offsets_start:offsets_end])
        self._x_ends = self._read_array("H", payload[offsets_end:ends_end])
        self._rgb_values = self._read_array("I", payload[ends_end:colors_end])

        if self._row_offsets[0] != 0 or self._row_offsets[-1] != span_count:
            raise ZoneMaskError("Zone lookup row index is invalid")
        for y in range(self.height):
            first = self._row_offsets[y]
            last = self._row_offsets[y + 1]
            if first >= last or self._x_ends[last - 1] != self.width:
                raise ZoneMaskError("Zone lookup contains an incomplete row")

    @staticmethod
    def _read_array(typecode: str, payload: bytes) -> array.array:
        values = array.array(typecode)
        values.frombytes(payload)
        if sys.byteorder != "little":
            values.byteswap()
        return values

    def lookup_u32(self, x: int, y: int) -> int:
        """Return the packed RGB at an exact full-resolution map pixel."""

        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            raise IndexError("Map coordinate is outside the zone lookup")
        first = self._row_offsets[y]
        last = self._row_offsets[y + 1]
        span = bisect.bisect_right(self._x_ends, x, first, last)
        if span >= last:
            raise ZoneMaskError("Zone lookup row does not cover this coordinate")
        return int(self._rgb_values[span])

    def lookup(self, x: int, y: int) -> str:
        return rgb_u32_to_key(self.lookup_u32(x, y))

    def bounds(self, rgb_values: Iterable[int]) -> dict[int, dict[str, int]]:
        """Return exclusive pixel bounds for each requested exact zone RGB.

        Bounds are derived directly from the run-length rows, so the map can
        avoid requesting highlight tiles that cannot contain the selected
        fishing region.
        """

        targets = {int(value) for value in rgb_values}
        result: dict[int, list[int]] = {}
        if not targets:
            return {}
        for y in range(self.height):
            row_first = self._row_offsets[y]
            row_last = self._row_offsets[y + 1]
            x_start = 0
            for span in range(row_first, row_last):
                x_end = int(self._x_ends[span])
                rgb = int(self._rgb_values[span])
                if rgb in targets and x_end > x_start:
                    current = result.get(rgb)
                    if current is None:
                        result[rgb] = [x_start, y, x_end, y + 1]
                    else:
                        current[0] = min(current[0], x_start)
                        current[1] = min(current[1], y)
                        current[2] = max(current[2], x_end)
                        current[3] = max(current[3], y + 1)
                x_start = x_end
        return {
            rgb: {"left": value[0], "top": value[1], "right": value[2], "bottom": value[3]}
            for rgb, value in result.items()
        }

    def representative_points(self, rgb_values: Iterable[int]) -> dict[int, ZonePoint]:
        """Find a guaranteed in-zone point close to each zone's area centroid.

        A mathematical centroid can land in a hole or a different disconnected
        polygon.  The second pass projects each centroid onto the nearest actual
        run, so every returned coordinate round-trips through :meth:`lookup_u32`.
        """

        targets = {int(value) for value in rgb_values}
        if not targets:
            return {}

        # [pixel count, sum x, sum y]
        totals: dict[int, list[int]] = defaultdict(lambda: [0, 0, 0])
        for y in range(self.height):
            row_first = self._row_offsets[y]
            row_last = self._row_offsets[y + 1]
            x_start = 0
            for span in range(row_first, row_last):
                x_end = int(self._x_ends[span])
                rgb = int(self._rgb_values[span])
                if rgb in targets and x_end > x_start:
                    count = x_end - x_start
                    entry = totals[rgb]
                    entry[0] += count
                    entry[1] += (x_start + x_end - 1) * count // 2
                    entry[2] += y * count
                x_start = x_end

        centroids = {
            rgb: (entry[1] / entry[0], entry[2] / entry[0])
            for rgb, entry in totals.items()
            if entry[0] > 0
        }
        best: dict[int, tuple[float, ZonePoint]] = {}
        for y in range(self.height):
            row_first = self._row_offsets[y]
            row_last = self._row_offsets[y + 1]
            x_start = 0
            for span in range(row_first, row_last):
                x_end = int(self._x_ends[span])
                rgb = int(self._rgb_values[span])
                centroid = centroids.get(rgb)
                if centroid is not None and x_end > x_start:
                    cx, cy = centroid
                    candidate_x = int(round(cx))
                    candidate_x = max(x_start, min(candidate_x, x_end - 1))
                    distance = (candidate_x - cx) ** 2 + (y - cy) ** 2
                    current = best.get(rgb)
                    if current is None or distance < current[0]:
                        best[rgb] = (distance, ZonePoint(candidate_x, y))
                x_start = x_end

        result = {rgb: candidate[1] for rgb, candidate in best.items()}
        for rgb, point in result.items():
            if self.lookup_u32(point.x, point.y) != rgb:
                raise ZoneMaskError("Representative point failed zone round-trip validation")
        return result
