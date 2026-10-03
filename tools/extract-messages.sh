#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Refresh po/klaude-monitor.pot from the QML sources and merge it into every po/*.po.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
find shared/qml plasmoids -name '*.qml' | sort | xargs xgettext --from-code=UTF-8 -C \
  -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
  --package-name=plasma-klaude-monitor --msgid-bugs-address=https://github.com/aqu1ntero/plasma-klaude-monitor/issues \
  -o po/klaude-monitor.pot
for po in po/*.po; do
  [ -e "$po" ] || continue
  msgmerge -q --update --backup=none "$po" po/klaude-monitor.pot
done
echo "updated po/klaude-monitor.pot"
