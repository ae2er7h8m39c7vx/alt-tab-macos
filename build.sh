#!/bin/bash
# Builds OptionTab.app. Run this on the Mac, not in a Linux container.
#
#   ./build.sh              native binary for this machine
#   UNIVERSAL=1 ./build.sh  arm64 + x86_64, for distributing to other Macs
set -euo pipefail

cd "$(dirname "$0")"

APP="OptionTab.app"
CONFIG="release"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
# Note: macOS ships bash 3.2, where a bare "${empty[@]}" trips `set -u`,
# hence the ${x[@]+...} guard on every expansion below.
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
