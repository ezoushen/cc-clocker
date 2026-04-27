#!/usr/bin/env bash
# Schedule math. Portable date arithmetic via sqlite3.
# Inputs are internal-only ISO8601 timestamps (already validated upstream).

# next_fire_time: when to fire relative to a reset.
# Delay defaults to 30s; override via CC_CLOCKER_PING_DELAY_SECONDS (integer).
# Negative or non-integer values fall back to 30.
next_fire_time() {
    local reset="$1"
    local delay="${CC_CLOCKER_PING_DELAY_SECONDS:-30}"
    [[ "$delay" =~ ^[0-9]+$ ]] || delay=30
    sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('${reset}','+${delay} seconds'));"
}

seconds_until() {
    local target="$1"
    sqlite3 :memory: "SELECT CAST((julianday('${target}') - julianday('now')) * 86400 AS INTEGER);"
}

# run_once_or_sleep
# Single iteration. Returns:
#   0 = ping fired
#   2 = no active window (caller sleeps long; we logged warning)
#   3 = future fire scheduled; stdout: "<sleep_s>\t<which>\t<reset>"
run_once_or_sleep() {
    local detected next_reset which fire_at sleep_s
    detected="$(detect_window)" || {
        log_warn "no active 5h or 7d window detected; will sleep + retry"
        return 2
    }
    next_reset="$(printf '%s' "$detected" | cut -f1)"
    which="$(printf '%s' "$detected" | cut -f2)"
    fire_at="$(next_fire_time "$next_reset")"
    sleep_s="$(seconds_until "$fire_at")"
    if [ "$sleep_s" -le 0 ]; then
        fire_ping "$next_reset" "$which"
        return 0
    fi
    printf '%s\t%s\t%s\n' "$sleep_s" "$which" "$next_reset"
    return 3
}

# fire_now: unconditional ping. Uses detected reset+which if available, else 'manual'.
fire_now() {
    local detected next_reset which
    if detected="$(detect_window)"; then
        next_reset="$(printf '%s' "$detected" | cut -f1)"
        which="$(printf '%s' "$detected" | cut -f2)"
    else
        next_reset="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        which="manual"
    fi
    fire_ping "$next_reset" "$which"
}

# run_loop: forever. Honors RUN_LOOP_ITERATIONS env for tests.
run_loop() {
    local iters="${RUN_LOOP_ITERATIONS:-0}"
    local i=0
    while :; do
        local out status=0
        out="$(run_once_or_sleep)" || status=$?
        case "$status" in
            0)  : ;;
            2)  sleep 300 ;;
            3)
                local s
                s="$(printf '%s' "$out" | cut -f1)"
                local w
                w="$(printf '%s' "$out" | cut -f2)"
                log_info "next fire in $(fmt_duration "$s") (window=$w)"
                sleep "$s"
                ;;
            *)  log_error "unexpected status $status"; sleep 60 ;;
        esac
        i=$((i+1))
        if [ "$iters" -gt 0 ] && [ "$i" -ge "$iters" ]; then
            return 0
        fi
    done
}
