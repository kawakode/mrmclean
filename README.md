# MrMcLean

A small macOS storage cleaner with per-category size alerts. Native SwiftUI, no
third-party dependencies, targets macOS 14 Sonoma and later.

## What it does

- Scans on-disk usage by category: user caches, system caches and logs, app logs,
  Trash, Time Machine local snapshots, Xcode and developer files, dev tool caches,
  Mail downloads, iOS backups, large files.
- Cleans the safe parts of each category. User-level items go straight through an
  allowlist. Root-owned system caches and snapshot thinning run through one
  administrator password prompt, with the exact shell script shown first.
- **Full Clean**: one button clears every safe category in a single pass — user
  caches, app logs, Xcode and developer files, the Trash, and (opt-in) the
  enabled dev-tool caches and the root-owned system step. It plays a progress
  animation while it works and ends on a report: space freed, items removed,
  time taken, and disk free space before and after.
- Alerts: enable a per-category threshold as a share of total disk size. When a
  category crosses it, MrMcLean posts a notification. Cooldown and re-alert growth
  are configurable.

## First launch

MrMcLean needs Full Disk Access to do anything useful. On launch, if the grant is
missing it opens an onboarding screen that explains the steps, opens the right
System Settings pane, and re-checks on a timer so it closes itself once access is
on — no relaunch needed in most cases, with a Quit & Reopen button for when macOS
wants one. "Continue with limited access" starts the app anyway with reduced,
lower-than-real size figures.

## About "System Data"

The large "System Data" figure in System Settings is mostly APFS snapshots, swap,
and protected system files. MrMcLean acts on the parts that are safe to remove
(snapshots, user and system caches, logs, diagnostic reports). The rest is managed
by macOS and freed automatically under disk pressure, or needs a restart.

## Install

Download the DMG or zip from the [Releases](../../releases) page and move
`MrMcLean.app` to `/Applications`.

The build is **not notarized**, so macOS Gatekeeper blocks it on first launch —
on recent macOS a double-click does nothing at all. Clear the quarantine flag,
then open it:

```sh
xattr -dr com.apple.quarantine /Applications/MrMcLean.app
open /Applications/MrMcLean.app
```

(Alternatively: double-click it, then open System Settings › Privacy & Security
and click **Open Anyway**.)

MrMcLean runs as a menu bar item. Enable a Dock icon in Settings if you prefer.

## Full Disk Access

macOS hides many folders (Mail, Messages, Safari, protected caches) from apps
that do not hold Full Disk Access. There is no system prompt for it, so MrMcLean
shows its own onboarding screen on first launch (see above): grant it in
System Settings › Privacy & Security › Full Disk Access, add MrMcLean, and the
screen closes itself once the grant lands. Without it, category sizes read lower
than the real usage; MrMcLean also keeps a warning on the Overview with a button
that opens the right pane. Root-owned system caches always need the separate
administrator step regardless of Full Disk Access.

## Build from source

Requires the Swift 6 toolchain. The Command Line Tools are enough; full Xcode is
only needed to cross-compile the Intel slice.

```
make build      # compile
make test       # run the test runner (plain executable, no XCTest needed)
make app        # assemble dist/MrMcLean.app, ad-hoc signed, plus DMG and zip
make run        # build and launch
make app VERSION=1.2.3
```

`make app` produces a universal binary when full Xcode is present, otherwise a
binary for the host architecture. `MRMCLEAN_LIVE=1 swift run MrMcLeanTests` also
runs a real scan and prints the category sizes.

## Release pipeline

`.github/workflows/release.yml` builds a universal binary on a `macos-14` runner,
packages `MrMcLean.app` into a DMG and a zip, and attaches them to a GitHub Release.
It triggers on a pushed `v*` tag, or manually via `workflow_dispatch` with a version
input. No secrets required.

`.github/workflows/ci.yml` builds and tests on every push and pull request.

## Safety

- Every user-level deletion is checked against an allowlist. Paths under `/System`,
  Documents, Desktop, Downloads, Photos, iCloud Drive, and the Mail message store
  are always rejected.
- Cleaning is dry-run first. Nothing is removed without an explicit confirm.
- The administrator step writes its script to a temp file, shows it verbatim, and
  runs it once. It contains no network calls and no deletion outside the printed list.

## License

GNU AGPL-3.0-or-later. See [LICENSE](LICENSE).
