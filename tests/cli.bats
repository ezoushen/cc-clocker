#!/usr/bin/env bats

load 'test_helper'

setup() {
    export PATH="$PROJECT_ROOT/tests/mocks:$PATH"
    export CC_CLOCKER_HOME="$BATS_TEST_TMPDIR/cc"
    export CC_CLOCKER_STATE="$BATS_TEST_TMPDIR/state"
    export CC_CLAUDE_HOME="$BATS_TEST_TMPDIR/claude"
    export MOCK_CLAUDE_LOG="$BATS_TEST_TMPDIR/claude.log"
    : > "$MOCK_CLAUDE_LOG"
    mkdir -p "$CC_CLAUDE_HOME/projects/p1"
}

@test "init creates db" {
    run "$PROJECT_ROOT/bin/cc-clocker" init
    [ "$status" -eq 0 ]
    [ -f "$CC_CLOCKER_HOME/clocker.db" ]
}

@test "tick fires a ping" {
    "$PROJECT_ROOT/bin/cc-clocker" init
    run "$PROJECT_ROOT/bin/cc-clocker" tick
    [ "$status" -eq 0 ]
    n=$(sqlite3 "$CC_CLOCKER_HOME/clocker.db" "SELECT count(*) FROM pings;")
    [ "$n" = "1" ]
}

@test "log prints recent pings" {
    "$PROJECT_ROOT/bin/cc-clocker" init
    "$PROJECT_ROOT/bin/cc-clocker" tick
    run "$PROJECT_ROOT/bin/cc-clocker" log
    [ "$status" -eq 0 ]
    [[ "$output" == *"manual"* ]] || [[ "$output" == *"5h"* ]] || [[ "$output" == *"7d"* ]]
}

@test "log respects N argument" {
    "$PROJECT_ROOT/bin/cc-clocker" init
    "$PROJECT_ROOT/bin/cc-clocker" tick
    "$PROJECT_ROOT/bin/cc-clocker" tick
    "$PROJECT_ROOT/bin/cc-clocker" tick
    run "$PROJECT_ROOT/bin/cc-clocker" log 2
    [ "$status" -eq 0 ]
    n=$(printf '%s\n' "$output" | grep -c '^')
    [ "$n" -le 3 ]
}

@test "status with no pings prints 'no pings'" {
    "$PROJECT_ROOT/bin/cc-clocker" init
    run "$PROJECT_ROOT/bin/cc-clocker" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"no pings"* ]] || [[ "$output" == *"never"* ]]
}

@test "status after tick shows last ping" {
    "$PROJECT_ROOT/bin/cc-clocker" init
    "$PROJECT_ROOT/bin/cc-clocker" tick
    run "$PROJECT_ROOT/bin/cc-clocker" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"last ping"* ]]
}

@test "status shows 5h and 7d resets when window active" {
    ts=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-1 hour'));")
    printf '{"type":"user","timestamp":"%s","message":"x"}\n' "$ts" \
        > "$CC_CLAUDE_HOME/projects/p1/s.jsonl"
    "$PROJECT_ROOT/bin/cc-clocker" init
    run "$PROJECT_ROOT/bin/cc-clocker" status
    [[ "$output" == *"5h reset"* ]]
    [[ "$output" == *"7d reset"* ]]
    [[ "$output" == *"next fire"* ]]
}

@test "stop reports not running when no pid file" {
    run "$PROJECT_ROOT/bin/cc-clocker" stop
    [[ "$output" == *"not running"* ]]
}

@test "unknown subcommand exits 1" {
    run "$PROJECT_ROOT/bin/cc-clocker" bogus
    [ "$status" -eq 1 ]
}
