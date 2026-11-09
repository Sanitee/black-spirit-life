# Build the Fishing service

Use 64-bit CPython 3.12.14 on Windows in a clean virtual environment. Install `tool/requirements-build.txt`, then run from this package:

```powershell
$env:PYTHONHASHSEED = '0'
$env:SOURCE_DATE_EPOCH = '1789430400'
python -B -m PyInstaller --clean --noconfirm tool/fish_companion_service.spec
```

Output: `dist/fish_companion_service.exe`. Two independent clean builds must match in size and SHA-256 before updating the executable, critical-file manifest, integrity record and runtime dependency list.

Only service code goes into the executable. UI and backend source stay in `assets/fish_companion/`. Do not include caches, icon catalogues, personal journals or browser profiles in build inputs.
