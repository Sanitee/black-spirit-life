# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path


package_root = Path(SPECPATH).parent.resolve()
launcher = package_root / "tool" / "fish_companion_service.py"
payload_root = package_root / "assets" / "fish_companion"

a = Analysis(
    [str(launcher)],
    pathex=[str(payload_root)],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="fish_companion_service",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
