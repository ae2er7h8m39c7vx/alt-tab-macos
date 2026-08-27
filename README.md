# OptionTab

⌥Tab switches **windows** on macOS, not applications.

macOS gives you ⌘Tab (per *application*) and ⌘` (windows of the *current* app only).
There is no built-in "cycle every window on the machine". This is that, bound to ⌥Tab.

## Behaviour

| Keys | Effect |
|---|---|
| `⌥Tab` | Open the switcher over every window, move forward one |
| `⌥⇧Tab` | Move backward |
| `⌥\`` | Open the switcher over the front app's windows only, move forward one |
| `⌥⇧\`` | Move backward |
| release `⌥` | Focus the highlighted window |
| `Esc` (while held) | Cancel, change nothing |
| click a tile | Focus that window |

A single quick ⌥Tab tap flips to the previously-used window, the way ⌘Tab does for apps;
a single ⌥\` tap does the same within the front app, the way ⌘\` does.
Minimized windows appear at the end of the list and are un-minimized when chosen.

The scope is fixed by whichever chord opens the session, so pressing ⌥\` part-way
through an ⌥Tab hold just moves the cursor — it does not narrow the list.

## Build

Requires macOS 12+ and Xcode command line tools. Releases target Apple Silicon;
building natively on an Intel Mac works too.

```sh
./build.sh                  # build for this machine
ARCH=arm64 ./build.sh       # build for a specific architecture
open ./OptionTab.app
```

To launch at login: System Settings ▸ General ▸ Login Items ▸ **+** ▸ `OptionTab.app`.

## Permissions

On first launch macOS prompts for **Accessibility** access
(System Settings ▸ Privacy & Security ▸ Accessibility). It is needed twice over:
to install the keyboard event tap, and to enumerate and raise other apps' windows.
The app polls once a second and starts working the moment you grant it — no relaunch.

Screen Recording is *not* required: window titles come from the Accessibility API
rather than from `CGWindowListCopyWindowInfo`, so tiles show app icons instead of
live window thumbnails.

> **After each rebuild**, remove OptionTab from the Accessibility list and re-add it.
> Ad-hoc signatures get a fresh hash every build, and macOS treats the new binary as
> a different app. A real Developer ID signing identity in `build.sh` avoids this.

## How it works

- **`HotKeyTap`** — a `CGEventTap` on the session. A Carbon hot key cannot see a
  modifier being *released*, and "hold ⌥, tab through, release to pick" depends on
  exactly that. The tap also swallows the chord so no app underneath reacts to it.
- **`WindowLister`** — walks `NSWorkspace.runningApplications` (or just the frontmost
  one, for ⌥\`), pulls each app's windows over the Accessibility API (titles,
  minimized state, and the handles used to raise them), then reorders that set by
  the front-to-back z-order reported by
  `CGWindowListCopyWindowInfo`. macOS exposes no MRU list, but z-order is an
  accurate stand-in: the last window you used is the one in front. The two views are
  correlated through the private `_AXUIElementGetWindow`, the same bridge AltTab
  uses; if it ever fails, those windows fall to the end of the list rather than
  vanishing.
- **`Switcher`** — snapshots the window list once when the session opens, so nothing
  shuffles under the cursor mid-tab.
- **`SwitcherPanel`** — a non-activating `NSPanel`. It must never take key focus,
  since doing so would itself disturb the ordering being navigated.

## Known limits

- Tiles show app icons, not window previews (that would require Screen Recording).
- Windows on other Spaces can be listed but macOS will switch Spaces to focus them.
- Apps that expose no Accessibility window tree (a few Electron and Java apps in
  odd configurations) will not be listed.

## Prior art

[AltTab](https://github.com/lwouis/alt-tab-macos) does all of this and much more —
window thumbnails, per-app filtering, extensive preferences. Use it if you want a
finished product; this is a single-purpose ~600-line version with no configuration.

## CI

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds on `macos-latest`
for every push, PR and manual dispatch. It calls the same `build.sh` you run
locally — CI and your machine cannot drift — with `ARCH=arm64`, then asserts the
resulting binary really is arm64 before uploading `OptionTab-arm64.zip` as a
workflow artifact.

Releases are **Apple Silicon only**. Intel Macs are not supported; building for
them is a matter of setting `ARCH=x86_64`, or dropping the `--arch` flag for a
native build.

Pushing a `v*` tag additionally publishes that zip as a GitHub release:

```sh
git tag v1.0 && git push origin v1.0
```

The bundle is **ad-hoc signed and not notarized**, because notarization needs a
paid Apple Developer ID and its secrets. Anyone downloading a release therefore
has to clear the quarantine flag Gatekeeper sets on it:

```sh
xattr -dr com.apple.quarantine OptionTab.app
```

To notarize properly, add `APPLE_CERTIFICATE_P12`, `APPLE_CERTIFICATE_PASSWORD`,
`APPLE_TEAM_ID` and an app-specific password as repository secrets, import the
cert into a temporary keychain, sign with `--options runtime` instead of `--sign -`,
and run `xcrun notarytool submit --wait` followed by `xcrun stapler staple`.
