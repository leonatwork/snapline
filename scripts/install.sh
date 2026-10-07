#!/usr/bin/env bash
# Builds Snapline, copies it to /Applications and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
pkill -x Snapline 2>/dev/null || true
rm -rf /Applications/Snapline.app
cp -R dist/Snapline.app /Applications/
open /Applications/Snapline.app
echo "Installed /Applications/Snapline.app"
