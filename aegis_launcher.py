#!/usr/bin/env python3
"""Aegis launcher - opens index.html as a standalone, chromeless app window.

Works the same way on Windows, macOS, and Linux: it looks for an installed
Chromium-family browser (Edge, Chrome, Brave, Chromium, in that order) and
opens the local index.html in that browser's "app mode" - no address bar,
no tabs, its own window and taskbar/dock icon. If none of those are found,
it falls back to opening index.html in the system's default browser.

Usage:
    python aegis_launcher.py

Keep this file in the same folder as index.html and vendor/.
"""
import os
import platform
import shutil
import subprocess
import sys
import webbrowser
from pathlib import Path
from typing import Optional

WINDOW_SIZE = "1320,880"
WINDOW_POSITION = "100,60"


def here() -> Path:
    """Directory containing this script (or the frozen executable, when
    built with PyInstaller)."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def find_browser() -> Optional[str]:
    """Locate an installed Chromium-family browser for this OS.

    Checked in order: Edge, Chrome, Brave, Chromium. Known install
    locations are checked first; if none exist, falls back to searching
    PATH (this is the common case on Linux, where browsers are usually
    installed by the package manager and already on PATH)."""
    system = platform.system()

    if system == "Windows":
        program_files = [os.environ.get("ProgramFiles", r"C:\Program Files"),
                          os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")]
        candidates = []
        for pf in program_files:
            candidates += [
                os.path.join(pf, "Microsoft", "Edge", "Application", "msedge.exe"),
                os.path.join(pf, "Google", "Chrome", "Application", "chrome.exe"),
                os.path.join(pf, "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
                os.path.join(pf, "Chromium", "Application", "chrome.exe"),
            ]
    elif system == "Darwin":
        candidates = [
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
        ]
    else:
        candidates = []

    for path in candidates:
        if os.path.isfile(path):
            return path

    for name in ("microsoft-edge", "msedge", "google-chrome", "google-chrome-stable",
                 "chrome", "brave-browser", "brave", "chromium-browser", "chromium"):
        found = shutil.which(name)
        if found:
            return found

    return None


def _report_missing_index(folder: Path) -> None:
    message = (
        f"index.html was not found next to this launcher ({folder}).\n"
        "Keep the Aegis executable in the same folder as index.html and vendor/."
    )
    print(message)
    if sys.stdin is not None and sys.stdin.isatty():
        input("Press Enter to exit...")
        return
    # No console attached (windowed build) - try a native message box instead.
    try:
        import tkinter
        from tkinter import messagebox
        root = tkinter.Tk()
        root.withdraw()
        messagebox.showerror("Aegis", message)
    except Exception:
        pass


def main() -> None:
    index = here() / "index.html"
    if not index.exists():
        _report_missing_index(here())
        sys.exit(1)

    url = index.resolve().as_uri()
    browser = find_browser()

    if not browser:
        webbrowser.open(url)
        return

    args = [
        browser,
        f"--app={url}",
        f"--window-size={WINDOW_SIZE}",
        f"--window-position={WINDOW_POSITION}",
    ]
    try:
        subprocess.Popen(args)
    except OSError:
        webbrowser.open(url)


if __name__ == "__main__":
    main()
