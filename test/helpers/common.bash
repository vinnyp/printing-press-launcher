#!/usr/bin/env bash
#
# Common bats helpers shared by every test file.
#
# Exported globals expected by stubs in test/helpers/stubs/:
#   SB_STUB_LOG                  Path to per-test log file (argv of each stub call).
#   SB_STUB_TMUX_SESSION_EXISTS  "true" -> tmux has-session returns 0, else returns 1.
#

SB_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SB_REPO_ROOT

# sb_setup_env: build a clean per-test environment.
sb_setup_env() {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  : > "$BATS_TEST_TMPDIR/log"
  export SB_PROJECTS_DIR="$BATS_TEST_TMPDIR/proj"
  export SB_STUB_LOG="$BATS_TEST_TMPDIR/log"
  export PATH="$SB_REPO_ROOT/test/helpers/stubs:$PATH"
}

# sb_source: source bin/sb so functions become callable. The source guard in
# bin/sb prevents main from running on source.
sb_source() {
  # shellcheck source=/dev/null
  source "$SB_REPO_ROOT/bin/sb"
}

# sb_stub_log_contains <pattern>: succeed if the stub log has a matching line.
sb_stub_log_contains() {
  grep -qE "$1" "$SB_STUB_LOG"
}
