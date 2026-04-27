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

@test "_read_cached_resets drops past resets" {
    local past=$(($(date +%s) - 3600))
    jq -n --arg o "org-X" --argjson r5 "$past" \
        '{org_id:$o,five_hour_resets_at:$r5,seven_day_resets_at:null,captured_at:now}' \
        > "$CC_CLOCKER_CACHE_FILE"
    run _read_cached_resets "org-X"
    [ "$status" -ne 0 ]
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
