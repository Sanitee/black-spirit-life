#!/usr/bin/env python3
"""Compare the logical file payloads of two NuGet/Velopack archives."""

from __future__ import annotations

import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path


if sys.flags.optimize != 0:
    raise RuntimeError("release verification requires Python assertions to be enabled")


_INVALID_WINDOWS_CHARS = re.compile(r'[\x00-\x1f<>:"|?*]')
_RESERVED_WINDOWS_NAME = re.compile(
    r"^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)", re.IGNORECASE
)


def _safe_archive_name(info: zipfile.ZipInfo, archive_path: Path) -> tuple[str, bool]:
    raw = info.filename
    normalized = raw.replace("\\", "/")
    is_directory = normalized.endswith("/")
    if not normalized or normalized.startswith("/") or normalized.startswith("//"):
        raise RuntimeError(f"rooted or empty archive entry in {archive_path}: {raw!r}")
    if re.match(r"^[A-Za-z]:", normalized) or ":" in normalized:
        raise RuntimeError(f"drive or ADS archive entry in {archive_path}: {raw!r}")
    trimmed = normalized[:-1] if is_directory else normalized
    segments = trimmed.split("/")
    if not trimmed or any(segment in ("", ".", "..") for segment in segments):
        raise RuntimeError(f"traversal or ambiguous archive entry in {archive_path}: {raw!r}")
    for segment in segments:
        if (
            _INVALID_WINDOWS_CHARS.search(segment)
            or segment.endswith((".", " "))
            or _RESERVED_WINDOWS_NAME.match(segment)
        ):
            raise RuntimeError(f"unsafe Windows archive entry in {archive_path}: {raw!r}")
    unix_mode = (info.external_attr >> 16) & 0o170000
    if unix_mode == 0o120000:
        raise RuntimeError(f"symbolic-link archive entry in {archive_path}: {raw!r}")
    return "/".join(segments) + ("/" if is_directory else ""), is_directory


def inventory(path: Path) -> tuple[list[dict[str, object]], str]:
    entries: list[dict[str, object]] = []
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        records: list[tuple[zipfile.ZipInfo, str, bool]] = []
        aliases: dict[str, tuple[str, bool]] = {}
        for info in infos:
            name, is_directory = _safe_archive_name(info, path)
            alias = name.rstrip("/").casefold()
            if alias in aliases:
                prior_name, prior_directory = aliases[alias]
                kind = "file/directory alias" if prior_directory != is_directory else "case-insensitive duplicate"
                raise RuntimeError(
                    f"{kind} in {path}: {prior_name!r} and {name!r}"
                )
            aliases[alias] = (name, is_directory)
            records.append((info, name, is_directory))
        for _, name, _ in records:
            segments = name.rstrip("/").split("/")
            for index in range(1, len(segments)):
                parent_alias = "/".join(segments[:index]).casefold()
                parent = aliases.get(parent_alias)
                if parent is not None and not parent[1]:
                    raise RuntimeError(
                        f"archive entry has a file as its parent in {path}: {name!r}"
                    )
        for info, name, is_directory in records:
            digest = hashlib.sha256()
            if not is_directory:
                with archive.open(info, "r") as source:
                    while chunk := source.read(1024 * 1024):
                        digest.update(chunk)
            entries.append(
                {
                    "path": name,
                    "directory": is_directory,
                    "size": info.file_size,
                    "sha256": digest.hexdigest(),
                }
            )
    entries.sort(key=lambda item: str(item["path"]))
    aggregate = hashlib.sha256()
    for item in entries:
        aggregate.update(json.dumps(item, sort_keys=True, separators=(",", ":")).encode())
        aggregate.update(b"\n")
    return entries, aggregate.hexdigest()


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: compare_nupkg.py LEFT RIGHT OUTPUT_JSON")
    left, right, output = map(Path, sys.argv[1:])
    left_entries, left_aggregate = inventory(left)
    right_entries, right_aggregate = inventory(right)
    left_map = {str(entry["path"]): entry for entry in left_entries}
    right_map = {str(entry["path"]): entry for entry in right_entries}
    missing_left = sorted(set(right_map) - set(left_map))
    missing_right = sorted(set(left_map) - set(right_map))
    changed = [
        {
            "path": name,
            "left": left_map[name],
            "right": right_map[name],
        }
        for name in sorted(set(left_map) & set(right_map))
        if left_map[name] != right_map[name]
    ]
    result = {
        "equivalent": not missing_left and not missing_right and not changed,
        "left": {
            "path": str(left),
            "entries": len(left_entries),
            "aggregateSha256": left_aggregate,
        },
        "right": {
            "path": str(right),
            "entries": len(right_entries),
            "aggregateSha256": right_aggregate,
        },
        "missingFromLeft": missing_left,
        "missingFromRight": missing_right,
        "changed": changed,
    }
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in ("equivalent", "left", "right")}))
    if missing_left or missing_right or changed:
        print(
            f"missingFromLeft={len(missing_left)} missingFromRight={len(missing_right)} "
            f"changed={len(changed)}",
            file=sys.stderr,
        )
    return 0 if result["equivalent"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
