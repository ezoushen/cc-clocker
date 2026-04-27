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

-- Per-account anchors. Switching Anthropic accounts (different orgId)
-- invalidates the rate-limits cache, and we fall back to whatever anchor
-- was last set for that account, if any.
CREATE TABLE IF NOT EXISTS accounts (
    org_id      TEXT PRIMARY KEY,
    anchor_5h   TEXT,
    anchor_7d   TEXT,
    updated_at  TEXT NOT NULL
);
SQL
}

# db_set_anchor <org_id> <5h|7d> <iso8601_utc>
db_set_anchor() {
    local org_id="$1" kind="$2" iso="$3"
    case "$kind" in 5h|7d) ;; *) return 1 ;; esac
    local col="anchor_$kind"
    _db_exec "INSERT INTO accounts(org_id, $col, updated_at) VALUES('$org_id', '$iso', datetime('now')) ON CONFLICT(org_id) DO UPDATE SET $col='$iso', updated_at=datetime('now');"
}

# db_get_anchor <org_id> <5h|7d>
db_get_anchor() {
    local org_id="$1" kind="$2"
    case "$kind" in 5h|7d) ;; *) return 1 ;; esac
    local col="anchor_$kind"
    _db_exec "SELECT COALESCE($col, '') FROM accounts WHERE org_id='$org_id';"
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
