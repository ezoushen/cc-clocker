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
        # Tolerate fire_ping nonzero exits — a failed ping is logged in the
        # db (ok=0) and we MUST keep the loop alive. Without `|| true`, the
        # caller's set -e would propagate the claude exit code and kill the
        # daemon mid-iteration, before db_insert_ping completes.
        fire_ping "$next_reset" "$which" || true
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
#
# DOES NOT re-detect after sleeping to a scheduled fire moment. Re-detecting
# at the boundary advances the projection past the current reset, causing
# the daemon to perpetually skip its own fires (anchor + N*period vs anchor
# + (N+1)*period). We commit to the originally-decided reset, sleep until
# its fire_at, fire, then idle past the boundary so the NEXT detection
# advances cleanly.
run_loop() {
    local iters="${RUN_LOOP_ITERATIONS:-0}"
    local i=0
    while :; do
        local detected next_reset which fire_at sleep_s
        if ! detected="$(detect_window)"; then
            log_warn "no active 5h or 7d window detected; will sleep + retry"
            sleep 300
        else
            next_reset="$(printf '%s' "$detected" | cut -f1)"
            which="$(printf '%s' "$detected" | cut -f2)"
            fire_at="$(next_fire_time "$next_reset")"
            sleep_s="$(seconds_until "$fire_at")"
            if [ "$sleep_s" -gt 0 ]; then
                log_info "next fire in $(fmt_duration "$sleep_s") (window=$which)"
                sleep "$sleep_s"
            fi
            # Fire on the originally chosen reset — NOT on whatever
            # detect_window would say now (it would have advanced).
            fire_ping "$next_reset" "$which" || true
            # Idle past the boundary so the next detect_window iteration
            # projects cleanly to the SUBSEQUENT reset. 60s is well above
            # the default 30s ping delay and any practical clock skew.
            sleep 60
        fi
        i=$((i+1))
        if [ "$iters" -gt 0 ] && [ "$i" -ge "$iters" ]; then
            return 0
        fi
    done
}
