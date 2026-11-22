#!/bin/bash
# Conservative cache cleanup with Mole's path validation and operation log.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'CachePaw cleanup is supported on macOS only.\n' >&2
    exit 2
fi

mkdir -p "$HOME/Library/Caches/CachePaw/tmp"
export MOLE_RESOLVED_TMPDIR="$HOME/Library/Caches/CachePaw/tmp"
source "$PROJECT_DIR/lib/core/common.sh"

APPLY=false
SCHEDULED=false
INTERVAL_DAYS=25
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=true ;;
        --dry-run) APPLY=false ;;
        --scheduled) SCHEDULED=true ;;
        --interval-days=*) INTERVAL_DAYS="${arg#*=}" ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

if ! [[ "$INTERVAL_DAYS" =~ ^[0-9]+$ ]] || [[ "$INTERVAL_DAYS" -lt 1 ]] || [[ "$INTERVAL_DAYS" -gt 365 ]]; then
    printf 'Interval must be a whole number from 1 to 365 days.\n' >&2
    exit 2
fi

readonly SECONDS_PER_DAY=86400
INTERVAL_SECONDS=$((INTERVAL_DAYS * SECONDS_PER_DAY))
STATE_DIR="$HOME/Library/Application Support/CachePaw"
STATE_FILE="$STATE_DIR/last-success-epoch"
LOG_DIR="$HOME/Library/Logs/CachePaw"
HB_CACHE="$HOME/Library/Caches/Homebrew"
PIP_CACHE="$HOME/Library/Caches/pip"
MOLE_DELETE_LOG="$LOG_DIR/deletions.log"
mkdir -p "$STATE_DIR" "$LOG_DIR"
export MOLE_DELETE_LOG
export MOLE_DELETE_MODE=permanent

if [[ "$SCHEDULED" == "true" ]]; then
    CURRENT_EPOCH=$(date +%s)
    if [[ -r "$STATE_FILE" ]]; then
        LAST_SUCCESS=$(cat "$STATE_FILE")
        if ! [[ "$LAST_SUCCESS" =~ ^[0-9]+$ ]]; then
            printf 'Invalid cleanup timestamp; skipping for safety.\n' >&2
            exit 0
        fi
        ELAPSED_SECONDS=$((CURRENT_EPOCH - LAST_SUCCESS))
        if [[ "$ELAPSED_SECONDS" -lt "$INTERVAL_SECONDS" ]]; then
            printf 'Not due; CachePaw runs every %s days.\n' "$INTERVAL_DAYS"
            exit 0
        fi
    fi
fi

if [[ "$APPLY" != "true" ]]; then
    export MOLE_DRY_RUN=1
else
    unset MOLE_DRY_RUN || true
fi

SKIPPED=0
clean_cache() {
    local path="$1"
    local description="$2"
    [[ -e "$path" ]] || { printf 'Nothing to clean: %s\n' "$description"; return 0; }

    if [[ ! -x /usr/sbin/lsof ]]; then
        printf 'Skipped %s because active-use checks are unavailable.\n' "$description"
        SKIPPED=1
        return 0
    fi

    local open_files
    if [[ -d "$path" ]]; then
        open_files=$(/usr/sbin/lsof -t +D "$path" 2>/dev/null || true)
    else
        open_files=$(/usr/sbin/lsof -t "$path" 2>/dev/null || true)
    fi
    if [[ -z "$open_files" ]]; then
        local size
        size=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
        if [[ "$APPLY" == "true" ]]; then
            if mole_delete "$path"; then
                printf 'Cleared %s (%s).\n' "$description" "${size:-unknown size}"
            else
                printf 'Could not clear %s; see the deletion log.\n' "$description"
                SKIPPED=1
            fi
        else
            printf 'Would clear %s (%s).\n' "$description" "${size:-unknown size}"
            mole_delete "$path"
        fi
    else
        printf 'Skipped %s because a process is using it.\n' "$description"
        SKIPPED=1
    fi
}

printf 'CachePaw conservative cleanup (%s)\n' "$([[ "$APPLY" == "true" ]] && printf 'apply' || printf 'preview')"
clean_cache "$HB_CACHE/downloads" "Homebrew downloads"
clean_cache "$PIP_CACHE" "Python pip cache"

shopt -s nullglob
for archive in "$HB_CACHE"/portable-ruby-*.bottle.tar.gz; do
    clean_cache "$archive" "Homebrew portable-Ruby archive"
done
shopt -u nullglob

if [[ "$SCHEDULED" == "true" && "$APPLY" == "true" && "$SKIPPED" -eq 0 ]]; then
    printf '%s\n' "$(date +%s)" >"$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
fi

df -h /System/Volumes/Data
