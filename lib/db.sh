#!/usr/bin/env bash
# SQLite wrapper. Source this; functions read CC_CLOCKER_HOME for db path.

: "${CC_CLOCKER_HOME:=$HOME/.local/share/cc-clocker}"

_db_path() { printf '%s/clocker.db' "$CC_CLOCKER_HOME"; }

# shellcheck disable=SC2120  # called both with heredoc and with sql string args (Task 4)
_db_exec() {
    sqlite3 -batch "$(_db_path)" "$@"
}

db_init() {
    mkdir -p "$CC_CLOCKER_HOME"
    _db_exec <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS pings (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    ts              TEXT NOT NULL,
    reset_detected  TEXT,
    which_window    TEXT,
    response_chars  INTEGER,
    ok              INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_pings_ts ON pings(ts);
SQL
}

db_insert_ping() {
    local ts="$1" reset="$2" which="$3" chars="$4" ok="$5"
    _db_exec "INSERT INTO pings(ts, reset_detected, which_window, response_chars, ok) VALUES('$ts', '$reset', '$which', $chars, $ok);"
}

db_last_ping() {
    _db_exec -separator $'\t' "SELECT ts, reset_detected, which_window, response_chars, ok FROM pings ORDER BY id DESC LIMIT 1;"
}

db_recent_pings() {
    local n="${1:-20}"
    [[ "$n" =~ ^[0-9]+$ ]] || n=20
    _db_exec -separator $'\t' "SELECT ts, reset_detected, which_window, response_chars, ok FROM pings ORDER BY id DESC LIMIT $n;"
}
