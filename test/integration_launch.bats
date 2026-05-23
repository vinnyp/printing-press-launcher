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

@test "existing dir, no tmux: resumes with the same stable uuid" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  mkdir -p "$SB_PROJECTS_DIR/test/.claude"
  cp "$SB_REPO_ROOT/template/settings.local.json" "$SB_PROJECTS_DIR/test/.claude/settings.local.json"
  run_sb test
  [ "$status" -eq 0 ]
  sb_stub_log_contains 'claude --session-id c24a89d6-d9a4-5122-a1a5-b3a6249b9d0b'
}
