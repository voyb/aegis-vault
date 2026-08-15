# PyInstaller spec - builds the Aegis launcher into a single-file executable.
#   Windows:  dist/Aegis.exe            (icon: icon/aegis.ico)
#   macOS:    dist/Aegis.app            (icon: icon/aegis.icns)
#   Linux:    dist/Aegis                (no embedded icon - ELF binaries don't
#                                        carry one; pair with a .desktop entry
#                                        that points at icon/aegis_256.png)
#
# Run: pyinstaller aegis.spec
import sys

block_cipher = None

if sys.platform == "win32":
    icon_file = "icon/aegis.ico"
elif sys.platform == "darwin":
    icon_file = "icon/aegis.icns"
else:
    icon_file = None

a = Analysis(
    ["aegis_launcher.py"],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="Aegis",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    icon=icon_file,
)

if sys.platform == "darwin":
    app = BUNDLE(
        exe,
        name="Aegis.app",
        icon="icon/aegis.icns",
        bundle_identifier="dev.aegis.vault",
        info_plist={
            "NSHighResolutionCapable": True,
            "CFBundleShortVersionString": "0.4.0",
        },
    )
