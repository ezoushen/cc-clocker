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
