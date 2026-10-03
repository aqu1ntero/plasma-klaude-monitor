#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Assemble the two plasmoid packages into build/: copy the shared QML into each package, add the
# icon, compile the translations, and zip them as .plasmoid files (for GitHub releases / KDE Store).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build"
rm -rf "$OUT"
mkdir -p "$OUT"

for name in panel desktop; do
  src="$ROOT/plasmoids/$name"
  id=$(sed -n 's/.*"Id": *"\([^"]*\)".*/\1/p' "$src/metadata.json")
  dst="$OUT/$id"
  cp -r "$src" "$dst"
  mkdir -p "$dst/contents/ui/shared" "$dst/contents/images"
  cp "$ROOT"/shared/qml/* "$dst/contents/ui/shared/"
  cp "$ROOT/data/klaude-monitor.svg" "$dst/contents/images/"
  if command -v msgfmt >/dev/null 2>&1; then
    for po in "$ROOT"/po/*.po; do
      [ -e "$po" ] || continue
      lang=$(basename "$po" .po)
      mkdir -p "$dst/contents/locale/$lang/LC_MESSAGES"
      msgfmt -o "$dst/contents/locale/$lang/LC_MESSAGES/plasma_applet_$id.mo" "$po"
    done
  else
    echo "msgfmt not found: building without translations" >&2
  fi
  (cd "$dst" && zip -qr "$OUT/$id.plasmoid" .)
  echo "built $dst ($id.plasmoid)"
done
