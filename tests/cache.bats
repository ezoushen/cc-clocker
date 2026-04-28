#!/usr/bin/env bats

load 'test_helper'

setup() {
    export CC_CLAUDE_HOME="$BATS_TEST_TMPDIR/claude"
    export CC_CLOCKER_HOME="$BATS_TEST_TMPDIR/cc"
    export CC_CLOCKER_CACHE_FILE="$BATS_TEST_TMPDIR/rate-limits.json"
    mkdir -p "$CC_CLAUDE_HOME/projects/p1"
    source "$PROJECT_ROOT/lib/db.sh"
    source "$PROJECT_ROOT/lib/window.sh"
    db_init
    # Seed a recent jsonl message so detect_window has *some* fallback data.
    ts=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-30 minutes'));")
    printf '{"type":"user","timestamp":"%s","message":"x"}\n' "$ts" \
        > "$CC_CLAUDE_HOME/projects/p1/s.jsonl"
}

@test "_read_cached_resets returns nothing when cache file missing" {
    run _read_cached_resets "org-X"
    [ "$status" -ne 0 ]
}

@test "_read_cached_resets matches by org_id" {
    local r5_epoch=$(($(date +%s) + 7200))
    local r7_epoch=$(($(date +%s) + 86400))
    jq -n --arg o "org-X" --argjson r5 "$r5_epoch" --argjson r7 "$r7_epoch" \
        '{org_id:$o,five_hour_resets_at:$r5,seven_day_resets_at:$r7,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"
    run _read_cached_resets "org-X"
    [ "$status" -eq 0 ]
    r5=$(printf '%s' "$output" | cut -f1)
    r7=$(printf '%s' "$output" | cut -f2)
    [ -n "$r5" ]
    [ -n "$r7" ]
}

@test "_read_cached_resets rejects mismatched org_id" {
    local r5_epoch=$(($(date +%s) + 7200))
    jq -n --arg o "org-X" --argjson r5 "$r5_epoch" \
        '{org_id:$o,five_hour_resets_at:$r5,seven_day_resets_at:null,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"
    run _read_cached_resets "org-DIFFERENT"
    [ "$status" -ne 0 ]
}

@test "_read_cached_resets projects past 5h forward instead of dropping" {
    # 1 hour ago -> next 5h reset = original + 5h = 4h from now (in future).
    local past=$(($(date +%s) - 3600))
    jq -n --arg o "org-X" --argjson r5 "$past" \
        '{org_id:$o,five_hour_resets_at:$r5,seven_day_resets_at:null,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"
    run _read_cached_resets "org-X"
    [ "$status" -eq 0 ]
    r5=$(printf '%s' "$output" | cut -f1)
    r5_epoch=$(sqlite3 :memory: "SELECT strftime('%s','$r5');")
    [ "$r5_epoch" -gt "$(date +%s)" ]
}

@test "detect_window prefers cache over walk when CC_CLOCKER_ORG_ID matches" {
    local r5_epoch=$(($(date +%s) + 1234))
    local r5_iso
    r5_iso=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', $r5_epoch, 'unixepoch');")
    jq -n --arg o "org-XYZ" --argjson r5 "$r5_epoch" \
        '{org_id:$o,five_hour_resets_at:$r5,seven_day_resets_at:null,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"
    CC_CLOCKER_ORG_ID="org-XYZ" run detect_window
    [ "$status" -eq 0 ]
    r5=$(printf '%s' "$output" | cut -f3)
    [ "$r5" = "$r5_iso" ]
}

@test "detect_window falls back when org_id mismatches cache" {
    local r5_epoch=$(($(date +%s) + 1234))
    jq -n --arg o "org-CACHED" --argjson r5 "$r5_epoch" \
        '{org_id:$o,five_hour_resets_at:$r5,seven_day_resets_at:null,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"
    # Different org -> cache rejected -> walk fallback -> picks 5h from jsonl
    CC_CLOCKER_ORG_ID="org-OTHER" run detect_window
    [ "$status" -eq 0 ]
    which=$(printf '%s' "$output" | cut -f2)
    [ "$which" = "5h" ]
    # The cache value should NOT be the answer
    r5=$(printf '%s' "$output" | cut -f3)
    cached_iso=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', $r5_epoch, 'unixepoch');")
    [ "$r5" != "$cached_iso" ]
}

@test "detect_window prefers DB anchor over walk when no cache" {
    db_set_anchor "org-Y" 5h "2026-04-27T16:20:00Z"
    CC_CLOCKER_ORG_ID="org-Y" run detect_window
    [ "$status" -eq 0 ]
    r5=$(printf '%s' "$output" | cut -f3)
    # 16:20:00 + N*5h projection — must end in :20:00Z
    [[ "$r5" == *":20:00Z" ]]
}

@test "_read_cached_resets projects past 5h reset forward as anchor" {
    # Cached reset 12 hours ago -> daemon should project to next future reset
    # (within next 5h).
    local past=$(($(date +%s) - 43200))
    jq -n --arg o "org-X" --argjson r5 "$past" \
        '{org_id:$o,five_hour_resets_at:$r5,seven_day_resets_at:null,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"
    run _read_cached_resets "org-X"
    [ "$status" -eq 0 ]
    r5=$(printf '%s' "$output" | cut -f1)
    [ -n "$r5" ]
    # Must be in the future, but no more than 5h ahead.
    r5_epoch=$(sqlite3 :memory: "SELECT strftime('%s','$r5');")
    now=$(date +%s)
    [ "$r5_epoch" -gt "$now" ]
    [ "$((r5_epoch - now))" -le 18000 ]
}

@test "_read_cached_resets projects past 7d reset forward as anchor" {
    local past=$(($(date +%s) - 86400))   # 1 day ago
    jq -n --arg o "org-X" --argjson r7 "$past" \
        '{org_id:$o,five_hour_resets_at:null,seven_day_resets_at:$r7,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"
    run _read_cached_resets "org-X"
    [ "$status" -eq 0 ]
    r7=$(printf '%s' "$output" | cut -f2)
    [ -n "$r7" ]
    r7_epoch=$(sqlite3 :memory: "SELECT strftime('%s','$r7');")
    now=$(date +%s)
    [ "$r7_epoch" -gt "$now" ]
    [ "$((r7_epoch - now))" -le 604800 ]
}

@test "detect_window: ping override beats projection when ping happens after stale cache" {
    # Cache says window expired 1h ago.
    # A successful ping landed 30m ago (between expiration and now).
    # The new active window started at the ping (not at cache.reset+epsilon),
    # so reset = ping_ts + 5h (~4h 30m from now), NOT cache.reset + 5h (~4h from now).
    local cache_past=$(($(date +%s) - 3600))
    jq -n --arg o "org-PING" --argjson r5 "$cache_past" \
        '{org_id:$o,five_hour_resets_at:$r5,seven_day_resets_at:null,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"

    local ping_ts
    ping_ts="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-30 minutes'));")"
    db_insert_ping "$ping_ts" "anchor" "5h" 2 1

    CC_CLOCKER_ORG_ID="org-PING" run detect_window
    [ "$status" -eq 0 ]
    r5=$(printf '%s' "$output" | cut -f3)
    expected=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('$ping_ts','+5 hours'));")
    [ "$r5" = "$expected" ]
}

@test "detect_window: cache projection used when no ping after cache expiration" {
    # Cache expired 1h ago. No successful ping after.
    # Falls back to anchor-style projection: cache + 5h*N -> ~4h from now.
    local cache_past=$(($(date +%s) - 3600))
    jq -n --arg o "org-NOPING" --argjson r5 "$cache_past" \
        '{org_id:$o,five_hour_resets_at:$r5,seven_day_resets_at:null,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"

    # Insert a ping that pre-dates the cache (NOT after expiration).
    local old_ping
    old_ping="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-3 hours'));")"
    db_insert_ping "$old_ping" "anchor" "5h" 2 1

    CC_CLOCKER_ORG_ID="org-NOPING" run detect_window
    [ "$status" -eq 0 ]
    r5=$(printf '%s' "$output" | cut -f3)
    cache_iso=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', $cache_past, 'unixepoch');")
    expected=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('$cache_iso','+5 hours'));")
    [ "$r5" = "$expected" ]
}
