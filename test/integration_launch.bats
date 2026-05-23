#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  sb_setup_env
  # Integration tests exec bin/sb directly; do not source it.
}

# Run bin/sb with closed stdin so it never blocks on a TTY-only path.
run_sb() {
  run bash -c "'$SB_REPO_ROOT/bin/sb' $*" </dev/null
}

@test "fresh project: scaffolds, launches claude with stable uuid, attaches, prints hint" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  run_sb test
  [ "$status" -eq 0 ]
  [ -f "$SB_PROJECTS_DIR/test/.claude/settings.local.json" ]
  [ ! -f "$SB_PROJECTS_DIR/test/.claude/.iteration" ]
  sb_stub_log_contains 'tmux new-session -d -s test'
  sb_stub_log_contains 'tmux send-keys -t test claude --session-id c24a89d6-d9a4-5122-a1a5-b3a6249b9d0b Enter'
  sb_stub_log_contains 'tmux attach -t test'
  [[ "$output" == *"detached with Ctrl-b d"* ]]
}

@test "live session: attach only, no new-session" {
  export SB_STUB_TMUX_SESSION_EXISTS=true
  mkdir -p "$SB_PROJECTS_DIR/test/.claude"
  run_sb test
  [ "$status" -eq 0 ]
  sb_stub_log_contains 'tmux attach -t test'
  ! sb_stub_log_contains 'tmux new-session'
}

@test "--fresh against a live session: attach only, --fresh ignored" {
  export SB_STUB_TMUX_SESSION_EXISTS=true
  mkdir -p "$SB_PROJECTS_DIR/test/.claude"
  run_sb --fresh test
  [ "$status" -eq 0 ]
  sb_stub_log_contains 'tmux attach -t test'
  ! sb_stub_log_contains 'tmux new-session'
  ! sb_stub_log_contains 'send-keys'
}

@test "existing dir, no tmux: resumes with the same stable uuid" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  mkdir -p "$SB_PROJECTS_DIR/test/.claude"
  cp "$SB_REPO_ROOT/template/settings.local.json" "$SB_PROJECTS_DIR/test/.claude/settings.local.json"
  run_sb test
  [ "$status" -eq 0 ]
  sb_stub_log_contains 'claude --session-id c24a89d6-d9a4-5122-a1a5-b3a6249b9d0b'
}

@test "--fresh: session id is a valid uuid and not the stable one" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  run_sb --fresh test
  [ "$status" -eq 0 ]
  ! sb_stub_log_contains 'c24a89d6-d9a4-5122-a1a5-b3a6249b9d0b'
  grep -qE 'claude --session-id [0-9a-f-]{36} Enter' "$SB_STUB_LOG"
}

@test "--agent agy: launches agy with a conversation id" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  run_sb --agent agy test
  [ "$status" -eq 0 ]
  sb_stub_log_contains 'tmux send-keys -t test agy --conversation'
}

@test "flag after positional: test --agent agy" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  run_sb test --agent agy
  [ "$status" -eq 0 ]
  sb_stub_log_contains 'tmux send-keys -t test agy --conversation'
}

@test "--agent bogus: exit 2, no side effects" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  run_sb --agent bogus test
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown agent 'bogus'"* ]]
  [ ! -d "$SB_PROJECTS_DIR/test" ]
  ! sb_stub_log_contains 'tmux'
}

@test "invalid name: exit 1, no dir created" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  run_sb "'foo bar'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid name"* ]]
  [ ! -d "$SB_PROJECTS_DIR/foo bar" ]
}

@test "missing template: exit 1 with documented message" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  local fake_home="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$fake_home/bin"
  cp "$SB_REPO_ROOT/bin/sb" "$fake_home/bin/sb"
  chmod +x "$fake_home/bin/sb"
  run bash -c "'$fake_home/bin/sb' test" </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"template missing"* ]]
}
