#!/usr/bin/env bash
# Leveled stderr logger + display formatters.
#
# DB and inter-component plumbing always carry ISO8601 UTC (`...Z`). Anything
# the user reads (stderr logs, `status`, `log`, `doctor`) is rendered in the
# host's local timezone via `fmt_local`. Never persist local time.

_log() {
    local level="$1"; shift
    local ts
    # Compact local time, e.g. "Apr 27 23:09:11".
    ts="$(date '+%b %d %H:%M:%S')"
    printf '%s  %-5s %s\n' "$ts" "$level" "$*" >&2
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }

# --- Display formatters -----------------------------------------------------
#
# All inputs are ISO8601 UTC ("...Z", optionally with fractional seconds).
# DB and inter-component plumbing keep UTC; everything humans read goes
# through these.

# Validate ISO8601 UTC format. Internal helper.
_iso_valid() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]
}

# fmt_local <iso8601_utc>
# Strict ISO8601 with local TZ offset, e.g. "2026-04-28T01:50:00+0800".
# Used for machine-readable surfaces (raw mode, debug logs).
fmt_local() {
    local iso="$1"
    [ -z "$iso" ] && return 0
    _iso_valid "$iso" || { printf '%s' "$iso"; return 0; }
    local local_ts tz_offset
    local_ts="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%S', '$iso', 'localtime');" 2>/dev/null)"
    tz_offset="$(date '+%z')"
    [ -z "$local_ts" ] && { printf '%s' "$iso"; return 0; }
    printf '%s%s' "$local_ts" "$tz_offset"
}

# fmt_when <iso8601_utc>
# Human short-form local time, smart about distance from "now":
#   today              -> "23:09"
#   yesterday/tomorrow -> "Tue 01:50"  (within +/- 6 days)
#   farther out        -> "Apr 28 01:50"
#   different year     -> "2027-01-15 09:00"
fmt_when() {
    local iso="$1"
    [ -z "$iso" ] && return 0
    _iso_valid "$iso" || { printf '%s' "$iso"; return 0; }
    local row
    row="$(sqlite3 -separator '|' :memory: "
        SELECT
            strftime('%Y-%m-%d', '$iso', 'localtime'),
            strftime('%Y-%m-%d', 'now',  'localtime'),
            strftime('%H:%M',    '$iso', 'localtime'),
            strftime('%Y',       '$iso', 'localtime'),
            strftime('%Y',       'now',  'localtime'),
            strftime('%w',       '$iso', 'localtime'),
            strftime('%m-%d',    '$iso', 'localtime'),
            CAST((julianday(date('$iso','localtime')) - julianday(date('now','localtime'))) AS INTEGER);
    " 2>/dev/null)"
    [ -z "$row" ] && { printf '%s' "$iso"; return 0; }
    local d_iso d_today hm yr_iso yr_now dow md diff_days
    IFS='|' read -r d_iso d_today hm yr_iso yr_now dow md diff_days <<<"$row"

    if [ "$d_iso" = "$d_today" ]; then
        printf '%s' "$hm"
        return 0
    fi
    if [ "$diff_days" -ge -6 ] && [ "$diff_days" -le 6 ]; then
        local label
        case "$dow" in
            0) label=Sun ;; 1) label=Mon ;; 2) label=Tue ;; 3) label=Wed ;;
            4) label=Thu ;; 5) label=Fri ;; 6) label=Sat ;;
            *) label="" ;;
        esac
        printf '%s %s' "$label" "$hm"
        return 0
    fi
    if [ "$yr_iso" = "$yr_now" ]; then
        # "Apr 28 01:50" — month name from sqlite3 mapping.
        local mon mday
        mon="${md%-*}"; mday="${md#*-}"
        local mname
        case "$mon" in
            01) mname=Jan ;; 02) mname=Feb ;; 03) mname=Mar ;; 04) mname=Apr ;;
            05) mname=May ;; 06) mname=Jun ;; 07) mname=Jul ;; 08) mname=Aug ;;
            09) mname=Sep ;; 10) mname=Oct ;; 11) mname=Nov ;; 12) mname=Dec ;;
        esac
        printf '%s %d %s' "$mname" "$((10#$mday))" "$hm"
        return 0
    fi
    printf '%s %s' "$d_iso" "$hm"
}

# fmt_relative <iso8601_utc>
# Distance from now: "in 2h 41m" / "3 min ago" / "just now".
fmt_relative() {
    local iso="$1"
    [ -z "$iso" ] && return 0
    _iso_valid "$iso" || return 0
    local sec
    sec="$(sqlite3 :memory: "SELECT CAST((julianday('$iso') - julianday('now')) * 86400 AS INTEGER);" 2>/dev/null)"
    [ -z "$sec" ] && return 0
    local sign="in" abs="$sec"
    if [ "$sec" -lt 0 ]; then sign="ago"; abs=$(( -sec )); fi
    if [ "$abs" -lt 60 ]; then
        printf 'just now'
        return 0
    fi
    local body
    if [ "$abs" -lt 3600 ]; then
        body="$((abs/60)) min"
    elif [ "$abs" -lt 86400 ]; then
        local h=$((abs/3600)) m=$(( (abs%3600)/60 ))
        if [ "$m" -gt 0 ]; then body="${h}h ${m}m"; else body="${h}h"; fi
    else
        local d=$((abs/86400)) h=$(( (abs%86400)/3600 ))
        if [ "$h" -gt 0 ]; then body="${d}d ${h}h"; else body="${d}d"; fi
    fi
    if [ "$sign" = "in" ]; then printf 'in %s' "$body"; else printf '%s ago' "$body"; fi
}

# fmt_duration <seconds>
# Compact human duration: "8385" -> "2h 19m", "65" -> "1m", "45" -> "45s".
fmt_duration() {
    local s="$1"
    [[ "$s" =~ ^[0-9]+$ ]] || { printf '%s' "$s"; return 0; }
    if [ "$s" -lt 60 ]; then printf '%ds' "$s"
    elif [ "$s" -lt 3600 ]; then printf '%dm' "$((s/60))"
    elif [ "$s" -lt 86400 ]; then
        local h=$((s/3600)) m=$(( (s%3600)/60 ))
        if [ "$m" -gt 0 ]; then printf '%dh %dm' "$h" "$m"; else printf '%dh' "$h"; fi
    else
        local d=$((s/86400)) h=$(( (s%86400)/3600 ))
        if [ "$h" -gt 0 ]; then printf '%dd %dh' "$d" "$h"; else printf '%dd' "$d"; fi
    fi
}

# fmt_when_with_relative <iso8601_utc>
# Combined: "Tue 01:50 (in 2h 41m)". When the time IS "now" the relative is
# omitted to avoid "just now (just now)".
fmt_when_with_relative() {
    local iso="$1"
    [ -z "$iso" ] && return 0
    local when rel
    when="$(fmt_when "$iso")"
    rel="$(fmt_relative "$iso")"
    if [ -z "$rel" ] || [ "$rel" = "just now" ]; then
        printf '%s' "$when"
    else
        printf '%s (%s)' "$when" "$rel"
    fi
}
