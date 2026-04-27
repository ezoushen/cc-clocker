#!/usr/bin/env bash
# Window detector. Claude Code enforces TWO rolling quota windows:
#   - 5h window: starts at first message of a usage period; expires 5h later
#   - 7d window: same idea with a 7-day length
#
# Window N's start = first message with timestamp >= window_{N-1}_end.
# So we walk forward through the message history, jumping window-by-window
# from the very first message ever recorded. The last "start" we land on is
# the start of the currently active window.
#
# Implemented via a recursive CTE in sqlite3 — one batch per window length.

: "${CC_CLAUDE_HOME:=$HOME/.claude}"

# detect_window
# stdout (TSV): "<next_reset>\t<which>\t<reset_5h>\t<reset_7d>"
#   - next_reset: ISO8601 UTC, the earlier of the two resets
#   - which: "5h" or "7d"
#   - reset_5h, reset_7d: each ISO8601 UTC or empty if that window has expired
# exit 0 on detection (at least one window active), 1 otherwise.
detect_window() {
    local projects_dir="$CC_CLAUDE_HOME/projects"
    [ -d "$projects_dir" ] || return 1

    # Collect every valid timestamp, sorted, deduped. jq -rR with fromjson
    # treats malformed lines as empty so a bad line cannot break the stream.
    local all_ts
    all_ts="$(
        find "$projects_dir" -type f -name '*.jsonl' -print0 2>/dev/null \
            | xargs -0 cat 2>/dev/null \
            | jq -rR 'try (fromjson | .timestamp // empty) // empty' 2>/dev/null \
            | sort -u
    )"

    [ -n "$all_ts" ] || return 1

    # Stash timestamps in a temp file so sqlite3 can .import them safely
    # (no SQL interpolation, so JSONL contents cannot inject SQL).
    local ts_file
    ts_file="$(mktemp -t cc-clocker-ts.XXXXXX)" || return 1
    # shellcheck disable=SC2064
    trap "rm -f '$ts_file'" RETURN
    printf '%s\n' "$all_ts" > "$ts_file"

    # Walk forward window-by-window from the earliest message and return the
    # start of the currently active 5h window. Recursive CTE iterates
    # O(history/5h) times — fine even for months of dense activity.
    local start_5h
    start_5h="$(_walk_window_start "$ts_file" '+5 hours' 2000)"

    local now_iso reset_5h="" reset_7d=""
    now_iso="$(_iso_now_offset '+0 seconds')"

    if [ -n "$start_5h" ]; then
        reset_5h="$(_iso_offset "$start_5h" '+5 hours')" || reset_5h=""
        [ -n "$reset_5h" ] && [[ "$reset_5h" < "$now_iso" ]] && reset_5h=""
    fi

    # 7d window is NOT auto-detected. The 7d weekly quota in Claude Code
    # subscriptions resets on a server-side schedule that cannot be
    # reconstructed from local message history alone (tied to billing /
    # subscription anchors, not message gaps). Users who want the daemon to
    # also fire 30s after the 7d reset must export CC_CLOCKER_NEXT_7D_RESET
    # to an ISO8601 UTC timestamp of the next 7d reset; we pick whichever of
    # the 5h or 7d resets comes sooner. After firing on it, the daemon
    # rotates the value forward by 7 days (handled by the scheduler).
    if [ -n "${CC_CLOCKER_NEXT_7D_RESET:-}" ] \
       && [[ "$CC_CLOCKER_NEXT_7D_RESET" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]] \
       && [[ "$CC_CLOCKER_NEXT_7D_RESET" > "$now_iso" ]]; then
        reset_7d="$CC_CLOCKER_NEXT_7D_RESET"
    fi

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

# Walk through the user's message history window-by-window for a given
# window length, returning the start of the currently active window.
# $1 = path to file containing one ISO8601 timestamp per line (sorted, unique)
# $2 = sqlite3 datetime modifier ('+5 hours', '+7 days', ...)
# $3 = max recursion depth (safety bound)
_walk_window_start() {
    local ts_file="$1" modifier="$2" max_depth="$3"
    sqlite3 :memory: 2>/dev/null <<SQL
.mode list
CREATE TABLE x(t TEXT);
.import "$ts_file" x
WITH RECURSIVE walk(start_ts, end_ts, depth) AS (
    SELECT MIN(t),
           strftime('%Y-%m-%dT%H:%M:%fZ', datetime(MIN(t), '$modifier')),
           0
    FROM x
    UNION ALL
    SELECT (SELECT MIN(t) FROM x WHERE t >= walk.end_ts),
           strftime('%Y-%m-%dT%H:%M:%fZ',
                    datetime((SELECT MIN(t) FROM x WHERE t >= walk.end_ts),
                             '$modifier')),
           walk.depth + 1
    FROM walk
    WHERE (SELECT MIN(t) FROM x WHERE t >= walk.end_ts) IS NOT NULL
      AND walk.depth < $max_depth
)
SELECT start_ts FROM walk WHERE start_ts IS NOT NULL ORDER BY depth DESC LIMIT 1;
SQL
}

# Portable ISO8601 UTC arithmetic via sqlite3.
_iso_now_offset() {
    sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','$1'));"
}

_iso_offset() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]] || return 1
    sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('$1','$2'));"
}
