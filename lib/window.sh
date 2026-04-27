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
: "${CC_CLOCKER_CACHE_FILE:=$HOME/.cc-clocker/rate-limits.json}"

# _current_org_id
# Print the current Anthropic orgId (per `claude auth status`), or empty.
# Used to detect account switches; cache entries from a different orgId
# are invalidated. Tests / hosts can override by exporting CC_CLOCKER_ORG_ID
# to skip the (slow) `claude auth status` call.
_current_org_id() {
    if [ -n "${CC_CLOCKER_ORG_ID:-}" ]; then
        printf '%s' "$CC_CLOCKER_ORG_ID"
        return 0
    fi
    claude auth status 2>/dev/null | jq -r 'try .orgId // empty' 2>/dev/null
}

# _read_cached_resets <org_id>
# Print "<reset_5h_iso>\t<reset_7d_iso>" if the cache file exists, the
# org_id matches, and at least one of the resets is in the future. Empty
# fields when expired or missing. Exit 1 if the cache is unusable.
# $1 = current org_id (empty -> skip cache)
_read_cached_resets() {
    local current_org="$1"
    local cache_file="$CC_CLOCKER_CACHE_FILE"
    [ -n "$current_org" ] || return 1
    [ -f "$cache_file" ] || return 1

    local cached_org r5_epoch r7_epoch
    cached_org="$(jq -r 'try .org_id // empty' "$cache_file" 2>/dev/null)"
    [ "$cached_org" = "$current_org" ] || return 1

    r5_epoch="$(jq -r 'try .five_hour_resets_at // empty' "$cache_file" 2>/dev/null)"
    r7_epoch="$(jq -r 'try .seven_day_resets_at // empty' "$cache_file" 2>/dev/null)"

    local now_epoch r5_iso="" r7_iso=""
    now_epoch="$(date +%s)"

    if [[ "$r5_epoch" =~ ^[0-9]+$ ]] && [ "$r5_epoch" -gt "$now_epoch" ]; then
        r5_iso="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', $r5_epoch, 'unixepoch');")"
    fi
    if [[ "$r7_epoch" =~ ^[0-9]+$ ]] && [ "$r7_epoch" -gt "$now_epoch" ]; then
        r7_iso="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', $r7_epoch, 'unixepoch');")"
    fi

    [ -n "$r5_iso" ] || [ -n "$r7_iso" ] || return 1

    printf '%s\t%s\n' "$r5_iso" "$r7_iso"
}

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

    local now_iso reset_5h="" reset_7d=""
    now_iso="$(_iso_now_offset '+0 seconds')"

    # Resolution order (highest to lowest):
    #   1. Cached statusline rate-limits (fresh, server-authoritative,
    #      account-fingerprinted). Account-change-safe.
    #   2. Per-account anchor stored in DB (set via `cc-clocker set-anchor`).
    #      Drift-free projection from any past reset; survives forever for
    #      that account.
    #   3. Env-var anchors: CC_CLOCKER_5H_ANCHOR / CC_CLOCKER_7D_ANCHOR
    #      (process-scoped override, useful in plist).
    #   4. CC_CLOCKER_NEXT_7D_RESET one-shot env var.
    #   5. JSONL walk (best-effort, drift-prone).

    local org_id cached
    org_id="$(_current_org_id)"
    if [ -n "$org_id" ] && cached="$(_read_cached_resets "$org_id" 2>/dev/null)"; then
        reset_5h="$(printf '%s' "$cached" | cut -f1)"
        reset_7d="$(printf '%s' "$cached" | cut -f2)"
    fi

    # 5h fallbacks (each only fills if not already set above).
    if [ -z "$reset_5h" ] && [ -n "$org_id" ]; then
        local db_anchor
        db_anchor="$(db_get_anchor "$org_id" 5h 2>/dev/null)"
        if [ -n "$db_anchor" ] \
           && [[ "$db_anchor" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]; then
            reset_5h="$(_next_reset_from_anchor "$db_anchor" 18000)"
        fi
    fi
    if [ -z "$reset_5h" ] \
       && [ -n "${CC_CLOCKER_5H_ANCHOR:-}" ] \
       && [[ "$CC_CLOCKER_5H_ANCHOR" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]; then
        reset_5h="$(_next_reset_from_anchor "$CC_CLOCKER_5H_ANCHOR" 18000)"
    fi
    if [ -z "$reset_5h" ]; then
        local start_5h
        start_5h="$(_walk_window_start "$ts_file" '+5 hours' 2000)"
        if [ -n "$start_5h" ]; then
            reset_5h="$(_iso_offset "$start_5h" '+5 hours')" || reset_5h=""
            [ -n "$reset_5h" ] && [[ "$reset_5h" < "$now_iso" ]] && reset_5h=""
        fi
    fi

    # 7d fallbacks.
    if [ -z "$reset_7d" ] && [ -n "$org_id" ]; then
        local db_anchor
        db_anchor="$(db_get_anchor "$org_id" 7d 2>/dev/null)"
        if [ -n "$db_anchor" ] \
           && [[ "$db_anchor" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]; then
            reset_7d="$(_next_reset_from_anchor "$db_anchor" 604800)"
        fi
    fi
    if [ -z "$reset_7d" ] \
       && [ -n "${CC_CLOCKER_7D_ANCHOR:-}" ] \
       && [[ "$CC_CLOCKER_7D_ANCHOR" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]; then
        reset_7d="$(_next_reset_from_anchor "$CC_CLOCKER_7D_ANCHOR" 604800)"
    fi
    if [ -z "$reset_7d" ] \
       && [ -n "${CC_CLOCKER_NEXT_7D_RESET:-}" ] \
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

# Project a past anchor reset forward by whole window-length steps to the
# NEXT reset that is strictly in the future.
# $1 = anchor ISO8601 UTC (any past reset of this window)
# $2 = window length in seconds (18000 for 5h, 604800 for 7d)
# stdout: ISO8601 UTC of next reset, or empty on error.
_next_reset_from_anchor() {
    local anchor="$1" period="$2"
    sqlite3 :memory: 2>/dev/null <<SQL
SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('$anchor', '+' || (
    CASE
        WHEN strftime('%s','now') < strftime('%s','$anchor') THEN 0
        ELSE ((CAST((strftime('%s','now') - strftime('%s','$anchor')) / $period AS INTEGER) + 1) * $period)
    END
) || ' seconds'));
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
