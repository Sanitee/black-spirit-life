# Fish Companion service third-party notices

`fish_companion_service.exe` was rebuilt on 2026-09-15 from the source checked
into this public package. It is a PyInstaller one-file executable for Windows
x64. Two clean builds with `PYTHONHASHSEED=0` and
`SOURCE_DATE_EPOCH=1789430400` produced the same pinned bytes. The executable
contains CPython and binary dependencies used by the Fish journal migration
and the local Fish service.

The following full license and notice texts are distributed beside the
executable:

- `licenses/CPython-LICENSE.txt` — CPython 3.12.14, including its bundled
  bzip2 notice and the Microsoft Distributable Code terms applicable to the
  Windows runtime components.
- `licenses/OpenSSL-LICENSE.txt` — OpenSSL 3.5.8 (Apache License 2.0).
- `licenses/libffi-LICENSE.txt` — libffi used by CPython `_ctypes`.
- `licenses/zlib-LICENSE.txt` — zlib 1.3.2.
- `licenses/NumPy-LICENSE.txt` — NumPy 2.3.5 and the complete notices shipped
  by that wheel for OpenBLAS/LAPACK and its bundled runtime libraries.
- `licenses/Pillow-LICENSE.txt` — Pillow 12.3.0 and the complete notices
  shipped by that wheel for its bundled image-codec libraries, including the
  XZ/liblzma and zlib notices.
- `licenses/PyInstaller-COPYING.txt` — PyInstaller 6.22.2 bootloader terms and
  exception.

SQLite 3.53.1 is dedicated to the public domain by its authors. See the
machine-readable inventory in `runtime-sbom.json` for versions, roles, and
license-file hashes.

The application also distributes the reviewed FishyStuff-derived response/map
snapshot, the credited FishyStuff brand image, node-marker references, and
Pearl Abyss game-item reference images used by the exact Fish Map experience.
Those materials remain owned by their respective creators and Pearl Abyss; no
separate endorsement or redistribution licence is claimed here. Source URLs
and attribution remain in the payload and the application's public notices.

The snapshot contains reference data only. No Fish journal, profile, loadout,
haul, saved session, selected personal-data path, browser profile, credential,
or cookie is distributed. Fresh reference refreshes write only to the
host-provided disposable cache and do not include personal values in requests.
