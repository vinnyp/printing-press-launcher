#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  ppl_setup_env
  ppl_source
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
  [[ "$output" == "ppl: test message" ]]
}

@test "die accepts custom exit code" {
  run die "test message" 2
  [ "$status" -eq 2 ]
}

@test "parse_args: positional only -> dontAsk default" {
  parse_args parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "dontAsk" ]
}

@test "parse_args: -p plan parcel" {
  parse_args -p plan parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "plan" ]
}

@test "parse_args: parcel -p plan (positional first)" {
  parse_args parcel -p plan
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "plan" ]
}

@test "parse_args: --permissions=acceptEdits parcel" {
  parse_args --permissions=acceptEdits parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "acceptEdits" ]
}

@test "parse_args: --permissions auto parcel" {
  parse_args --permissions auto parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "auto" ]
}

@test "parse_args: -p parcel (parcel consumed as mode, invalid) -> exit 2" {
  run parse_args -p parcel
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'parcel'"* ]]
}

@test "parse_args: -p plan with no positional -> exit 2" {
  run parse_args -p plan
  [ "$status" -eq 2 ]
}

@test "parse_args: -p bogus parcel -> invalid-mode exit 2" {
  run parse_args -p bogus parcel
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'bogus'"* ]]
}

@test "parse_args: no positional -> usage exit 2" {
  run parse_args
  [ "$status" -eq 2 ]
}

@test "parse_args: unknown flag -> usage exit 2" {
  run parse_args --bogus parcel
  [ "$status" -eq 2 ]
}

@test "parse_args: slug named 'plan' works without flag" {
  parse_args plan
  [ "$g_name" = "pp-plan" ]
  [ "$g_perm_mode" = "dontAsk" ]
}

@test "parse_args: last -p flag wins" {
  parse_args -p plan -p auto parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "auto" ]
}

@test "parse_args: parcel -p with non-TTY stdin -> exit 2" {
  run bash -c 'source "'"$PPL_REPO_ROOT"'/bin/ppl"; parse_args parcel -p' </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--permissions requires a value when stdin is not a tty"* ]]
}

@test "parse_args: bare -p with non-TTY stdin -> exit 2" {
  run bash -c 'source "'"$PPL_REPO_ROOT"'/bin/ppl"; parse_args -p' </dev/null
  [ "$status" -eq 2 ]
}
