#!/usr/bin/env bash
# Aegis one-command installer for macOS and Linux.
#
# Downloads the latest release for your OS, unpacks it into ~/Aegis, and
# launches it. Nothing is installed system-wide and no sudo is required.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/voyb/aegis-vault/main/install.sh | bash
set -euo pipefail

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

url="https://github.com/$REPO/releases/latest/download/$asset"
curl -fsSL "$url" -o "$tmp/$asset"

if [ "$os" = "Darwin" ]; then
  unzip -oq "$tmp/$asset" -d "$DEST"
  echo "Installed. Launching Aegis..."
  open "$DEST/Aegis.app"
else
  tar -xzf "$tmp/$asset" -C "$DEST"
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
