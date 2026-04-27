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
