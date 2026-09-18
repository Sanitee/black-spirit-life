#!/usr/bin/env python3
"""Read-only exact installed-payload comparison for the reviewed Velopack 1.2 layout.

Pinned producer reference:
https://github.com/velopack/velopack/blob/1.2.0/src/lib-rust/src/bundle.rs
extract_lib_contents_to_path / extract_stubs_to_dir relocate two root tools.
There are no excluded files inside current/, including sq.version. Installation
root packages/logs/registration are separate lifecycle obligations, not payload.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import uuid
import zipfile

if sys.flags.optimize != 0:
    raise RuntimeError("release verification requires Python assertions to be enabled")

_POLICY_FILE = Path(__file__).with_name("compare_nupkg.py")
_SPEC = importlib.util.spec_from_file_location("bsl_archive_name_policy", _POLICY_FILE)
_POLICY = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_POLICY)
PREFIX = "lib/app/"
RELOCATED = {
    "Squirrel.exe": "Update.exe",
    "BlackSpiritLife_ExecutionStub.exe": "BlackSpiritLife.exe",
}
REQUIRED = {"sq.version", "BlackSpiritLife.exe", *RELOCATED}
POLICY_ID = "bsl-velopack-1.2-lib-app-current-and-relocated-root-v1"


def digest_stream(stream) -> str:
    digest = hashlib.sha256()
    while block := stream.read(1024 * 1024):
        digest.update(block)
    return digest.hexdigest().upper()


def stable_identity(info: os.stat_result) -> tuple[int, ...]:
    # Windows Python currently reports st_ctime differently through stat versus
    # fstat (creation versus change time). Compare their common stable fields.
    change_or_birth = getattr(info, "st_birthtime_ns", 0) if os.name == "nt" else info.st_ctime_ns
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, change_or_birth)


def ordinary(path: Path, *, directory: bool = False) -> os.stat_result:
    for ancestor in (*path.parents, path):
        info = ancestor.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise RuntimeError("installed/package path contains a reparse point")
    info = path.lstat()
    if not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)):
        raise RuntimeError("installed/package input is not an ordinary file/directory")
    return info


def file_record(path: Path, logical: str) -> dict[str, object]:
    before = ordinary(path)
    with path.open("rb") as stream:
        if stable_identity(os.fstat(stream.fileno())) != stable_identity(before):
            raise RuntimeError("installed file changed while opening")
        digest = digest_stream(stream)
        if stable_identity(os.fstat(stream.fileno())) != stable_identity(before):
            raise RuntimeError("installed file changed during verification")
    if stable_identity(ordinary(path)) != stable_identity(before):
        raise RuntimeError("installed file changed after verification")
    return {"path": logical, "bytes": before.st_size, "sha256": digest}


def canonical_inventory(records: list[dict[str, object]]) -> str:
    digest = hashlib.sha256()
    for record in sorted(records, key=lambda value: str(value["path"])):
        digest.update(json.dumps(record, sort_keys=True, separators=(",", ":")).encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest().upper()


def package_inventory(archive: zipfile.ZipFile) -> list[dict[str, object]]:
    explicit: set[str] = set()
    nodes: dict[str, tuple[str, bool]] = {}
    entries: list[tuple[zipfile.ZipInfo, str, bool]] = []
    for info in archive.infolist():
        name, directory = _POLICY._safe_archive_name(info, Path("reviewed-package"))
        normalized = name.rstrip("/")
        alias = normalized.casefold()
        if alias in explicit:
            raise RuntimeError("duplicate or file/directory archive alias")
        explicit.add(alias)
        parts = normalized.split("/")
        for index in range(1, len(parts) + 1):
            node = "/".join(parts[:index])
            is_directory = directory if index == len(parts) else True
            existing = nodes.get(node.casefold())
            if existing is not None and existing != (node, is_directory):
                raise RuntimeError("archive case/file/directory alias including implicit parent")
            nodes[node.casefold()] = (node, is_directory)
        if normalized.endswith(".__symlink"):
            raise RuntimeError("Velopack encoded symlink entry is not allowed")
        if normalized.endswith(("Squirrel.exe", "_ExecutionStub.exe")) and normalized not in {PREFIX + name for name in RELOCATED}:
            raise RuntimeError("unreviewed relocated package tool")
        if normalized.startswith("lib/") and not name.startswith(PREFIX) and normalized not in {"lib", "lib/app"}:
            raise RuntimeError("unsupported package payload prefix; review producer layout")
        entries.append((info, name, directory))
    seen: set[str] = set()
    records: list[dict[str, object]] = []
    for info, name, directory in entries:
        if directory or not name.startswith(PREFIX):
            continue
        relative = name[len(PREFIX):]
        if relative.endswith(("Squirrel.exe", "_ExecutionStub.exe")) and relative not in RELOCATED:
            raise RuntimeError("unreviewed relocated package tool")
        logical = "root/" + RELOCATED[relative] if relative in RELOCATED else "current/" + relative
        with archive.open(info) as stream:
            sha256 = digest_stream(stream)
        records.append({"path": logical, "bytes": info.file_size, "sha256": sha256})
        seen.add(relative)
    if not REQUIRED.issubset(seen):
        raise RuntimeError("package is missing required application/control payload files")
    return records


def installed_listing(current: Path) -> dict[str, tuple[Path, tuple[int, ...]]]:
    ordinary(current, directory=True)
    records: dict[str, tuple[Path, tuple[int, ...]]] = {}
    aliases: set[str] = set()
    pending = [current]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                path = Path(entry.path)
                relative = path.relative_to(current).as_posix()
                info = entry.stat(follow_symlinks=False)
                if entry.is_symlink() or getattr(info, "st_file_attributes", 0) & 0x400:
                    raise RuntimeError("installed tree contains a reparse point")
                synthetic = zipfile.ZipInfo(relative + ("/" if stat.S_ISDIR(info.st_mode) else ""))
                _POLICY._safe_archive_name(synthetic, Path("installed-current"))
                if relative.casefold() in aliases:
                    raise RuntimeError("installed case-insensitive path collision")
                aliases.add(relative.casefold())
                if stat.S_ISDIR(info.st_mode):
                    pending.append(path)
                elif stat.S_ISREG(info.st_mode):
                    records["current/" + relative] = (path, stable_identity(info))
                else:
                    raise RuntimeError("installed tree has a non-ordinary file")
    for root_name in RELOCATED.values():
        path = current.parent / root_name
        if path.exists() or path.is_symlink():
            records["root/" + root_name] = (path, stable_identity(ordinary(path)))
    return records


def verify(package: Path, approved_sha256: str, current: Path) -> dict[str, object]:
    if len(approved_sha256) != 64 or any(value not in "0123456789abcdefABCDEF" for value in approved_sha256):
        raise RuntimeError("approved full-package SHA-256 is required")
    package = package.absolute()
    current = current.absolute()
    if current.name.casefold() != "current":
        raise RuntimeError("installed-current must identify the current directory")
    initial_package = ordinary(package)
    with package.open("rb") as stream:
        actual_sha256 = digest_stream(stream)
        if actual_sha256 != approved_sha256.upper():
            raise RuntimeError("full-package SHA-256 mismatch")
        stream.seek(0)
        with zipfile.ZipFile(stream) as archive:
            expected = package_inventory(archive)
        if stable_identity(os.fstat(stream.fileno())) != stable_identity(initial_package):
            raise RuntimeError("package changed during verification")
    initial = installed_listing(current)
    actual = [file_record(path, name) for name, (path, _) in sorted(initial.items())]
    if installed_listing(current) != initial:
        raise RuntimeError("installed tree changed during verification; quiesce and retry")
    if stable_identity(ordinary(package)) != stable_identity(initial_package):
        raise RuntimeError("package changed after verification")
    expected_map = {entry["path"]: entry for entry in expected}
    actual_map = {entry["path"]: entry for entry in actual}
    missing = sorted(expected_map.keys() - actual_map.keys())
    unexpected = sorted(actual_map.keys() - expected_map.keys())
    changed = sorted(name for name in expected_map.keys() & actual_map.keys() if expected_map[name] != actual_map[name])
    return {
        "schemaVersion": 1, "purpose": "installed-payload-parity", "policy": POLICY_ID,
        "success": not missing and not unexpected and not changed,
        "scope": "exhaustive-current-plus-two-exact-relocated-root-tools",
        "packageSha256": actual_sha256,
        "expectedInventorySha256": canonical_inventory(expected),
        "installedInventorySha256": canonical_inventory(actual),
        "expectedFileCount": len(expected), "installedFileCount": len(actual),
        "missing": missing, "unexpected": unexpected, "changed": changed,
        "excludedCurrentFiles": [],
        "verifierSha256": file_record(Path(__file__).absolute(), "verifier")["sha256"],
        "archiveNamePolicySha256": file_record(_POLICY_FILE.absolute(), "archive-policy")["sha256"],
        "isWholeReleaseVerification": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--approved-package-sha256", required=True)
    parser.add_argument("--installed-current", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    output = args.output.absolute()
    ordinary(output.parent, directory=True)
    current = args.installed_current.absolute()
    if output.exists() or output.is_symlink():
        raise RuntimeError("parity output must be a new file")
    if output == args.package.absolute() or current == output or current in output.parents:
        raise RuntimeError("parity evidence must be separate from the immutable inputs")
    result = verify(args.package, args.approved_package_sha256, current)
    partial = output.with_name(output.name + ".partial-" + uuid.uuid4().hex)
    with partial.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    if os.name == "nt":
        partial.rename(output)  # Atomic and refuses an existing Windows target.
    else:
        os.link(partial, output)  # Exclusive publication on non-Windows fixtures.
        partial.unlink()
    print(json.dumps({key: result[key] for key in ("purpose", "success", "expectedFileCount", "installedFileCount")}))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
