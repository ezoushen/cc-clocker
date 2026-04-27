#!/usr/bin/env bats

load 'test_helper'

@test "log_info writes to stderr with INFO prefix" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; log_info 'hello' 2>&1 1>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO"* ]]
    [[ "$output" == *"hello"* ]]
}

@test "log_warn writes to stderr with WARN prefix" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; log_warn 'careful' 2>&1 1>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"careful"* ]]
}

@test "log_error writes to stderr with ERROR prefix" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; log_error 'broken' 2>&1 1>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"broken"* ]]
}

@test "log lines include ISO8601 timestamp" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; log_info 'x' 2>&1 1>/dev/null"
    [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "fmt_local converts UTC to local with offset (TZ=UTC)" {
    TZ=UTC run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_local '2026-04-27T16:20:00Z'"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-04-27T16:20:00+0000" ]
}

@test "fmt_local converts UTC to local with offset (TZ=Asia/Taipei)" {
    TZ=Asia/Taipei run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_local '2026-04-27T16:20:00Z'"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-04-28T00:20:00+0800" ]
}

@test "fmt_local handles fractional seconds" {
    TZ=UTC run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_local '2026-04-27T16:20:00.339Z'"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-04-27T16:20:00+0000" ]
}

@test "fmt_local empty input -> empty output" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_local ''"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "fmt_local invalid input -> echoed verbatim" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_local 'not-a-timestamp'"
    [ "$status" -eq 0 ]
    [ "$output" = "not-a-timestamp" ]
}

@test "_log timestamp includes TZ offset" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; log_info x 2>&1 1>/dev/null"
    # Match either +HHMM or -HHMM offset (any TZ)
    [[ "$output" =~ [+-][0-9]{4} ]]
}
