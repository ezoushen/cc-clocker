#!/usr/bin/env bats

load 'test_helper'

setup() {
    export CC_CLAUDE_HOME="$BATS_TEST_TMPDIR/claude"
    # Isolate from the host's real cache + claude auth.
    export CC_CLOCKER_CACHE_FILE="$BATS_TEST_TMPDIR/rate-limits.json"
    export CC_CLOCKER_ORG_ID=""
    mkdir -p "$CC_CLAUDE_HOME/projects/proj1"
    source "$PROJECT_ROOT/lib/window.sh"
}

# Replace __TS_MINUS_*__ placeholders with iso timestamps relative to now.
_install_fixture() {
    local fixture="$1" dest="$2"
    python3 - "$PROJECT_ROOT/tests/fixtures/$fixture" "$dest" <<'PY'
import sys, re, datetime as dt
src, dst = sys.argv[1], sys.argv[2]
now = dt.datetime.now(dt.timezone.utc)
mapping = {
    "MINUS_5MIN": dt.timedelta(minutes=5),
    "MINUS_1H":   dt.timedelta(hours=1),
    "MINUS_2H":   dt.timedelta(hours=2),
    "MINUS_3H":   dt.timedelta(hours=3),
    "MINUS_10H":  dt.timedelta(hours=10),
    "MINUS_3D":   dt.timedelta(days=3),
    "MINUS_30D":  dt.timedelta(days=30),
}
def sub(m):
    return (now - mapping[m.group(1)]).strftime("%Y-%m-%dT%H:%M:%SZ")
content = open(src).read()
content = re.sub(r"__TS_(\w+)__", sub, content)
open(dst, "w").write(content)
PY
}

@test "detect_window: 5h active -> picks 5h reset (always sooner than 7d)" {
    _install_fixture active-5h.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    run detect_window
    [ "$status" -eq 0 ]
    # output: <next_reset>\t<which>\t<reset_5h>\t<reset_7d>
    which=$(printf '%s' "$output" | cut -f2)
    [ "$which" = "5h" ]
}

@test "detect_window: idle (>5h, <7d) -> exit 1 (no env override)" {
    # 7d is no longer auto-detected from jsonl; idle 5h means no window.
    _install_fixture idle-but-7d-active.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    run detect_window
    [ "$status" -ne 0 ]
}

@test "detect_window: idle 5h + CC_CLOCKER_NEXT_7D_RESET env -> picks 7d" {
    _install_fixture idle-but-7d-active.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    local future
    future="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','+2 hours'));")"
    run env CC_CLOCKER_NEXT_7D_RESET="$future" \
        bash -c "source '$PROJECT_ROOT/lib/window.sh'; detect_window"
    [ "$status" -eq 0 ]
    which=$(printf '%s' "$output" | cut -f2)
    [ "$which" = "7d" ]
    r7=$(printf '%s' "$output" | cut -f4)
    [ "$r7" = "$future" ]
}

@test "detect_window: ignores past CC_CLOCKER_NEXT_7D_RESET" {
    _install_fixture active-5h.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    local past="2020-01-01T00:00:00Z"
    run env CC_CLOCKER_NEXT_7D_RESET="$past" \
        bash -c "source '$PROJECT_ROOT/lib/window.sh'; detect_window"
    [ "$status" -eq 0 ]
    r7=$(printf '%s' "$output" | cut -f4)
    [ -z "$r7" ]
}

@test "detect_window: all msgs >7d old -> exit 1" {
    _install_fixture all-old.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    run detect_window
    [ "$status" -ne 0 ]
}

@test "detect_window: ignores malformed lines" {
    _install_fixture malformed.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    run detect_window
    [ "$status" -eq 0 ]
}

@test "detect_window: scans multiple project dirs" {
    mkdir -p "$CC_CLAUDE_HOME/projects/proj2"
    _install_fixture active-5h.jsonl "$CC_CLAUDE_HOME/projects/proj2/sess.jsonl"
    run detect_window
    [ "$status" -eq 0 ]
}

@test "detect_window: no jsonl files -> exit 1" {
    run detect_window
    [ "$status" -ne 0 ]
}

@test "detect_window: recovers timestamps after malformed line" {
    _install_fixture malformed.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    run detect_window
    [ "$status" -eq 0 ]
    # Both 5h and 7d windows should be active; the bad line must not have
    # dropped the recent timestamp.
    which=$(printf '%s' "$output" | cut -f2)
    [ "$which" = "5h" ]
}

@test "detect_window: handles real Claude Code timestamps (with milliseconds)" {
    # Real ~/.claude/projects/*.jsonl timestamps look like "2026-04-27T11:55:22.339Z".
    local ts
    ts="$(python3 -c 'import datetime as dt; print((dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%S.339Z"))')"
    printf '{"type":"user","timestamp":"%s","message":"x"}\n' "$ts" \
        > "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    run detect_window
    [ "$status" -eq 0 ]
    which=$(printf '%s' "$output" | cut -f2)
    [ "$which" = "5h" ]
    r5=$(printf '%s' "$output" | cut -f3)
    [ -n "$r5" ]
}

@test "detect_window: CC_CLOCKER_5H_ANCHOR projects to next future 5h reset" {
    _install_fixture active-5h.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    # Anchor: 12 hours ago. Next 5h reset must be in (now, now+5h].
    local anchor
    anchor="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-12 hours'));")"
    run env CC_CLOCKER_5H_ANCHOR="$anchor" \
        bash -c "source '$PROJECT_ROOT/lib/window.sh'; detect_window"
    [ "$status" -eq 0 ]
    r5=$(printf '%s' "$output" | cut -f3)
    [ -n "$r5" ]
    # r5 should be > now and <= now+5h
    now_iso=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now'));")
    plus5=$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','+5 hours','+1 minute'));")
    [[ "$r5" > "$now_iso" ]]
    [[ "$r5" < "$plus5" ]]
}

@test "detect_window: CC_CLOCKER_7D_ANCHOR projects to next future 7d reset" {
    _install_fixture active-5h.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    local anchor
    anchor="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-3 days'));")"
    run env CC_CLOCKER_7D_ANCHOR="$anchor" \
        bash -c "source '$PROJECT_ROOT/lib/window.sh'; detect_window"
    [ "$status" -eq 0 ]
    r7=$(printf '%s' "$output" | cut -f4)
    [ -n "$r7" ]
}

@test "detect_window: 5h reset chosen iff sooner than env 7d" {
    _install_fixture active-5h.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    local far_future
    far_future="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','+30 days'));")"
    run env CC_CLOCKER_NEXT_7D_RESET="$far_future" \
        bash -c "source '$PROJECT_ROOT/lib/window.sh'; detect_window"
    [ "$status" -eq 0 ]
    which=$(printf '%s' "$output" | cut -f2)
    [ "$which" = "5h" ]
    r5=$(printf '%s' "$output" | cut -f3)
    r7=$(printf '%s' "$output" | cut -f4)
    [ "$r7" = "$far_future" ]
    [[ "$r5" < "$r7" ]]
}
