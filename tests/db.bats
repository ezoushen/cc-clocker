#!/usr/bin/env bats

load 'test_helper'

setup() {
    export CC_CLOCKER_HOME="$BATS_TEST_TMPDIR/cc"
    source "$PROJECT_ROOT/lib/db.sh"
}

@test "db_init creates db file and pings table" {
    db_init
    [ -f "$CC_CLOCKER_HOME/clocker.db" ]
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" ".schema pings"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CREATE TABLE pings"* ]]
    [[ "$output" == *"reset_detected"* ]]
    [[ "$output" == *"which_window"* ]]
}

@test "db_init is idempotent" {
    db_init
    db_init
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" "SELECT count(*) FROM pings;"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "db_init enables WAL mode" {
    db_init
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" "PRAGMA journal_mode;"
    [ "$output" = "wal" ]
}

@test "db_insert_ping persists a row with which_window" {
    db_init
    db_insert_ping "2026-04-27T19:00:30Z" "2026-04-27T19:00:00Z" "5h" 5 1
    run sqlite3 "$CC_CLOCKER_HOME/clocker.db" "SELECT which_window FROM pings LIMIT 1;"
    [ "$output" = "5h" ]
}

@test "db_last_ping returns most recent row as TSV" {
    db_init
    db_insert_ping "2026-04-27T14:00:00Z" "2026-04-27T13:59:30Z" "5h" 3 1
    db_insert_ping "2026-04-27T19:00:30Z" "2026-04-27T19:00:00Z" "7d" 5 1
    run db_last_ping
    [ "$status" -eq 0 ]
    [[ "$output" == *"2026-04-27T19:00:30Z"* ]]
    [[ "$output" == *"7d"* ]]
}

@test "db_last_ping returns empty when no rows" {
    db_init
    run db_last_ping
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "db_recent_pings returns N rows" {
    db_init
    for i in 1 2 3 4 5; do
        db_insert_ping "2026-04-27T0${i}:00:00Z" "2026-04-27T0${i}:00:00Z" "5h" 5 1
    done
    run db_recent_pings 3
    [ "$status" -eq 0 ]
    n=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
    [ "$n" = "3" ]
}
