#!/usr/bin/env bats

load 'test_helper'

setup() {
    source "$PROJECT_ROOT/lib/schedule.sh"
}

@test "next_fire_time adds 30s to reset" {
    run next_fire_time "2026-04-27T19:00:00Z"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-04-27T19:00:30Z" ]
}

@test "seconds_until returns positive when target is future" {
    local future
    future="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','+1 minute'));")"
    run seconds_until "$future"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
    [ "$output" -le 60 ]
}

@test "seconds_until returns 0 or negative when target is past" {
    local past
    past="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-1 minute'));")"
    run seconds_until "$past"
    [ "$status" -eq 0 ]
    [ "$output" -le 0 ]
}

@test "next_fire_time honors CC_CLOCKER_PING_DELAY_SECONDS" {
    CC_CLOCKER_PING_DELAY_SECONDS=120 run next_fire_time "2026-04-27T19:00:00Z"
    [ "$output" = "2026-04-27T19:02:00Z" ]
}

@test "next_fire_time falls back to 30s for non-integer delay" {
    CC_CLOCKER_PING_DELAY_SECONDS="bogus" run next_fire_time "2026-04-27T19:00:00Z"
    [ "$output" = "2026-04-27T19:00:30Z" ]
}

@test "next_fire_time falls back to 30s for negative delay" {
    CC_CLOCKER_PING_DELAY_SECONDS="-5" run next_fire_time "2026-04-27T19:00:00Z"
    [ "$output" = "2026-04-27T19:00:30Z" ]
}
