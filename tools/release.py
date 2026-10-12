#!/usr/bin/env python3
"""Offline release tooling for Aegis. See SIGNING.md.

  manifest  DIR  --version 0.9.0 --sequence 7 --pubkey HEX [--created YYYY-MM-DD] [--expires YYYY-MM-DD] [-o RELEASE.manifest]
  sign      MANIFEST --key-file KEY [-o RELEASE.manifest.sig]
  verify    DIR  --pubkey HEX [--manifest M] [--sig S] [--state FILE]
  pubkey    --key-file KEY            (prints the public key and key id to pin in aegis_launcher.py / install.sh)

There is deliberately NO "keygen" command: this tool never creates a private key. Generate one offline (SIGNING.md),
keep it off the repo and off CI, and point --key-file at it. The signer refuses a key file inside the repository or one
readable by other users, re-verifies its own signature before writing it, and checks that the key matches the manifest.
"""
import argparse
import base64
import datetime
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import aegis_release as R  # noqa: E402


def read_seed(path: Path) -> bytes:
    problem = R.key_file_problem(path, ROOT)
    if problem:
        sys.exit("refusing to use the key file: " + problem)
    raw = Path(path).read_bytes().strip()
    if len(raw) == 64:
        try:
            return bytes.fromhex(raw.decode("ascii"))
        except ValueError:
            pass
    if len(raw) == 32:
        return raw
    sys.exit("key file must hold a 32-byte Ed25519 seed, raw or as 64 hex characters")


def cmd_manifest(a):
    pub = bytes.fromhex(a.pubkey)
    created = a.created or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    data = R.build_manifest(Path(a.dir), a.version, a.sequence, pub, created, a.expires)
    Path(a.output).write_bytes(data)
    print("wrote %s (%d files, key-id %s, sequence %d)" % (a.output, data.count(b"  "), R.key_id(pub), a.sequence))


def cmd_sign(a):
    seed = read_seed(Path(a.key_file))
    pub = R.public_from_seed(seed)
    manifest = Path(a.manifest).read_bytes()
    headers, _ = R.parse_manifest(manifest)
    if headers["key-id"] != R.key_id(pub):
        sys.exit("this key (%s) is not the key named in the manifest (%s)" % (R.key_id(pub), headers["key-id"]))
    sig = R.ed25519_sign(seed, R.DOMAIN + manifest)
    if not R.ed25519_verify(pub, R.DOMAIN + manifest, sig):
        sys.exit("internal error: the fresh signature does not verify; nothing written")
    Path(a.output).write_text(base64.b64encode(sig).decode("ascii") + "\n")
    print("signed %s with key %s -> %s" % (a.manifest, R.key_id(pub), a.output))


def cmd_verify(a):
    pub = bytes.fromhex(a.pubkey)
    trusted = {R.key_id(pub): a.pubkey}
    state = Path(a.state) if a.state else None
    h = R.verify_release(Path(a.dir), trusted, state, today=datetime.date.today().isoformat(),
                         manifest_path=Path(a.manifest) if a.manifest else None, sig_path=Path(a.sig) if a.sig else None)
    print("OK: version %s, sequence %s, signed by %s%s" % (h["version"], h["sequence"], h["key-id"], "  (EXPIRED)" if h.get("expired") else ""))


def cmd_pubkey(a):
    pub = R.public_from_seed(read_seed(Path(a.key_file)))
    print("public key: %s\nkey id:     %s" % (pub.hex(), R.key_id(pub)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    m = sp.add_parser("manifest"); m.add_argument("dir"); m.add_argument("--version", required=True); m.add_argument("--sequence", type=int, required=True)
    m.add_argument("--pubkey", required=True); m.add_argument("--created"); m.add_argument("--expires"); m.add_argument("-o", "--output", default="RELEASE.manifest"); m.set_defaults(f=cmd_manifest)
    s = sp.add_parser("sign"); s.add_argument("manifest"); s.add_argument("--key-file", required=True); s.add_argument("-o", "--output", default="RELEASE.manifest.sig"); s.set_defaults(f=cmd_sign)
    v = sp.add_parser("verify"); v.add_argument("dir"); v.add_argument("--pubkey", required=True); v.add_argument("--manifest"); v.add_argument("--sig"); v.add_argument("--state"); v.set_defaults(f=cmd_verify)
    k = sp.add_parser("pubkey"); k.add_argument("--key-file", required=True); k.set_defaults(f=cmd_pubkey)
    a = ap.parse_args()
    try:
        a.f(a)
    except R.ReleaseError as e:
        sys.exit("FAILED: %s" % e)


if __name__ == "__main__":
    main()
