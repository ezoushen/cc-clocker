#!/usr/bin/env bats

load 'test_helper'

setup() {
    export PATH="$PROJECT_ROOT/tests/mocks:$PATH"
    export CC_CLOCKER_HOME="$BATS_TEST_TMPDIR/cc"
    export CC_CLAUDE_HOME="$BATS_TEST_TMPDIR/claude"
    export MOCK_CLAUDE_LOG="$BATS_TEST_TMPDIR/claude.log"
    : > "$MOCK_CLAUDE_LOG"
    mkdir -p "$CC_CLAUDE_HOME/projects/p1"
    source "$PROJECT_ROOT/lib/db.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/window.sh"
    source "$PROJECT_ROOT/lib/ping.sh"
    source "$PROJECT_ROOT/lib/schedule.sh"
    db_init
}

@test "run_once_or_sleep with no window returns status 2" {
    run run_once_or_sleep
    [ "$status" -eq 2 ]
}

@test "run_once_or_sleep with active 5h returns status 3 + sleep_seconds + which" {
    ts=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-30 minutes'));")
    printf '{"type":"user","timestamp":"%s","message":"x"}\n' "$ts" \
        > "$CC_CLAUDE_HOME/projects/p1/s.jsonl"
    run run_once_or_sleep
    [ "$status" -eq 3 ]
    # output: "<sleep_s>\t<which>\t<reset>"
    sleep_s=$(printf '%s' "$output" | cut -f1)
    which=$(printf '%s' "$output" | cut -f2)
    [ "$sleep_s" -gt 0 ]
    [ "$which" = "5h" ]
}

@test "run_once_or_sleep with idle (>5h, <7d) picks 7d" {
    ts=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-3 days'));")
    printf '{"type":"user","timestamp":"%s","message":"x"}\n' "$ts" \
        > "$CC_CLAUDE_HOME/projects/p1/s.jsonl"
    run run_once_or_sleep
    [ "$status" -eq 3 ]
    which=$(printf '%s' "$output" | cut -f2)
    [ "$which" = "7d" ]
}

@test "fire_now records a ping" {
    fire_now || true
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" "SELECT count(*) FROM pings;"
    [ "$output" = "1" ]
}

@test "fire_now records which='manual' when no window detected" {
    fire_now || true
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" "SELECT which_window FROM pings LIMIT 1;"
    [ "$output" = "manual" ]
}
