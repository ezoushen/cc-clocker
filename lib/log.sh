#!/usr/bin/env bash
# Leveled stderr logger + display formatters.
#
# DB and inter-component plumbing always carry ISO8601 UTC (`...Z`). Anything
# the user reads (stderr logs, `status`, `log`, `doctor`) is rendered in the
# host's local timezone via `fmt_local`. Never persist local time.

_log() {
    local level="$1"; shift
    local ts
    # ISO8601 with local TZ offset (e.g. 2026-04-27T22:55:46+0800).
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf '%s [%s] %s\n' "$ts" "$level" "$*" >&2
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }

# fmt_local <iso8601_utc>
# Convert an ISO8601 UTC timestamp (Z suffix, optional fractional seconds)
# into the host's local timezone, formatted as "YYYY-MM-DDTHH:MM:SS+ZZZZ".
# Empty input -> empty output. Unparseable input is echoed back verbatim
# so callers never silently drop data.
fmt_local() {
    local iso="$1"
    [ -z "$iso" ] && return 0
    if ! [[ "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]; then
        printf '%s' "$iso"
        return 0
    fi
    local local_ts tz_offset
    local_ts="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%S', '$iso', 'localtime');" 2>/dev/null)"
    tz_offset="$(date '+%z')"
    if [ -z "$local_ts" ]; then
        printf '%s' "$iso"
        return 0
    fi
    printf '%s%s' "$local_ts" "$tz_offset"
}
