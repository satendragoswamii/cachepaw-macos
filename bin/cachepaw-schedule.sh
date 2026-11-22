#!/bin/bash
# Install and manage CachePaw's user-level macOS LaunchAgent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LABEL="com.cachepaw.cleanup"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT_DIR="$HOME/Library/Application Support/CachePaw"
DOMAIN="gui/$(id -u)"

usage() {
    cat <<'EOF'
Usage: cachepaw schedule install [--days N] [--hour H] [--minute M]
       cachepaw schedule status
       cachepaw schedule remove
EOF
}

require_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        printf 'CachePaw scheduling requires macOS launchd.\n' >&2
        exit 2
    fi
}

require_mutation_allowed() {
    if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
        printf 'LaunchAgent changes are disabled in test mode.\n' >&2
        exit 2
    fi
}

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

schedule_install() {
    require_macos
    require_mutation_allowed
    local days=25 hour=10 minute=0 arg helper_path log_path temp_plist
    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --days) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; days="$2"; shift 2 ;;
            --hour) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; hour="$2"; shift 2 ;;
            --minute) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; minute="$2"; shift 2 ;;
            *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
        esac
    done

    [[ "$days" =~ ^[0-9]+$ ]] && [[ "$days" -ge 1 ]] && [[ "$days" -le 365 ]] || { printf 'Days must be 1..365.\n' >&2; exit 2; }
    [[ "$hour" =~ ^[0-9]+$ ]] && [[ "$hour" -ge 0 ]] && [[ "$hour" -le 23 ]] || { printf 'Hour must be 0..23.\n' >&2; exit 2; }
    [[ "$minute" =~ ^[0-9]+$ ]] && [[ "$minute" -ge 0 ]] && [[ "$minute" -le 59 ]] || { printf 'Minute must be 0..59.\n' >&2; exit 2; }

    if [[ -e "$PLIST_PATH" ]] || launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
        printf 'Schedule already exists; run `cachepaw schedule status` or remove it first.\n' >&2
        exit 1
    fi

    mkdir -p "$HOME/Library/LaunchAgents" "$SUPPORT_DIR/bin" "$SUPPORT_DIR/lib" "$HOME/Library/Logs/CachePaw"
    ditto "$PROJECT_DIR/lib" "$SUPPORT_DIR/lib"
    install -m 700 "$PROJECT_DIR/bin/cachepaw-safe-clean.sh" "$SUPPORT_DIR/bin/cachepaw-safe-clean.sh"
    if [[ ! -e "$SUPPORT_DIR/last-success-epoch" ]]; then
        date +%s >"$SUPPORT_DIR/last-success-epoch"
    fi

    helper_path=$(xml_escape "$SUPPORT_DIR/bin/cachepaw-safe-clean.sh")
    log_path=$(xml_escape "$HOME/Library/Logs/CachePaw/launchd.log")
    temp_plist=$(mktemp "${TMPDIR:-/tmp}/cachepaw.XXXXXX")
    cat >"$temp_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$helper_path</string><string>--apply</string><string>--scheduled</string><string>--interval-days=$days</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$log_path</string>
  <key>StandardErrorPath</key><string>$log_path</string>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
EOF

    if ! plutil -lint "$temp_plist"; then
        /usr/bin/trash "$temp_plist"
        printf 'Generated LaunchAgent plist did not validate.\n' >&2
        exit 1
    fi
    install -m 644 "$temp_plist" "$PLIST_PATH"
    /usr/bin/trash "$temp_plist"
    if ! launchctl bootstrap "$DOMAIN" "$PLIST_PATH"; then
        /usr/bin/trash "$PLIST_PATH"
        printf 'Could not load the CachePaw LaunchAgent.\n' >&2
        exit 1
    fi
    printf 'Installed %s. Cleanup runs no more often than every %s days, checking daily at %02d:%02d local time.\n' "$LABEL" "$days" "$hour" "$minute"
}

schedule_status() {
    require_macos
    if [[ ! -f "$PLIST_PATH" ]]; then
        printf 'CachePaw schedule is not installed.\n'
        exit 1
    fi
    if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
        printf 'LaunchAgent status checks are disabled in test mode.\n' >&2
        exit 2
    fi
    launchctl print "$DOMAIN/$LABEL"
}

schedule_remove() {
    require_macos
    require_mutation_allowed
    if [[ ! -f "$PLIST_PATH" ]]; then
        printf 'CachePaw schedule is not installed.\n'
        exit 1
    fi
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
        launchctl bootout "$DOMAIN" "$PLIST_PATH"
    fi
    /usr/bin/trash "$PLIST_PATH"
    printf 'Removed the CachePaw LaunchAgent. Cleanup files and logs were kept.\n'
}

case "${1:-}" in
    install) shift; schedule_install "$@" ;;
    status) shift; schedule_status "$@" ;;
    remove) shift; schedule_remove "$@" ;;
    *) usage >&2; exit 2 ;;
esac
