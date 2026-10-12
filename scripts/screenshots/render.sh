#!/usr/bin/env bash
# Renders the README screenshots into docs/screenshots/ (English <name>.png,
# German <name>.de.png).
#
# Nothing is captured from the real screen and no real windows or user data are
# read: the harness draws invented demo windows itself and renders Snapline's own
# view code (flyout grid, zone overlay, Snap Assist cards) offscreen at 2×.
#
# How it works: SnaplineCore is compiled as a static library, the app's UI sources
# (without main.swift / AppDelegate / LayoutStore / controllers) are compiled
# together with the harness in this folder, and the result is wrapped in a
# temporary .app bundle with the Resources/*.lproj folders so L10n resolves the
# real translations. The harness never ships in Snapline.app.
#
# Usage: scripts/screenshots/render.sh            (all languages)
#        WORK_DIR=/some/tmp scripts/screenshots/render.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="docs/screenshots"
WORK="${WORK_DIR:-$(mktemp -d)}"
[ -n "${WORK_DIR:-}" ] || trap 'rm -rf "${WORK:?}"' EXIT
mkdir -p "$WORK" "$OUT"
rm -rf "${WORK:?}/src" "${WORK:?}/mods" "${WORK:?}/SnaplineShots.app"
mkdir -p "$WORK/src" "$WORK/mods"

# App sources the screenshots need. Their file-private view classes are made
# module-internal in the copy so the harness can instantiate them.
APP_SOURCES=(
    L10n.swift Screens.swift SnapEngine.swift Settings.swift
    AX/AXWindow.swift AX/WindowList.swift AX/ThumbnailProvider.swift
    UI/LayoutFlyout.swift UI/ZoneOverlay.swift UI/SnapAssist.swift
)
for f in "${APP_SOURCES[@]}"; do
    sed -E 's/^private (final class|class|struct|enum) /\1 /' "Sources/Snapline/$f" > "$WORK/src/$(basename "$f")"
done

SWIFTC=(xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos14.0")

"${SWIFTC[@]}" -parse-as-library -module-name SnaplineCore -emit-library -static \
    -emit-module -emit-module-path "$WORK/mods/SnaplineCore.swiftmodule" \
    -o "$WORK/libSnaplineCore.a" Sources/SnaplineCore/*.swift

APP="$WORK/SnaplineShots.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
"${SWIFTC[@]}" -module-name SnaplineShots -I "$WORK/mods" -L "$WORK" -lSnaplineCore \
    -o "$APP/Contents/MacOS/SnaplineShots" "$WORK"/src/*.swift scripts/screenshots/*.swift
for lproj in Resources/*.lproj; do cp -R "$lproj" "$APP/Contents/Resources/"; done
# Own bundle id: the harness must never see Snapline's preferences.
sed -e 's/<string>io.github.leonatwork.snapline<\/string>/<string>io.github.leonatwork.snapline.screenshots<\/string>/' \
    -e 's/<string>Snapline<\/string>/<string>SnaplineShots<\/string>/' \
    Resources/Info.plist > "$APP/Contents/Info.plist"

for lang in ${LANGS:-en de}; do
    suffix=""; [ "$lang" = en ] || suffix=".$lang"
    "$APP/Contents/MacOS/SnaplineShots" "${OUT_OVERRIDE:-$OUT}" "$suffix" \
        -AppleLanguages "($lang)" -AppleLocale "$([ "$lang" = en ] && echo en_US || echo de_DE)" -gap 8 -AppleAccentColor 4 -AppleHighlightColor "0.698039 0.843137 1.000000 Blue"
done
echo "Screenshots written to $OUT/"
