#!/usr/bin/env bash
# Window detector. Claude Code enforces TWO rolling quota windows:
#   - 5h window: starts at first message in last 5 hours
#   - 7d window: starts at first message in last 7 days
# We compute both reset times and return the SOONER one as the next ping target.

: "${CC_CLAUDE_HOME:=$HOME/.claude}"

# detect_window
# stdout (TSV): "<next_reset>\t<which>\t<reset_5h>\t<reset_7d>"
#   - next_reset: ISO8601 UTC, the earlier of the two resets
#   - which: "5h" or "7d"
#   - reset_5h, reset_7d: each ISO8601 UTC or empty if that window is inactive
# exit 0 on detection (at least one window active), 1 otherwise.
detect_window() {
    local projects_dir="$CC_CLAUDE_HOME/projects"
    [ -d "$projects_dir" ] || return 1

    local cutoff_5h cutoff_7d
    cutoff_5h="$(_iso_now_offset '-5 hours')"
    cutoff_7d="$(_iso_now_offset '-7 days')"

    # Collect every valid timestamp from every jsonl file once.
    local all_ts
    all_ts="$(
        find "$projects_dir" -type f -name '*.jsonl' -print0 2>/dev/null \
            | xargs -0 cat 2>/dev/null \
            | jq -rR 'try (fromjson | .timestamp // empty) // empty' 2>/dev/null \
            | sort
    )"

    [ -n "$all_ts" ] || return 1

    local start_5h start_7d reset_5h="" reset_7d=""
    start_5h="$(awk -v c="$cutoff_5h" '$0 >= c { print; exit }' <<< "$all_ts")"
    start_7d="$(awk -v c="$cutoff_7d" '$0 >= c { print; exit }' <<< "$all_ts")"

    [ -n "$start_5h" ] && reset_5h="$(_iso_offset "$start_5h" '+5 hours')"
    [ -n "$start_7d" ] && reset_7d="$(_iso_offset "$start_7d" '+7 days')"

    local next which
    if [ -n "$reset_5h" ] && [ -n "$reset_7d" ]; then
        if [[ "$reset_5h" < "$reset_7d" ]]; then
            next="$reset_5h"; which="5h"
        else
            next="$reset_7d"; which="7d"
        fi
    elif [ -n "$reset_5h" ]; then
        next="$reset_5h"; which="5h"
    elif [ -n "$reset_7d" ]; then
        next="$reset_7d"; which="7d"
    else
        return 1
    fi

    printf '%s\t%s\t%s\t%s\n' "$next" "$which" "$reset_5h" "$reset_7d"
}

# Portable ISO8601 UTC arithmetic via sqlite3.
_iso_now_offset() {
    sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','$1'));"
}

_iso_offset() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]] || return 1
    sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('$1','$2'));"
}
