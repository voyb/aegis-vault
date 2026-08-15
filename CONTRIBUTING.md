# Contributing

Aegis is a single `index.html` file on purpose, no build step, no
framework, no bundler. Contributions that keep it that way are the
easiest to review and merge.

## Reporting bugs

Open an issue with your OS, browser, and exact steps to reproduce. If it
is a security issue, see [SECURITY.md](SECURITY.md) instead of a public
issue.

## Code style

- Vanilla JS/CSS/HTML, matching what is already there. No new
  dependencies without a real reason, the current footprint is
  Argon2id (hash-wasm) and a static word list, that is deliberate.
- Follow the existing patterns: template-literal `innerHTML` blocks,
  `esc()`/`escAttr()` for anything user-controlled, `openModal()`/
  `closeModal()` for dialogs.
- Keep the aesthetic: near-black background, gunmetal borders, gold
  accents used sparingly, tracked-out uppercase section titles.

## Pull requests

- Small, focused PRs are easier to review than large ones. If you are
  planning something big, open an issue first to talk through the
  approach.
- Test the change by actually opening `index.html` in a browser and
  exercising the flow you touched, there is no automated test suite.
- If you touch `aegis_launcher.py`, `aegis.spec`, or the install
  scripts, mention which OS you tested on, I cannot verify macOS/Linux
  changes locally.

## What is especially welcome

Security review of the crypto code in `index.html` (search for
`CRYPTO`), and testing the install scripts and packaged executables on
OSes and configurations I have not personally covered.
