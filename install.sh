#!/usr/bin/env bash
# Aegis one-command installer for macOS and Linux.
#
# Downloads the latest release for your OS, unpacks it into ~/Aegis, and
# launches it. Nothing is installed system-wide and no sudo is required.
#
# Usage:
#   curl --proto "=https" --tlsv1.2 -fsSLO https://raw.githubusercontent.com/voyb/aegis-vault/main/install.sh && less install.sh && bash install.sh
#   (read it first: piping an unread script into a shell is how supply-chain attacks happen)
set -euo pipefail

# Pinned release-signing public keys, "key_id:64-hex" per entry, space separated. EMPTY until the maintainer generates the
# offline release key (see SIGNING.md). While empty this installer is checksum-only and says so. Once set, it REFUSES to
# install anything whose signed manifest does not verify, and it verifies BEFORE a single file is copied or executed.
PINNED_KEYS=""

REPO="voyb/aegis-vault"
DEST="$HOME/Aegis"

os="$(uname -s)"
case "$os" in
  Darwin) asset="Aegis-macos.zip" ;;
  Linux)  asset="Aegis-linux.tar.gz" ;;
  *)
    echo "Unsupported OS: $os" >&2
    exit 1
    ;;
esac

echo "Installing Aegis to $DEST ..."
mkdir -p "$DEST"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
VERIFIER_PY="$tmp/aegis_release.py"
cat > "$VERIFIER_PY" <<'AEGIS_VERIFIER_EOF'
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
AEGIS_VERIFIER_EOF

base="https://github.com/$REPO/releases/latest/download"
curl --proto "=https" --tlsv1.2 -fsSL "$base/$asset" -o "$tmp/$asset"

# Verify the download against the release's checksum list BEFORE anything is unpacked or run.
# (Same trust root as the download itself; set AEGIS_MINISIGN_PUBKEY to also verify a minisign signature.)
curl --proto "=https" --tlsv1.2 -fsSL "$base/Aegis-SHA256SUMS.txt" -o "$tmp/sums"
want="$(awk -v a="$asset" '$2==a {print $1}' "$tmp/sums")"
[ -n "$want" ] || { echo "No checksum published for $asset. Refusing to install." >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$tmp/$asset" | awk '{print $1}')"; else got="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"; fi
if [ "$got" != "$want" ]; then echo "CHECKSUM MISMATCH for $asset (expected $want, got $got). Refusing to install." >&2; exit 1; fi
echo "Checksum OK ($got)"
if [ -n "${AEGIS_MINISIGN_PUBKEY:-}" ]; then
  command -v minisign >/dev/null 2>&1 || { echo "AEGIS_MINISIGN_PUBKEY set but minisign is not installed." >&2; exit 1; }
  curl --proto "=https" --tlsv1.2 -fsSL "$base/Aegis-SHA256SUMS.txt.minisig" -o "$tmp/sums.minisig"
  minisign -Vm "$tmp/sums" -x "$tmp/sums.minisig" -P "$AEGIS_MINISIGN_PUBKEY" || { echo "SIGNATURE CHECK FAILED. Refusing to install." >&2; exit 1; }
elif [ -z "$PINNED_KEYS" ]; then
  echo "Note: UNSIGNED BUILD. This release is checksum-verified only: no release-signing key is pinned in this installer yet."
fi

# Unpack into a staging folder first. Nothing reaches $DEST (and nothing runs) until the release has been verified.
stage="$tmp/stage"; mkdir -p "$stage"
if [ "$os" = "Darwin" ]; then unzip -oq "$tmp/$asset" -d "$stage"; else tar -xzf "$tmp/$asset" -C "$stage" --no-same-owner; fi

if [ -n "$PINNED_KEYS" ]; then
  command -v python3 >/dev/null 2>&1 || { echo "python3 is required to verify the release signature. Refusing to install." >&2; exit 1; }
  curl --proto "=https" --tlsv1.2 -fsSL "$base/$asset.manifest" -o "$tmp/RELEASE.manifest"
  curl --proto "=https" --tlsv1.2 -fsSL "$base/$asset.manifest.sig" -o "$tmp/RELEASE.manifest.sig" || { echo "This release has no signature. Refusing to install." >&2; exit 1; }
  AEGIS_PINNED="$PINNED_KEYS" python3 -I - "$stage" "$tmp/RELEASE.manifest" "$tmp/RELEASE.manifest.sig" "$VERIFIER_PY" "$DEST/release-state/sequence" <<'AEGIS_DRIVER_EOF' || { echo "SIGNATURE / MANIFEST CHECK FAILED. Refusing to install." >&2; exit 1; }
import importlib.util, os, sys
from pathlib import Path
stage, man, sig, mod, state = sys.argv[1:6]
spec = importlib.util.spec_from_file_location("aegis_release", mod); R = importlib.util.module_from_spec(spec); spec.loader.exec_module(R)
trusted = dict(item.split(":", 1) for item in os.environ["AEGIS_PINNED"].split())
# strict: an archive may not carry profile/, release-state/ or anything else unlisted; the sequence check refuses a downgrade
h = R.verify_release(Path(stage), trusted, Path(state), manifest_path=Path(man), sig_path=Path(sig), strict=True)
print("Signature OK: version %s, sequence %s, key %s" % (h["version"], h["sequence"], h["key-id"]))
AEGIS_DRIVER_EOF
  cp "$tmp/RELEASE.manifest" "$tmp/RELEASE.manifest.sig" "$stage/"
fi

# Remove the files of the PREVIOUS signed release first, so a file the new release dropped cannot survive and brick verification.
if [ -f "$DEST/RELEASE.manifest" ]; then
  awk 'f && NF {print $2} /^$/ {f=1}' "$DEST/RELEASE.manifest" | while IFS= read -r rel; do
    case "$rel" in ''|/*|*..*) continue ;; esac
    rm -f -- "$DEST/$rel"
  done
fi
cp -R "$stage"/. "$DEST"/
if [ "$os" = "Darwin" ]; then
  echo "Installed. Launching Aegis..."
  open "$DEST/Aegis.app"
else
  chmod +x "$DEST/Aegis"
  echo "Installed. Launching Aegis..."
  "$DEST/Aegis" &
fi

echo ""
echo "Aegis lives in $DEST - keep that folder together (the executable"
echo "needs index.html and vendor/ next to it). Run it again any time with:"
if [ "$os" = "Darwin" ]; then
  echo "  open \"$DEST/Aegis.app\""
else
  echo "  \"$DEST/Aegis\""
fi
