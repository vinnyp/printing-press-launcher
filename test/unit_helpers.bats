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

@test "agent_binary returns claude" {
  run agent_binary claude
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
}

@test "agent_binary returns gemini" {
  run agent_binary gemini
  [ "$status" -eq 0 ]
  [ "$output" = "gemini" ]
}

@test "agent_binary rejects unknown agent with exit 2" {
  run agent_binary bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown agent 'bogus'"* ]]
}

@test "derive_uuid test returns pinned UUIDv5 for sb:test" {
  run derive_uuid test
  [ "$status" -eq 0 ]
  [ "$output" = "c24a89d6-d9a4-5122-a1a5-b3a6249b9d0b" ]
}

@test "fresh_uuid returns distinct valid uuids" {
  run fresh_uuid
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
  local first="$output"
  run fresh_uuid
  [[ "$output" != "$first" ]]
}
