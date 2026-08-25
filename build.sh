#!/bin/bash
# Builds OptionTab.app. Run this on the Mac, not in a Linux container.
set -euo pipefail

cd "$(dirname "$0")"

APP="OptionTab.app"
CONFIG="release"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/OptionTab"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OptionTab"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Accessibility grants are keyed to the code signature, so the bundle must be
# signed even for local use. Ad-hoc is enough, but note that its hash changes on
# every build -- see the README for what that means for permissions.
codesign --force --sign - "$APP"

echo "Built ./$APP"
echo "Run it with: open ./$APP"
