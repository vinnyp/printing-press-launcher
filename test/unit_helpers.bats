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

@test "agent_cmd returns claude invocation (--session-id)" {
  run agent_cmd claude
  [ "$status" -eq 0 ]
  [ "$output" = "claude --session-id" ]
}

@test "agent_cmd returns agy invocation (--conversation)" {
  run agent_cmd agy
  [ "$status" -eq 0 ]
  [ "$output" = "agy --conversation" ]
}

@test "agent_cmd rejects unknown agent with exit 2" {
  run agent_cmd bogus
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

@test "ensure_scaffolding creates .claude and settings, no .iteration" {
  local target="$BATS_TEST_TMPDIR/proj/fresh"
  ensure_scaffolding "$target"
  [ -d "$target/.claude" ]
  [ -f "$target/.claude/settings.local.json" ]
  [ ! -f "$target/.claude/.iteration" ]
}

@test "ensure_scaffolding does not overwrite existing settings" {
  local target="$BATS_TEST_TMPDIR/proj/existing"
  mkdir -p "$target/.claude"
  printf 'CUSTOM\n' > "$target/.claude/settings.local.json"
  ensure_scaffolding "$target"
  [ "$(cat "$target/.claude/settings.local.json")" = "CUSTOM" ]
}

@test "preflight passes with stubs on PATH and dirs present" {
  g_agent=claude
  run preflight
  [ "$status" -eq 0 ]
}

@test "preflight dies when projects dir is missing" {
  g_agent=claude
  PROJECTS_DIR="$BATS_TEST_TMPDIR/does-not-exist"
  run preflight
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "template is permissions-only (defaultMode acceptEdits, no skills)" {
  grep -q '"defaultMode": "acceptEdits"' "$SB_REPO_ROOT/template/settings.local.json"
  ! grep -q 'Skill(' "$SB_REPO_ROOT/template/settings.local.json"
}
