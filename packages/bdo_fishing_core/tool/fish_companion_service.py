"""Self-contained launcher for the public Fish Companion localhost service.

The immutable frontend and auditable backend source live beside this executable
in the installed package. The host supplies separate, explicit roots for the
selected user's SQLite journal and disposable public-reference cache.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import re
import threading
from pathlib import Path

from backend.http import create_server
from backend.migration import LegacyV017MigrationError, migrate_v017_json


SYNCHRONIZE = 0x00100000
INFINITE = 0xFFFFFFFF


def _exit_with_parent(parent_pid: int) -> None:
    """Prevent a crashed or force-closed Flutter host leaving a local server."""

    kernel32 = ctypes.windll.kernel32
    handle = kernel32.OpenProcess(SYNCHRONIZE, False, parent_pid)
    if not handle:
        return
    try:
        kernel32.WaitForSingleObject(handle, INFINITE)
    finally:
        kernel32.CloseHandle(handle)
    os._exit(0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--personal-data-root", type=Path)
    parser.add_argument("--reference-cache-root", type=Path)
    parser.add_argument("--database", type=Path)
    parser.add_argument("--migrate-v017-json", type=Path)
    parser.add_argument("--port", type=int)
    parser.add_argument("--parent-pid", type=int)
    parser.add_argument("--api-token")
    args = parser.parse_args()

    if args.migrate_v017_json is not None:
        if args.database is None:
            parser.error("--database is required for legacy migration")
        if any(
            value is not None
            for value in (
                args.root,
                args.personal_data_root,
                args.reference_cache_root,
                args.port,
                args.parent_pid,
                args.api_token,
            )
        ):
            parser.error("service arguments cannot be combined with migration")
        try:
            result = migrate_v017_json(args.migrate_v017_json, args.database)
        except (LegacyV017MigrationError, OSError) as exc:
            print(json.dumps({"status": "error", "message": str(exc)}))
            return 2
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0

    required = {
        "--root": args.root,
        "--personal-data-root": args.personal_data_root,
        "--reference-cache-root": args.reference_cache_root,
        "--port": args.port,
        "--parent-pid": args.parent_pid,
        "--api-token": args.api_token,
    }
    missing = [name for name, value in required.items() if value is None]
    if missing:
        parser.error(f"the following arguments are required: {', '.join(missing)}")
    if re.fullmatch(r"[A-Za-z0-9_-]{32,128}", args.api_token) is None:
        parser.error("--api-token must be a 32-128 character URL-safe secret")

    app_root = args.root.resolve()
    if not (app_root / "static" / "index.html").is_file():
        parser.error("Fish Companion runtime files are incomplete")

    threading.Thread(
        target=_exit_with_parent,
        args=(args.parent_pid,),
        daemon=True,
        name="fish-companion-parent-monitor",
    ).start()

    service = create_server(
        app_root,
        args.port,
        personal_data_root=args.personal_data_root,
        reference_cache_root=args.reference_cache_root,
        api_token=args.api_token,
    )
    try:
        service.serve_forever(poll_interval=0.25)
    finally:
        service.store.checkpoint()
        service.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
