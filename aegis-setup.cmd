:<<'AEGIS_BATCH'
@echo off
rem ============================================================================
rem  Aegis one-file setup. Same file on Windows, macOS and Linux.
rem    Windows : double-click it, or run   aegis-setup.cmd
rem    macOS / Linux : sh aegis-setup.cmd      (or chmod +x, then ./aegis-setup.cmd)
rem  Finds Python 3.8+; if there is none it fetches the latest Python for you,
rem  then runs the embedded Python installer (the last part of this file) and installs Aegis.
rem  Read it first - it is plain text. Windows part is this block; PowerShell
rem  helper is the AEGIS_PS block; the Unix part follows AEGIS_BATCH; Python last.
rem ============================================================================
setlocal
set "AEGIS_SELF_PS=%~f0"
set "PYX="
set "PYCHK=import sys;sys.exit(0 if sys.version_info>=(3,8) else 1)"
set "PYRUN=import sys;f=sys.argv[1];sys.argv[:]=sys.argv[1:];exec(compile(open(f,encoding='utf-8').read().split('#'+'@@PY@@',1)[1],f,'exec'))"
py -3 -c "%PYCHK%" >nul 2>nul
if not errorlevel 1 set "PYX=py -3"
if not defined PYX python -c "%PYCHK%" >nul 2>nul
if not defined PYX if not errorlevel 1 set "PYX=python"
if not defined PYX (
  echo [aegis] No usable Python found - fetching the latest Python from python.org ...
  set "AEGIS_PYOUT=%TEMP%\aegis-py-path-%RANDOM%.txt"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:AEGIS_SELF_PS);$a=$t.IndexOf('#AEGIS_PS_'+'BEGIN');$b=$t.IndexOf('#AEGIS_PS_'+'END');& ([scriptblock]::Create($t.Substring($a,$b-$a)))"
)
if not defined PYX if exist "%AEGIS_PYOUT%" set /p PYX=<"%AEGIS_PYOUT%"
if defined AEGIS_PYOUT if defined PYX if exist "%AEGIS_PYOUT%" set PYX="%PYX%"
if defined AEGIS_PYOUT del "%AEGIS_PYOUT%" >nul 2>nul
if not defined PYX (
  echo [aegis] Could not set up Python automatically. Install it from https://www.python.org/downloads/ and run this file again.
  pause
  exit /b 1
)
set "YES=--yes"
if "%AEGIS_ASK%"=="1" set "YES="
%PYX% -I -c "%PYRUN%" "%~f0" %YES% %*
set "RC=%errorlevel%"
if not "%RC%"=="0" pause
exit /b %RC%
rem ---- PowerShell helper: latest stable CPython installer from python.org, Authenticode-checked ----
#AEGIS_PS_BEGIN
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$arch = switch ($env:PROCESSOR_ARCHITECTURE) { 'ARM64' { '-arm64' } 'x86' { '' } default { '-amd64' } }
$idx = (Invoke-WebRequest -UseBasicParsing 'https://www.python.org/ftp/python/').Content
$vers = [regex]::Matches($idx, 'href="(\d+\.\d+\.\d+)/"') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending
$exe = $null
foreach ($v in $vers) {
  $name = "python-$v$arch.exe"
  $url = "https://www.python.org/ftp/python/$v/$name"
  try { $r = Invoke-WebRequest -UseBasicParsing -Method Head $url; if ($r.StatusCode -eq 200) { $exe = Join-Path $env:TEMP $name; Invoke-WebRequest -UseBasicParsing $url -OutFile $exe; break } } catch { }
}
if (-not $exe) { throw 'no Python installer found on python.org' }
$sig = Get-AuthenticodeSignature $exe
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Python Software Foundation') { Remove-Item $exe -Force; throw 'installer signature is not a valid Python Software Foundation signature' }
Write-Host "[aegis] Installing Python (per-user, no admin) ..."
$p = Start-Process -FilePath $exe -ArgumentList '/quiet','InstallAllUsers=0','PrependPath=1','Include_test=0','Include_launcher=0','Shortcuts=0','AssociateFiles=0' -Wait -PassThru
Remove-Item $exe -Force
if ($p.ExitCode -ne 0) { throw "Python installer exit code $($p.ExitCode)" }
$py = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Filter python.exe -Recurse -Depth 1 | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $py) { throw 'python.exe not found after install' }
[IO.File]::WriteAllText($env:AEGIS_PYOUT, $py.FullName)
#AEGIS_PS_END
AEGIS_BATCH
# ---------------------------------------------------------------- macOS / Linux
# Piped (curl ... | sh): this script is on stdin and has no file name. Save everything after this
# block to a temp file and run that, so the Python payload can be read back.
case "${0##*/}" in sh|bash|dash|zsh|ash|ksh|-sh|-bash)
  AEGIS_STAGED=$(mktemp "${TMPDIR:-/tmp}/aegis-setup-XXXXXX") || exit 1
  cat > "$AEGIS_STAGED"
  AEGIS_TMP_SELF=$AEGIS_STAGED exec sh "$AEGIS_STAGED" "$@" ;;
esac
SELF=$0
AEGIS_HOME="${AEGIS_HOME:-$HOME/.aegis}"
say() { printf '[aegis] %s\n' "$*"; }
die() { printf '[aegis] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
pyok() { "$1" -c 'import sys;sys.exit(0 if sys.version_info>=(3,8) else 1)' >/dev/null 2>&1; }

find_py() {
  for c in "$AEGIS_HOME/python/bin/python3" python3 python3.15 python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3.8 python; do
    case "$c" in /*) [ -x "$c" ] || continue ;; *) have "$c" || continue; c=$(command -v "$c") ;; esac
    # macOS ships a /usr/bin/python3 stub that pops an Xcode installer dialog when the tools are missing
    if [ "$c" = /usr/bin/python3 ] && [ "$(uname -s)" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then continue; fi
    if pyok "$c"; then PY=$c; return 0; fi
  done
  return 1
}

fetch() { if have curl; then curl -fsSL --proto '=https' --tlsv1.2 "$1" -o "$2"; elif have wget; then wget -q -O "$2" "$1"; else die "need curl or wget to download Python"; fi; }
sha256_of() { if have sha256sum; then sha256sum "$1" | cut -d' ' -f1; elif have shasum; then shasum -a 256 "$1" | cut -d' ' -f1; else openssl dgst -sha256 "$1" | sed 's/^.*= //'; fi; }

# latest CPython build from astral-sh/python-build-standalone: one tarball, no root, SHA-256 checked
install_standalone() {
  case "$(uname -m)" in x86_64|amd64) a=x86_64 ;; aarch64|arm64) a=aarch64 ;; *) return 1 ;; esac
  case "$(uname -s)" in
    Darwin) t="$a-apple-darwin" ;;
    Linux) if (ldd --version 2>&1 || true) | grep -qi musl; then t="$a-unknown-linux-musl"; else t="$a-unknown-linux-gnu"; fi ;;
    *) return 1 ;;
  esac
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/aegis-py-XXXXXX") || return 1
  fetch https://raw.githubusercontent.com/astral-sh/python-build-standalone/latest-release/latest-release.json "$tmp/rel.json" || return 1
  prefix=$(sed -n 's/.*"asset_url_prefix"[^"]*"\([^"]*\)".*/\1/p' "$tmp/rel.json")
  case "$prefix" in https://github.com/astral-sh/python-build-standalone/releases/download/*) ;; *) return 1 ;; esac
  fetch "$prefix/SHA256SUMS" "$tmp/sums" || return 1
  line=$(grep -F -- "-$t-install_only.tar.gz" "$tmp/sums" | grep -v -F -- '_stripped' |
         awk '{n=$2; sub(/^cpython-/,"",n); sub(/\+.*/,"",n); print n, $1, $2}' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1) || return 1
  [ -n "$line" ] || return 1
  want=$(echo "$line" | awk '{print $2}'); file=$(echo "$line" | awk '{print $3}'); ver=$(echo "$line" | awk '{print $1}')
  say "Downloading Python $ver (latest) ..."
  fetch "$prefix/$file" "$tmp/py.tgz" || return 1
  [ "$(sha256_of "$tmp/py.tgz")" = "$want" ] || { say "Python download failed its SHA-256 check - discarding."; return 1; }
  mkdir -p "$AEGIS_HOME" && rm -rf "$AEGIS_HOME/python" && tar -xzf "$tmp/py.tgz" -C "$AEGIS_HOME" || return 1
  [ -x "$AEGIS_HOME/python/bin/python3" ]
}

# fallback: signed distro / Homebrew packages (asks for sudo only if it must)
install_system() {
  if [ "$(uname -s)" = Darwin ]; then have brew && brew install python3; return; fi
  [ -r /etc/os-release ] || return 1
  ids=$( . /etc/os-release; printf '%s %s' "${ID:-}" "${ID_LIKE:-}" )
  case " $ids " in
    *\ debian*|*\ ubuntu*) cmd="apt-get install -y python3" ;;
    *\ fedora*|*\ rhel*|*\ centos*) cmd="dnf install -y python3" ;;
    *\ arch*) cmd="pacman -S --needed --noconfirm python" ;;
    *\ suse*) cmd="zypper install -n python3" ;;
    *\ alpine*) cmd="apk add python3" ;;
    *) return 1 ;;
  esac
  if [ "$(id -u)" -ne 0 ]; then have sudo || return 1; cmd="sudo $cmd"; fi
  say "Running: $cmd"; $cmd
}

if ! find_py; then
  say "No usable Python 3.8+ found - setting up the latest one for you ..."
  { install_standalone || install_system; } || die "could not install Python automatically. Install python3 and run this file again."
  [ -z "${tmp:-}" ] || rm -rf "$tmp"
  find_py || die "Python was installed but is not usable. Install python3 manually and run this file again."
fi
# after the first line of each run: pass --yes unless the user asked for prompts (AEGIS_ASK=1)
if [ "${AEGIS_ASK:-0}" = 1 ]; then Y=""; else Y="--yes"; fi
exec "$PY" -I -c "import os,sys;f=sys.argv[1];sys.argv[:]=sys.argv[1:];t=open(f,encoding='utf-8').read().split('#'+'@@PY@@',1)[1];os.environ.get('AEGIS_TMP_SELF')==f and os.unlink(f);exec(compile(t,f,'exec'))" "$SELF" $Y "$@"
exit 1
#@@PY@@
#!/usr/bin/env python3
"""Aegis universal installer for Windows, macOS and Linux.

One script, every OS, stdlib only (no pip install, no admin rights):

  Windows (PowerShell) .. Invoke-WebRequest https://raw.githubusercontent.com/voyb/aegis-vault/main/install.py -OutFile install.py
                           Get-Content install.py | Select-Object -First 40   (read it first)
                           py install.py
  macOS / Linux ......... curl -fsSLO https://raw.githubusercontent.com/voyb/aegis-vault/main/install.py
                           less install.py                                         (read it first)
                           python3 install.py

What it does: downloads the release archive for your OS into ~/Aegis
(%USERPROFILE%\\Aegis on Windows), verifies its SHA-256 against the release's
checksum list BEFORE anything is unpacked or run, optionally verifies a
minisign signature (set AEGIS_MINISIGN_PUBKEY) and the signed release manifest
(once PINNED_KEYS below holds the offline release key), unpacks into a staging
folder, verifies again, removes stale files, copies into place, and launches.

Interface: terminal only. An animated color terminal UI that degrades to
plain output when piped, dumb, or NO_COLOR. Flags: --tui / --quiet / --yes
/ --no-launch / --no-python / --dev / --dest DIR / --repo OWNER/NAME / --base-url URL.
"""
from __future__ import annotations

import argparse
import atexit
import contextlib
import ctypes
import hashlib
import io
import math
import os
import queue
import re
import shutil
import ssl
import stat
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

# ---- BEGIN EMBEDDED aegis_release.py ----
"""Aegis release verification: Ed25519 signature check + strict signed manifest + exact file-set check.

Zero dependencies (stdlib only) so the launcher, the installer and the tests all run the SAME code.
This module can verify and (for the offline signing tool only) sign. It never generates keys.

Trust model, in one paragraph: a release is a set of files. A *manifest* lists every file with its SHA-256 plus
a version, a monotonically increasing sequence number and the id of the signing key. The manifest is signed
offline with an Ed25519 key whose public half is pinned inside the launcher and the installer. Verification
fails closed unless: the signature is valid for a pinned key, the manifest is in canonical form, every listed
file matches, NO unlisted code file exists, nothing is a symlink, and the sequence number is not lower than the
highest one this machine has already accepted (so an attacker cannot replay an older, genuinely signed, vulnerable
release). The signature is domain-separated so it can never be confused with a signature over anything else.
"""
import base64
import hashlib
import os
import re
import stat
from pathlib import Path
from typing import Dict, List, Optional, Tuple

DOMAIN = b"AEGIS-RELEASE-v1\n"
MAGIC = "AEGIS-RELEASE 1"
MANIFEST_NAME = "RELEASE.manifest"
SIGNATURE_NAME = "RELEASE.manifest.sig"
# What the APP creates next to itself at runtime. They are never part of a release, so:
#   * the INSTALLER verifies strictly (strict=True): none of these may exist in a release archive at all;
#   * the LAUNCHER (strict=False) tolerates them, but still refuses symlinks, and never lets them influence verification.
RUNTIME_IGNORE = {"profile", "profile-webview", "release-state", "__pycache__", MANIFEST_NAME, SIGNATURE_NAME}
# harmless files a user or the OS legitimately drops beside the app (launcher mode only): never executed by Aegis
TOLERATED_EXTRA_NAMES = {".DS_Store", "Thumbs.db", ".aegis_write_test"}
TOLERATED_EXTRA_SUFFIXES = (".vlt",)
# shipped templates the user is TOLD to edit in place (linux/aegis.desktop says so): a changed copy is tolerated in launcher mode
USER_EDITABLE = {"aegis.desktop"}
MAX_SEQUENCE = 2 ** 31 - 1

# BEGIN ED25519 (RFC 8032, section 6 reference algorithm; verify-only needs no secrets, so timing is irrelevant here)
_p = 2 ** 255 - 19
_q = 2 ** 252 + 27742317777372353535851937790883648493


def _sha512(s: bytes) -> bytes:
    return hashlib.sha512(s).digest()


def _sha512_modq(s: bytes) -> int:
    return int.from_bytes(_sha512(s), "little") % _q


def _inv(x: int) -> int:
    return pow(x, _p - 2, _p)


_d = -121665 * _inv(121666) % _p
_sqrt_m1 = pow(2, (_p - 1) // 4, _p)


def _add(P, Q):
    A, B = (P[1] - P[0]) * (Q[1] - Q[0]) % _p, (P[1] + P[0]) * (Q[1] + Q[0]) % _p
    C, D = 2 * P[3] * Q[3] * _d % _p, 2 * P[2] * Q[2] % _p
    E, F, G, H = B - A, D - C, D + C, B + A
    return (E * F % _p, G * H % _p, F * G % _p, E * H % _p)


def _mul(s: int, P):
    Q = (0, 1, 1, 0)
    while s > 0:
        if s & 1:
            Q = _add(Q, P)
        P = _add(P, P)
        s >>= 1
    return Q


def _equal(P, Q) -> bool:
    return (P[0] * Q[2] - Q[0] * P[2]) % _p == 0 and (P[1] * Q[2] - Q[1] * P[2]) % _p == 0


def _recover_x(y: int, sign: int) -> Optional[int]:
    if y >= _p:
        return None
    x2 = (y * y - 1) * _inv(_d * y * y + 1) % _p
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (_p + 3) // 8, _p)
    if (x * x - x2) % _p != 0:
        x = x * _sqrt_m1 % _p
    if (x * x - x2) % _p != 0:
        return None
    if (x & 1) != sign:
        x = _p - x
    return x


_gy = 4 * _inv(5) % _p
_gx = _recover_x(_gy, 0)
_G = (_gx, _gy, 1, _gx * _gy % _p)


def _compress(P) -> bytes:
    zi = _inv(P[2])
    x, y = P[0] * zi % _p, P[1] * zi % _p
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def _decompress(s: bytes):
    if len(s) != 32:
        return None
    y = int.from_bytes(s, "little")
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _recover_x(y, sign)
    return None if x is None else (x, y, 1, x * y % _p)


def _expand(secret: bytes):
    if len(secret) != 32:
        raise ValueError("an Ed25519 seed is exactly 32 bytes")
    h = _sha512(secret)
    a = int.from_bytes(h[:32], "little")
    a &= (1 << 254) - 8
    a |= 1 << 254
    return a, h[32:]


def public_from_seed(seed: bytes) -> bytes:
    a, _ = _expand(seed)
    return _compress(_mul(a, _G))


def ed25519_sign(seed: bytes, msg: bytes) -> bytes:
    """Offline signing tool only. Not constant-time: never expose this to an attacker who can time it."""
    a, prefix = _expand(seed)
    A = _compress(_mul(a, _G))
    r = _sha512_modq(prefix + msg)
    Rs = _compress(_mul(r, _G))
    h = _sha512_modq(Rs + A + msg)
    return Rs + int.to_bytes((r + h * a) % _q, 32, "little")


def ed25519_verify(public: bytes, msg: bytes, sig: bytes) -> bool:
    if len(public) != 32 or len(sig) != 64:
        return False
    A = _decompress(public)
    R = _decompress(sig[:32])
    if A is None or R is None:
        return False
    s = int.from_bytes(sig[32:], "little")
    if s >= _q:
        return False
    h = _sha512_modq(sig[:32] + public + msg)
    return _equal(_mul(s, _G), _add(R, _mul(h, A)))
# END ED25519


class ReleaseError(Exception):
    """Verification failed. The message is safe to show to the user."""


def key_id(public: bytes) -> str:
    return hashlib.sha256(b"AEGIS-KEY\n" + public).hexdigest()[:16]


_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_VERSION = re.compile(r"^\d{1,4}\.\d{1,4}\.\d{1,4}$")
_HEADERS = ["version", "sequence", "key-id", "created", "expires"]


def _clean(text: str) -> str:
    """Attacker-controlled names must never reach a terminal raw (escape sequences, newlines)."""
    return "".join(c if (c.isprintable() and c not in "\x1b") else "?" for c in str(text))[:200]


def _safe_rel(path: str) -> str:
    if not path or path.startswith("/") or "\\" in path or "\x00" in path or path != path.strip():
        raise ReleaseError("unsafe path in manifest: %s" % _clean(repr(path)))
    parts = path.split("/")
    if any(p in ("", ".", "..") for p in parts):
        raise ReleaseError("unsafe path in manifest: %s" % _clean(repr(path)))
    return path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def list_tree(root: Path, strict: bool = False) -> Dict[str, Path]:
    """Every regular file under root (relative posix path -> path). A symlink ANYWHERE, including inside the runtime-ignored
    names, is a verification failure: a link can point outside the folder the manifest vouched for (and `profile` is where the
    vault lives). strict=True (installer, manifest builder) ignores nothing: runtime names inside an archive are refused."""
    root = Path(root)
    out: Dict[str, Path] = {}
    ignore = set() if strict else RUNTIME_IGNORE
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        rel_dir = Path(dirpath).relative_to(root)
        for name in list(dirnames) + filenames:
            if (Path(dirpath) / name).is_symlink():
                raise ReleaseError("symbolic link inside the release folder: %s" % _clean((rel_dir / name).as_posix()))
        if rel_dir == Path("."):
            dirnames[:] = [d for d in dirnames if d not in ignore]
        for name in filenames:
            if rel_dir == Path(".") and (name in ignore or name in (MANIFEST_NAME, SIGNATURE_NAME)):
                continue          # the manifest and its signature are the sidecars, never content
            out[(rel_dir / name).as_posix()] = Path(dirpath) / name
    return out


def build_manifest(root: Path, version: str, sequence: int, pubkey: bytes, created: str, expires: Optional[str] = None) -> bytes:
    present = [n for n in RUNTIME_IGNORE if (Path(root) / n).exists() and n not in (MANIFEST_NAME, SIGNATURE_NAME)]
    if present:
        raise ReleaseError("the release folder contains runtime-only names that must never ship: %s" % ", ".join(sorted(present)))
    if not _VERSION.match(version):
        raise ReleaseError("version must look like 1.2.3")
    if not (isinstance(sequence, int) and 1 <= sequence <= MAX_SEQUENCE):
        raise ReleaseError("sequence must be a positive integer")
    if not _DATE.match(created) or (expires is not None and not _DATE.match(expires)):
        raise ReleaseError("dates must be YYYY-MM-DD")
    lines = [MAGIC, "version: %s" % version, "sequence: %d" % sequence, "key-id: %s" % key_id(pubkey), "created: %s" % created]
    if expires:
        lines.append("expires: %s" % expires)
    lines.append("")
    for rel, path in sorted(list_tree(root, strict=True).items()):
        if rel in (MANIFEST_NAME, SIGNATURE_NAME):
            continue
        lines.append("%s  %s" % (sha256_file(path), _safe_rel(rel)))
    return ("\n".join(lines) + "\n").encode("utf-8")


def parse_manifest(data: bytes) -> Tuple[Dict[str, str], List[Tuple[str, str]]]:
    """Strict parser. Accepts ONLY the canonical serialisation: the signature covers exact bytes, so there must be exactly
    one way to write a given manifest. Anything else (extra headers, unsorted files, CRLF, duplicates, odd paths) is refused."""
    if len(data) > 4_000_000 or b"\r" in data or b"\x00" in data:
        raise ReleaseError("manifest is malformed")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise ReleaseError("manifest is not UTF-8")
    if not text.endswith("\n") or text.endswith("\n\n"):
        raise ReleaseError("manifest must end with exactly one newline")
    lines = text[:-1].split("\n")
    if not lines or lines[0] != MAGIC:
        raise ReleaseError("not an Aegis release manifest (or an unsupported version)")
    headers: Dict[str, str] = {}
    i = 1
    while i < len(lines) and lines[i] != "":
        k, sep, v = lines[i].partition(": ")
        if not sep or k in headers or k not in _HEADERS or v != v.strip() or not v:
            raise ReleaseError("bad manifest header: %r" % lines[i])
        headers[k] = v
        i += 1
    if [h for h in _HEADERS if h in headers] != list(headers.keys()):
        raise ReleaseError("manifest headers are out of order")
    for need in ("version", "sequence", "key-id", "created"):
        if need not in headers:
            raise ReleaseError("manifest is missing %s" % need)
    if not _VERSION.match(headers["version"]) or not re.match(r"^[1-9][0-9]{0,9}$", headers["sequence"]) or int(headers["sequence"]) > MAX_SEQUENCE \
            or not re.match(r"^[0-9a-f]{16}$", headers["key-id"]) or not _DATE.match(headers["created"]) \
            or ("expires" in headers and not _DATE.match(headers["expires"])):
        raise ReleaseError("manifest header values are invalid")
    if i >= len(lines) or lines[i] != "":
        raise ReleaseError("manifest has no file list")
    files: List[Tuple[str, str]] = []
    for line in lines[i + 1:]:
        digest, sep, path = line.partition("  ")
        if not sep or not _HEX64.match(digest):
            raise ReleaseError("bad file line: %r" % line)
        files.append((_safe_rel(path), digest))
    if not files:
        raise ReleaseError("manifest lists no files")
    paths = [p for p, _ in files]
    if paths != sorted(paths) or len(set(paths)) != len(paths):
        raise ReleaseError("manifest files must be unique and sorted")
    return headers, files


def verify_signature(manifest: bytes, sig_b64: str, trusted: Dict[str, str]) -> str:
    """Returns the key-id that signed it, or raises. `trusted` maps key-id -> 64-hex public key."""
    if not trusted:
        raise ReleaseError("no trusted release key is configured")
    headers, _ = parse_manifest(manifest)
    kid = headers["key-id"]
    if kid not in trusted:
        raise ReleaseError("manifest is signed by an unknown key (%s)" % kid)
    try:
        pub = bytes.fromhex(trusted[kid])
    except ValueError:
        raise ReleaseError("trusted key table is malformed")
    if len(pub) != 32 or key_id(pub) != kid:
        raise ReleaseError("trusted key table is inconsistent")
    A = _decompress(pub)
    if A is None or _equal(_mul(8, A), (0, 1, 1, 0)):
        raise ReleaseError("pinned public key is invalid or of small order")
    try:
        sig = base64.b64decode(str(sig_b64).strip(), validate=True)
    except Exception:
        raise ReleaseError("signature is not valid base64")
    if not ed25519_verify(pub, DOMAIN + manifest, sig):
        raise ReleaseError("SIGNATURE DOES NOT MATCH: this release was not signed by the Aegis release key")
    return kid


def check_tree(root: Path, files: List[Tuple[str, str]], strict: bool = True) -> None:
    """The release on disk must be EXACTLY the manifest: every listed file present and matching, nothing else.
    strict=False (launcher only) additionally tolerates harmless user/OS files and a user-edited aegis.desktop."""
    root = Path(root)
    on_disk = list_tree(root, strict=strict)
    listed = dict(files)
    extra = sorted(set(on_disk) - set(listed))
    if not strict:
        extra = [e for e in extra if not (("/" not in e) and (e in TOLERATED_EXTRA_NAMES or e.endswith(TOLERATED_EXTRA_SUFFIXES)))]
    missing = sorted(set(listed) - set(on_disk))
    if missing:
        raise ReleaseError("file listed in the manifest is missing: %s" % _clean(missing[0]))
    if extra:
        raise ReleaseError("file that is not part of the signed release: %s" % _clean(extra[0]))
    for rel, want in files:
        if not strict and rel in USER_EDITABLE:
            continue
        if sha256_file(on_disk[rel]) != want:
            raise ReleaseError("%s was modified (does not match the signed manifest)" % _clean(rel))


def read_sequence(state_file: Path) -> int:
    """High-water mark. Anything unreadable, non-ASCII, absurd or not a regular file counts as 0 (never as an exception
    and never as a way to brick every future release)."""
    try:
        sf = Path(state_file)
        if sf.is_symlink() or not sf.is_file():
            return 0
        v = sf.read_bytes()[:16].decode("ascii").strip()
        return int(v) if re.match(r"^[0-9]{1,10}$", v) and int(v) <= MAX_SEQUENCE else 0
    except (OSError, UnicodeDecodeError, ValueError):
        return 0


def verify_release(root: Path, trusted: Dict[str, str], state_file: Optional[Path] = None, today: Optional[str] = None,
                   manifest_path: Optional[Path] = None, sig_path: Optional[Path] = None, strict: bool = True) -> Dict[str, str]:
    """Full verification. Returns the manifest headers (plus 'expired': 'yes' when past expiry) or raises ReleaseError (and ONLY
    ReleaseError: every parsing/decoding surprise is converted). On success the highest accepted sequence is recorded in
    state_file, so an older release can never be installed over a newer one. strict=True is for installers; the launcher
    passes strict=False (tolerates the runtime folders and a few harmless files, but never symlinks)."""
    try:
        return _verify_release(root, trusted, state_file, today, manifest_path, sig_path, strict)
    except ReleaseError:
        raise
    except (ValueError, UnicodeError, OverflowError, TypeError, KeyError, IndexError, MemoryError, RecursionError) as e:
        raise ReleaseError("release data is malformed (%s)" % type(e).__name__)


def _verify_release(root, trusted, state_file, today, manifest_path, sig_path, strict):
    root = Path(root)
    mp = Path(manifest_path) if manifest_path else root / MANIFEST_NAME
    sp = Path(sig_path) if sig_path else root / SIGNATURE_NAME
    if not mp.is_file() or not sp.is_file():
        raise ReleaseError("this release has no signed manifest (%s / %s)" % (MANIFEST_NAME, SIGNATURE_NAME))
    manifest = mp.read_bytes()
    verify_signature(manifest, sp.read_bytes()[:4096].decode("ascii", "strict"), trusted)
    headers, files = parse_manifest(manifest)
    check_tree(root, files, strict=strict)
    seq = int(headers["sequence"])
    sf = Path(state_file) if state_file is not None else None
    if sf is not None:
        if sf.parent.is_symlink() or (sf.parent.exists() and not sf.parent.is_dir()) or sf.is_symlink():
            raise ReleaseError("the release-state location is not a plain folder/file (symlink or file in the way): refusing")
        seen = read_sequence(sf)
        if seq < seen:
            raise ReleaseError("ROLLBACK REFUSED: this release (sequence %d) is older than one already accepted here (%d)" % (seq, seen))
    if today and "expires" in headers and today > headers["expires"]:
        headers = dict(headers, expired="yes")
    if sf is not None:
        try:
            sf.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            if seq > read_sequence(sf):
                sf.write_text(str(seq))
                if os.name != "nt":
                    os.chmod(sf, 0o600)
        except OSError:
            raise ReleaseError("cannot record the release sequence (anti-rollback state is not writable): refusing")
    return headers


def key_file_problem(path: Path, repo_root: Path) -> Optional[str]:
    """The signing tool refuses unsafe private-key files. Returns a reason, or None when the file is acceptable."""
    path = Path(path).resolve()
    try:
        path.relative_to(Path(repo_root).resolve())
        return "the private key file is inside the repository folder; keep it outside the repo (and off any synced folder)"
    except ValueError:
        pass
    if not path.is_file():
        return "key file not found"
    if os.name != "nt":
        mode = stat.S_IMODE(path.stat().st_mode)
        if mode & 0o077:
            return "the private key file is readable by other users (mode %s); run chmod 600" % oct(mode)
    return None
# ---- END EMBEDDED aegis_release.py ----

# Pinned release-signing public keys, "key_id: 64-hex-public-key". EMPTY until the maintainer generates the
# offline release key (see SIGNING.md). While empty this installer is checksum-only and says so. Once set, it REFUSES to
# install anything whose signed manifest does not verify, and it verifies BEFORE a single file is copied or executed.
PINNED_KEYS = {}

REPO = "voyb/aegis-vault"
SUMS_NAME = "Aegis-SHA256SUMS.txt"
ASSETS = {
    "Windows": "Aegis-windows.zip",
    "Darwin": "Aegis-macos.zip",
    "Linux": "Aegis-linux.tar.gz",
}
# league-maximums that keep a malicious archive from hurting this machine
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_UNPACKED_BYTES = 1024 * 1024 * 1024
MAX_ARCHIVE_FILES = 4096
CHUNK = 1 << 20


class InstallError(Exception):
    """A verification or install step failed. The message is safe to show."""


# --------------------------------------------------------------------------
# small utilities
# --------------------------------------------------------------------------

def clean_text(text: object) -> str:
    """Attacker-controlled names must never reach a terminal raw."""
    return "".join(c if (c.isprintable() and c not in "\x1b") else "?" for c in str(text))[:200]


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_sums(text: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2 and re.fullmatch(r"[0-9a-f]{64}", parts[0]):
            out[" ".join(parts[1:]).lstrip("*")] = parts[0]
    return out


def asset_for_platform(system: str) -> str:
    try:
        return ASSETS[system]
    except KeyError:
        raise InstallError("unsupported OS: %s (Windows, macOS or Linux required)" % clean_text(system))


def default_base_url(repo: str) -> str:
    return "https://github.com/%s/releases/latest/download" % repo


def github_asset_digest(repo: str, asset: str) -> Optional[str]:
    """'<hex>  <asset>' from the GitHub API's recorded digest of the latest release's asset, or None."""
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        return None
    tmp = Path(tempfile.mkdtemp(prefix="aegis-api-"))
    try:
        f = tmp / "rel.json"
        download_file("https://api.github.com/repos/%s/releases/latest" % repo, f)
        import json
        for a in json.loads(f.read_text(encoding="utf-8")).get("assets", []):
            m = re.fullmatch(r"sha256:([0-9a-f]{64})", str(a.get("digest", "")))
            if a.get("name") == asset and m:
                return "%s  %s\n" % (m.group(1), asset)
    except (InstallError, ValueError, OSError):
        return None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return None


def default_dest() -> Path:
    return Path.home() / "Aegis"


# --------------------------------------------------------------------------
# network (HTTPS only, certificates verified by default)
# --------------------------------------------------------------------------

class _Transient(InstallError):
    """A network hiccup worth another try (timeouts, resets, 5xx). 4xx and policy refusals are never retried."""


_CA_FILES = ("/etc/ssl/cert.pem", "/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt",
             "/etc/ssl/ca-bundle.pem", "/usr/local/etc/openssl/cert.pem", "/opt/homebrew/etc/openssl/cert.pem")


def ssl_context() -> ssl.SSLContext:
    """Normal verified context. Some freshly installed Pythons (python.org on macOS, standalone builds) ship with
    no CA list at all: then, and only then, borrow the operating system's own bundle. Verification stays ON."""
    ctx = ssl.create_default_context()
    try:
        empty = ctx.cert_store_stats().get("x509_ca", 0) == 0
    except Exception:
        empty = False
    if empty:
        for f in _CA_FILES:
            if os.path.isfile(f):
                try:
                    ctx.load_verify_locations(cafile=f)
                    break
                except (ssl.SSLError, OSError):
                    continue
    return ctx


def _download_once(url: str, dest: Path, progress: Optional[Callable[[int, Optional[int]], None]],
                   cancel: Optional[Callable[[], bool]], timeout: int) -> int:
    req = urllib.request.Request(url, headers={"User-Agent": "aegis-installer/2"})
    done = 0
    total: Optional[int] = None
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ssl_context()) as resp:  # noqa: S310 (https-only, verified)
            raw = resp.headers.get("Content-Length")
            if raw and raw.isdigit():
                total = int(raw)
                if total > MAX_ARCHIVE_BYTES + 65536:
                    raise InstallError("release file is implausibly large: refusing")
            with open(dest, "wb") as f:
                while True:
                    if cancel is not None and cancel():
                        raise InstallError("cancelled")
                    buf = resp.read(CHUNK)
                    if not buf:
                        break
                    f.write(buf)
                    done += len(buf)
                    if done > MAX_ARCHIVE_BYTES + 65536:
                        raise InstallError("download exceeded the size limit: refusing")
                    if progress is not None:
                        progress(done, total)
    except InstallError:
        raise
    except urllib.error.HTTPError as e:
        msg = "download failed: HTTP %d" % e.code
        raise (_Transient(msg) if e.code >= 500 else InstallError(msg))
    except ssl.SSLError:
        raise InstallError("download failed: certificate check failed (is your clock right? is a proxy rewriting HTTPS?)")
    except Exception as e:
        raise _Transient("download failed: %s (check your internet connection)" % clean_text(type(e).__name__))
    if total is not None and done != total:
        raise _Transient("download failed: connection dropped at %d of %d bytes" % (done, total))
    if progress is not None and total is None:
        progress(done, done)
    return done


def download_file(url: str, dest: Path, progress: Optional[Callable[[int, Optional[int]], None]] = None,
                  cancel: Optional[Callable[[], bool]] = None, timeout: int = 30, attempts: int = 3) -> int:
    if not url.startswith("https://"):
        raise InstallError("refusing non-HTTPS URL")
    for n in range(1, attempts + 1):
        try:
            return _download_once(url, dest, progress, cancel, timeout)
        except _Transient:
            if n == attempts:
                raise InstallError(str(sys.exc_info()[1]))
            time.sleep(1.5 * n)
    raise InstallError("download failed")


# --------------------------------------------------------------------------
# verification (mirrors install.sh / install.ps1, same fail-closed order)
# --------------------------------------------------------------------------

def verify_archive_checksum(archive: Path, sums_text: str, asset: str) -> str:
    sums = parse_sums(sums_text)
    want = sums.get(asset)
    if not want:
        raise InstallError("no checksum published for %s. Refusing to install." % clean_text(asset))
    got = sha256_of_file(archive)
    if got != want:
        raise InstallError("CHECKSUM MISMATCH for %s. Refusing to install." % clean_text(asset))
    return got


def verify_minisign_if_configured(sums_file: Path, workdir: Path, base_url: str,
                                  progress: Optional[Callable[[str], None]] = None) -> bool:
    """Returns True when a minisign check ran and passed. Unsigned-but-checksummed stays allowed (announced)."""
    pubkey = os.environ.get("AEGIS_MINISIGN_PUBKEY", "").strip()
    if not pubkey:
        return False
    if shutil.which("minisign") is None:
        raise InstallError("AEGIS_MINISIGN_PUBKEY is set but minisign is not installed.")
    sig = workdir / (SUMS_NAME + ".minisig")
    download_file(base_url + "/" + SUMS_NAME + ".minisig", sig)
    try:
        subprocess.run(["minisign", "-Vm", str(sums_file), "-x", str(sig), "-P", pubkey],
                       check=True, capture_output=True, timeout=60)
    except subprocess.CalledProcessError:
        raise InstallError("SIGNATURE CHECK FAILED. Refusing to install.")
    except subprocess.TimeoutExpired:
        raise InstallError("signature check timed out. Refusing to install.")
    if progress is not None:
        progress("minisign signature OK")
    return True


# --------------------------------------------------------------------------
# safe extraction (zip-slip, absolute paths and symlinks are all refused)
# --------------------------------------------------------------------------

_RUNTIME_TOPS = {"profile", "profile-webview", "release-state", "__pycache__",
                 "RELEASE.manifest", "RELEASE.manifest.sig"}


def _norm_arc_name(name: str) -> str:
    """Strip leading './' self-references that archivers emit for the top
    folder (e.g. `tar -C bundle .`). Anything else, including '..', is left
    for _refuse_entry to judge."""
    while name.startswith("./"):
        name = name[2:]
    return name


def _refuse_entry(name: str) -> Optional[str]:
    if not name or name.startswith("/") or name.startswith("\\"):
        return "absolute path"
    if "\\" in name or "\x00" in name:
        return "unsafe separator"
    if len(name) > 512:
        return "path too long"
    parts = name.split("/")
    if any(p in ("", ".", "..") for p in parts):
        return "dot-dot path"
    if parts[0] in _RUNTIME_TOPS:
        return "runtime-only name must never ship in an archive"
    return None


def safe_extract_zip(archive: Path, stage: Path) -> List[str]:
    rels: List[str] = []
    total = 0
    with zipfile.ZipFile(archive) as zf:
        infos = zf.infolist()
        if len(infos) > MAX_ARCHIVE_FILES:
            raise InstallError("archive lists too many files: refusing")
        for info in infos:
            if info.is_dir():
                continue
            name = _norm_arc_name(info.filename)
            if not name or name.endswith("/"):
                continue
            why = _refuse_entry(name)
            if why:
                raise InstallError("unsafe entry in archive (%s): %s" % (why, clean_text(info.filename)))
            if (info.external_attr >> 16) & 0o170000 in (0o120000,):
                raise InstallError("symbolic link inside the archive: %s" % clean_text(info.filename))
            total += info.file_size
            if total > MAX_UNPACKED_BYTES:
                raise InstallError("archive unpacks to an implausible size: refusing")
        for info in infos:
            if info.is_dir():
                continue
            name = _norm_arc_name(info.filename)
            if not name or name.endswith("/"):
                continue
            target = stage / Path(*name.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info, "r") as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out, CHUNK)
            rels.append(name)
    return rels


def safe_extract_tar(archive: Path, stage: Path) -> List[str]:
    rels: List[str] = []
    total = 0
    with tarfile.open(archive, "r:gz") as tf:
        members = tf.getmembers()
        # `tar czf x -C dir .` (what our CI does) prefixes every name with "./" and adds a "." root entry: normalise, then
        # every name still goes through the same strict checks below
        kept = []
        for m in members:
            n = m.name
            while n.startswith("./"):
                n = n[2:]
            n = n.rstrip("/") if m.isdir() else n
            if n in ("", "."):
                if m.isdir():
                    continue
            m.name = n
            kept.append(m)
        members = kept
        if len(members) > MAX_ARCHIVE_FILES:
            raise InstallError("archive lists too many files: refusing")
        for m in members:
            if m.isdir():
                why = _refuse_entry(m.name.rstrip("/"))
                if why:
                    raise InstallError("unsafe entry in archive (%s): %s" % (why, clean_text(m.name)))
                continue
            if not m.isfile():
                raise InstallError("non-regular file inside the archive: %s" % clean_text(m.name))
            why = _refuse_entry(m.name)
            if why:
                raise InstallError("unsafe entry in archive (%s): %s" % (why, clean_text(m.name)))
            total += m.size
            if total > MAX_UNPACKED_BYTES:
                raise InstallError("archive unpacks to an implausible size: refusing")
        for m in members:
            if m.isdir():
                (stage / Path(*m.name.rstrip("/").split("/"))).mkdir(parents=True, exist_ok=True)
                continue
            if not m.isfile():
                continue
            target = stage / Path(*m.name.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            src = tf.extractfile(m)
            if src is None:
                raise InstallError("cannot read archive member: %s" % clean_text(m.name))
            with src, open(target, "wb") as out:
                shutil.copyfileobj(src, out, CHUNK)
            rels.append(m.name)
    return rels


# --------------------------------------------------------------------------
# staging -> destination (stale files removed, symlinks in the way refused)
# --------------------------------------------------------------------------

def _manifest_file_list(manifest_text: str) -> List[str]:
    try:
        data = manifest_text.encode("utf-8")
        _headers, files = parse_manifest(data)
        return [rel for rel, _ in files]
    except Exception:
        return []


def remove_stale_files(dest: Path, previous_manifest: Optional[str]) -> int:
    if not previous_manifest:
        return 0
    removed = 0
    for rel in _manifest_file_list(previous_manifest):
        if not rel or rel.startswith("/") or "\\" in rel or "\x00" in rel:
            continue
        parts = rel.split("/")
        if any(p in ("", ".", "..") for p in parts):
            continue
        target = dest.joinpath(*parts)
        try:
            if target.is_file() and not target.is_symlink():
                target.unlink()
                removed += 1
        except OSError:
            pass
    return removed


def assert_no_symlink_in_the_way(dest: Path, rels: List[str]) -> None:
    if dest.is_symlink():
        raise InstallError("the install folder is a symlink: refusing")
    for rel in rels:
        target = dest.joinpath(*rel.split("/"))
        for parent in [target] + list(target.parents):
            try:
                if parent.is_symlink():
                    raise InstallError("a symlink is in the way: %s" % clean_text(rel))
            except OSError:
                pass
            if parent == dest:
                break


def copy_stage_to_dest(stage: Path, dest: Path, rels: List[str]) -> None:
    assert_no_symlink_in_the_way(dest, rels)
    dest.mkdir(parents=True, exist_ok=True)
    for rel in rels:
        src = stage.joinpath(*rel.split("/"))
        dst = dest.joinpath(*rel.split("/"))
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.is_symlink() or (dst.exists() and not dst.is_file()):
            raise InstallError("cannot replace: %s" % clean_text(rel))
        shutil.copy2(src, dst)


def executable_name(system: str) -> str:
    if system == "Windows":
        return "Aegis.exe"
    if system == "Darwin":
        return "Aegis.app"
    return "Aegis"


def launch_app(dest: Path, system: str) -> str:
    exe = executable_name(system)
    if system == "Darwin":
        app = dest / "Aegis.app"
        if not app.is_dir():
            raise InstallError("install finished but Aegis.app is missing")
        subprocess.Popen(["open", str(app)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return 'open "%s"' % app
    target = dest / exe
    if not target.is_file():
        raise InstallError("install finished but %s is missing" % exe)
    if system != "Windows":
        try:
            mode = stat.S_IMODE(target.stat().st_mode)
            os.chmod(target, mode | 0o755)
        except OSError:
            pass
        subprocess.Popen([str(target)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         stdin=subprocess.DEVNULL, start_new_session=True)
        return '"%s"' % target
    try:
        os.startfile(str(target))  # type: ignore[attr-defined]
    except AttributeError:
        subprocess.Popen([str(target)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         stdin=subprocess.DEVNULL, close_fds=True)
    return str(target)


# --------------------------------------------------------------------------
# Python bootstrap (best-effort; the Aegis app itself needs no system Python)
#
# What "requirements" means here, honestly: the launcher is stdlib-only and
# runs without anything else. `pywebview` (optional) enables its most isolated
# native-window mode; without it the launcher falls back to browser app mode.
# --dev adds the source-build tools from the
# README (pyinstaller, pillow). Nothing is installed without asking first,
# interpreters come only from signed OS channels (winget / Homebrew / distro
# repos), and a failed bootstrap never blocks the Aegis install itself.
# --------------------------------------------------------------------------

MIN_PYTHON = (3, 10)
# Fresh interpreters always track the latest stable Python 3 (winget's
# Python.Python.3, Homebrew's python3, the distro's python3). MIN_PYTHON above
# is the compatibility floor the installer refuses to go below.
PY_PACKAGES = ["pywebview"]
DEV_PACKAGES = ["pyinstaller", "pillow"]
# pip project name -> import name (they differ more often than not)
IMPORT_NAMES = {"pywebview": "webview", "pillow": "PIL", "pyinstaller": "PyInstaller"}


def import_name_of(package: str) -> str:
    base = package.split("==")[0].split("[")[0].strip()
    return IMPORT_NAMES.get(base, base.replace("-", "_"))


def parse_python_version(text: str) -> Optional[Tuple[int, int, int]]:
    m = re.search(r"Python\s+(\d+)\.(\d+)\.(\d+)", str(text))
    if not m:
        return None
    try:
        return (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        return None


def probe_python(argv: List[str], timeout: int = 15) -> Optional[Tuple[List[str], Tuple[int, int, int]]]:
    try:
        proc = subprocess.run(argv + ["--version"], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    ver = parse_python_version((proc.stdout or "") + "\n" + (proc.stderr or ""))
    if ver is None:
        return None
    return (argv, ver)


def candidate_interpreters() -> List[List[str]]:
    cands: List[List[str]] = [[sys.executable]]
    if os.name == "nt":
        cands += [["py", "-3.12"], ["py", "-3.11"], ["py", "-3"],
                  ["python3.12"], ["python3"], ["python"]]
    else:
        cands += [["python3.12"], ["python3.11"], ["python3.10"],
                  ["python3"], ["python"]]
    out: List[List[str]] = []
    for argv in cands:
        if argv[0] == sys.executable:
            out.append(argv)
        elif shutil.which(argv[0]) is not None:
            out.append(argv)
    return out


def find_suitable_python(min_version: Tuple[int, int] = MIN_PYTHON) -> Optional[Tuple[List[str], Tuple[int, int, int]]]:
    for argv in candidate_interpreters():
        hit = probe_python(argv)
        if hit is not None and (hit[1][0], hit[1][1]) >= (min_version[0], min_version[1]):
            return hit
    return None


def module_available(python_argv: List[str], module: str, timeout: int = 20) -> bool:
    try:
        proc = subprocess.run(python_argv + ["-c", "import %s" % module],
                              capture_output=True, timeout=timeout)
        return proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def pip_install(python_argv: List[str], packages: List[str], extra_args: Optional[List[str]] = None,
                timeout: int = 300) -> Tuple[bool, str, bool]:
    """Returns (ok, stderr_tail, externally_managed). Never raises."""
    args = list(python_argv) + ["-m", "pip", "install", "--user",
                                "--disable-pip-version-check"] + list(packages)
    if extra_args:
        args += extra_args
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return (False, clean_text(type(e).__name__), False)
    err = proc.stderr or ""
    if proc.returncode == 0:
        return (True, "", False)
    return (False, clean_text(err[-400:]), "externally-managed-environment" in err)


def ensure_pip(python_argv: List[str], timeout: int = 120) -> bool:
    if module_available(python_argv, "pip"):
        return True
    try:
        proc = subprocess.run(list(python_argv) + ["-m", "ensurepip", "--user", "--default-pip"],
                              capture_output=True, text=True, timeout=timeout)
        return proc.returncode == 0 and module_available(python_argv, "pip")
    except (OSError, subprocess.TimeoutExpired):
        return False


def linux_distro_ids(os_release_text: str) -> List[str]:
    ids: List[str] = []
    for line in str(os_release_text).splitlines():
        if line.startswith("ID="):
            ids.append(line[3:].strip().strip('"').lower())
        elif line.startswith("ID_LIKE="):
            ids.extend(w.strip().strip('"').lower() for w in line[8:].split())
    return ids


def os_python_plan(system: str, have_sudo: bool, is_root: bool, os_release_text: str,
                   which: Callable[[str], Optional[str]]) -> Optional[Dict[str, object]]:
    """How to get a suitable interpreter from a signed channel, or None when
    there is no safe automatic route (caller prints manual steps instead)."""
    if system == "Windows":
        if which("winget") is None:
            return None
        return {"label": "winget (Microsoft-verified package manifest)",
                "cmd": ["winget", "install", "--id", "Python.Python.3", "-e",
                        "--accept-package-agreements", "--accept-source-agreements"],
                "needs_terminal": False}
    if system == "Darwin":
        if which("brew") is None:
            return None
        return {"label": "Homebrew (bottle signatures verified by brew)",
                "cmd": ["brew", "install", "python3"],
                "needs_terminal": False}
    if system == "Linux":
        ids = set(linux_distro_ids(os_release_text))
        cmd: Optional[List[str]] = None
        if ids & {"debian", "ubuntu", "linuxmint", "pop", "raspbian", "kali"}:
            cmd = ["apt-get", "install", "-y", "python3", "python3-venv", "python3-pip"]
        elif ids & {"fedora", "rhel", "centos", "rocky", "alma", "ol"}:
            mgr = "dnf" if which("dnf") else ("yum" if which("yum") else None)
            if mgr is None:
                return None
            cmd = [mgr, "install", "-y", "python3", "python3-pip"]
        elif ids & {"arch", "manjaro", "endeavouros"}:
            cmd = ["pacman", "-S", "--needed", "--noconfirm", "python", "python-pip"]
        elif ids & {"opensuse", "suse", "opensuse-leap", "opensuse-tumbleweed"}:
            cmd = ["zypper", "install", "-n", "python3", "python3-pip"]
        elif ids & {"alpine"}:
            cmd = ["apk", "add", "python3", "py3-pip"]
        else:
            return None
        if not is_root:
            if not have_sudo:
                return None
            cmd = ["sudo"] + cmd
        return {"label": "your distro's signed packages",
                "cmd": cmd, "needs_terminal": True}
    return None


def manual_python_instructions(system: str) -> str:
    if system == "Windows":
        return ("Install the latest Python 3 from python.org (tick 'Add python.exe to PATH'), "
                "then re-run this installer.")
    if system == "Darwin":
        return ("Install the latest Python 3 (python.org installer or `brew install python3`), "
                "then re-run this installer.")
    return ("Install the latest Python 3 (3.10 or newer) with your distro's package manager "
            "(Debian/Ubuntu: `sudo apt-get install -y python3 python3-venv python3-pip`), "
            "then re-run this installer.")


def format_cmd(cmd: List[str]) -> str:
    return " ".join((("'%s'" % c) if (" " in c or '"' in c) else c) for c in cmd)


def ensure_python_setup(job: "Job", ui: UI, auto_accept: bool = False, dev: bool = False) -> Dict[str, str]:
    """Best-effort interpreter + package bootstrap. Reports; never fails the
    Aegis install itself (only a user cancellation aborts the pipeline)."""
    info: Dict[str, str] = {"status": "skipped"}
    found = find_suitable_python()
    if found is None:
        ui.note("No Python %s+ found on PATH." % ".".join(map(str, MIN_PYTHON)))
        plan = os_python_plan(job.system, shutil.which("sudo") is not None,
                              (os.geteuid() == 0) if hasattr(os, "geteuid") else False,
                              "", shutil.which)
        if job.system == "Linux":
            try:
                plan = os_python_plan(job.system, shutil.which("sudo") is not None,
                                      (os.geteuid() == 0) if hasattr(os, "geteuid") else False,
                                      Path("/etc/os-release").read_text(errors="replace")
                                      if Path("/etc/os-release").exists() else "",
                                      shutil.which)
            except OSError:
                pass
        if plan is None:
            ui.note(manual_python_instructions(job.system))
            info["status"] = "missing-manual"
            return info
        ui.note("Interpreter plan: %s" % plan["label"])
        ui.note("Command: %s" % format_cmd(plan["cmd"]))  # type: ignore[arg-type]
        if plan.get("needs_terminal"):
            try:
                stdin_tty = sys.stdin.isatty()
            except Exception:
                stdin_tty = False
            if not stdin_tty and not auto_accept:
                ui.note("That command needs a terminal (admin rights). Run it, then re-run this installer.")
                info["status"] = "missing-manual"
                return info
        if not auto_accept and not ui.ask("Install the latest Python 3 now?", default=True):
            ui.note("Python setup declined. Aegis itself needs no system Python.")
            info["status"] = "declined"
            return info
        ui.note("Installing Python (this can take a few minutes) ...")
        try:
            proc = subprocess.run(plan["cmd"], timeout=900)  # type: ignore[arg-type]
        except (OSError, subprocess.TimeoutExpired):
            proc = None
        if proc is None or proc.returncode != 0:
            ui.note("Python install did not complete. %s" % manual_python_instructions(job.system))
            info["status"] = "failed-manual"
            return info
        found = find_suitable_python()
        if found is None:
            ui.note("Still no suitable Python after install. %s" % manual_python_instructions(job.system))
            info["status"] = "failed-manual"
            return info
    exe, ver = found
    vstr = "%d.%d.%d" % ver
    ui.ok("Python %s found" % vstr)
    info.update({"status": "ok", "python": vstr, "exe": exe[0]})
    for label, packages in (("recommended", list(PY_PACKAGES)), ("dev", list(DEV_PACKAGES) if dev else [])):
        if not packages:
            continue
        missing = [p for p in packages if not module_available(exe, import_name_of(p))]
        if not missing:
            ui.note("%s packages already present (%s)" % (label, ", ".join(packages)))
            info[label] = "present"
            continue
        if label == "recommended":
            ui.note("pywebview enables the launcher's most isolated native-window mode "
                    "(without it, the launcher uses browser app mode).")
        if not auto_accept and not ui.ask("Install %s package(s) with pip (%s)?" % (label, ", ".join(missing)), default=True):
            ui.note("Skipped %s packages." % label)
            info[label] = "declined"
            continue
        with ui.working("Getting pip ready"):
            pip_ready = ensure_pip(exe)
        if not pip_ready:
            ui.note("pip is unavailable for %s; skipping package installs." % exe[0])
            info[label] = "no-pip"
            continue
        with ui.working("Installing %s" % ", ".join(missing)):
            ok, err, managed = pip_install(exe, missing)
        if ok:
            ui.ok("%s packages installed (%s)" % (label.capitalize(), ", ".join(missing)))
            info[label] = "installed"
            continue
        if managed:
            ui.note("That interpreter is externally managed (distro Python): pip refuses "
                    "to avoid breaking system packages.")
            if os.environ.get("AEGIS_BREAK_SYSTEM") == "1" or ui.ask("Retry with --break-system-packages (may affect system packages)?", default=False):
                ok2, err2, _ = pip_install(exe, missing, extra_args=["--break-system-packages"])
                if ok2:
                    ui.ok("%s packages installed (%s)" % (label.capitalize(), ", ".join(missing)))
                    info[label] = "installed"
                    continue
                ui.note("Package install failed: %s" % (err2 or "unknown error"))
            else:
                ui.note("Left system packages untouched. The launcher works without pywebview.")
            info[label] = "skipped-managed"
            continue
        ui.note("Package install failed: %s" % (err or "unknown error"))
        info[label] = "failed"
    if info.get("recommended") in ("present", "installed"):
        info["native"] = ensure_native_window(exe, ui, auto_accept)
    return info


def native_backend_ok(python_argv: List[str]) -> bool:
    """pywebview needs a real window toolkit. Windows (WebView2) and macOS (WebKit) come with the pip install; Linux needs GTK
    (the `gi` module) or Qt (qtpy plus a Qt binding)."""
    if os.name == "nt" or __import__("platform").system() == "Darwin":
        return True
    if module_available(python_argv, "gi"):
        return True
    return module_available(python_argv, "qtpy") and any(
        module_available(python_argv, m) for m in ("PyQt6", "PySide6", "PyQt5", "PySide2"))


def ensure_native_window(python_argv: List[str], ui: "UI", auto_accept: bool) -> str:
    """Make Aegis open in its own Python window instead of a browser. Best effort: a failure never blocks the install."""
    if native_backend_ok(python_argv):
        ui.note("native window ready (Python opens Aegis in its own window)")
        return "present"
    if not (auto_accept or ui.ask("Install the Qt window toolkit so Aegis opens in its own Python window, not a browser? (about 150 MB)", default=True)):
        ui.note("Skipped. Aegis will open in a browser app window instead.")
        return "skipped"
    with ui.working("Installing the native window (Qt)"):
        ok, err, managed = pip_install(python_argv, ["pywebview[qt]"], timeout=900)
    if ok:
        ui.ok("native window installed")
        return "installed"
    if managed:
        ui.note("This Python is externally managed, so pip refused. Use a venv, or install your distro's python3-gobject "
                "and webkit2gtk packages. Until then Aegis opens in a browser app window.")
        return "skipped-managed"
    ui.note("Could not install the native window (%s). Aegis will open in a browser app window." % (err or "unknown error"))
    return "failed"


# --------------------------------------------------------------------------
# pipeline (terminal UI)
# --------------------------------------------------------------------------

class Job:
    def __init__(self, dest: Path, repo: str, base_url: str, launch: bool = True,
                 setup_python: bool = True, dev: bool = False, auto_accept: bool = False,
                 channel: str = "release") -> None:
        self.channel = channel   # "source": the current files from the repo, run by the launcher. "release": packaged build.
        self.dest = dest
        self.repo = repo
        self.base_url = base_url
        self.launch = launch
        self.setup_python = setup_python
        self.dev = dev
        self.auto_accept = auto_accept
        self.system = "Windows" if os.name == "nt" else __import__("platform").system()
        self.asset = asset_for_platform(self.system)
        self.cancelled = False

    def cancel(self) -> None:
        self.cancelled = True

    def _check_cancel(self) -> None:
        if self.cancelled:
            raise InstallError("cancelled")


class UI:
    def set_total(self, _n: int) -> None: ...
    def working(self, _msg: str):
        return contextlib.nullcontext()
    def done(self, _result: Dict[str, str], _secs: float) -> None: ...
    def step(self, _name: str) -> None: ...
    def progress(self, _done: int, _total: Optional[int], _msg: str = "") -> None: ...
    def ok(self, _msg: str) -> None: ...
    def note(self, _msg: str) -> None: ...
    def fail(self, _msg: str) -> None: ...
    def ask(self, question: str, default: bool = True) -> bool: return True


# --------------------------------------------------------------------------
# source channel: the CURRENT app, straight from the repo, run by the launcher.
# Small (about 1 MB), always as new as the repo, and needs only Python. Every
# file is checked against the repo's SHA256SUMS before anything is installed.
# --------------------------------------------------------------------------

SOURCE_ALLOW = ("index.html", "aegis_launcher.py", "aegis_release.py")


def source_raw_base(job: "Job") -> str:
    return job.base_url if job.base_url.startswith("https://") and job.base_url != default_base_url(job.repo) \
        else "https://raw.githubusercontent.com/%s/main" % job.repo


def source_wanted(sums: Dict[str, str]) -> List[str]:
    """Only the files that actually run. Names come from a downloaded list, so each one is checked as a safe relative path."""
    want = []
    for name in sums:
        if name in SOURCE_ALLOW or (name.startswith("vendor/") and name.count("/") == 1):
            if not re.fullmatch(r"[A-Za-z0-9_.\-]+(/[A-Za-z0-9_.\-]+)?", name) or ".." in name:
                raise InstallError("unsafe file name in the checksum list: %s" % clean_text(name))
            want.append(name)
    if "index.html" not in want or "aegis_launcher.py" not in want:
        raise InstallError("the checksum list does not cover the app files. Refusing to install.")
    return sorted(want)


def windowed_python(argv: List[str]) -> List[str]:
    """On Windows use pythonw so no console window sits behind the app."""
    if os.name != "nt":
        return list(argv)
    exe = argv[0]
    if exe.lower() in ("py", "py.exe"):
        return ["pyw"] + list(argv[1:])
    if exe.lower().endswith("python.exe"):
        w = exe[:-len("python.exe")] + "pythonw.exe"
        if os.path.isfile(w):
            return [w] + list(argv[1:])
    return list(argv)


def write_run_script(dest: Path, argv: List[str], system: str) -> Path:
    """Aegis / Aegis.cmd: one stable command that starts the launcher with the Python that has pywebview."""
    launcher = dest / "aegis_launcher.py"
    if system == "Windows":
        path = dest / "Aegis.cmd"
        cmd = " ".join('"%s"' % a for a in windowed_python(argv))
        path.write_text('@echo off\r\ncd /d "%%~dp0"\r\nstart "" %s "%s"\r\n' % (cmd, launcher), encoding="utf-8")
    else:
        path = dest / "Aegis"
        cmd = " ".join("'%s'" % a.replace("'", "'\\''") for a in argv)
        path.write_text("#!/bin/sh\ncd \"$(dirname \"$0\")\" || exit 1\nexec %s '%s' \"$@\"\n"
                        % (cmd, str(launcher).replace("'", "'\\''")), encoding="utf-8")
        os.chmod(path, 0o755)
    return path


def run_source_pipeline(job: "Job", ui: "UI") -> Dict[str, str]:
    if PINNED_KEYS:
        raise InstallError("release signing is on: the source channel cannot be signed. Re-run with --release.")
    base = source_raw_base(job)
    if not base.startswith("https://"):
        raise InstallError("refusing non-HTTPS URL")
    tmp = Path(tempfile.mkdtemp(prefix="aegis-install-"))
    result: Dict[str, str] = {"dest": str(job.dest), "channel": "source"}
    try:
        ui.set_total(4 + (1 if job.launch else 0))
        ui.step("python")
        argv: List[str] = [sys.executable]
        if job.setup_python:
            pyinfo = ensure_python_setup(job, ui, auto_accept=job.auto_accept, dev=job.dev)
            if pyinfo.get("python"):
                result["python"] = pyinfo["python"]
            found = find_suitable_python()
            if found is not None:
                argv = list(found[0])
        else:
            ui.note("Python setup skipped (--no-python).")

        ui.step("download")
        sums_file = tmp / "SHA256SUMS"
        job._check_cancel()
        download_file(base + "/SHA256SUMS", sums_file)
        sums = parse_sums(sums_file.read_text(encoding="utf-8", errors="strict"))
        wanted = source_wanted(sums)
        stage = tmp / "stage"
        total = 0
        for i, name in enumerate(wanted):
            job._check_cancel()
            target = stage.joinpath(*name.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            base_done = total
            total += download_file(base + "/" + name, target,
                                   progress=lambda d, t, b=base_done, n=name: ui.progress(b + d, None, n),
                                   cancel=lambda: job.cancelled)
        ui.ok("downloaded %d files (%s)" % (len(wanted), TUI._human(total)))

        ui.step("verify")
        with ui.working("Checking every file's SHA-256 fingerprint"):
            for name in wanted:
                if sha256_of_file(stage.joinpath(*name.split("/"))) != sums[name]:
                    raise InstallError("CHECKSUM MISMATCH for %s. Refusing to install." % clean_text(name))
        ui.ok("all %d files match the published checksums" % len(wanted))
        ui.note("Note: UNSIGNED BUILD. Checksum-verified only: no release-signing key is pinned yet.")
        result["sha256"] = "all-files"
        result["minisign"] = "unsigned"
        shutil.copy2(sums_file, stage / "SHA256SUMS")

        ui.step("install")
        job._check_cancel()
        with ui.working("Copying files into place"):
            copy_stage_to_dest(stage, job.dest, wanted + ["SHA256SUMS"])
            for old in ("Aegis.exe",):                      # leftovers of an older packaged install; the vault (profile/) is never touched
                try:
                    (job.dest / old).unlink()
                except OSError:
                    pass
            shutil.rmtree(job.dest / "Aegis.app", ignore_errors=True)
            script = write_run_script(job.dest, argv, job.system)
        ui.ok("installed to %s" % job.dest)
        result["installed"] = str(job.dest)
        result["run"] = str(script) if job.system == "Windows" else '"%s"' % script

        if job.launch:
            ui.step("launch")
            try:
                if job.system == "Windows":
                    os.startfile(str(script))  # type: ignore[attr-defined]
                else:
                    subprocess.Popen([str(script)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                     stdin=subprocess.DEVNULL, start_new_session=True)
            except OSError as e:
                ui.note("could not start it automatically (%s). Run: %s" % (type(e).__name__, result["run"]))
                result["launch"] = "skipped"
            else:
                ui.ok("launched")
                result["launch"] = "ok"
        return result
    finally:
        shutil.rmtree(tmp, ignore_errors=True)



def run_pipeline(job: Job, ui: UI) -> Dict[str, str]:
    if job.channel == "source":
        return run_source_pipeline(job, ui)
    if not job.base_url.startswith("https://"):
        raise InstallError("refusing non-HTTPS release URL")
    tmp = Path(tempfile.mkdtemp(prefix="aegis-install-"))
    result: Dict[str, str] = {"dest": str(job.dest), "asset": job.asset}
    try:
        ui.set_total(5 + (1 if PINNED_KEYS else 0) + (1 if job.launch else 0))
        ui.step("python")
        if job.setup_python:
            pyinfo = ensure_python_setup(job, ui, auto_accept=job.auto_accept, dev=job.dev)
            if pyinfo.get("python"):
                result["python"] = pyinfo["python"]
        else:
            ui.note("Python setup skipped (--no-python).")
        ui.step("download")
        archive = tmp / job.asset
        job._check_cancel()
        download_file(job.base_url + "/" + job.asset, archive,
                      progress=lambda d, t: ui.progress(d, t, "Aegis"),
                      cancel=lambda: job.cancelled)
        ui.ok("downloaded %s" % job.asset)
        sums_file = tmp / SUMS_NAME
        try:
            download_file(job.base_url + "/" + SUMS_NAME, sums_file)  # tiny: no bar
        except InstallError:
            # Older releases (before the CI step that publishes Aegis-SHA256SUMS.txt) have no list. GitHub still records a
            # SHA-256 for every uploaded asset; use that, only for the official repo, and say so out loud.
            digest_line = github_asset_digest(job.repo, job.asset) if job.base_url == default_base_url(job.repo) else None
            if not digest_line:
                raise InstallError("no checksum list published for this release. Refusing to install.")
            sums_file.write_text(digest_line, encoding="utf-8")
            ui.note("This release has no checksum list; using the SHA-256 GitHub recorded when it was uploaded.")

        ui.step("verify")
        sums_text = sums_file.read_text(encoding="utf-8", errors="strict")
        with ui.working("Checking the SHA-256 fingerprint"):
            digest = verify_archive_checksum(archive, sums_text, job.asset)
        ui.ok("checksum OK (%s…)" % digest[:16])
        result["sha256"] = digest
        try:
            signed = verify_minisign_if_configured(sums_file, tmp, job.base_url, progress=ui.note)
        except InstallError as e:
            ui.fail(str(e))
            raise
        if signed:
            ui.ok("minisign signature OK")
            result["minisign"] = "ok"
        elif PINNED_KEYS:
            ui.note("manifest signature will be checked next")
        else:
            ui.note("Note: UNSIGNED BUILD. Checksum-verified only: no release-signing key is pinned yet.")
            result["minisign"] = "unsigned"

        ui.step("unpack")
        job._check_cancel()
        stage = tmp / "stage"
        stage.mkdir()
        with ui.working("Unpacking safely into a staging folder"):
            if job.asset.endswith(".zip"):
                rels = safe_extract_zip(archive, stage)
            else:
                rels = safe_extract_tar(archive, stage)
        ui.ok("unpacked %d files to a staging folder" % len(rels))

        if PINNED_KEYS:
            ui.step("signature")
            job._check_cancel()
            man = tmp / "RELEASE.manifest"
            sig = tmp / "RELEASE.manifest.sig"
            try:
                download_file(job.base_url + "/" + job.asset + ".manifest", man)
                download_file(job.base_url + "/" + job.asset + ".manifest.sig", sig)
            except InstallError:
                raise InstallError("this release has no signature. Refusing to install.")
            state = job.dest / "release-state" / "sequence"
            try:
                headers = verify_release(stage, dict(PINNED_KEYS), state,
                                         manifest_path=man, sig_path=sig, strict=True)
            except ReleaseError as e:
                raise InstallError("SIGNATURE / MANIFEST CHECK FAILED (%s). Refusing to install." % e)
            ui.ok("signature OK: version %s, sequence %s, key %s"
                  % (headers.get("version"), headers.get("sequence"), headers.get("key-id")))
            result["manifest"] = "ok"
            shutil.copy2(man, stage / "RELEASE.manifest")
            shutil.copy2(sig, stage / "RELEASE.manifest.sig")
            rels = rels + ["RELEASE.manifest", "RELEASE.manifest.sig"]

        ui.step("install")
        job._check_cancel()
        previous = None
        prev_manifest = job.dest / "RELEASE.manifest"
        if prev_manifest.is_file() and not prev_manifest.is_symlink():
            try:
                previous = prev_manifest.read_text(encoding="utf-8", errors="strict")
            except OSError:
                previous = None
        dropped = remove_stale_files(job.dest, previous)
        if dropped:
            ui.note("removed %d stale file(s) from the previous release" % dropped)
        with ui.working("Copying files into place"):
            copy_stage_to_dest(stage, job.dest, rels)
        ui.ok("installed to %s" % job.dest)
        result["installed"] = str(job.dest)

        if job.launch:
            ui.step("launch")
            try:
                how = launch_app(job.dest, job.system)
            except InstallError as e:
                ui.note(str(e))
                result["launch"] = "skipped"
            else:
                ui.ok("launched")
                result["launch"] = how
        return result
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# --------------------------------------------------------------------------
# terminal UI: color + animation, degrades gracefully (NO_COLOR, dumb, pipes)
# --------------------------------------------------------------------------

_GOLD = "C9A86A"
_SPIN_FULL = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
_SPIN_ASCII = "|/-\\"

# AEGIS in block letters. Painted top to bottom: dark gold at the top, bright gold at the bottom.
_BANNER = [ln for ln in r'''
  ___   _____ _____ _____ _____ 
 / _ \ |  ___|  __ \_   _/  ___|
/ /_\ \| |__ | |  \/ | | \ `--. 
|  _  ||  __|| | __  | |  `--. \
| | | || |___| |_\ \_| |_/\__/ /
\_| |_/\____/ \____/\___/\____/ 
'''.splitlines() if ln.strip()]
_GOLD_DARK = (104, 74, 12)
_GOLD_LIGHT = (255, 214, 82)
_SHINE = (255, 246, 205)


def _lerp(a: Tuple[int, int, int], b: Tuple[int, int, int], t: float) -> Tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return (int(a[0] + (b[0] - a[0]) * t), int(a[1] + (b[1] - a[1]) * t), int(a[2] + (b[2] - a[2]) * t))


class TUI(UI):
    def __init__(self, out: Optional[io.TextIOBase] = None, quiet: bool = False) -> None:
        self.out = out if out is not None else sys.stdout
        self.quiet = quiet
        self.is_tty = False
        try:
            self.is_tty = self.out.isatty()
        except Exception:
            self.is_tty = False
        dumb = (os.environ.get("TERM") == "dumb") or not self.is_tty or quiet
        self.color = not dumb and "NO_COLOR" not in os.environ and self._vt_ready()
        enc = (getattr(self.out, "encoding", "") or "").lower()
        self.utf = enc.startswith("utf") and not dumb
        self.frames = _SPIN_FULL if self.utf else _SPIN_ASCII
        self.animate = (not dumb) and "AEGIS_NO_ANIM" not in os.environ
        self.truecolor = self.color and (os.name == "nt" or os.environ.get("COLORTERM", "").lower() in ("truecolor", "24bit"))
        self._spin_i = 0
        self._spin_t = 0.0
        self._line_busy = False
        self._xfer_t0 = time.time()
        self._xfer_last = 0
        self._steps = 0
        self._step_i = 0
        self._cursor_hidden = False

    # ---- terminal plumbing -------------------------------------------------
    def _vt_ready(self) -> bool:
        if os.name != "nt":
            return True
        try:
            kernel = ctypes.windll.kernel32  # type: ignore[attr-defined]
            handle = kernel.GetStdHandle(-11)
            mode = ctypes.c_ulong()
            if kernel.GetConsoleMode(handle, ctypes.byref(mode)):
                kernel.SetConsoleMode(handle, mode.value | 4)
                return True
        except Exception:
            pass
        return False

    def _cols(self) -> int:
        try:
            return max(40, shutil.get_terminal_size((80, 24)).columns)
        except Exception:
            return 80

    def _c(self, code: str, text: str) -> str:
        if not self.color:
            return text
        return "\x1b[%sm%s\x1b[0m" % (code, text)

    def _rgb(self, rgb: Tuple[int, int, int], text: str, bold: bool = False) -> str:
        if not self.color:
            return text
        if self.truecolor:
            code = "38;2;%d;%d;%d" % rgb
        else:  # 256-colour cube: close enough, and every terminal made since 2010 has it
            r, g, b = (round(v / 255 * 5) for v in rgb)
            code = "38;5;%d" % (16 + 36 * r + 6 * g + b)
        return self._c(("1;" if bold else "") + code, text)

    def gold(self, t: str) -> str: return self._rgb(_GOLD_LIGHT, t)
    def green(self, t: str) -> str: return self._c("32", t)
    def red(self, t: str) -> str: return self._c("31", t)
    def dim(self, t: str) -> str: return self._c("2", t)
    def bold(self, t: str) -> str: return self._c("1", t)

    def _write(self, s: str) -> None:
        try:
            self.out.write(s)
            self.out.flush()
        except (OSError, ValueError):
            pass

    def _hide_cursor(self) -> None:
        if self.color and self.is_tty and not self._cursor_hidden:
            self._cursor_hidden = True
            self._write("\x1b[?25l")
            atexit.register(self.close)

    def close(self) -> None:
        if self._cursor_hidden:
            self._cursor_hidden = False
            self._write("\x1b[?25h")

    def _newline(self) -> None:
        if self._line_busy:
            self._write("\n")
            self._line_busy = False

    # ---- banner -------------------------------------------------------------
    def _banner_lines(self, shine_col: Optional[int] = None) -> List[str]:
        n = len(_BANNER)
        rows = []
        for i, line in enumerate(_BANNER):
            base = _lerp(_GOLD_DARK, _GOLD_LIGHT, i / (n - 1) if n > 1 else 1.0)
            if shine_col is None:
                rows.append(self._rgb(base, line, bold=True))
                continue
            parts = []
            for x, ch in enumerate(line):
                if ch == " ":
                    parts.append(ch)
                else:
                    glow = max(0.0, 1.0 - abs(x - shine_col) / 5.0)
                    parts.append(self._rgb(_lerp(base, _SHINE, glow * 0.85), ch, bold=True))
            rows.append("".join(parts))
        return rows

    def splash(self) -> None:
        if self.quiet:
            return
        width = max(len(ln) for ln in _BANNER)
        n = len(_BANNER)
        self._write("\n")
        if self.animate and self.is_tty and self.color:
            self._hide_cursor()
            for row in self._banner_lines():          # reveal: top (dark) to bottom (bright)
                self._write("  " + row + "\n")
                time.sleep(0.06)
            for col in range(-6, width + 8, 2):        # one shimmer sweep, left to right
                self._write("\x1b[%dA" % n)
                for row in self._banner_lines(col):
                    self._write("\r  " + row + "\n")
                time.sleep(0.014)
            self._write("\x1b[%dA" % n)               # settle back to the resting gradient
            for row in self._banner_lines():
                self._write("\r  " + row + "\n")
        else:
            for row in self._banner_lines():
                self._write("  " + row + "\n")
        self._write("\n  " + self.dim("Secure vault installer  ·  Windows  ·  macOS  ·  Linux") + "\n\n")

    # ---- steps, progress, spinner -------------------------------------------
    def set_total(self, n: int) -> None:
        self._steps, self._step_i = n, 0

    def step(self, name: str) -> None:
        self._newline()
        if self.quiet:
            return
        self._step_i += 1
        count = ("  " + self.dim("%d/%d" % (self._step_i, self._steps))) if self._steps else ""
        self._write("\n  " + self.gold("▸ " if self.utf else "> ") + self.bold(name.capitalize()) + count + "\n")

    def _bar(self, frac: float, width: int) -> str:
        fill = int(width * frac)
        cell = "█" if self.utf else "#"
        rest = "░" if self.utf else "-"
        if not self.color:
            return cell * fill + rest * (width - fill)
        head = "".join(self._rgb(_lerp(_GOLD_DARK, _GOLD_LIGHT, k / max(1, width - 1)), cell) for k in range(fill))
        return head + self.dim(rest * (width - fill))

    def progress(self, done: int, total: Optional[int], msg: str = "") -> None:
        if self.quiet or not self.is_tty or not self.animate:
            return
        now = time.time()
        if done < self._xfer_last or done == 0:      # a new transfer started: restart the speed clock
            self._xfer_t0 = now
        self._xfer_last = done
        if now - self._spin_t < 0.05 and (total is None or done != total):
            return
        self._spin_t = now
        self._spin_i += 1
        spin = self.frames[self._spin_i % len(self.frames)]
        el = max(now - self._xfer_t0, 0.001)
        rate = done / el if el > 0.25 else 0.0
        cols = self._cols()
        if total:
            frac = min(1.0, done / total)
            width = max(10, min(34, cols - 50))
            tail = "%s / %s" % (self._human(done), self._human(total))
            if rate:
                tail += "  %s/s" % self._human(int(rate))
                if frac < 1.0 and cols >= 84:
                    tail += "  %ds left" % int((total - done) / rate + 0.5)
            line = "\r  %s %s %s %s  %s" % (self._rgb(_GOLD_LIGHT, spin), self.dim(msg.ljust(11)), self._bar(frac, width),
                                          self.bold("%3d%%" % int(frac * 100)), self.dim(tail))
        else:
            line = "\r  %s %s  %s" % (self._rgb(_GOLD_LIGHT, spin), self.dim(msg), self._human(done))
        self._write(line + "\x1b[K")
        self._line_busy = True
        if total is not None and done >= total:
            self._newline()

    @contextlib.contextmanager
    def working(self, msg: str):
        """A pulsing gold spinner for steps that have no progress to report. Shows only on a live terminal."""
        if self.quiet:
            yield
            return
        if not (self.animate and self.is_tty):
            self.note(msg + " ...")
            yield
            return
        self._newline()
        stop = threading.Event()
        t0 = time.time()

        def spin() -> None:
            i = 0
            while not stop.is_set():
                pulse = (math.sin(i / 2.5) + 1) / 2
                glyph = self._rgb(_lerp(_GOLD_DARK, _GOLD_LIGHT, pulse), self.frames[i % len(self.frames)], bold=True)
                self._write("\r  %s %s %s\x1b[K" % (glyph, msg, self.dim("%ds" % int(time.time() - t0))))
                i += 1
                stop.wait(0.08)

        th = threading.Thread(target=spin, daemon=True)
        th.start()
        try:
            yield
        finally:
            stop.set()
            th.join(timeout=1)
            self._write("\r\x1b[K")

    @staticmethod
    def _human(n: int) -> str:
        f = float(n)
        for unit in ("B", "KB", "MB", "GB"):
            if f < 1024 or unit == "GB":
                return ("%d%s" % (f, unit)) if unit == "B" else ("%.1f%s" % (f, unit))
            f /= 1024
        return "%dB" % n

    # ---- messages -----------------------------------------------------------
    def ok(self, msg: str) -> None:
        self._newline()
        if not self.quiet:
            self._write("  " + self.green("✔ " if self.utf else "+ ") + msg + "\n")

    def note(self, msg: str) -> None:
        self._newline()
        if not self.quiet:
            self._write(self.dim("    " + msg) + "\n")

    def fail(self, msg: str) -> None:
        self._newline()
        self._write("  " + self.red(("✘ " if self.utf else "x ") + msg) + "\n")

    def ask(self, question: str, default: bool = True) -> bool:
        self._newline()
        hint = "[Y/n]" if default else "[y/N]"
        try:
            ans = input("  %s %s " % (question, hint)).strip().lower()
        except EOFError:
            return False
        if not ans:
            return default
        return ans[:1] == "y"

    def done(self, result: Dict[str, str], secs: float) -> None:
        self._newline()
        folder = result.get("installed", result.get("dest", ""))
        system = "Windows" if os.name == "nt" else __import__("platform").system()
        if result.get("run"):
            run = result["run"]
        elif system == "Darwin":
            run = 'open "%s"' % (Path(folder) / "Aegis.app")
        elif system == "Windows":
            run = str(Path(folder) / "Aegis.exe")
        else:
            run = '"%s"' % (Path(folder) / "Aegis")
        trust = "signature verified" if result.get("manifest") == "ok" else (
            "checksum verified (unsigned build)" if result.get("sha256") else "")
        if self.quiet:
            self._write("Aegis installed to %s\n" % folder)
            return
        rows = [("Folder", folder), ("Python", result.get("python", "")), ("Trust", trust), ("Run again", run)]
        rows = [(k, v) for k, v in rows if v]
        inner = max(11 + len(v) for _k, v in rows)
        inner = min(max(inner, 34), self._cols() - 8)
        tl, tr, bl, br, h, v = ("╭", "╮", "╰", "╯", "─", "│") if self.utf else ("+", "+", "+", "+", "-", "|")
        title = " Aegis is ready  ·  %ds " % int(secs + 0.5)
        self._write("\n  " + self._rgb(_GOLD_LIGHT, tl + h + title + h * max(0, inner - len(title) + 1) + tr, bold=True) + "\n")
        for k, val in rows:
            body = ("%s  %s" % (k.ljust(9), val))[:inner + 2]
            self._write("  " + self._rgb(_GOLD_LIGHT, v) + " " + body.ljust(inner + 1) + self._rgb(_GOLD_LIGHT, v) + "\n")
        self._write("  " + self._rgb(_GOLD_LIGHT, bl + h * (inner + 2) + br) + "\n\n")


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="aegis-setup", description="Aegis universal installer (Windows/macOS/Linux).")
    p.add_argument("--dest", default=str(default_dest()), help="install folder (default: ~/Aegis)")
    p.add_argument("--repo", default=REPO, help="GitHub repo OWNER/NAME for releases")
    p.add_argument("--base-url", default="", help="override the release download URL (must be https://)")
    p.add_argument("--release", action="store_true",
                   help="install the packaged release build instead of the current source (default: current source)")
    p.add_argument("--no-launch", action="store_true", help="install but do not launch")
    p.add_argument("--yes", action="store_true", help="skip confirmation prompts")
    p.add_argument("--no-python", action="store_true",
                   help="skip the Python + packages setup step")
    p.add_argument("--dev", action="store_true",
                   help="also install source-build tools (pyinstaller, pillow)")
    p.add_argument("--tui", action="store_true", help="force the terminal UI (the only UI)")
    p.add_argument("--quiet", action="store_true", help="minimal output (implies --tui)")
    return p


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.quiet:
        args.tui = True
    base_url = args.base_url or default_base_url(args.repo)
    if not base_url.startswith("https://"):
        print("refusing non-HTTPS release URL", file=sys.stderr)
        return 2
    job = Job(dest=Path(args.dest).expanduser(), repo=args.repo, base_url=base_url,
              launch=not args.no_launch, setup_python=not args.no_python,
              dev=args.dev, auto_accept=args.yes, channel="release" if args.release else "source")
    tui = TUI(quiet=args.quiet)
    t_start = time.time()
    tui.splash()
    tui.note("Installing Aegis to %s" % job.dest)
    if not args.yes:
        what = "the latest Aegis" if job.channel == "source" else job.asset
        if not tui.ask("Install %s for %s?" % (what, job.system), default=True):
            tui.note("aborted. Nothing was downloaded or changed.")
            return 1
    try:
        result = run_pipeline(job, tui)
    except (InstallError, ReleaseError) as e:
        tui.fail(str(e))
        return 1
    except KeyboardInterrupt:
        tui.fail("interrupted. Nothing was left half-installed (staging is discarded).")
        return 130
    except Exception as e:  # fail closed, no tracebacks to users
        tui.fail("unexpected failure (%s): refusing to continue" % type(e).__name__)
        return 1
    tui.done(result, time.time() - t_start)
    return 0


if __name__ == "__main__":
    sys.exit(main())
