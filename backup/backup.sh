#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  macbackup v2.1.0 — incremental, multi-destination backup for macOS
#
#  Config format:
#    [profile:name]
#    ~/source path with spaces : /dest1, /dest 2
#
#  Separator rules:
#    • Source and destinations are separated by  " : "  (space-colon-space)
#    • Destinations are separated by  " , "  (space-comma-space) OR just ","
#    • Paths may contain spaces — do NOT quote them in backup.config
#
#  Usage: ./backup.sh [--compress] [--dry-run] [--profile <name>] [--verbose]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup.config"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

# ── Defaults ──────────────────────────────────────────────────────────────────
COMPRESS=false
DRY_RUN=false
DIFF=false
MIRROR=false
PROFILE="default"
VERBOSE=false
LIST_PROFILES=false

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}✗  $*${NC}" | tee -a "$LOG_FILE" 2>/dev/null || true; exit 1; }
dim()     { echo -e "${DIM}$*${NC}" | tee -a "$LOG_FILE"; }

banner() {
  echo -e "${BOLD}${BLUE}"
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║        macbackup  v2.1.0             ║"
  echo "  ║  incremental · multi-dest · git-safe ║"
  echo "  ╚══════════════════════════════════════╝"
  echo -e "${NC}"
}

usage() {
  echo -e "${BOLD}Usage:${NC} ./backup.sh [options]"
  echo ""
  echo "Options:"
  echo "  --compress          Compress each destination with gzip after sync"
  echo "  --dry-run           Preview what would be copied (no changes made)"
  echo "  --diff              Show differences between source and destination (no changes made)"
  echo "  --mirror            Delete files from destination that no longer exist in source"
  echo "  --profile <name>    Use a named profile from backup.config (default: 'default')"
  echo "  --verbose           Show every file being transferred"
  echo "  --list-profiles     List all profiles defined in backup.config"
  echo "  --usage             Show example commands"
  echo "  --help              Show this help"
  echo ""
  echo "Config format (backup.config):"
  echo "  [profile:work]"
  echo "  ~/Projects  : /Volumes/HDD/Code, /Volumes/NAS/Code"
  echo "  ~/.ssh      : /Volumes/HDD/Dotfiles"
  exit 0
}

show_usage_examples() {
  echo -e "${BOLD}macbackup — example commands${NC}"
  echo ""
  echo -e "${BOLD}Basic sync${NC}"
  echo "  ./backup.sh                                   # sync default profile"
  echo "  ./backup.sh --profile work                    # sync a named profile"
  echo "  ./backup.sh --profile photos                  # sync photos profile"
  echo ""
  echo -e "${BOLD}Preview (no changes made)${NC}"
  echo "  ./backup.sh --dry-run                         # show what would be copied"
  echo "  ./backup.sh --dry-run --profile work          # dry-run for a named profile"
  echo "  ./backup.sh --diff                            # show what differs between source and destination"
  echo "  ./backup.sh --diff --profile work             # diff for a named profile"
  echo ""
  echo -e "${BOLD}Verbose output${NC}"
  echo "  ./backup.sh --verbose                         # print every file transferred"
  echo "  ./backup.sh --verbose --profile work          # verbose for a named profile"
  echo ""
  echo -e "${BOLD}Compression${NC}"
  echo "  ./backup.sh --compress                        # sync and create a .tar.gz archive per destination"
  echo "  ./backup.sh --compress --profile photos       # compress a named profile"
  echo ""
  echo -e "${BOLD}Mirror (destructive — deletes extra files on destination)${NC}"
  echo "  ./backup.sh --mirror --dry-run                # preview what would be deleted"
  echo "  ./backup.sh --mirror                          # exact-copy source → destination"
  echo "  ./backup.sh --mirror --profile work           # mirror a named profile"
  echo ""
  echo -e "${BOLD}Combining flags${NC}"
  echo "  ./backup.sh --profile work --compress --verbose"
  echo "  ./backup.sh --profile photos --compress --dry-run"
  echo "  ./backup.sh --profile work --mirror --dry-run"
  echo ""
  echo -e "${BOLD}Profiles${NC}"
  echo "  ./backup.sh --list-profiles                   # list all profiles in backup.config"
  exit 0
}

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --compress)      COMPRESS=true; shift ;;
    --dry-run)       DRY_RUN=true;  shift ;;
    --diff)          DIFF=true;     shift ;;
    --mirror)        MIRROR=true;   shift ;;
    --verbose)       VERBOSE=true;  shift ;;
    --profile)       PROFILE="${2:-default}"; shift 2 ;;
    --list-profiles) LIST_PROFILES=true; shift ;;
    --help|-h)       usage ;;
    --usage)         show_usage_examples ;;
    *) error "Unknown option: $1. Run --help for usage." ;;
  esac
done

# ── Config parser ──────────────────────────────────────────────────────────────
# Parses the INI-style backup.config into structured data.
# Populates:
#   MAPPING_SRCS[]  — source paths
#   MAPPING_DESTS[] — pipe-separated destination list per source
#   EXCLUDES_LIST   — comma-separated global excludes
#   ARCHIVE_KEEP    — number of archives to retain

[[ -f "$CONFIG_FILE" ]] || error "Config not found: $CONFIG_FILE\nRun: cp backup.config.example backup.config and edit it."

parse_config() {
  local target_profile="$1"
  local current_section=""
  MAPPING_SRCS=()
  MAPPING_DESTS=()
  EXCLUDES_LIST=""
  ARCHIVE_KEEP=5

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    # Strip comments and trim whitespace
    local line
    line="$(echo "$raw_line" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue

    # Section header: [profile:name] or [excludes] or [settings]
    if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi

    case "$current_section" in
      "profile:${target_profile}")
        # ── Parse:  ~/source path : /dest1, /dest 2
        #
        # Delimiter is " : " (space-colon-space) so that colons inside
        # paths (e.g. a drive named "Backup:2") are never mis-split,
        # and so that directory names with spaces are preserved verbatim.
        #
        # We use parameter expansion instead of regex capture groups so
        # that the full path — including any embedded spaces — is kept
        # intact on both sides of the split.

        # Must contain the explicit delimiter " : "
        [[ "$line" != *" : "* ]] && continue

        local raw_src="${line%% : *}"   # everything before first " : "
        local raw_dests="${line#* : }"  # everything after  first " : "

        # Trim trailing whitespace from src (column-aligned configs add padding)
        raw_src="${raw_src%"${raw_src##*[! ]}"}"

        # Expand ~ (parameter expansion is word-split–safe)
        local src="${raw_src/#\~/$HOME}"

        # Split destinations on " , " OR "," — support both styles.
        # We normalise to " , " first, then split on that fixed token
        # using a while-read loop so spaces inside path segments survive.
        local normalised_dests="${raw_dests//,/ , }"  # ensure spaces around comma
        local dests_pipe=""
        while IFS= read -r dest_token; do
          # Trim leading/trailing whitespace from each token
          dest_token="${dest_token#"${dest_token%%[! ]*}"}"   # ltrim
          dest_token="${dest_token%"${dest_token##*[! ]}"}"   # rtrim
          dest_token="${dest_token/#\~/$HOME}"
          [[ -z "$dest_token" ]] && continue
          dests_pipe="${dests_pipe}	${dest_token}"  # TAB-delimited internally
        done < <(echo "$normalised_dests" | tr ',' '\n')
        dests_pipe="${dests_pipe#	}"  # strip leading TAB

        MAPPING_SRCS+=("$src")
        MAPPING_DESTS+=("$dests_pipe")
        ;;

      "excludes")
        EXCLUDES_LIST="$line"
        ;;

      "settings")
        if [[ "$line" =~ ^ARCHIVE_KEEP=([0-9]+)$ ]]; then
          ARCHIVE_KEEP="${BASH_REMATCH[1]}"
        fi
        ;;
    esac
  done < "$CONFIG_FILE"
}

# ── List profiles ──────────────────────────────────────────────────────────────
if [[ "$LIST_PROFILES" == "true" ]]; then
  echo -e "${BOLD}Profiles in backup.config:${NC}"
  grep -E '^\[profile:' "$CONFIG_FILE" | sed "s/\[profile:\(.*\)\]/  ${GREEN}•${NC} \1/"
  exit 0
fi

# ── Parse config for chosen profile ───────────────────────────────────────────
mkdir -p "$LOG_DIR"
parse_config "$PROFILE"

if [[ ${#MAPPING_SRCS[@]} -eq 0 ]]; then
  error "Profile '${PROFILE}' not found or has no mappings in backup.config\nRun --list-profiles to see available profiles."
fi

# ── Build rsync flags ──────────────────────────────────────────────────────────
RSYNC_FLAGS=(
  --archive          # preserve perms, timestamps, symlinks, owner
  --update           # skip files newer on destination (incremental)
  --human-readable
  --stats
)

[[ "$MIRROR"  == "true" ]] && RSYNC_FLAGS+=(--delete)
[[ "$DRY_RUN" == "true" ]] && RSYNC_FLAGS+=(--dry-run)

# --info=progress2 requires rsync >= 3.1.0.
# macOS ships rsync 2.6.9 (2006); brew install rsync gives 3.x.
# Detect version and fall back gracefully.
RSYNC_VERSION=$(rsync --version 2>/dev/null | awk 'NR==1{print $3}')
RSYNC_MAJOR=$(echo "$RSYNC_VERSION" | cut -d. -f1)
RSYNC_MINOR=$(echo "$RSYNC_VERSION" | cut -d. -f2)

if [[ "$VERBOSE" == "true" ]]; then
  RSYNC_FLAGS+=(--verbose)
elif (( RSYNC_MAJOR > 3 || ( RSYNC_MAJOR == 3 && RSYNC_MINOR >= 1 ) )); then
  RSYNC_FLAGS+=(--info=progress2)
else
  # Old rsync (macOS built-in 2.6.x): fall back to per-file listing
  RSYNC_FLAGS+=(--verbose)
  warn "rsync ${RSYNC_VERSION} detected (macOS built-in). For nicer progress: brew install rsync"
fi

# Global excludes from [excludes] section
if [[ -n "$EXCLUDES_LIST" ]]; then
  IFS=',' read -ra EXCL_ARR <<< "$EXCLUDES_LIST"
  for excl in "${EXCL_ARR[@]}"; do
    excl="$(echo "$excl" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$excl" ]] && RSYNC_FLAGS+=(--exclude="$excl")
  done
fi

# ── Banner ─────────────────────────────────────────────────────────────────────
banner
log "Profile   : ${BOLD}${PROFILE}${NC}"
log "Mappings  : ${#MAPPING_SRCS[@]} source(s)"
log "Compress  : ${COMPRESS}"
log "Dry run   : ${DRY_RUN}"
log "Diff only : ${DIFF}"
log "Mirror    : ${MIRROR}"
echo ""

# ── Run backups ────────────────────────────────────────────────────────────────
TOTAL=${#MAPPING_SRCS[@]}
IDX=0
ERRORS=0
SYNCED=0

for i in "${!MAPPING_SRCS[@]}"; do
  IDX=$((IDX + 1))
  src="${MAPPING_SRCS[$i]}"
  dests_pipe="${MAPPING_DESTS[$i]}"

  echo -e "${BOLD}── [${IDX}/${TOTAL}] Source: ${CYAN}${src}${NC}"

  # Validate source
  if [[ ! -e "$src" ]]; then
    warn "Source not found, skipping: $src"
    ERRORS=$((ERRORS + 1))
    echo ""
    continue
  fi

  # Split destinations — TAB-delimited internally (safe for paths with spaces)
  IFS=$'\t' read -ra dests <<< "$dests_pipe"
  DEST_COUNT=${#dests[@]}
  DEST_IDX=0

  for dest in "${dests[@]}"; do
    DEST_IDX=$((DEST_IDX + 1))

    log "  [dest ${DEST_IDX}/${DEST_COUNT}] → ${dest}"

    # Ensure parent of destination exists (the destination itself will be created by rsync)
    parent="$(dirname "$dest")"
    if [[ "$DRY_RUN" == "false" ]]; then
      if [[ ! -d "$parent" ]]; then
        warn "  Destination parent not found: $parent (is the drive mounted?)"
        ERRORS=$((ERRORS + 1))
        continue
      fi
      mkdir -p "$dest"
    fi

    # Diff mode — show what differs without copying anything
    if [[ "$DIFF" == "true" ]]; then
      log "  Differences: ${src} → ${dest}"
      echo -e "${DIM}  (legend: >f+++ new file  >f... updated file  *deleting removed)${NC}" | tee -a "$LOG_FILE"
      rsync --archive --dry-run --itemize-changes --human-readable \
        "${RSYNC_FLAGS[@]}" "$src/" "$dest/" 2>&1 \
        | grep -v '^sending\|^sent\|^total\|^$' \
        | tee -a "$LOG_FILE" || true
      SYNCED=$((SYNCED + 1))
      continue
    fi

    # Run rsync, logging to file
    if rsync "${RSYNC_FLAGS[@]}" --log-file="$LOG_FILE" "$src/" "$dest/" 2>&1 | tee -a "$LOG_FILE"; then
      success "  Synced → $dest"
      SYNCED=$((SYNCED + 1))
    else
      warn "  rsync error for: $src → $dest"
      ERRORS=$((ERRORS + 1))
    fi

    if [[ "$COMPRESS" == "true" && "$DRY_RUN" == "false" ]]; then
      # Derive a safe, space-free archive slug from the destination path:
      #   1. Replace every '/' with '_'   (path separators → underscores)
      #   2. Replace every ' ' with '_'   (spaces → underscores)
      #   3. Strip the leading underscore left by the leading slash
      dest_slug="${dest//\//_}"
      dest_slug="${dest_slug// /_}"
      dest_slug="${dest_slug#_}"
      archive_dir="$(dirname "$dest")/archives"
      archive="${archive_dir}/${PROFILE}_${dest_slug}_${TIMESTAMP}.tar.gz"
      mkdir -p "$archive_dir"

      log "  Compressing → $(basename "$archive")"
      if tar -czf "$archive" -C "$dest" . 2>>"$LOG_FILE"; then
        success "  Archive: $archive"

        # Prune old archives for this destination — glob is now space-free
        # Use find+sort instead of ls to avoid word-splitting on any edge case
        mapfile -t old_archives < <(
          find "$archive_dir" -maxdepth 1 -name "${PROFILE}_${dest_slug}_*.tar.gz" \
            -print0 | xargs -0 ls -t 2>/dev/null
        )
        archive_count=${#old_archives[@]}
        if (( archive_count > ARCHIVE_KEEP )); then
          to_delete=$((archive_count - ARCHIVE_KEEP))
          for (( pi = ARCHIVE_KEEP; pi < archive_count; pi++ )); do
            rm -f "${old_archives[$pi]}"
          done
          dim "  Pruned ${to_delete} old archive(s) (keeping last ${ARCHIVE_KEEP})"
        fi
      else
        warn "  Compression failed for: $dest"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  done

  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}─── Backup Summary ──────────────────────────────────────────${NC}"
echo -e "  Profile       : ${PROFILE}"
echo -e "  Sources       : ${TOTAL}"
echo -e "  Syncs ok      : ${SYNCED}"
echo -e "  Errors        : ${ERRORS}"
echo -e "  Compressed    : ${COMPRESS}"
echo -e "  Log           : ${LOG_FILE}"
echo -e "  Timestamp     : ${TIMESTAMP}"
echo ""

if (( ERRORS > 0 )); then
  warn "Completed with ${ERRORS} error(s). Check the log for details."
  exit 1
else
  success "All done!"
fi