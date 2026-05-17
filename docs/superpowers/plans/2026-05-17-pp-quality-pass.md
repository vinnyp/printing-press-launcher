# pp launcher quality pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add LICENSE, ShellCheck linting, a bats-core test suite, a Google-Style-Guide refactor with header comments, a `-p` / `--permissions` flag with a `select` picker, a `Makefile`, and a cross-platform GitHub Actions CI workflow to `bin/pp` without changing any existing observable behavior.

**Architecture:** Single-file `bin/pp` keeps its current install/symlink contract. A `BASH_SOURCE`-vs-`$0` guard at the bottom lets tests `source` the script and unit-test pure helpers; integration tests `exec` the script with stub `tmux`/`claude` on `PATH`. `make check` (= `lint` + `test`) is the single command CI and humans run.

**Tech Stack:** bash (3.2+ compatible), [bats-core](https://github.com/bats-core/bats-core), [ShellCheck](https://www.shellcheck.net/), GNU make, GitHub Actions (`ubuntu-latest` + `macos-latest`).

**Spec:** [`docs/superpowers/specs/2026-05-17-pp-quality-pass-design.md`](../specs/2026-05-17-pp-quality-pass-design.md)

---

## File Structure

| Path | Status | Responsibility |
|---|---|---|
| `LICENSE` | Create | MIT license text. Holder "Vinny Pasceri", year 2026. |
| `bin/pp` | Modify | Refactored launcher: file header, function header blocks, new `validate_permission_mode` / `pick_permission_mode` / `parse_args`, source guard. |
| `Makefile` | Create | `lint`, `test`, `check`, `help` targets. |
| `.github/workflows/ci.yml` | Create | Matrix CI on `ubuntu-latest` + `macos-latest`; installs deps, runs `make check`. |
| `test/helpers/common.bash` | Create | bats `setup`/`teardown` helpers — tmpdir, `PATH` munging, source/exec dispatch. |
| `test/helpers/stubs/tmux` | Create | Logging stub for `tmux`; honors `PP_STUB_TMUX_SESSION_EXISTS`. |
| `test/helpers/stubs/claude` | Create | Logging stub for `claude`. |
| `test/unit_helpers.bats` | Create | Unit cases for `compute_slug`, `validate_slug`, `bump_iteration`, `derive_uuid`, `ensure_scaffolding`. |
| `test/unit_permissions.bats` | Create | Unit cases for `validate_permission_mode` and `parse_args`. |
| `test/integration_launch.bats` | Create | End-to-end cases against the script with stubs on `PATH`. |
| `README.md` | Modify | Permissions section, Development section, CI badge, License section, updated Layout. |
| `template/settings.local.json` | Untouched | — |
| `.gitignore` | Untouched | — |

**Decomposition principle:** unit tests live in dedicated bats files per concern (helpers vs. permissions); integration tests in a third file. Helpers and stubs live under `test/helpers/`. The launcher remains one file because the install path is a symlink to `bin/pp`; splitting would complicate that.

---

## Task ordering rationale

Tasks 1–3 add scaffolding (LICENSE, Makefile, stubs+helpers) that lets every subsequent task be testable. Task 4 adds the source-guard refactor with **no behavior change**, which unlocks unit tests in Tasks 5–6. Task 7 adds the comments per the style guide (pure documentation, no logic change). Task 8 adds the `--permissions` feature behind its own tests. Task 9 wires CI. Task 10 updates README. Task 11 does final cleanup + manual verification.

---

## Task 1: Add MIT LICENSE

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: Create the LICENSE file**

Write `/Users/vinnypasceri/Projects/printing-press-launcher/LICENSE` with this exact content:

```
MIT License

Copyright (c) 2026 Vinny Pasceri

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Commit**

```bash
git add LICENSE
git commit -m "Add MIT license"
```

---

## Task 2: Add Makefile

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create the Makefile**

Write `/Users/vinnypasceri/Projects/printing-press-launcher/Makefile`. Recipe bodies must be indented with a single TAB (not spaces) — Make requires this:

```make
.PHONY: lint test check help

SHELL := /bin/bash

help:  ## Show this help.
	@awk -F':.*##' '/^[a-z][a-zA-Z_-]*:.*##/ {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

lint:  ## Run ShellCheck on bin/pp and test helpers.
	shellcheck --shell=bash --severity=style bin/pp test/helpers/common.bash test/helpers/stubs/*

test:  ## Run the bats-core test suite.
	bats test

check: lint test  ## Run lint + tests (what CI runs).
```

- [ ] **Step 2: Verify `make help` works**

Run: `make help`
Expected output (formatting may vary slightly with awk versions):
```
  help       Show this help.
  lint       Run ShellCheck on bin/pp and test helpers.
  test       Run the bats-core test suite.
  check      Run lint + tests (what CI runs).
```

(`make lint` and `make test` will fail right now — they need the stubs/tests created in subsequent tasks. That's expected.)

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "Add Makefile with lint/test/check/help"
```

---

## Task 3: Add test helpers and stubs

**Files:**
- Create: `test/helpers/common.bash`
- Create: `test/helpers/stubs/tmux`
- Create: `test/helpers/stubs/claude`

- [ ] **Step 1: Create `test/helpers/common.bash`**

Write `/Users/vinnypasceri/Projects/printing-press-launcher/test/helpers/common.bash`:

```bash
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
```

- [ ] **Step 2: Create the tmux stub**

Write `/Users/vinnypasceri/Projects/printing-press-launcher/test/helpers/stubs/tmux`:

```bash
#!/usr/bin/env bash
#
# tmux stub for tests. Logs argv to $PP_STUB_LOG. Returns exit codes that
# make the launcher's branches deterministic.
#

printf 'tmux %s\n' "$*" >> "${PP_STUB_LOG:-/dev/null}"

case "${1:-}" in
  has-session)
    if [[ "${PP_STUB_TMUX_SESSION_EXISTS:-false}" == "true" ]]; then
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
```

Then make it executable:

```bash
chmod +x test/helpers/stubs/tmux
```

- [ ] **Step 3: Create the claude stub**

Write `/Users/vinnypasceri/Projects/printing-press-launcher/test/helpers/stubs/claude`:

```bash
#!/usr/bin/env bash
#
# claude stub for tests. Logs argv to $PP_STUB_LOG. Always succeeds.
#

printf 'claude %s\n' "$*" >> "${PP_STUB_LOG:-/dev/null}"
exit 0
```

Then:

```bash
chmod +x test/helpers/stubs/claude
```

- [ ] **Step 4: Sanity-check the stubs**

Run:

```bash
PP_STUB_LOG=/tmp/pp-stub-sanity.log test/helpers/stubs/tmux new-session -d -s foo
PP_STUB_TMUX_SESSION_EXISTS=true test/helpers/stubs/tmux has-session -t foo && echo OK1
PP_STUB_TMUX_SESSION_EXISTS=false test/helpers/stubs/tmux has-session -t foo || echo OK2
cat /tmp/pp-stub-sanity.log
rm /tmp/pp-stub-sanity.log
```

Expected: prints `OK1` and `OK2`; the log file contains three `tmux ...` lines.

- [ ] **Step 5: Commit**

```bash
git add test/helpers/
git commit -m "Add bats test helpers and tmux/claude stubs"
```

---

## Task 4: Add source guard to bin/pp (no behavior change)

**Files:**
- Modify: `bin/pp` (replace the bare `main "$@"` at the end)

- [ ] **Step 1: Replace the trailing `main "$@"` line**

In `/Users/vinnypasceri/Projects/printing-press-launcher/bin/pp`, replace the final line:

```bash
main "$@"
```

with:

```bash
# Source guard: when this script is sourced from tests, BASH_SOURCE[0] != $0,
# so we skip running main and let the test file call functions directly.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

- [ ] **Step 2: Verify the script still runs end-to-end as before**

Run a manual sanity check that doesn't actually launch a session:

```bash
bin/pp 2>&1 || echo "exit: $?"
```

Expected: prints `usage: pp <name>` and `exit: 2` (existing behavior, unchanged).

- [ ] **Step 3: Verify sourcing does not run main**

Run:

```bash
bash -c 'source bin/pp; echo "sourced OK, functions defined: $(declare -F | grep -c "declare -f")"'
```

Expected: prints `sourced OK, functions defined: <some-positive-number>` and does NOT print the `usage:` message.

- [ ] **Step 4: Commit**

```bash
git add bin/pp
git commit -m "bin/pp: add source guard for tests (no behavior change)"
```

---

## Task 5: Add unit tests for existing helpers

**Files:**
- Create: `test/unit_helpers.bats`

The Python UUIDv5 of `pp:pp-parcel-01` (NAMESPACE_URL) is deterministic. To get the pinned value used below, run:

```bash
python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "pp:pp-parcel-01"))'
```

For this plan we use **`<UUID-PP-PARCEL-01>`** as a placeholder you must replace with the output of that command before committing. Same for **`<UUID-PP-PARCEL-09>`** for the 9→10 bump assertion test (run with `pp:pp-parcel-09` if you want a second pin).

> Engineer note: write the placeholder out, run the command, paste the actual UUID into the test, and verify the test passes before committing. There is exactly one correct value per session name.

- [ ] **Step 1: Compute the pinned UUIDs**

Run:

```bash
python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "pp:pp-parcel-01"))'
```

Record the output. You'll paste it into the test below in place of `<UUID-PP-PARCEL-01>`.

- [ ] **Step 2: Write the unit test file**

Write `/Users/vinnypasceri/Projects/printing-press-launcher/test/unit_helpers.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  pp_setup_env
  pp_source
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
  [ "$output" = "<UUID-PP-PARCEL-01>" ]
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
```

- [ ] **Step 3: Replace `<UUID-PP-PARCEL-01>` with the real UUID**

Edit the file and paste the UUID you recorded in Step 1.

- [ ] **Step 4: Run the unit tests**

Install bats first if needed (`brew install bats-core` on macOS).

Run: `bats test/unit_helpers.bats`

Expected: all 10 tests pass. If `derive_uuid` fails with a mismatch, re-run Step 1 and paste the correct value.

- [ ] **Step 5: Commit**

```bash
git add test/unit_helpers.bats
git commit -m "Add unit tests for pp helper functions"
```

---

## Task 6: Add `validate_permission_mode` function and unit tests

**Files:**
- Modify: `bin/pp` (add the function and its header)
- Create: `test/unit_permissions.bats` (just the `validate_permission_mode` cases for now)

- [ ] **Step 1: Add the function to `bin/pp`**

In `/Users/vinnypasceri/Projects/printing-press-launcher/bin/pp`, add this function above `main` (above the existing `derive_uuid` is fine; group new functions together):

```bash
#######################################
# Accept-or-die for a permission mode string.
# Globals:
#   None
# Arguments:
#   $1 - mode string to validate
# Outputs:
#   On invalid mode, writes the documented error to stderr via die.
# Returns:
#   0 if valid; otherwise calls die (exit 2).
#######################################
validate_permission_mode() {
  local mode="$1"
  case "$mode" in
    default|acceptEdits|plan|auto|dontAsk) return 0 ;;
    *) die "invalid permission mode '$mode' (valid: default, acceptEdits, plan, auto, dontAsk)" ;;
  esac
}
```

Note: `die` currently does `exit 1`. The spec says invalid mode → exit 2. Update `die` to accept an optional exit code, OR add a dedicated `die2` helper, OR change `die` to always exit 2. Cleanest: extend `die` to take an optional exit code.

Replace the existing `die()` function:

```bash
die()   { printf 'pp: %s\n' "$*" >&2; exit 1; }
```

with:

```bash
#######################################
# Print an error to stderr and exit.
# Globals:
#   None
# Arguments:
#   $1 - message
#   $2 - optional exit code (default: 1)
# Outputs:
#   Writes "pp: <message>" to stderr.
# Returns:
#   Exits with the given code (does not return).
#######################################
die() {
  local msg="$1"
  local code="${2:-1}"
  printf 'pp: %s\n' "$msg" >&2
  exit "$code"
}
```

Then update `validate_permission_mode`'s die call to pass exit code 2:

```bash
*) die "invalid permission mode '$mode' (valid: default, acceptEdits, plan, auto, dontAsk)" 2 ;;
```

- [ ] **Step 2: Write the test file**

Write `/Users/vinnypasceri/Projects/printing-press-launcher/test/unit_permissions.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  pp_setup_env
  pp_source
}

@test "validate_permission_mode accepts default" {
  run validate_permission_mode default
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode accepts acceptEdits" {
  run validate_permission_mode acceptEdits
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode accepts plan" {
  run validate_permission_mode plan
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode accepts auto" {
  run validate_permission_mode auto
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode accepts dontAsk" {
  run validate_permission_mode dontAsk
  [ "$status" -eq 0 ]
}

@test "validate_permission_mode rejects wrong case" {
  run validate_permission_mode Plan
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'Plan'"* ]]
}

@test "validate_permission_mode rejects unknown mode" {
  run validate_permission_mode yolo
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'yolo'"* ]]
}

@test "validate_permission_mode rejects empty string" {
  run validate_permission_mode ""
  [ "$status" -eq 2 ]
}

@test "die uses exit code 1 by default" {
  run die "test message"
  [ "$status" -eq 1 ]
  [[ "$output" == "pp: test message" ]]
}

@test "die accepts custom exit code" {
  run die "test message" 2
  [ "$status" -eq 2 ]
}
```

- [ ] **Step 3: Run the tests**

Run: `bats test/unit_permissions.bats`

Expected: all 10 tests pass.

- [ ] **Step 4: Run the full suite to confirm no regressions**

Run: `bats test`

Expected: all tests from `unit_helpers.bats` and `unit_permissions.bats` pass.

- [ ] **Step 5: Commit**

```bash
git add bin/pp test/unit_permissions.bats
git commit -m "Add validate_permission_mode and extend die with exit code"
```

---

## Task 7: Add `parse_args` function and unit tests

**Files:**
- Modify: `bin/pp` (add `parse_args`, refactor `main` to use it, add globals)
- Modify: `test/unit_permissions.bats` (add `parse_args` cases)

- [ ] **Step 1: Add globals for parsed args at the top of `bin/pp`**

In `/Users/vinnypasceri/Projects/printing-press-launcher/bin/pp`, after the existing globals (`SCRIPT_DIR`, `PP_HOME`, `TEMPLATE`, `PROJECTS_DIR`), add:

```bash
# Populated by parse_args; consumed by main.
g_name=""
g_perm_mode=""
```

- [ ] **Step 2: Add `parse_args` function**

Add this function to `bin/pp` (above `main`):

```bash
#######################################
# Parse command-line arguments. Populates globals g_name and g_perm_mode.
# Strict rule: -p / --permissions always consumes the next argv element as
# the mode value when one is present. The select picker is invoked by passing
# the flag as the LAST argv element (no following arg).
# Globals:
#   g_name       Written: the prefixed slug (e.g. "pp-parcel").
#   g_perm_mode  Written: the resolved permission mode.
# Arguments:
#   $@ - original argv
# Outputs:
#   On error, writes usage or error message to stderr via die/usage.
# Returns:
#   0 on success. On error: usage() -> exit 2 or die ... 2.
#######################################
parse_args() {
  local mode="dontAsk"
  local positional=""
  local saw_double_dash=0

  while [[ $# -gt 0 ]]; do
    if [[ $saw_double_dash -eq 1 ]]; then
      [[ -z "$positional" ]] || die "too many positional arguments" 2
      positional="$1"
      shift
      continue
    fi
    case "$1" in
      --)
        saw_double_dash=1
        shift
        ;;
      --permissions=*)
        mode="${1#--permissions=}"
        validate_permission_mode "$mode"
        shift
        ;;
      -p|--permissions)
        if [[ $# -ge 2 ]]; then
          mode="$2"
          validate_permission_mode "$mode"
          shift 2
        else
          # Bare flag at end of argv → picker (if TTY).
          if [[ -t 0 ]]; then
            mode="$(pick_permission_mode)"
          else
            die "--permissions requires a value when stdin is not a tty" 2
          fi
          shift
        fi
        ;;
      -*)
        usage
        ;;
      *)
        [[ -z "$positional" ]] || die "too many positional arguments" 2
        positional="$1"
        shift
        ;;
    esac
  done

  [[ -n "$positional" ]] || usage

  g_name="$(compute_slug "$positional")"
  validate_slug "$g_name"
  g_perm_mode="$mode"
}
```

- [ ] **Step 3: Add a stub `pick_permission_mode` function**

Add this above `parse_args` (the real implementation lands in Task 8 — this stub is enough to make non-TTY parse_args tests pass and to keep the script ShellCheck-clean):

```bash
#######################################
# Interactive `select` picker for permission mode.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes the picker menu to stderr; echoes the chosen mode to stdout.
# Returns:
#   0 on selection. Caller is responsible for ensuring stdin is a TTY.
#######################################
pick_permission_mode() {
  local mode
  PS3='Select permission mode: '
  select mode in default acceptEdits plan auto dontAsk; do
    [[ -n "$mode" ]] && break
  done
  printf '%s' "$mode"
}
```

- [ ] **Step 4: Refactor `main` to call `parse_args`**

Replace the existing `main()`:

```bash
main() {
    [[ $# -eq 1 ]] || usage
    preflight
    local slug; slug="$(compute_slug "$1")"
    validate_slug "$slug"
    local target="$PROJECTS_DIR/$slug"

    if tmux_session_alive "$slug"; then
        exec tmux attach -t "$slug"
    fi

    ensure_scaffolding "$target"
    local iter; iter="$(bump_iteration "$target")"
    local session_name; session_name="$(printf '%s-%02d' "$slug" "$iter")"
    local session_uuid; session_uuid="$(derive_uuid "$session_name")"

    cd "$target"
    tmux new-session -d -s "$slug" -c "$target"
    tmux send-keys -t "$slug" \
        "claude --permission-mode dontAsk -n $session_name --session-id $session_uuid" Enter
    exec tmux attach -t "$slug"
}
```

with:

```bash
#######################################
# Orchestrator: parse args, preflight, attach-or-launch.
# Globals:
#   g_name, g_perm_mode  Read after parse_args populates them.
#   PROJECTS_DIR         Read.
# Arguments:
#   $@ - original argv (passed through to parse_args)
# Outputs:
#   On success, exec's tmux attach.
# Returns:
#   Does not return on success (exec). On error, exits non-zero via die/usage.
#######################################
main() {
  parse_args "$@"
  preflight
  local target="$PROJECTS_DIR/$g_name"

  if tmux_session_alive "$g_name"; then
    exec tmux attach -t "$g_name"
  fi

  ensure_scaffolding "$target"
  local iter
  iter="$(bump_iteration "$target")"
  local session_name
  session_name="$(printf '%s-%02d' "$g_name" "$iter")"
  local session_uuid
  session_uuid="$(derive_uuid "$session_name")"

  cd "$target"
  tmux new-session -d -s "$g_name" -c "$target"
  tmux send-keys -t "$g_name" \
    "claude --permission-mode $g_perm_mode -n $session_name --session-id $session_uuid" Enter
  exec tmux attach -t "$g_name"
}
```

- [ ] **Step 5: Append `parse_args` cases to `test/unit_permissions.bats`**

Append the following cases at the end of `/Users/vinnypasceri/Projects/printing-press-launcher/test/unit_permissions.bats`:

```bash
@test "parse_args: positional only -> dontAsk default" {
  parse_args parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "dontAsk" ]
}

@test "parse_args: -p plan parcel" {
  parse_args -p plan parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "plan" ]
}

@test "parse_args: parcel -p plan (positional first)" {
  parse_args parcel -p plan
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "plan" ]
}

@test "parse_args: --permissions=acceptEdits parcel" {
  parse_args --permissions=acceptEdits parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "acceptEdits" ]
}

@test "parse_args: --permissions auto parcel" {
  parse_args --permissions auto parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "auto" ]
}

@test "parse_args: -p parcel (parcel consumed as mode, invalid) -> exit 2" {
  run parse_args -p parcel
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'parcel'"* ]]
}

@test "parse_args: -p plan with no positional -> exit 2" {
  run parse_args -p plan
  [ "$status" -eq 2 ]
}

@test "parse_args: -p bogus parcel -> invalid-mode exit 2" {
  run parse_args -p bogus parcel
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid permission mode 'bogus'"* ]]
}

@test "parse_args: no positional -> usage exit 2" {
  run parse_args
  [ "$status" -eq 2 ]
}

@test "parse_args: unknown flag -> usage exit 2" {
  run parse_args --bogus parcel
  [ "$status" -eq 2 ]
}

@test "parse_args: slug named 'plan' works without flag" {
  parse_args plan
  [ "$g_name" = "pp-plan" ]
  [ "$g_perm_mode" = "dontAsk" ]
}

@test "parse_args: last -p flag wins" {
  parse_args -p plan -p auto parcel
  [ "$g_name" = "pp-parcel" ]
  [ "$g_perm_mode" = "auto" ]
}

@test "parse_args: parcel -p with non-TTY stdin -> exit 2" {
  run bash -c 'source "'"$PP_REPO_ROOT"'/bin/pp"; parse_args parcel -p' </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--permissions requires a value when stdin is not a tty"* ]]
}

@test "parse_args: bare -p with non-TTY stdin -> exit 2" {
  run bash -c 'source "'"$PP_REPO_ROOT"'/bin/pp"; parse_args -p' </dev/null
  [ "$status" -eq 2 ]
}
```

> Engineer note: the last two cases use `bash -c` + `</dev/null` because `bats`'s `run` doesn't reliably make stdin a non-TTY in the test process itself; spawning a subprocess with stdin redirected from `/dev/null` does. Both invocations also have no positional → either error firing first is acceptable, but as written the TTY check fires before the missing-positional check for the bare-`-p` case in argv-position-0; both exit with code 2.

- [ ] **Step 6: Run the suite**

Run: `bats test`

Expected: all unit tests pass (helpers + permissions). If a `parse_args` case errors with an unhandled `set -u` reference (e.g., `g_name` unset), ensure the globals at the top of `bin/pp` initialize them to empty strings as in Step 1.

- [ ] **Step 7: Commit**

```bash
git add bin/pp test/unit_permissions.bats
git commit -m "Add parse_args with strict -p resolution and unit tests"
```

---

## Task 8: Add integration tests

**Files:**
- Create: `test/integration_launch.bats`

Pin the UUIDs needed by integration tests up front:

```bash
python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "pp:pp-test-01"))'
python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "pp:pp-test-02"))'
```

Use these in the test as **`<UUID-PP-TEST-01>`** and **`<UUID-PP-TEST-02>`** — replace before committing.

- [ ] **Step 1: Compute the pinned UUIDs**

Run both `python3` commands above and record the outputs.

- [ ] **Step 2: Write the integration test file**

Write `/Users/vinnypasceri/Projects/printing-press-launcher/test/integration_launch.bats`:

```bash
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
  pp_stub_log_contains 'tmux send-keys -t pp-test claude --permission-mode dontAsk -n pp-test-01 --session-id <UUID-PP-TEST-01> Enter'
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
  pp_stub_log_contains '<UUID-PP-TEST-02>'
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
  # Point PP_HOME at a tmpdir without template/ by symlinking a fake repo.
  local fake_home="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$fake_home/bin"
  ln -sf "$PP_REPO_ROOT/bin/pp" "$fake_home/bin/pp"
  run bash -c "'$fake_home/bin/pp' test" </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"template missing"* ]]
}
```

- [ ] **Step 3: Replace the UUID placeholders**

Edit the file and paste the UUIDs you recorded in Step 1 in place of `<UUID-PP-TEST-01>` and `<UUID-PP-TEST-02>`.

- [ ] **Step 4: Run the integration tests**

Run: `bats test/integration_launch.bats`

Expected: all 10 tests pass.

Troubleshooting:
- If the order or quoting of `tmux send-keys` args differs from your assertion, copy the actual log line out (`cat "$PP_STUB_LOG"` from within a `@test`) and adjust the `grep -E` pattern. The strict assertion in test 1 includes the literal `Enter` keyword from the `send-keys` call.
- If the missing-template test does not fire as expected, double-check that `PP_HOME` is being resolved from `bin/pp`'s own `readlink -f` chain rather than an env var. The symlink trick in the test points `bin/pp` at a sibling `bin/` whose parent has no `template/`.

- [ ] **Step 5: Run the full suite**

Run: `bats test`

Expected: every unit + integration test green.

- [ ] **Step 6: Commit**

```bash
git add test/integration_launch.bats
git commit -m "Add integration tests for pp launcher"
```

---

## Task 9: Add Google-style header comments to remaining functions

**Files:**
- Modify: `bin/pp` (add file-level header and per-function header blocks for the unchanged helpers)

The new functions added in earlier tasks already have header blocks. This task adds the file header and headers for the pre-existing helpers (`usage`, `preflight`, `compute_slug`, `validate_slug`, `tmux_session_alive`, `ensure_scaffolding`, `bump_iteration`, `derive_uuid`).

- [ ] **Step 1: Add the file header**

In `/Users/vinnypasceri/Projects/printing-press-launcher/bin/pp`, replace the existing comment at the top:

```bash
# Resolve this script's own dir so we can find the template no matter how `pp` is invoked.
```

with:

```bash
#
# pp — bootstrap and resume Claude Code projects for the cli-printing-press
# workflow. See README.md and docs/superpowers/specs/ for full design.
#
# Globals:
#   PP_PROJECTS_DIR  Where projects live (default: $HOME/Projects).
#   PP_HOME          Resolved repo root, used to find template/.
#

# Resolve this script's own dir so we can find the template no matter how `pp` is invoked.
```

(Keep the existing one-line `# Resolve ...` comment — it explains *why* `readlink -f` is used, which is non-obvious.)

- [ ] **Step 2: Add header for `usage`**

Replace:

```bash
usage() { printf 'usage: pp <name>\n' >&2; exit 2; }
```

with:

```bash
#######################################
# Print usage to stderr and exit 2.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   "usage: pp [-p MODE | --permissions[=MODE] | -p] <name>" to stderr.
# Returns:
#   Exits 2 (does not return).
#######################################
usage() { printf 'usage: pp [-p MODE | --permissions[=MODE] | -p] <name>\n' >&2; exit 2; }
```

- [ ] **Step 3: Add header for `preflight`**

Above the existing `preflight()` function:

```bash
#######################################
# Verify required commands and paths are available before any side effects.
# Globals:
#   PROJECTS_DIR, TEMPLATE  Read.
# Arguments:
#   None
# Outputs:
#   On failure, writes a one-line reason to stderr via die.
# Returns:
#   0 on success; calls die on failure.
#######################################
```

- [ ] **Step 4: Add header for `compute_slug`**

```bash
#######################################
# Add the "pp-" prefix to a name if not already present.
# Globals:
#   None
# Arguments:
#   $1 - candidate name
# Outputs:
#   Echoes the prefixed slug to stdout.
# Returns:
#   0 always.
#######################################
```

- [ ] **Step 5: Add header for `validate_slug`**

```bash
#######################################
# Reject anything outside ^[a-z0-9-]+$.
# Globals:
#   None
# Arguments:
#   $1 - slug to validate
# Outputs:
#   On failure, writes the invalid-name error to stderr via die.
# Returns:
#   0 on success; calls die on failure (exit 1).
#######################################
```

- [ ] **Step 6: Add header for `tmux_session_alive`**

```bash
#######################################
# True iff a tmux session with the given name exists.
# Globals:
#   None
# Arguments:
#   $1 - tmux session name
# Outputs:
#   None
# Returns:
#   0 if alive, non-zero otherwise.
#######################################
```

- [ ] **Step 7: Add header for `ensure_scaffolding`**

```bash
#######################################
# Idempotently create the per-project .claude/ layout: dir, template copy,
# .iteration counter seeded to 0. Never overwrites existing files.
# Globals:
#   TEMPLATE  Read.
# Arguments:
#   $1 - target project directory (will be created if missing)
# Outputs:
#   None on success.
# Returns:
#   0 on success.
#######################################
```

- [ ] **Step 8: Add header for `bump_iteration`**

```bash
#######################################
# Read the integer from .iteration, increment, write back, echo new value.
# Globals:
#   None
# Arguments:
#   $1 - target project directory (must contain .claude/.iteration)
# Outputs:
#   Echoes the new iteration value to stdout.
# Returns:
#   0 on success; calls die if .iteration is not an integer.
#######################################
```

- [ ] **Step 9: Add header for `derive_uuid`**

```bash
#######################################
# Derive a UUIDv5 from a session name. UUIDv5 (vs. v4) so the same iteration
# always yields the same Claude --session-id, enabling true session resume.
# Globals:
#   None
# Arguments:
#   $1 - session name (e.g. "pp-parcel-01")
# Outputs:
#   Echoes the UUID to stdout.
# Returns:
#   0 on success.
#######################################
```

- [ ] **Step 10: Run the full test suite to confirm no regressions**

Run: `bats test`

Expected: all tests green. Comments only — no logic changed.

- [ ] **Step 11: Commit**

```bash
git add bin/pp
git commit -m "Add Google-style header comments to all pp functions"
```

---

## Task 10: Install ShellCheck and pass `make lint`

**Files:**
- Modify: `bin/pp` (any fixes needed to reach zero findings)
- Modify: `test/helpers/common.bash` (likewise)
- Modify: `test/helpers/stubs/{tmux,claude}` (likewise)

- [ ] **Step 1: Install ShellCheck if needed**

```bash
brew install shellcheck      # macOS
# or: sudo apt-get install -y shellcheck   # Linux
```

- [ ] **Step 2: Run `make lint`**

```bash
make lint
```

- [ ] **Step 3: Fix any findings**

Common findings to expect and how to address:
- **SC2155** ("Declare and assign separately"): split `local foo="$(cmd)"` into `local foo; foo="$(cmd)"`.
- **SC2086** ("Double-quote to prevent globbing"): add `"..."` around variables used in commands.
- **SC1091** ("Not following sourced file"): add `# shellcheck source=/dev/null` above the `source` line in helpers.
- **SC2154** ("var is referenced but not assigned"): for `BATS_TEST_TMPDIR` in helpers, add `# shellcheck disable=SC2154` with a comment explaining bats provides it.

Fix each finding rather than blanket-disabling. If a disable is genuinely warranted, inline `# shellcheck disable=SCxxxx # reason: ...`.

- [ ] **Step 4: Re-run until zero findings**

Run: `make lint`
Expected: exit 0, no output (or only the `shellcheck ...` echo from `make`).

- [ ] **Step 5: Run the full check**

Run: `make check`
Expected: lint passes, all bats tests pass.

- [ ] **Step 6: Commit**

```bash
git add bin/pp test/
git commit -m "Pass ShellCheck on bin/pp and test helpers"
```

---

## Task 11: Add GitHub Actions CI

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflow directory**

Run: `mkdir -p .github/workflows`

- [ ] **Step 2: Write the workflow file**

Write `/Users/vinnypasceri/Projects/printing-press-launcher/.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: ['**']
  pull_request:
    branches: ['**']

jobs:
  check:
    name: lint + test (${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies (Linux)
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck bats

      - name: Install dependencies (macOS)
        if: runner.os == 'macOS'
        run: |
          brew install shellcheck bats-core coreutils
          echo "$(brew --prefix coreutils)/libexec/gnubin" >> "$GITHUB_PATH"

      - name: Run make check
        run: make check
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "Add GitHub Actions CI on ubuntu-latest and macos-latest"
```

- [ ] **Step 4: Push and verify CI runs green**

After pushing this branch to GitHub:
```bash
git push -u origin <branch-name>
```
Open the PR (or push to main if that's the workflow) and confirm both `check (ubuntu-latest)` and `check (macos-latest)` jobs pass. If either fails, fix the underlying issue (most likely a path or dep issue on macOS — e.g., `readlink -f` failing because `gnubin` wasn't added to PATH before `make check` ran).

---

## Task 12: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a CI badge near the top**

In `/Users/vinnypasceri/Projects/printing-press-launcher/README.md`, immediately after the `# pp-setup` heading, add a blank line and:

```markdown
![CI](https://github.com/<your-github-username>/<repo-name>/actions/workflows/ci.yml/badge.svg)
```

Replace `<your-github-username>` and `<repo-name>` with the actual values. (If the repo isn't on GitHub yet, omit this badge — return to it after the first push.)

- [ ] **Step 2: Add a Permissions section under Configuration**

After the existing `## Configuration` section's content, add:

```markdown
## Permissions

By default, `pp` launches Claude with `--permission-mode dontAsk`. Override per-invocation with `-p` / `--permissions`:

```bash
pp parcel -p plan                    # plan mode
pp parcel --permissions=acceptEdits  # accept-edits mode
pp parcel -p auto                    # auto mode
pp parcel -p                         # interactive picker (TTY only)
```

Valid modes: `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`.

The flag follows a strict rule: `-p` always consumes the next argument as the mode value when one is present. To launch the picker, put `-p` as the last argument (`pp parcel -p`). On non-TTY stdin, the picker is unavailable and bare `-p` errors out.

If your project name collides with a mode (`plan`, `default`, `auto`):
- `pp plan` works directly with the `dontAsk` default.
- `pp plan -p` launches the picker for the project named `plan`.
- `pp -p dontAsk plan` is an explicit form.
```

- [ ] **Step 3: Add a Development section**

After the Permissions section, add:

```markdown
## Development

```bash
make help    # list targets
make lint    # shellcheck
make test    # bats
make check   # both (what CI runs)
```

Prerequisites (dev only): `shellcheck`, `bats-core`. On macOS: `brew install shellcheck bats-core coreutils`. On Debian/Ubuntu: `sudo apt-get install -y shellcheck bats`.

CI runs `make check` on both `ubuntu-latest` and `macos-latest` on every push and pull request.
```

- [ ] **Step 4: Update the Layout block**

Replace the existing `## Layout` content:

```markdown
## Layout

```
pp-setup/
├── bin/pp                          # the launcher
├── template/settings.local.json    # canonical Claude permissions
├── docs/superpowers/
│   ├── specs/                      # design docs
│   └── plans/                      # implementation plans
└── README.md
```
```

with:

```markdown
## Layout

```
pp-setup/
├── bin/pp                          # the launcher
├── template/settings.local.json    # canonical Claude permissions
├── test/                           # bats-core suite + stubs
├── Makefile                        # lint / test / check targets
├── .github/workflows/ci.yml        # CI on Linux + macOS
├── docs/superpowers/
│   ├── specs/                      # design docs
│   └── plans/                      # implementation plans
├── LICENSE                         # MIT
└── README.md
```
```

- [ ] **Step 5: Add a License section at the very bottom**

Append to the file:

```markdown
## License

[MIT](LICENSE) © Vinny Pasceri.
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "README: document permissions flag, development workflow, license"
```

---

## Task 13: Manual end-to-end verification

This is the validation procedure from the spec, run against a throwaway slug after CI is green.

- [ ] **Step 1: Confirm CI is green**

Visit the PR (or branch) on GitHub. Both `check (ubuntu-latest)` and `check (macos-latest)` must be green before manual verification.

- [ ] **Step 2: Run the manual procedure**

In a real terminal (TTY required for the picker):

```bash
# 1. Fresh launch
pp test123
#   → tmux session pp-test123 attached, Claude running with -n pp-test123-01 and --permission-mode dontAsk.

# 2. Detach (prefix + d), then re-run with -p plan
pp -p plan test123
#   → reattaches existing session, no relaunch, no error.

# 3. Kill the session and re-launch with -p plan
tmux kill-session -t pp-test123
pp -p plan test123
#   → iter 02, send-keys payload contains --permission-mode plan.

# 4. Bare -p (picker)
tmux kill-session -t pp-test123
pp test123 -p
#   → picker appears; pick acceptEdits; iter 03 launches with that mode.

# 5. Non-TTY bare -p
pp test123 -p </dev/null
#   → exit 2, no iter bump.

# 6. Invalid mode
pp -p bogus test123
#   → exit 2 with invalid-mode message, no iter bump.

# 7. Clean up
tmux kill-session -t pp-test123 2>/dev/null || true
rm -rf "$HOME/Projects/pp-test123"
```

- [ ] **Step 3: If anything in Step 2 misbehaves**

Open an issue or amend tests to capture the failure mode and fix. Manual verification is the final acceptance gate — no skipping.

- [ ] **Step 4: Final commit (if anything was fixed)**

If Step 2 turned up a real bug:
```bash
git add <files>
git commit -m "<descriptive message>"
```

Otherwise this task is complete with no commit.

---

## Done criteria

- `LICENSE` exists in repo root.
- `make check` passes locally and in CI on both `ubuntu-latest` and `macos-latest`.
- `bin/pp` has a file header and a Google-format header above every function; no drive-by `# what this line does` comments.
- `pp <name>` with no flag is byte-for-byte identical to pre-change behavior.
- `pp -p <mode> <name>` (in any flag/positional order) launches Claude with the chosen `--permission-mode`.
- `pp <name> -p` launches the interactive picker on a TTY; errors on non-TTY.
- Invalid mode values and unknown flags exit 2 with the documented messages and no side effects.
- README documents the flag, the picker rule, the slug/mode collision behavior, the development workflow, the license, and links to CI.
