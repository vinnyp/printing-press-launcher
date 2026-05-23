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
