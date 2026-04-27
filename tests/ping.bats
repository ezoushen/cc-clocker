#!/usr/bin/env bats

load 'test_helper'

setup() {
    export PATH="$PROJECT_ROOT/tests/mocks:$PATH"
    export MOCK_CLAUDE_LOG="$BATS_TEST_TMPDIR/claude.log"
    export CC_CLOCKER_HOME="$BATS_TEST_TMPDIR/cc"
    : > "$MOCK_CLAUDE_LOG"
    source "$PROJECT_ROOT/lib/db.sh"
    source "$PROJECT_ROOT/lib/log.sh"
    source "$PROJECT_ROOT/lib/ping.sh"
    db_init
}

@test "ping invokes claude with all locked flags" {
    fire_ping "2026-04-27T19:00:00Z" "5h"
    run cat "$MOCK_CLAUDE_LOG"
    [[ "$output" == *"-p"* ]]
    [[ "$output" == *"--no-session-persistence"* ]]
    [[ "$output" == *"--disable-slash-commands"* ]]
    [[ "$output" == *"--tools"* ]]
    [[ "$output" == *"--strict-mcp-config"* ]]
    [[ "$output" == *"--mcp-config"* ]]
    [[ "$output" == *"/dev/null"* ]]
    [[ "$output" == *"--setting-sources"* ]]
    [[ "$output" == *"user"* ]]
    [[ "$output" == *"claude-haiku-4-5-20251001"* ]]
    [[ "$output" == *"--output-format"* ]]
    [[ "$output" == *"text"* ]]
    [[ "$output" == *"reply with: ok"* ]]
}

@test "ping does NOT pass --bare (would force API key auth)" {
    fire_ping "2026-04-27T19:00:00Z" "5h"
    run cat "$MOCK_CLAUDE_LOG"
    [[ "$output" != *"--bare"* ]]
}

@test "ping records ok=1 + which_window on success" {
    fire_ping "2026-04-27T19:00:00Z" "5h"
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" \
        "SELECT ok, reset_detected, which_window FROM pings ORDER BY id DESC LIMIT 1;"
    [ "$output" = "1|2026-04-27T19:00:00Z|5h" ]
}

@test "ping records ok=0 on claude failure" {
    MOCK_CLAUDE_FAIL=1 fire_ping "2026-04-27T19:00:00Z" "5h" || true
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" "SELECT ok FROM pings ORDER BY id DESC LIMIT 1;"
    [ "$output" = "0" ]
}

@test "ping records response_chars" {
    MOCK_CLAUDE_OUTPUT="hello world" fire_ping "2026-04-27T19:00:00Z" "5h"
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" "SELECT response_chars FROM pings ORDER BY id DESC LIMIT 1;"
    [ "$output" = "11" ]
}

@test "ping handles 7d which_window" {
    fire_ping "2026-04-27T19:00:00Z" "7d"
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" "SELECT which_window FROM pings ORDER BY id DESC LIMIT 1;"
    [ "$output" = "7d" ]
}

@test "ping.sh source contains CLAUDE_CODE_SIMPLE=1" {
    run grep -F "CLAUDE_CODE_SIMPLE=1" "$PROJECT_ROOT/lib/ping.sh"
    [ "$status" -eq 0 ]
}
