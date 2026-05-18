#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  pp_setup_env
  pp_source
}

@test "validate_permission_mode accepts default" {
  run validate_permission_mode default
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode accepts acceptEdits" {
  run validate_permission_mode acceptEdits
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode accepts plan" {
  run validate_permission_mode plan
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode accepts auto" {
  run validate_permission_mode auto
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode accepts dontAsk" {
  run validate_permission_mode dontAsk
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode rejects wrong case" {
  run validate_permission_mode Plan
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'Plan'"* ]]
}

@test "validate_permission_mode rejects unknown mode" {
  run validate_permission_mode yolo
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'yolo'"* ]]
}

@test "validate_permission_mode rejects empty string" {
  run validate_permission_mode ""
  [ "$status" -eq 2 ]
}

@test "die uses exit code 1 by default" {
  run die "test message"
  [ "$status" -eq 1 ]
  [[ "$output" == "pp: test message" ]]
}

@test "die accepts custom exit code" {
  run die "test message" 2
  [ "$status" -eq 2 ]
}
