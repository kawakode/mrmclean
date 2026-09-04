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
- Alerts: enable a per-category threshold as a share of total disk size. When a
  category crosses it, MrMcLean posts a notification. Cooldown and re-alert growth
  are configurable.

## About "System Data"

The large "System Data" figure in System Settings is mostly APFS snapshots, swap,
and protected system files. MrMcLean acts on the parts that are safe to remove
(snapshots, user and system caches, logs, diagnostic reports). The rest is managed
by macOS and freed automatically under disk pressure, or needs a restart.

## Install

Download the DMG from the [Releases](../../releases) page. The build is unsigned.
On first launch, right-click the app and choose Open, then confirm.

MrMcLean runs as a menu bar item. Enable a Dock icon in Settings if you prefer.

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
