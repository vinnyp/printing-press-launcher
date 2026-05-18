#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  ppl_setup_env
  ppl_source
}

@test "compute_slug adds pp- prefix when missing" {
  run compute_slug parcel
  [ "$status" -eq 0 ]
  [ "$output" = "pp-parcel" ]
}

@test "compute_slug keeps pp- prefix when already present" {
  run compute_slug pp-parcel
  [ "$status" -eq 0 ]
  [ "$output" = "pp-parcel" ]
}

@test "validate_slug accepts valid slugs" {
  run validate_slug pp-foo
  [ "$status" -eq 0 ]
  run validate_slug pp-foo-1
  [ "$status" -eq 0 ]
  run validate_slug pp-a-b-c
  [ "$status" -eq 0 ]
}

@test "validate_slug rejects invalid slugs" {
  run validate_slug "foo bar"
  [ "$status" -ne 0 ]
  run validate_slug "Foo"
  [ "$status" -ne 0 ]
  run validate_slug ""
  [ "$status" -ne 0 ]
  run validate_slug "pp_foo"
  [ "$status" -ne 0 ]
}

@test "bump_iteration: 0 -> 1" {
  local target="$BATS_TEST_TMPDIR/proj/pp-test"
  mkdir -p "$target/.claude"
  printf '0\n' > "$target/.claude/.iteration"
  run bump_iteration "$target"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  [ "$(cat "$target/.claude/.iteration")" = "1" ]
}

@test "bump_iteration: 9 -> 10" {
  local target="$BATS_TEST_TMPDIR/proj/pp-test"
  mkdir -p "$target/.claude"
  printf '9\n' > "$target/.claude/.iteration"
  run bump_iteration "$target"
  [ "$status" -eq 0 ]
  [ "$output" = "10" ]
  [ "$(cat "$target/.claude/.iteration")" = "10" ]
}

@test "bump_iteration: rejects non-integer" {
  local target="$BATS_TEST_TMPDIR/proj/pp-test"
  mkdir -p "$target/.claude"
  printf 'abc\n' > "$target/.claude/.iteration"
  run bump_iteration "$target"
  [ "$status" -ne 0 ]
}

@test "derive_uuid pp-parcel-01 returns pinned UUIDv5" {
  run derive_uuid pp-parcel-01
  [ "$status" -eq 0 ]
  [ "$output" = "8c271dfc-73c6-5318-89b2-891608f9c4b2" ]
}

@test "ensure_scaffolding creates fresh project layout" {
  local target="$BATS_TEST_TMPDIR/proj/pp-fresh"
  ensure_scaffolding "$target"
  [ -d "$target/.claude" ]
  [ -f "$target/.claude/settings.local.json" ]
  [ "$(cat "$target/.claude/.iteration")" = "0" ]
}

@test "ensure_scaffolding does not overwrite existing template" {
  local target="$BATS_TEST_TMPDIR/proj/pp-existing"
  mkdir -p "$target/.claude"
  printf 'CUSTOM\n' > "$target/.claude/settings.local.json"
  printf '7\n' > "$target/.claude/.iteration"
  ensure_scaffolding "$target"
  [ "$(cat "$target/.claude/settings.local.json")" = "CUSTOM" ]
  [ "$(cat "$target/.claude/.iteration")" = "7" ]
}
