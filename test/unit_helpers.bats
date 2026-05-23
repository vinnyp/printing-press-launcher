#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  sb_setup_env
  sb_source
}

@test "die default exit 1 with sb prefix" {
  run die "boom"
  [ "$status" -eq 1 ]
  [[ "$output" == "sb: boom" ]]
}

@test "die accepts a custom exit code" {
  run die "boom" 2
  [ "$status" -eq 2 ]
}

@test "validate_name accepts valid slugs" {
  run validate_name numista
  [ "$status" -eq 0 ]
  run validate_name my-proj-1
  [ "$status" -eq 0 ]
}

@test "validate_name rejects invalid slugs" {
  run validate_name "foo bar"
  [ "$status" -ne 0 ]
  run validate_name "Foo"
  [ "$status" -ne 0 ]
  run validate_name ""
  [ "$status" -ne 0 ]
  run validate_name "pp_foo"
  [ "$status" -ne 0 ]
}
