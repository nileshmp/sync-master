# macbackup 🗄️

Lightweight, incremental backup utility for macOS → external HDD.  
Built on `rsync` — only copies **changed files**, supports **compression**, and is fully **git-trackable**.

---

## Features

| Feature | Detail |
|---|---|
| ⚡ Incremental | `rsync --update` — only copies new or changed files |
| 🗜️ Compression | Optional `.tar.gz` archives per destination, with auto-pruning |
| 🗂️ Multi-destination | Each source can sync to multiple destinations in one run |
| 👤 Profiles | Named source sets (`work`, `photos`, `default`…) |
| 🔤 Spaces in paths | Directory names with spaces work without quoting |
| 🧪 Dry-run | Preview exactly what would be copied — no changes made |
| 🔍 Diff | Show what differs between source and destination — no changes made |
| 📋 Logs | Timestamped log file per run in `logs/` |
| 🔄 Scheduled | Works with `cron` or `launchd` |

---

## Setup

```bash
# 1. Clone / copy this repo
git clone https://github.com/YOU/macbackup ~/macbackup
cd ~/macbackup

# 2. Create your config (gitignored — your real paths never get committed)
cp backup.config.example backup.config

# 3. Edit backup.config — set your profiles and destinations
nano backup.config

# 4. Run!
./backup.sh
```

---

## Usage

```bash
# Basic incremental backup (default profile)
./backup.sh

# With compression — creates a timestamped .tar.gz per destination
./backup.sh --compress

# Preview only — no files are changed
./backup.sh --dry-run

# Use a named profile
./backup.sh --profile work
./backup.sh --profile photos --compress

# List all profiles defined in backup.config
./backup.sh --list-profiles

# Verbose — print every file being transferred
./backup.sh --verbose --profile work

# Mirror mode — also delete files on HDD that were deleted from source
# ⚠️  Read the warning below before using this
./backup.sh --mirror

# Show what differs between source and destination (no changes made)
./backup.sh --diff
./backup.sh --diff --profile work
```

---

## Config Reference (`backup.config`)

The config uses a simple INI-style format with named sections:

```ini
[profile:default]
~/Documents              : /Volumes/HDD/Docs, /Volumes/NAS/Docs
~/Desktop                : /Volumes/HDD/Desktop
~/.config                : /Volumes/HDD/Config

[profile:work]
~/Projects               : /Volumes/HDD/Code, /Volumes/NAS/Code
~/.ssh                   : /Volumes/HDD/Dotfiles

[profile:photos]
~/Pictures               : /Volumes/HDD/Photos, /Volumes/NAS/Photos
# Paths with spaces work fine — no quoting needed:
~/Pictures/from pixel-6a : /Volumes/HDD/Phone Photos

[excludes]
node_modules, .git, .DS_Store, *.tmp, venv, dist, build

[settings]
ARCHIVE_KEEP=5
```

### Mapping format

```
<source> : <destination1>, <destination2>, ...
```

- The separator between source and destinations is ` : ` (space · colon · space)
- Destinations are comma-separated; spaces inside path names are fine — no quoting needed
- `~` expands to your home directory
- Each source syncs to **all** listed destinations independently
- Multiple source lines per profile are all processed in order
- Lines starting with `#` are comments

---

## ⚠️ --mirror flag

By default the script only ever **adds** files to your destination — it will **never delete** anything from the destination. Extra files on the HDD that no longer exist in the source are left untouched. This is the safe default for backup drives.

`--mirror` enables `rsync --delete`, which makes the destination an **exact copy** of the source. Any file on the HDD that no longer exists in the source folder will be **permanently deleted**.

Only use `--mirror` if you are certain the destination contains nothing you want to keep beyond what's in the source. Always run `--diff` or `--dry-run` first to preview what would be removed:

```bash
# Preview what would be deleted before mirroring
./backup.sh --profile work --mirror --dry-run

# Then run for real only if the preview looks correct
./backup.sh --profile work --mirror
```

---

## --diff flag

Shows exactly what differs between your source and destination — no files are copied or deleted.

```bash
./backup.sh --diff
./backup.sh --diff --profile work
```

Each line of output is prefixed with a change code:

| Code | Meaning |
|---|---|
| `>f+++++++++` | New file — exists in source, missing from destination |
| `>f.....t...` | File updated — timestamps or size differ |
| `*deleting` | File removed from source (only shown if `--mirror` would delete it) |

Use `--diff` before a first-time sync to verify your mappings, or periodically to see what has changed since your last backup.

---

## Scheduled Backups

### Using `cron`
```bash
crontab -e

# Daily at 11pm — default profile with compression
0 23 * * * /Users/YOU/macbackup/backup.sh --compress >> /Users/YOU/macbackup/logs/cron.log 2>&1

# Every 6 hours — work profile
0 */6 * * * /Users/YOU/macbackup/backup.sh --profile work >> /Users/YOU/macbackup/logs/cron.log 2>&1
```

### Using `launchd` (macOS native, preferred)
```bash
# Install the provided plist:
cp launchd/com.macbackup.daily.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.macbackup.daily.plist
```

---

## What's Git-tracked

```
✅ backup.sh               — the script
✅ backup.config.example   — config template (no real paths)
✅ README.md
✅ launchd/                — scheduler plists
❌ backup.config           — gitignored (contains your real paths)
❌ logs/                   — gitignored (local only)
❌ *.tar.gz                — gitignored (large binary files)
```

---

## Requirements

- macOS (tested on Ventura / Sonoma / Sequoia)
- `rsync` — pre-installed on macOS; run `brew install rsync` for a modern version (2.6.9 ships by default, 3.x recommended)
- `bash` 4+ — `brew install bash` if needed (macOS ships bash 3.2)

---

## Tips

- Run `diskutil list` to find your HDD's mount name under `/Volumes/`
- Always use `--dry-run` before the first backup to a new destination
- Check the log after any run: `cat logs/backup_<timestamp>.log`
- To see what a previous run deleted (if `--mirror` was used): `grep "^deleting" logs/backup_*.log`
- For best progress display, install the modern rsync: `brew install rsync`


# Recovery (accidental deletion)
- sudo photorec /dev/rdisk4 (use raw disk [rdisk4])
  