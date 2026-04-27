#!/usr/bin/env bats

load 'test_helper'

@test "cc-clocker exists and is executable" {
    [ -x "$PROJECT_ROOT/bin/cc-clocker" ]
}

@test "cc-clocker prints usage on no args" {
    run "$PROJECT_ROOT/bin/cc-clocker"
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage:"* ]]
}

@test "cc-clocker --version prints semver" {
    run "$PROJECT_ROOT/bin/cc-clocker" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
