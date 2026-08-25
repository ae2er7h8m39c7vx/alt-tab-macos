#!/bin/bash
# Builds OptionTab.app. Run this on the Mac, not in a Linux container.
#
#   ./build.sh              build for this machine's architecture
#   ARCH=arm64 ./build.sh   build for a specific architecture
set -euo pipefail

cd "$(dirname "$0")"

APP="OptionTab.app"
CONFIG="release"

# Note: macOS ships bash 3.2, where a bare "${empty[@]}" trips `set -u`,
# hence the ${x[@]+...} guard on every expansion below.
ARCH_FLAGS=()
if [[ -n "${ARCH:-}" ]]; then
    ARCH_FLAGS=(--arch "$ARCH")
fi

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/OptionTab"

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
