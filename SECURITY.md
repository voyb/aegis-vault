# Security

Aegis is a security tool. Trust in it should be earned through code you
can read and verify, not through claims. This document exists so that
verification is easy.

## Verify the binaries match the source

Every release executable is built by the [GitHub Actions workflow](.github/workflows/build.yml)
directly from this repository, on GitHub's own runners, not on any
machine of mine. You can:
- Read the exact build steps in `.github/workflows/build.yml`.
- Compare a release's build log against the tagged commit it claims to
  build from, in the [Actions tab](../../actions).
- Build it yourself from source instead of trusting the release binary,
  with `pyinstaller aegis.spec --noconfirm`.

## What the app actually claims

The in-app **Security** page (and the "Security model" section of the
[README](README.md#security-model)) states plainly what Argon2id and
AES-256-GCM protect against, and what no software-only vault can protect
against. Read that before trusting this, or any other password manager,
with real secrets.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting (Security tab,
"Report a vulnerability") rather than a public issue, so a fix can ship
before the details are public. If that is not available, open a normal
issue describing the problem in general terms and ask for a private
channel.

## Scope

In scope: the encryption and key-derivation code in `index.html`, the
duress vault's isolation guarantees, the launcher scripts, and the build
pipeline. Out of scope: an attacker who already has arbitrary code
execution on your unlocked device, this is a stated limitation, not a
bug, see the Security page.

Code reviews, security audits, and pull requests are genuinely welcome.
This is exactly the kind of project that benefits from more eyes on it.
