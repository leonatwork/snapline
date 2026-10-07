#!/usr/bin/env bash
# Builds dist/Snapline.app (release, signed).
#
# Signing: $SIGN_IDENTITY if set, otherwise "Snapline Local Signing" (create it once
# with scripts/setup-signing.sh) or Tappi's local identity, otherwise ad-hoc. With
# ad-hoc signing macOS treats every build as a new app and forgets the
# Accessibility / Screen Recording grants.
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
if [ -z "$IDENTITY" ]; then
    for candidate in "Snapline Local Signing" "Tappi Local Signing"; do
        if security find-identity -p codesigning 2>/dev/null | grep -q "$candidate"; then
            IDENTITY="$candidate"
            break
        fi
    done
fi
if [ -z "$IDENTITY" ]; then
    echo "!!  signing ad-hoc: macOS forgets granted permissions on every rebuild."
    echo "!!  run scripts/setup-signing.sh once to avoid that."
fi
codesign --force --options runtime --timestamp=none --sign "${IDENTITY:--}" "$APP"

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"
