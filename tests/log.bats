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

@test "log lines include compact local timestamp (Mon DD HH:MM:SS)" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; log_info 'x' 2>&1 1>/dev/null"
    [[ "$output" =~ [A-Z][a-z]{2}\ +[0-9]{1,2}\ +[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
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

@test "_log line is compact and starts with month name" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; log_info hello 2>&1 1>/dev/null"
    [[ "$output" =~ ^[A-Z][a-z]{2}\  ]]
    [[ "$output" == *"hello"* ]]
    [[ "$output" == *"INFO"* ]]
}

@test "fmt_when shows time only when same day (TZ=UTC)" {
    local today
    today="$(date -u '+%Y-%m-%d')"
    TZ=UTC run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_when '${today}T16:20:00Z'"
    [[ "$output" =~ ^[0-9]{2}:[0-9]{2}$ ]]
}

@test "fmt_when shows weekday + time within +/- 6 days (TZ=UTC)" {
    local future
    future="$(date -u -v+3d '+%Y-%m-%d' 2>/dev/null || date -u -d '+3 days' '+%Y-%m-%d')"
    TZ=UTC run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_when '${future}T16:20:00Z'"
    [[ "$output" =~ ^(Sun|Mon|Tue|Wed|Thu|Fri|Sat)\ [0-9]{2}:[0-9]{2}$ ]]
}

@test "fmt_relative future returns 'in <duration>'" {
    local future
    future="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','+2 hours'));")"
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_relative '$future'"
    [[ "$output" =~ ^in\  ]]
}

@test "fmt_relative past returns '<duration> ago'" {
    local past
    past="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','-2 hours'));")"
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_relative '$past'"
    [[ "$output" =~ ago$ ]]
}

@test "fmt_relative within 60s returns 'just now'" {
    local nowish
    nowish="$(sqlite3 :memory: "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now','+10 seconds'));")"
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_relative '$nowish'"
    [ "$output" = "just now" ]
}

@test "fmt_duration formats seconds into human units" {
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_duration 45"
    [ "$output" = "45s" ]
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_duration 600"
    [ "$output" = "10m" ]
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_duration 8385"
    [ "$output" = "2h 19m" ]
    run bash -c "source '$PROJECT_ROOT/lib/log.sh'; fmt_duration 90000"
    [ "$output" = "1d 1h" ]
}
