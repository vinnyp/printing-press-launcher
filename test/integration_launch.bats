#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  pp_setup_env
  # Integration tests exec bin/pp directly; do not source it.
}

# Helper to run bin/pp with closed stdin so the script never blocks on a TTY-only path.
run_pp() {
  run bash -c "'$PP_REPO_ROOT/bin/pp' $*" </dev/null
}

@test "fresh project, no flag: launches with dontAsk, iter 01" {
  export PP_STUB_TMUX_SESSION_EXISTS=false
  run_pp test
  [ "$status" -eq 0 ]
  pp_stub_log_contains 'tmux new-session -d -s pp-test'
  pp_stub_log_contains 'tmux send-keys -t pp-test claude --permission-mode dontAsk -n pp-test-01 --session-id c5afa652-6383-5606-ad1a-b2232c25bd8f Enter'
  pp_stub_log_contains 'tmux attach -t pp-test'
  [ "$(cat "$PP_PROJECTS_DIR/pp-test/.claude/.iteration")" = "1" ]
}

@test "live attach: no new-session, no iter bump" {
  export PP_STUB_TMUX_SESSION_EXISTS=true
  mkdir -p "$PP_PROJECTS_DIR/pp-test/.claude"
  printf '5\n' > "$PP_PROJECTS_DIR/pp-test/.claude/.iteration"
  run_pp test
  [ "$status" -eq 0 ]
  pp_stub_log_contains 'tmux attach -t pp-test'
  ! pp_stub_log_contains 'tmux new-session'
  [ "$(cat "$PP_PROJECTS_DIR/pp-test/.claude/.iteration")" = "5" ]
}

@test "second launch after kill bumps iter to 02" {
  export PP_STUB_TMUX_SESSION_EXISTS=false
  mkdir -p "$PP_PROJECTS_DIR/pp-test/.claude"
  cp "$PP_REPO_ROOT/template/settings.local.json" "$PP_PROJECTS_DIR/pp-test/.claude/settings.local.json"
  printf '1\n' > "$PP_PROJECTS_DIR/pp-test/.claude/.iteration"
  run_pp test
  [ "$status" -eq 0 ]
  [ "$(cat "$PP_PROJECTS_DIR/pp-test/.claude/.iteration")" = "2" ]
  pp_stub_log_contains 'pp-test-02'
  pp_stub_log_contains '11c2061f-1aaa-5a9f-ac7b-042c7c3790ab'
}

@test "-p plan wires through to claude" {
  export PP_STUB_TMUX_SESSION_EXISTS=false
  run_pp -p plan test
  [ "$status" -eq 0 ]
  pp_stub_log_contains 'claude --permission-mode plan'
}

@test "--permissions=acceptEdits wires through" {
  export PP_STUB_TMUX_SESSION_EXISTS=false
  run_pp --permissions=acceptEdits test
  [ "$status" -eq 0 ]
  pp_stub_log_contains 'claude --permission-mode acceptEdits'
}

@test "positional before flag: test -p plan" {
  export PP_STUB_TMUX_SESSION_EXISTS=false
  run_pp test -p plan
  [ "$status" -eq 0 ]
  pp_stub_log_contains 'claude --permission-mode plan'
}

@test "bare -p with non-TTY: exit 2, no scaffolding" {
  export PP_STUB_TMUX_SESSION_EXISTS=false
  run_pp test -p
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value when stdin is not a tty"* ]]
  [ ! -d "$PP_PROJECTS_DIR/pp-test" ]
  ! pp_stub_log_contains 'tmux'
}

@test "-p bogus: invalid mode, exit 2, no side effects" {
  export PP_STUB_TMUX_SESSION_EXISTS=false
  run_pp -p bogus test
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'bogus'"* ]]
  [ ! -d "$PP_PROJECTS_DIR/pp-test" ]
  ! pp_stub_log_contains 'tmux'
}

@test "invalid slug name rejected" {
  export PP_STUB_TMUX_SESSION_EXISTS=false
  run_pp "'foo bar'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid name"* ]]
  [ ! -d "$PP_PROJECTS_DIR/pp-foo bar" ]
}

@test "missing template: exit 1 with documented message" {
  export PP_STUB_TMUX_SESSION_EXISTS=false
  local fake_home="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$fake_home/bin"
  cp "$PP_REPO_ROOT/bin/pp" "$fake_home/bin/pp"
  chmod +x "$fake_home/bin/pp"
  run bash -c "'$fake_home/bin/pp' test" </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"template missing"* ]]
}
