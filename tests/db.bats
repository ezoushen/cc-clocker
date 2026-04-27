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
