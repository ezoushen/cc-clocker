#!/usr/bin/env bash
# Pinger. Fires the canonical minimal-token claude invocation and records
# the result. Requires lib/db.sh and lib/log.sh sourced.
#
# fire_ping <reset_iso> <which_window>
#   reset_iso:    ISO8601 UTC of the window reset this ping follows
#   which_window: '5h' | '7d' | 'manual'
# Returns 0 on success (ok=1 written), nonzero on claude failure (ok=0 written).
fire_ping() {
    local reset="$1" which="$2"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local out rc=0
    out="$(
        CC_CLOCKER_PING=1 \
        claude -p "reply with: ok" \
            --no-session-persistence \
            --disable-slash-commands \
            --tools "" \
            --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
            --model claude-haiku-4-5-20251001 \
            --output-format text \
            2>/dev/null
    )" || rc=$?

    local chars=${#out}
    local ok=1
    if [ "$rc" -ne 0 ]; then
        ok=0
        log_warn "ping ($which) failed (exit $rc)"
    else
        log_info "ping ($which) ok ($chars chars)"
    fi

    # `|| true`: a transient sqlite write failure must not kill a long-running
    # daemon. Surface it via stderr instead. set -e in the caller would
    # otherwise propagate db_insert_ping's nonzero exit and bring everything
    # down before this function even reaches `return "$rc"`.
    db_insert_ping "$ts" "$reset" "$which" "$chars" "$ok" \
        || log_warn "db_insert_ping failed; ping NOT recorded"
    return "$rc"
}
