#!/usr/bin/env bash
#
# Common bats helpers shared by every test file.
#
# Exported globals expected by stubs in test/helpers/stubs/:
#   PPL_STUB_LOG                   Path to per-test log file (argv of each stub call).
#   PPL_STUB_TMUX_SESSION_EXISTS   "true" → tmux has-session returns 0, "false" or unset → returns 1.
#

# Repo root (one level up from test/).
PPL_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PPL_REPO_ROOT

# ppl_setup_env: build a clean per-test environment.
#
# Creates:
#   - $BATS_TEST_TMPDIR/proj    (PPL_PROJECTS_DIR)
#   - $BATS_TEST_TMPDIR/log     (PPL_STUB_LOG, empty)
# Prepends the stubs dir to PATH so `tmux` and `claude` resolve to our shims.
ppl_setup_env() {
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  : > "$BATS_TEST_TMPDIR/log"
  export PPL_PROJECTS_DIR="$BATS_TEST_TMPDIR/proj"
  export PPL_STUB_LOG="$BATS_TEST_TMPDIR/log"
  export PATH="$PPL_REPO_ROOT/test/helpers/stubs:$PATH"
}

# ppl_source: source bin/ppl for unit tests so functions become callable.
# The source guard in bin/ppl prevents main from running on source.
ppl_source() {
  # shellcheck source=/dev/null
  source "$PPL_REPO_ROOT/bin/ppl"
}

# ppl_stub_log_contains <pattern>: succeed if the stub log contains a line matching <pattern>.
ppl_stub_log_contains() {
  grep -qE "$1" "$PPL_STUB_LOG"
}
