#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  ppl_setup_env
  # Integration tests exec bin/ppl directly; do not source it.
}

# Helper to run bin/ppl with closed stdin so the script never blocks on a TTY-only path.
run_ppl() {
  run bash -c "'$PPL_REPO_ROOT/bin/ppl' $*" </dev/null
}

@test "fresh project, no flag: launches with dontAsk, iter 01" {
  export PPL_STUB_TMUX_SESSION_EXISTS=false
  run_ppl test
  [ "$status" -eq 0 ]
  ppl_stub_log_contains 'tmux new-session -d -s pp-test'
  ppl_stub_log_contains 'tmux send-keys -t pp-test claude --permission-mode dontAsk -n pp-test-01 --session-id c5afa652-6383-5606-ad1a-b2232c25bd8f Enter'
  ppl_stub_log_contains 'tmux attach -t pp-test'
  [ "$(cat "$PPL_PROJECTS_DIR/pp-test/.claude/.iteration")" = "1" ]
}

@test "live attach: no new-session, no iter bump" {
  export PPL_STUB_TMUX_SESSION_EXISTS=true
  mkdir -p "$PPL_PROJECTS_DIR/pp-test/.claude"
  printf '5\n' > "$PPL_PROJECTS_DIR/pp-test/.claude/.iteration"
  run_ppl test
  [ "$status" -eq 0 ]
  ppl_stub_log_contains 'tmux attach -t pp-test'
  ! ppl_stub_log_contains 'tmux new-session'
  [ "$(cat "$PPL_PROJECTS_DIR/pp-test/.claude/.iteration")" = "5" ]
}

@test "second launch after kill bumps iter to 02" {
  export PPL_STUB_TMUX_SESSION_EXISTS=false
  mkdir -p "$PPL_PROJECTS_DIR/pp-test/.claude"
  cp "$PPL_REPO_ROOT/template/settings.local.json" "$PPL_PROJECTS_DIR/pp-test/.claude/settings.local.json"
  printf '1\n' > "$PPL_PROJECTS_DIR/pp-test/.claude/.iteration"
  run_ppl test
  [ "$status" -eq 0 ]
  [ "$(cat "$PPL_PROJECTS_DIR/pp-test/.claude/.iteration")" = "2" ]
  ppl_stub_log_contains 'pp-test-02'
  ppl_stub_log_contains '11c2061f-1aaa-5a9f-ac7b-042c7c3790ab'
}

@test "-p plan wires through to claude" {
  export PPL_STUB_TMUX_SESSION_EXISTS=false
  run_ppl -p plan test
  [ "$status" -eq 0 ]
  ppl_stub_log_contains 'claude --permission-mode plan'
}

@test "--permissions=acceptEdits wires through" {
  export PPL_STUB_TMUX_SESSION_EXISTS=false
  run_ppl --permissions=acceptEdits test
  [ "$status" -eq 0 ]
  ppl_stub_log_contains 'claude --permission-mode acceptEdits'
}

@test "positional before flag: test -p plan" {
  export PPL_STUB_TMUX_SESSION_EXISTS=false
  run_ppl test -p plan
  [ "$status" -eq 0 ]
  ppl_stub_log_contains 'claude --permission-mode plan'
}

@test "bare -p with non-TTY: exit 2, no scaffolding" {
  export PPL_STUB_TMUX_SESSION_EXISTS=false
  run_ppl test -p
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value when stdin is not a tty"* ]]
  [ ! -d "$PPL_PROJECTS_DIR/pp-test" ]
  ! ppl_stub_log_contains 'tmux'
}

@test "-p bogus: invalid mode, exit 2, no side effects" {
  export PPL_STUB_TMUX_SESSION_EXISTS=false
  run_ppl -p bogus test
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'bogus'"* ]]
  [ ! -d "$PPL_PROJECTS_DIR/pp-test" ]
  ! ppl_stub_log_contains 'tmux'
}

@test "invalid slug name rejected" {
  export PPL_STUB_TMUX_SESSION_EXISTS=false
  run_ppl "'foo bar'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid name"* ]]
  [ ! -d "$PPL_PROJECTS_DIR/pp-foo bar" ]
}

@test "missing template: exit 1 with documented message" {
  export PPL_STUB_TMUX_SESSION_EXISTS=false
  local fake_home="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$fake_home/bin"
  cp "$PPL_REPO_ROOT/bin/ppl" "$fake_home/bin/ppl"
  chmod +x "$fake_home/bin/ppl"
  run bash -c "'$fake_home/bin/ppl' test" </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"template missing"* ]]
}
