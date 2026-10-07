#!/usr/bin/env bash
# Builds dist/Snapline.app (release, signed).
#
# Signing: uses $SIGN_IDENTITY if set, otherwise a code-signing identity named
# "Snapline Dev" if one exists, otherwise ad-hoc. With ad-hoc signing macOS treats
# every build as a new app, so the Accessibility permission must be granted again
# after each rebuild – see README.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Snapline.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Snapline"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Snapline"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Snapline Dev"; then
    IDENTITY="Snapline Dev"
fi
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"
