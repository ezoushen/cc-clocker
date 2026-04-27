#!/usr/bin/env bats

load 'test_helper'

setup() {
    export CC_CLAUDE_HOME="$BATS_TEST_TMPDIR/claude"
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

@test "detect_window: idle (>5h, <7d) -> picks 7d reset" {
    _install_fixture idle-but-7d-active.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    run detect_window
    [ "$status" -eq 0 ]
    which=$(printf '%s' "$output" | cut -f2)
    [ "$which" = "7d" ]
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

@test "detect_window: 5h reset chosen iff sooner than 7d" {
    _install_fixture active-5h.jsonl "$CC_CLAUDE_HOME/projects/proj1/sess.jsonl"
    run detect_window
    next=$(printf '%s' "$output" | cut -f1)
    r5=$(printf '%s' "$output" | cut -f3)
    r7=$(printf '%s' "$output" | cut -f4)
    [ "$next" = "$r5" ]
    [ -n "$r7" ]
    # r5 < r7 lexicographically (ISO8601)
    [[ "$r5" < "$r7" ]]
}
