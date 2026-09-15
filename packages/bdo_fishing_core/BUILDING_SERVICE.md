# Rebuilding the Fish Companion service

Use 64-bit CPython 3.12.14 on Windows and create an isolated virtual
environment. Install `tool/requirements-build.txt`, then run these commands
from this package directory:

```powershell
$env:PYTHONHASHSEED = '0'
$env:SOURCE_DATE_EPOCH = '1789430400'
python -B -m PyInstaller --clean --noconfirm tool/fish_companion_service.spec
```

The expected executable is `dist/fish_companion_service.exe`. Two independent
clean builds must produce identical length and SHA-256 before the executable,
install-critical manifest, integrity receipt, and runtime SBOM are updated.

The executable contains only Python service code. The static UI and public
backend sources remain external and auditable under
`assets/fish_companion/`. No response cache, reference icon catalog, personal
journal, or WebView2 profile belongs in the build input.
