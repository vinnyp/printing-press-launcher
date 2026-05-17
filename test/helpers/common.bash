#!/usr/bin/env bash
#
# Common bats helpers shared by every test file.
#
# Exported globals expected by stubs in test/helpers/stubs/:
#   PP_STUB_LOG                   Path to per-test log file (argv of each stub call).
#   PP_STUB_TMUX_SESSION_EXISTS   "true" → tmux has-session returns 0, "false" or unset → returns 1.
#

# Repo root (one level up from test/).
PP_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PP_REPO_ROOT

# pp_setup_env: build a clean per-test environment.
#
# Creates:
#   - $BATS_TEST_TMPDIR/proj    (PP_PROJECTS_DIR)
#   - $BATS_TEST_TMPDIR/log     (PP_STUB_LOG, empty)
# Prepends the stubs dir to PATH so `tmux` and `claude` resolve to our shims.
pp_setup_env() {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  : > "$BATS_TEST_TMPDIR/log"
  export PP_PROJECTS_DIR="$BATS_TEST_TMPDIR/proj"
  export PP_STUB_LOG="$BATS_TEST_TMPDIR/log"
  export PATH="$PP_REPO_ROOT/test/helpers/stubs:$PATH"
}

# pp_source: source bin/pp for unit tests so functions become callable.
# The source guard in bin/pp prevents main from running on source.
pp_source() {
  # shellcheck source=/dev/null
  source "$PP_REPO_ROOT/bin/pp"
}

# pp_stub_log_contains <pattern>: succeed if the stub log contains a line matching <pattern>.
pp_stub_log_contains() {
  grep -qE "$1" "$PP_STUB_LOG"
}
