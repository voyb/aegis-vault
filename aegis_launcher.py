#!/usr/bin/env python3
"""Aegis launcher - runs index.html outside the browser when possible.

Order:
  1. pywebview (native window, no browser UI, no extensions, isolated storage).
  2. Chromium-family --app mode with an isolated profile (no extensions, no sync).
  3. System default browser (last resort, still offline, still encrypted).

Usage:
    python aegis_launcher.py
    pip install pywebview  # optional, enables mode 1

Keep this file in the same folder as index.html and vendor/.
"""
import datetime
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path
from typing import Optional

# Pinned release-signing public keys: {key_id: 64-hex Ed25519 public key}. EMPTY until the maintainer generates the
# offline release key (see SIGNING.md and `python3 tools/release.py pubkey --key-file ...`). While empty the launcher runs
# in "unsigned build" mode (checksum-only integrity, announced loudly). Once a key is pinned here the launcher REFUSES to
# start unless RELEASE.manifest + RELEASE.manifest.sig verify, the folder is exactly the signed file set, and the release
# sequence is not older than one already accepted on this machine.
TRUSTED_RELEASE_KEYS = {}

WINDOW_SIZE = "1320,880"
WINDOW_POSITION = "100,60"
WINDOW_W, WINDOW_H = 1320, 880


def storage_check(folder: Path) -> Optional[str]:
    """Verify the vault folder is writable and has room. Returns warning or None."""
    try:
        if not os.access(folder, os.W_OK):
            return f"Vault folder is not writable: {folder}"
        probe = folder / ".aegis_write_test"
        try:
            probe.write_bytes(b"ok")
            probe.unlink(missing_ok=True)
        except OSError as e:
            return f"Cannot write to vault folder ({folder}): {e}"
        try:
            import shutil as _sh
            free = _sh.disk_usage(folder).free
            if free < 50 * 1024 * 1024:
                return f"Low disk space ({free // 1024 // 1024} MB free). Back up your .vlt file."
        except OSError:
            pass
    except Exception as e:
        return f"Storage check failed: {e}"
    return None


def verify_integrity(folder: Path) -> Optional[str]:
    """Refuse to run code that does not match SHA256SUMS. Checks index.html and vendor/* (the only code that
    executes). Returns an error string, or None when everything matches (or no SHA256SUMS ships, in which case
    a warning is printed). Honest limit: an attacker who can edit these files can edit SHA256SUMS too; this catches
    corruption, partial updates and casual tampering. Real tamper-evidence needs a signature you verify out of band.
    Set AEGIS_ALLOW_MODIFIED=1 to run a deliberately modified build."""
    sums = folder / "SHA256SUMS"
    if not sums.is_file():
        print("Aegis integrity: no SHA256SUMS next to index.html, code is unverified.")
        return None
    expected = {}
    try:
        for line in sums.read_text(encoding="utf-8").splitlines():
            parts = line.split(None, 1)
            if len(parts) == 2 and len(parts[0]) == 64:
                expected[parts[1].strip().lstrip("*")] = parts[0].lower()
    except (OSError, UnicodeDecodeError) as e:
        return f"SHA256SUMS is unreadable: {e}"
    checked = 0
    for name, want in expected.items():
        if not (name == "index.html" or name.startswith("vendor/")):
            continue
        f = (folder / name).resolve()
        try:
            f.relative_to(folder.resolve())          # a SHA256SUMS entry must not point outside the app folder
        except ValueError:
            return f"SHA256SUMS entry escapes the app folder: {name}"
        if not f.is_file():
            return f"Missing file listed in SHA256SUMS: {name}"
        got = hashlib.sha256(f.read_bytes()).hexdigest()
        if got != want:
            return f"{name} does not match SHA256SUMS (expected {want[:16]}..., got {got[:16]}...)"
        checked += 1
    if checked == 0:
        return "SHA256SUMS lists no code files"
    return None


def _load_release_module(folder: Path):
    """Load the verifier. From source it is compiled straight from the .py (never from __pycache__: a planted unchecked-hash
    .pyc would otherwise run BEFORE any verification). A frozen build already contains it."""
    sys.dont_write_bytecode = True
    if getattr(sys, "frozen", False):
        import aegis_release as R
        return R
    import types
    path = Path(__file__).resolve().parent / "aegis_release.py"
    mod = types.ModuleType("aegis_release")
    exec(compile(path.read_text(encoding="utf-8"), str(path), "exec"), mod.__dict__)
    return mod


def check_release(folder: Path) -> Optional[str]:
    """Signed-release gate. Returns an error string (refuse to start) or None (ok / unsigned-build mode). Never raises."""
    try:
        if not TRUSTED_RELEASE_KEYS:
            print("Aegis release: UNSIGNED BUILD (no release key is pinned in this launcher). Integrity is checksum-only.")
            return verify_integrity(folder)
        R = _load_release_module(folder)
        try:
            h = R.verify_release(folder, TRUSTED_RELEASE_KEYS, folder / "release-state" / "sequence",
                                 today=datetime.date.today().isoformat(), strict=False)
        except R.ReleaseError as e:
            return str(e)
        print(f"Aegis release: verified version {h['version']} (sequence {h['sequence']}), signed by key {h['key-id']}.")
        if h.get("expired") == "yes":
            print("Aegis release: WARNING this release is past its expiry date. Check for an update.")
        return None
    except Exception as e:  # a verifier crash must read as "refuse", never as "pass" and never as an unhandled traceback
        return f"verification could not complete ({type(e).__name__}): refusing to start"


def private_dir(path: Path) -> None:
    """Create a folder only the current user can read (the browser profile holds the encrypted vault)."""
    try:
        path.mkdir(mode=0o700, exist_ok=True)
        if os.name != "nt":
            os.chmod(path, 0o700)
    except OSError:
        pass


def harden_process() -> list:
    """Best-effort OS hardening for the process that holds the unlocked vault in memory. Never fatal: each step that the
    platform refuses is simply skipped. Returns the names of the protections that took effect."""
    done = []
    try:
        os.umask(0o077)                                   # anything we create is private to this user
        done.append("private-files")
    except OSError:
        pass
    if os.name == "nt":
        return done
    try:
        import resource
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))  # a crash must not write the unlocked vault into a core file
        done.append("no-core-dumps")
    except Exception:
        pass
    try:
        import ctypes
        libc = ctypes.CDLL(None, use_errno=True)
        if sys.platform.startswith("linux"):
            if libc.prctl(4, 0, 0, 0, 0) == 0:            # PR_SET_DUMPABLE=0: other processes cannot ptrace us or read our memory
                done.append("not-ptraceable")
        elif sys.platform == "darwin":
            if libc.ptrace(31, 0, 0, 0) == 0:             # PT_DENY_ATTACH
                done.append("not-ptraceable")
    except Exception:
        pass
    return done


def _clip_backend():
    """(write_argv, read_argv) for the operating system's real clipboard, or None. Standard tools only."""
    system = platform.system()
    if system == "Darwin":
        return (["pbcopy"], ["pbpaste"])
    if system == "Windows":
        ps = ["powershell", "-NoProfile", "-NonInteractive", "-Command"]
        return (ps + ["[Console]::InputEncoding=[Text.Encoding]::UTF8; Set-Clipboard -Value ([Console]::In.ReadToEnd())"],
                ps + ["[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Clipboard -Raw"])
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-copy") and shutil.which("wl-paste"):
        return (["wl-copy"], ["wl-paste", "--no-newline"])
    if shutil.which("xclip"):
        return (["xclip", "-selection", "clipboard", "-i"], ["xclip", "-selection", "clipboard", "-o"])
    if shutil.which("xsel"):
        return (["xsel", "-b", "-i"], ["xsel", "-b", "-o"])
    return None


def _clip_write(text: str, backend=None) -> bool:
    be = backend or _clip_backend()
    if not be:
        return False
    try:
        subprocess.run(be[0], input=text.encode("utf-8"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=True)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def _clip_read(backend=None):
    be = backend or _clip_backend()
    if not be:
        return None
    try:
        r = subprocess.run(be[1], capture_output=True, timeout=5)
        return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return None


class Bridge:
    """The small, deliberate surface the page can call through pywebview (window.pywebview.api).
    Only the clipboard lives here: the page cannot read files, run commands or reach the network through it.

    Clipboard policy, stated honestly: a copy sets the REAL OS clipboard and, for secrets, schedules a clear. The clear only
    happens if the clipboard still holds exactly what we put there (compared by SHA-256), so it never wipes something the
    user copied afterwards. Clipboard managers and history features of the OS can keep their own copies; Aegis cannot reach those."""

    def __init__(self, backend=None) -> None:
        self._backend = backend
        self._lock = threading.Lock()
        self._timer = None
        self._mine = None

    def copy_secret(self, text, seconds=30):
        text = str(text)[:100000]
        try:
            seconds = max(0, min(300, int(seconds)))
        except (TypeError, ValueError):
            seconds = 30
        if not _clip_write(text, self._backend):
            return {"ok": False}
        with self._lock:
            if self._timer is not None:
                self._timer.cancel()
                self._timer = None
            self._mine = hashlib.sha256(text.encode("utf-8")).hexdigest() if seconds else None
            if seconds:
                self._timer = threading.Timer(seconds, self._expire)
                self._timer.daemon = True
                self._timer.start()
        return {"ok": True, "clears": bool(seconds)}

    def clear_clipboard(self):
        return {"ok": True, "cleared": self._expire()}

    def _expire(self) -> bool:
        with self._lock:
            mine, self._mine = self._mine, None
            if self._timer is not None:
                self._timer.cancel()
                self._timer = None
        if not mine:
            return False
        cur = _clip_read(self._backend)
        if cur is None or hashlib.sha256(cur.encode("utf-8")).hexdigest() != mine:
            return False                                   # someone copied something else since: leave it alone
        return _clip_write("", self._backend)

    def shutdown(self) -> None:
        self._expire()


def try_pywebview(index: Path) -> bool:
    """Native window via pywebview. Returns True if it ran."""
    try:
        import webview  # type: ignore
    except ImportError:
        print("Aegis: no native window library (pip install \"pywebview[qt]\"). Falling back to a browser app window.")
        return False
    bridge = Bridge()
    try:
        win = webview.create_window(
            "Aegis",
            url=index.resolve().as_uri(),
            width=WINDOW_W,
            height=WINDOW_H,
            text_select=False,
            js_api=bridge,
        )
        store = here() / "profile-webview"
        private_dir(store)
        try:
            # private_mode=False + a storage path, otherwise pywebview 4+ keeps nothing between runs (vault lost on exit)
            webview.start(debug=False, private_mode=False, storage_path=str(store))
        except TypeError:
            webview.start(debug=False)
        bridge.shutdown()                                  # window closed: clear our clipboard copy if it is still there
        return True
    except Exception as e:
        print(f"pywebview failed ({e}), trying browser app mode.")
        return False


def here() -> Path:
    """Directory containing this script (or the frozen executable, when
    built with PyInstaller)."""
    if getattr(sys, "frozen", False):
        exe = Path(sys.executable).resolve()
        # macOS release layout: bundle/Aegis.app/Contents/MacOS/Aegis with index.html + vendor/ beside the .app (UNVERIFIED on a real Mac)
        if platform.system() == "Darwin" and exe.parent.name == "MacOS" and exe.parent.parent.name == "Contents" and exe.parent.parent.parent.suffix == ".app":
            return exe.parent.parent.parent.parent
        return exe.parent
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

    bad = check_release(here())
    if bad and os.environ.get("AEGIS_ALLOW_MODIFIED") == "1":
        print("=" * 72 + "\nWARNING: AEGIS_ALLOW_MODIFIED=1: RUNNING CODE THAT FAILED VERIFICATION:\n  " + bad + "\nAnything on this machine can be reading what you type. Unset it unless you wrote this code.\n" + "=" * 72)
    if bad and os.environ.get("AEGIS_ALLOW_MODIFIED") != "1":
        msg = ("Aegis will not start: " + bad + "\n\nThe files next to this launcher are not the ones that were "
               "released. Re-download Aegis from the official release. (Set AEGIS_ALLOW_MODIFIED=1 only if you "
               "changed the code yourself.)")
        print(msg)
        try:
            import tkinter
            from tkinter import messagebox
            root = tkinter.Tk(); root.withdraw(); messagebox.showerror("Aegis", msg)
        except Exception:
            pass
        sys.exit(2)

    protections = harden_process()
    if protections:
        print("Aegis hardening: " + ", ".join(protections))
    warn = storage_check(here())
    if warn:
        print(f"Aegis storage warning: {warn}")

    if try_pywebview(index):
        return

    url = index.resolve().as_uri()
    browser = find_browser()

    if not browser:
        print("No Chromium browser found and pywebview is not installed.")
        print("For the most isolated run: pip install pywebview")
        webbrowser.open(url)
        return

    profile = here() / "profile"
    private_dir(profile)
    args = [
        browser,
        f"--app={url}",
        f"--window-size={WINDOW_SIZE}",
        f"--window-position={WINDOW_POSITION}",
        f"--user-data-dir={profile.resolve()}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions",
        "--disable-sync",
        "--disable-background-networking",
        "--disable-component-update",
        "--disable-domain-reliability",
        "--disable-breakpad",
        "--no-pings",
        "--metrics-recording-only",
        "--disable-features=Translate,OptimizationHints,MediaRouter",
    ]
    try:
        subprocess.Popen(args)
    except OSError:
        webbrowser.open(url)


if __name__ == "__main__":
    main()
