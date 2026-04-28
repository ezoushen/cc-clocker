#!/usr/bin/env bash
# Container entrypoint. Runs every time the container starts (after volume
# mounts), so anything that lives under /root/.* must be re-asserted here:
# the underlying volume is otherwise empty on first run, and the build-time
# mkdir is shadowed by the mount.

set -e

# 1. Ensure expected dirs exist on the volume side.
mkdir -p \
    /root/.claude/projects \
    /root/.cc-clocker \
    /root/.local/share/cc-clocker \
    /root/.local/state/cc-clocker

# 2. Configure Claude Code statusline to feed our cache. We merge into
#    settings.json (preserve theme, hooks, etc) rather than overwrite. The
#    statusline-tee wrapper passes through to the silent stub, so the only
#    visible side effect is that rate_limits land in our cache file.
SETTINGS=/root/.claude/settings.json
DESIRED_STATUSLINE_CMD="/usr/local/bin/cc-clocker statusline-tee /opt/cc-clocker/contrib/docker/silent-statusline.sh"

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

current_cmd="$(jq -r 'try .statusLine.command // empty' "$SETTINGS" 2>/dev/null)"
if [ "$current_cmd" != "$DESIRED_STATUSLINE_CMD" ]; then
    tmp="${SETTINGS}.tmp.$$"
    jq --arg cmd "$DESIRED_STATUSLINE_CMD" \
       '.statusLine = {type:"command", command:$cmd}' \
       "$SETTINGS" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$SETTINGS"
    rm -f "$tmp"
fi

# 3. If the daemon is not already running, start it in the background so
#    pings happen even when no shell is attached. Logs go to /tmp.
if ! pgrep -f "cc-clocker run" >/dev/null 2>&1; then
    # APPEND, never truncate. We want to be able to look back when the
    # daemon dies for any reason.
    nohup /usr/local/bin/cc-clocker run >>/tmp/cc-clocker.log 2>&1 &
fi

# 4. Friendly first-attach hint.
cat <<'EOF'

  cc-clocker container ready.

  First-time setup:
    1. claude /login          # OAuth (paste URL into host browser)
    2. cc-clocker doctor      # verify auth + deps
    3. cc-clocker set-anchor 5h <ISO8601 UTC of any past 5h reset>
       cc-clocker set-anchor 7d <ISO8601 UTC of any past 7d reset>   # optional
    4. cc-clocker status      # daemon already running in background

  After any interactive `claude` session, statusline-tee auto-refreshes
  the rate-limits cache — anchors become a fallback.

  Daemon log: tail -f /tmp/cc-clocker.log

EOF

exec "$@"
