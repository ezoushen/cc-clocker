#!/usr/bin/env bats

load 'test_helper'

setup() {
    export PATH="$PROJECT_ROOT/tests/mocks:$PATH"
    export CC_CLOCKER_HOME="$BATS_TEST_TMPDIR/cc"
    export CC_CLOCKER_STATE="$BATS_TEST_TMPDIR/state"
    export CC_CLOCKER_CACHE_FILE="$BATS_TEST_TMPDIR/rate-limits.json"
    export CC_CLAUDE_HOME="$BATS_TEST_TMPDIR/claude"
    export CC_CLOCKER_ORG_ID="org-test-12345"
    mkdir -p "$CC_CLAUDE_HOME/projects/p1"
}

@test "statusline-tee writes cache file with rate_limits + org_id" {
    local r5_epoch=$(($(date +%s) + 5000))
    local r7_epoch=$(($(date +%s) + 50000))
    local stdin_json
    stdin_json="$(jq -nc \
        --argjson r5 "$r5_epoch" --argjson r7 "$r7_epoch" \
        '{model:{display_name:"Haiku"}, rate_limits:{five_hour:{used_percentage:30,resets_at:$r5}, seven_day:{used_percentage:40,resets_at:$r7}}}')"
    run bash -c "printf '%s' '$stdin_json' | '$PROJECT_ROOT/bin/cc-clocker' statusline-tee echo wrapped"
    [ "$status" -eq 0 ]
    [ -f "$CC_CLOCKER_CACHE_FILE" ]
    cached_org=$(jq -r '.org_id' "$CC_CLOCKER_CACHE_FILE")
    cached_r5=$(jq -r '.five_hour_resets_at' "$CC_CLOCKER_CACHE_FILE")
    [ "$cached_org" = "$CC_CLOCKER_ORG_ID" ]
    [ "$cached_r5" = "$r5_epoch" ]
}

@test "statusline-tee forwards stdin to wrapped command unchanged" {
    local stdin_json='{"model":{"display_name":"Haiku"}}'
    run bash -c "printf '%s' '$stdin_json' | '$PROJECT_ROOT/bin/cc-clocker' statusline-tee cat"
    [ "$status" -eq 0 ]
    [ "$output" = "$stdin_json" ]
}

@test "statusline-tee with no wrapped command echoes stdin" {
    local stdin_json='{"x":1}'
    run bash -c "printf '%s' '$stdin_json' | '$PROJECT_ROOT/bin/cc-clocker' statusline-tee"
    [ "$output" = "$stdin_json" ]
}

@test "statusline-tee skips cache write when rate_limits absent" {
    rm -f "$CC_CLOCKER_CACHE_FILE"
    local stdin_json='{"model":{"display_name":"Haiku"}}'
    run bash -c "printf '%s' '$stdin_json' | '$PROJECT_ROOT/bin/cc-clocker' statusline-tee cat"
    [ ! -f "$CC_CLOCKER_CACHE_FILE" ]
}

@test "set-anchor 5h saves anchor for current org_id" {
    run "$PROJECT_ROOT/bin/cc-clocker" set-anchor 5h "2026-04-27T16:20:00Z"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$CC_CLOCKER_ORG_ID"* ]]
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" "SELECT anchor_5h FROM accounts WHERE org_id='$CC_CLOCKER_ORG_ID';"
    [ "$output" = "2026-04-27T16:20:00Z" ]
}

@test "set-anchor rejects bad ISO format" {
    run "$PROJECT_ROOT/bin/cc-clocker" set-anchor 5h "yesterday"
    [ "$status" -ne 0 ]
}

@test "set-anchor rejects unknown kind" {
    run "$PROJECT_ROOT/bin/cc-clocker" set-anchor 1h "2026-04-27T16:20:00Z"
    [ "$status" -ne 0 ]
}
