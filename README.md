# mBACKUP

[![Listed on OpenMacApps](https://openmacapps.com/badge.svg)](https://openmacapps.com/apps/mbackup/)

Scheduled mirror copies of your folders, in the menu bar. A personal, simplified alternative to Get Backup Pro.

## About

mBACKUP is made by Starbudweiser & Claude Code (Anthropic). MIT License, © 2026 Starbudweiser. Provided as is, without warranty: check your copies before relying on them. Inspired by Get Backup Pro, not affiliated with BeLight Software. See "About mBACKUP" in the app menu.

## Features

- Mirror synchronization (rsync 3.x) from a source folder to a destination, with the same options as Get Backup Pro.
- Per-task schedule (days, time), catch-up of a missed run, automatic mounting of external disks and SMB shares.
- Optional versioned copies (replaced or deleted files go to a dated folder next to the destination, N kept).
- Dry run (simulation), exclusion patterns, optional administrator rights per task (password stored in the Keychain).
- Menu bar app, opens at login. Languages: French, English, Spanish, Italian. Interface follows the Socle design system.

## Build

```bash
./build_app.sh     # builds, signs and installs ~/Applications/Applications Personnelles/mBACKUP.app
./tests/run_tests.sh
```

The build embeds the rsync 3.2.3 binary kept in `Resources/rsync`, and falls back to the system rsync if it is missing. rsync is free software under the GNU GPL v3 (© Andrew Tridgell, Wayne Davison and contributors); its source code is available at https://rsync.samba.org and https://github.com/RsyncProject/rsync. It is shipped unmodified.

If protected folders fail (iCloud Drive, Library), grant mBACKUP Full Disk Access in System Settings.
