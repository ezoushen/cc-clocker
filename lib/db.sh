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
