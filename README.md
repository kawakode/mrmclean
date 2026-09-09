# MrMcLean

A small macOS storage cleaner with automatic file rules and configurable alerts. Native SwiftUI, no
third-party dependencies, targets macOS 14 Sonoma and later.

## What it does

- Scans on-disk usage by category: user caches, system caches and logs, app logs,
  Trash, Time Machine local snapshots, Xcode and developer files, dev tool caches,
  Mail downloads, iOS backups, large files.
- Reviews the selected files or dev-tool commands before each cleanup.
- Cleans the safe parts of each category. User-level items go straight through an
  allowlist. Root-owned system caches and snapshot thinning run through one
  administrator password prompt, with the exact shell script shown first.
- **Caches & Logs**: the quick action clears user caches and app logs. Developer
  archives and the Trash are reviewed separately through their categories or Full Clean.
- **Full Clean**: one button clears every safe category in a single pass — user
  caches, app logs, Xcode and developer files, the Trash, and (opt-in) the
  enabled dev-tool caches and the root-owned system step. It plays a progress
  animation while it works and ends on a report: space freed, items removed,
  time taken, and disk free space before and after. The setup includes the exact
  administrator script when the system step is selected; failed commands and
  skipped files stay visible in the report.
- Large Files: scan on demand, filter by name or path, and reveal results in Finder.
  Partial scans are marked; the largest 100 files are listed and all matches count
  toward the total.
- Choose which detected dev tools participate in Full Clean under Settings › Cleaners.
- Alerts: enable a per-category threshold as a share of total disk size. When a
  category crosses it, MrMcLean posts a notification. Cooldown and re-alert growth
  are configurable. Background scans continue even when notifications are disabled.
- File Rules: match metadata in selected folders, then move files into folders,
  add Finder tags, rename them using templates, or move them to the Trash.
- Low-storage alerts: notify when available space falls to a configured percentage
  or number of GB.
- App file-activity alerts: watch an app's logs or output folder for too many new
  files or too much added data within a configurable time window.

## Automatic file management

Open **File Rules** in the sidebar and add a rule. Choose a source folder, whether
to include subfolders, and whether all or any conditions must match. Conditions
support file names, extensions, kinds (image, audio, video, document, archive,
other), size in decimal MB, creation/modification/access age in days, and Finder
tags. Text comparisons ignore case. Last accessed uses filesystem access time;
files without an access date do not match that condition.

Actions run in the order shown. Add a Finder tag without removing existing tags,
rename a file, or move it into a selected folder with optional date/extension
subfolders. A Trash action must be the rule's only action. Filename and subfolder
templates support `{name}` (without extension), `{ext}`, `{year}`, `{month}`,
`{day}`, `{created}` and `{modified}`. Dates use the file's creation date, except
`{modified}`; full dates are `yyyy-MM-dd`. For example, rename to
`{created}-{name}.{ext}` or arrange files under `{ext}/{year}/{month}`.

**Preview** lists the proposed actions and skipped files without changing anything.
Enable the rule and the main automatic-rules switch to authorize scheduled changes.
Choose a 1, 5, 15 or 60 minute interval, or use **Run Enabled Rules Now**. Rules run
while MrMcLean is open, including with its main window closed. They wait while
another scan or cleanup is running. Rules are disabled by default.
Turning off the main switch pauses a running batch after the current file finishes.

Rules run in displayed order and handle a file at most once per pass. Persistent
history prevents the same file from being processed again by the same rule version,
including after restarting the app. Editing a rule's conditions, folder or actions
allows another run; simply renaming or toggling a rule does not. Recent Activity
shows completed, interrupted and failed actions. Interrupted or partially failed
sequences are not automatically retried; inspect the file before changing the rule.

Rules can manage specific folders in your home directory or on an external volume.
Within Library, only Logs and Caches can be modified. Moves must stay on one volume
so file identity survives; moving between volumes is reported as a skipped action.
Existing destinations are never replaced. Hidden files/folders, symbolic and hard
links, packages, incomplete downloads (`.download`, `.crdownload`, `.part`, `.tmp`)
and files modified in the last 30 seconds are skipped. Scans stop after 20,000
entries or 15 seconds; an incomplete scan performs no actions and reports why.
History must be saved successfully before a file can be changed.

## Configuring alerts

Under **Settings → Alerts**, enable alerts and choose a low-space threshold, add
activity alerts, or keep using the category thresholds. Low-space checks use
available capacity including purgeable space that macOS can reclaim. Low-space and
activity checks run every 30 or 60 seconds independently of the slower category
scans. macOS notification permission is required; the pane displays its status.
Notification cooldowns advance only after macOS accepts a notification request.

For an activity alert, choose a specific app's logs or output folder and give it an
app/folder label. Set a rolling window of 1–60 minutes and thresholds for new-file
count, added MB, or both; either threshold can trigger the alert. Added data includes
growth of existing files, so one rapidly growing log also triggers a warning.
Deleting other files does not cancel this growth. The shared cooldown limits
repeated notifications; the growth override applies only to category-size alerts.

Activity monitoring observes folders, not processes: all writers in a chosen folder
contribute to its alert. Unlike modification rules, these read-only monitors can
also watch specific folders in Application Support or app containers. The first
successful check establishes a baseline; restarting, changing settings, an incomplete
scan or a long sleep starts a new baseline without treating existing files as new.
Counts are sampled, so files created and removed between checks can be missed, and
window boundaries are approximate to the check interval. Checks pause during other
disk operations and stop when the app quits.

Existing settings are preserved when upgrading. Rules and alert preferences live in
`~/Library/Application Support/MrMcLean/config.json`; execution receipts live beside
them in `rule-history.jsonl`. Removing that history allows rules to process files again.

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

Download the DMG or zip from the [Releases](../../releases) page. Open the DMG
and drag `MrMcLean.app` onto the **Applications** shortcut to install it. If using
the zip, extract it and move `MrMcLean.app` to `/Applications`.

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

## UI smoke checks

`bash Scripts/ui-smoke.sh settings` opens the actual views with synthetic data and
in-memory settings. Disk scans and cleanup execution are disabled in this harness.
Other screens: `overview`, any category ID (for example `userCaches` or
`largeFiles`), `gate`, `setup`, `review`, `running`, `report`, `fileRules`,
`ruleEditor`, `rulePreview`, `alerts`, and `activityEditor`. Append `--dark`
for dark appearance. Append `--snapshot /tmp/screen.png` to capture the app view
and exit automatically, or stop the interactive harness with Ctrl-C.

`bash Scripts/ui-smoke.sh automationChecks` exercises background scheduling,
enabled/disabled rules, busy/access guards, and activity status with disposable
temporary files. It does not start real scans or send notifications.

The normal test runner exercises parsing, allowlists, subprocess failures and
filesystem regressions using disposable fixtures. It never runs administrator or
dev-tool cleanup commands. A live scan is read-only.

## Release pipeline

`.github/workflows/release.yml` builds a universal binary on a `macos-14` runner,
packages `MrMcLean.app` into a DMG and a zip, and attaches them to a GitHub Release.
It triggers on a pushed `v*` tag, or manually via `workflow_dispatch` with a version
input. No secrets required.

`.github/workflows/ci.yml` builds and tests on every push and pull request.

## Safety

- Every user-level cleanup deletion is checked against an allowlist. Paths under `/System`,
  Documents, Desktop, Downloads, Photos, iCloud Drive, and the Mail message store
  are always rejected.
- Cleaning is dry-run first and requires explicit confirmation. Separately, enabling
  File Rules authorizes their automatic actions inside the selected folders; rules
  only move files to Trash and never permanently delete them.
- The administrator step writes its script to a temp file, shows it verbatim, and
  runs it once. It contains no network calls and no deletion outside the printed list.

## License

GNU AGPL-3.0-or-later. See [LICENSE](LICENSE).
