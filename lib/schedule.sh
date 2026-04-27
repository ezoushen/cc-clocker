#!/usr/bin/env bash
# Schedule math. Portable date arithmetic via sqlite3.
# Inputs are internal-only ISO8601 timestamps (already validated upstream).

next_fire_time() {
    local reset="$1"
    sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('${reset}','+30 seconds'));"
}

seconds_until() {
    local target="$1"
    sqlite3 :memory: "SELECT CAST((julianday('${target}') - julianday('now')) * 86400 AS INTEGER);"
}
