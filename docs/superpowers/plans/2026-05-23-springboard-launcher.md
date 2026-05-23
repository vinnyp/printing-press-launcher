# springboard Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the printing-press-specific `ppl` launcher into `sb` ("springboard"), a generic per-project launcher that pairs a tmux session with an AI-agent session resumed by default, supporting `--agent` (claude default, gemini wired) and `--fresh`.

**Architecture:** A single bash script `bin/sb`, sourced by bats tests via a source guard so each function is unit-testable. Agents are a one-`case`-statement table. No `.iteration` counter, no `pp-` prefix, no `--permission-mode` flag — permissions live in a permissions-only `template/settings.local.json`. Session id is `uuid5("sb:"+name)` (stable, resumed by default) or `uuid4()` (`--fresh`).

**Tech Stack:** bash (must stay bash-3.2-safe for macOS — no associative arrays), python3 (UUID derivation), tmux, bats-core + shellcheck (CI on ubuntu + macos via `make check`).

**Branch:** `springboard-launcher` (already created; spec committed there).

---

## File structure

| File | Responsibility | Action |
|---|---|---|
| `bin/sb` | The launcher (renamed from `bin/ppl`, rewritten) | git mv + rewrite |
| `template/settings.local.json` | Per-project template — permissions only | Modify |
| `test/helpers/common.bash` | bats helpers + env setup (`SB_*`) | Rewrite |
| `test/helpers/stubs/tmux` | tmux stub, logs argv | Modify (env var rename) |
| `test/helpers/stubs/claude` | claude stub for `command -v` | Modify (env var rename) |
| `test/helpers/stubs/gemini` | gemini stub for `command -v` | Create |
| `test/unit_helpers.bats` | Unit tests: die, validate_name, agent_binary, derive_uuid, fresh_uuid, ensure_scaffolding, preflight | Rewrite |
| `test/unit_args.bats` | Unit tests: parse_args | Create |
| `test/unit_permissions.bats` | (permission-mode tests — obsolete) | Delete |
| `test/integration_launch.bats` | End-to-end launch/attach/resume tests | Rewrite |
| `Makefile` | lint path `bin/ppl`→`bin/sb` | Modify |
| `README.md` | User docs for springboard/sb | Rewrite |
| `.github/workflows/ci.yml` | No change needed (only runs `make check`) | — |

**Final shape of `bin/sb`** (built up across Tasks 1–8; shown here for reference):

```bash
#!/usr/bin/env bash
set -euo pipefail

#
# sb — springboard: bootstrap and resume project workspaces. Pairs a tmux
# session with an AI-agent session under one stable per-project name.
# See README.md and docs/superpowers/specs/ for the full design.
#
# Globals:
#   SB_PROJECTS_DIR  Where projects live (default: $HOME/Projects).
#   SB_HOME          Resolved repo root, used to find template/.
#

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SB_HOME="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$SB_HOME/template/settings.local.json"
PROJECTS_DIR="${SB_PROJECTS_DIR:-$HOME/Projects}"
USAGE='usage: sb [--agent claude|gemini] [--fresh] <name>'

# Populated by parse_args; consumed by main.
g_name=""
g_agent=""
g_fresh=0

die() { printf 'sb: %s\n' "$1" >&2; exit "${2:-1}"; }
usage() { printf '%s\n' "$USAGE" >&2; exit 2; }
validate_name() { [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "invalid name, must match ^[a-z0-9-]+\$ (got: $1)"; }
agent_binary() {
  case "$1" in
    claude) printf 'claude' ;;
    gemini) printf 'gemini' ;;
    *) die "unknown agent '$1' (valid: claude, gemini)" 2 ;;
  esac
}
derive_uuid() { python3 -c 'import sys, uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "sb:" + sys.argv[1]))' "$1"; }
fresh_uuid() { python3 -c 'import uuid; print(uuid.uuid4())'; }
tmux_session_alive() { tmux has-session -t "$1" 2>/dev/null; }
ensure_scaffolding() {
  local target="$1"
  mkdir -p "$target/.claude"
  [[ -f "$target/.claude/settings.local.json" ]] || cp "$TEMPLATE" "$target/.claude/settings.local.json"
}
preflight() {
  local agent_bin; agent_bin="$(agent_binary "$g_agent")"
  command -v tmux       >/dev/null 2>&1 || die "tmux not found on PATH"
  command -v "$agent_bin" >/dev/null 2>&1 || die "$agent_bin not found on PATH"
  command -v python3    >/dev/null 2>&1 || die "python3 not found on PATH"
  [[ -d "$PROJECTS_DIR" ]] || die "$PROJECTS_DIR does not exist"
  [[ -f "$TEMPLATE" ]]     || die "template missing at $TEMPLATE — see README"
}
parse_args() {
  local agent="claude" fresh=0 positional="" saw_double_dash=0
  while [[ $# -gt 0 ]]; do
    if [[ $saw_double_dash -eq 1 ]]; then
      [[ -z "$positional" ]] || die "too many positional arguments" 2
      positional="$1"; shift; continue
    fi
    case "$1" in
      --) saw_double_dash=1; shift ;;
      -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
      --fresh) fresh=1; shift ;;
      --agent=*) agent="${1#--agent=}"; shift ;;
      --agent)
        [[ $# -ge 2 ]] || die "--agent requires a value" 2
        agent="$2"; shift 2 ;;
      -*) usage ;;
      *)
        [[ -z "$positional" ]] || die "too many positional arguments" 2
        positional="$1"; shift ;;
    esac
  done
  [[ -n "$positional" ]] || usage
  validate_name "$positional"
  agent_binary "$agent" >/dev/null   # validates agent or dies 2
  g_name="$positional"; g_agent="$agent"; g_fresh="$fresh"
}
main() {
  parse_args "$@"
  preflight
  local target="$PROJECTS_DIR/$g_name"
  if tmux_session_alive "$g_name"; then
    exec tmux attach -t "$g_name"
  fi
  ensure_scaffolding "$target"
  local session_uuid
  if [[ "$g_fresh" -eq 1 ]]; then
    session_uuid="$(fresh_uuid)"
  else
    session_uuid="$(derive_uuid "$g_name")"
  fi
  local agent_bin; agent_bin="$(agent_binary "$g_agent")"
  cd "$target"
  tmux new-session -d -s "$g_name" -c "$target"
  tmux send-keys -t "$g_name" "$agent_bin --session-id $session_uuid" Enter
  printf 'sb: detached with Ctrl-b d · resume with: sb %s\n' "$g_name" >&2
  exec tmux attach -t "$g_name"
}

# Source guard: tests source this file (BASH_SOURCE[0] != $0) and call functions
# directly without running main.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

**Pinned UUID** used in tests: `derive_uuid test` → `c24a89d6-d9a4-5122-a1a5-b3a6249b9d0b` (verified: `uuid5(NAMESPACE_URL, "sb:test")`).

---

### Task 1: Rename test harness, scaffold `bin/sb`, drop obsolete tests

**Files:**
- Modify: `test/helpers/common.bash`
- Modify: `test/helpers/stubs/tmux`
- Modify: `test/helpers/stubs/claude`
- Create: `test/helpers/stubs/gemini`
- Rename + rewrite: `bin/ppl` → `bin/sb`
- Delete: `test/unit_permissions.bats`
- Rewrite: `test/unit_helpers.bats` (start with die tests only)

- [ ] **Step 1: git mv the binary**

```bash
git mv bin/ppl bin/sb
```

- [ ] **Step 2: Write the `bin/sb` skeleton**

Overwrite `bin/sb` with exactly this (functions are added in later tasks, between the globals block and the source guard):

```bash
#!/usr/bin/env bash
set -euo pipefail

#
# sb — springboard: bootstrap and resume project workspaces. Pairs a tmux
# session with an AI-agent session under one stable per-project name.
# See README.md and docs/superpowers/specs/ for the full design.
#
# Globals:
#   SB_PROJECTS_DIR  Where projects live (default: $HOME/Projects).
#   SB_HOME          Resolved repo root, used to find template/.
#

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SB_HOME="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$SB_HOME/template/settings.local.json"
PROJECTS_DIR="${SB_PROJECTS_DIR:-$HOME/Projects}"
USAGE='usage: sb [--agent claude|gemini] [--fresh] <name>'

# Populated by parse_args; consumed by main.
g_name=""
g_agent=""
g_fresh=0

die() { printf 'sb: %s\n' "$1" >&2; exit "${2:-1}"; }
usage() { printf '%s\n' "$USAGE" >&2; exit 2; }

# Source guard: tests source this file (BASH_SOURCE[0] != $0) and call functions
# directly without running main.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

- [ ] **Step 3: Rewrite `test/helpers/common.bash`**

```bash
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
```

- [ ] **Step 4: Update the tmux stub**

Overwrite `test/helpers/stubs/tmux`:

```bash
#!/usr/bin/env bash
#
# tmux stub for tests. Logs argv to $SB_STUB_LOG. Returns exit codes that
# make the launcher's branches deterministic.
#

printf 'tmux %s\n' "$*" >> "${SB_STUB_LOG:-/dev/null}"

case "${1:-}" in
  has-session)
    if [[ "${SB_STUB_TMUX_SESSION_EXISTS:-false}" == "true" ]]; then
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
```

- [ ] **Step 5: Update the claude stub and create the gemini stub**

Overwrite `test/helpers/stubs/claude`:

```bash
#!/usr/bin/env bash
#
# claude stub for tests. Logs argv to $SB_STUB_LOG. Always succeeds.
#

printf 'claude %s\n' "$*" >> "${SB_STUB_LOG:-/dev/null}"
exit 0
```

Create `test/helpers/stubs/gemini`:

```bash
#!/usr/bin/env bash
#
# gemini stub for tests. Logs argv to $SB_STUB_LOG. Always succeeds.
#

printf 'gemini %s\n' "$*" >> "${SB_STUB_LOG:-/dev/null}"
exit 0
```

Make the new stub executable:

```bash
chmod +x test/helpers/stubs/gemini
```

- [ ] **Step 6: Delete the obsolete permissions test**

```bash
git rm test/unit_permissions.bats
```

- [ ] **Step 7: Write the failing test — `test/unit_helpers.bats` (die only for now)**

Overwrite `test/unit_helpers.bats`:

```bash
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
```

- [ ] **Step 8: Run the test**

Run: `bats test/unit_helpers.bats`
Expected: PASS (2 tests).

- [ ] **Step 9: Commit**

```bash
git add bin/sb test/helpers/common.bash test/helpers/stubs/tmux test/helpers/stubs/claude test/helpers/stubs/gemini test/unit_helpers.bats
git rm --cached test/unit_permissions.bats 2>/dev/null || true
git commit -m "refactor: rename ppl->sb, rewrite test harness with SB_ globals"
```

---

### Task 2: `validate_name`

**Files:**
- Modify: `bin/sb` (add function)
- Modify: `test/unit_helpers.bats` (add tests)

- [ ] **Step 1: Write the failing tests**

Append to `test/unit_helpers.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bats test/unit_helpers.bats`
Expected: FAIL — `validate_name: command not found`.

- [ ] **Step 3: Add the function to `bin/sb`**

Insert after the `usage()` line, before the source guard:

```bash
validate_name() { [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "invalid name, must match ^[a-z0-9-]+\$ (got: $1)"; }
```

- [ ] **Step 4: Run to verify pass**

Run: `bats test/unit_helpers.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/sb test/unit_helpers.bats
git commit -m "feat: add validate_name (no auto-prefix)"
```

---

### Task 3: `agent_binary`

**Files:**
- Modify: `bin/sb`
- Modify: `test/unit_helpers.bats`

- [ ] **Step 1: Write the failing tests**

Append to `test/unit_helpers.bats`:

```bash
@test "agent_binary returns claude" {
  run agent_binary claude
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
}

@test "agent_binary returns gemini" {
  run agent_binary gemini
  [ "$status" -eq 0 ]
  [ "$output" = "gemini" ]
}

@test "agent_binary rejects unknown agent with exit 2" {
  run agent_binary bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown agent 'bogus'"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats test/unit_helpers.bats`
Expected: FAIL — `agent_binary: command not found`.

- [ ] **Step 3: Add the function to `bin/sb`**

Insert after `validate_name`:

```bash
agent_binary() {
  case "$1" in
    claude) printf 'claude' ;;
    gemini) printf 'gemini' ;;
    *) die "unknown agent '$1' (valid: claude, gemini)" 2 ;;
  esac
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats test/unit_helpers.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/sb test/unit_helpers.bats
git commit -m "feat: add agent_binary table (claude, gemini)"
```

---

### Task 4: `derive_uuid` + `fresh_uuid`

**Files:**
- Modify: `bin/sb`
- Modify: `test/unit_helpers.bats`

- [ ] **Step 1: Write the failing tests**

Append to `test/unit_helpers.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bats test/unit_helpers.bats`
Expected: FAIL — `derive_uuid: command not found`.

- [ ] **Step 3: Add the functions to `bin/sb`**

Insert after `agent_binary`:

```bash
derive_uuid() { python3 -c 'import sys, uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "sb:" + sys.argv[1]))' "$1"; }
fresh_uuid() { python3 -c 'import uuid; print(uuid.uuid4())'; }
```

- [ ] **Step 4: Run to verify pass**

Run: `bats test/unit_helpers.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/sb test/unit_helpers.bats
git commit -m "feat: add derive_uuid (sb: namespace) and fresh_uuid"
```

---

### Task 5: `ensure_scaffolding` + `tmux_session_alive`

**Files:**
- Modify: `bin/sb`
- Modify: `test/unit_helpers.bats`

- [ ] **Step 1: Write the failing tests**

Append to `test/unit_helpers.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bats test/unit_helpers.bats`
Expected: FAIL — `ensure_scaffolding: command not found`.

- [ ] **Step 3: Add the functions to `bin/sb`**

Insert after `fresh_uuid`:

```bash
tmux_session_alive() { tmux has-session -t "$1" 2>/dev/null; }
ensure_scaffolding() {
  local target="$1"
  mkdir -p "$target/.claude"
  [[ -f "$target/.claude/settings.local.json" ]] || cp "$TEMPLATE" "$target/.claude/settings.local.json"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats test/unit_helpers.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/sb test/unit_helpers.bats
git commit -m "feat: add ensure_scaffolding (no .iteration) and tmux_session_alive"
```

---

### Task 6: `parse_args`

**Files:**
- Modify: `bin/sb`
- Create: `test/unit_args.bats`

- [ ] **Step 1: Write the failing tests**

Create `test/unit_args.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  sb_setup_env
  sb_source
}

@test "positional only -> claude, not fresh" {
  parse_args numista
  [ "$g_name" = "numista" ]
  [ "$g_agent" = "claude" ]
  [ "$g_fresh" -eq 0 ]
}

@test "--agent gemini numista" {
  parse_args --agent gemini numista
  [ "$g_name" = "numista" ]
  [ "$g_agent" = "gemini" ]
}

@test "--agent=gemini numista" {
  parse_args --agent=gemini numista
  [ "$g_agent" = "gemini" ]
}

@test "--fresh sets the flag" {
  parse_args --fresh numista
  [ "$g_fresh" -eq 1 ]
}

@test "flags after positional: numista --agent gemini --fresh" {
  parse_args numista --agent gemini --fresh
  [ "$g_name" = "numista" ]
  [ "$g_agent" = "gemini" ]
  [ "$g_fresh" -eq 1 ]
}

@test "name that looks like a former mode is just a name" {
  parse_args plan
  [ "$g_name" = "plan" ]
  [ "$g_agent" = "claude" ]
}

@test "--agent bogus -> exit 2" {
  run parse_args --agent bogus numista
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown agent 'bogus'"* ]]
}

@test "--agent with no value -> exit 2" {
  run parse_args --agent
  [ "$status" -eq 2 ]
}

@test "no positional -> usage exit 2" {
  run parse_args
  [ "$status" -eq 2 ]
}

@test "unknown flag -> usage exit 2" {
  run parse_args --bogus numista
  [ "$status" -eq 2 ]
}

@test "too many positionals -> exit 2" {
  run parse_args a b
  [ "$status" -eq 2 ]
}

@test "-h prints usage to stdout, exit 0" {
  run parse_args -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: sb"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats test/unit_args.bats`
Expected: FAIL — `parse_args: command not found`.

- [ ] **Step 3: Add the function to `bin/sb`**

Insert after `ensure_scaffolding`:

```bash
parse_args() {
  local agent="claude" fresh=0 positional="" saw_double_dash=0
  while [[ $# -gt 0 ]]; do
    if [[ $saw_double_dash -eq 1 ]]; then
      [[ -z "$positional" ]] || die "too many positional arguments" 2
      positional="$1"; shift; continue
    fi
    case "$1" in
      --) saw_double_dash=1; shift ;;
      -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
      --fresh) fresh=1; shift ;;
      --agent=*) agent="${1#--agent=}"; shift ;;
      --agent)
        [[ $# -ge 2 ]] || die "--agent requires a value" 2
        agent="$2"; shift 2 ;;
      -*) usage ;;
      *)
        [[ -z "$positional" ]] || die "too many positional arguments" 2
        positional="$1"; shift ;;
    esac
  done
  [[ -n "$positional" ]] || usage
  validate_name "$positional"
  agent_binary "$agent" >/dev/null   # validates agent or dies 2
  g_name="$positional"; g_agent="$agent"; g_fresh="$fresh"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats test/unit_args.bats`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add bin/sb test/unit_args.bats
git commit -m "feat: add parse_args (--agent, --fresh, no permission flags)"
```

---

### Task 7: `preflight`

**Files:**
- Modify: `bin/sb`
- Modify: `test/unit_helpers.bats`

- [ ] **Step 1: Write the failing tests**

Append to `test/unit_helpers.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bats test/unit_helpers.bats`
Expected: FAIL — `preflight: command not found`.

- [ ] **Step 3: Add the function to `bin/sb`**

Insert after `parse_args`:

```bash
preflight() {
  local agent_bin; agent_bin="$(agent_binary "$g_agent")"
  command -v tmux         >/dev/null 2>&1 || die "tmux not found on PATH"
  command -v "$agent_bin" >/dev/null 2>&1 || die "$agent_bin not found on PATH"
  command -v python3      >/dev/null 2>&1 || die "python3 not found on PATH"
  [[ -d "$PROJECTS_DIR" ]] || die "$PROJECTS_DIR does not exist"
  [[ -f "$TEMPLATE" ]]     || die "template missing at $TEMPLATE — see README"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats test/unit_helpers.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/sb test/unit_helpers.bats
git commit -m "feat: add preflight (checks tmux, agent binary, python3, dirs)"
```

---

### Task 8: `main` — fresh launch, attach, resume (integration)

**Files:**
- Modify: `bin/sb` (add `main`)
- Rewrite: `test/integration_launch.bats`

- [ ] **Step 1: Write the failing tests**

Overwrite `test/integration_launch.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bats test/integration_launch.bats`
Expected: FAIL — `main` is referenced by the source guard but not defined (`main: command not found`).

- [ ] **Step 3: Add `main` to `bin/sb`**

Insert after `preflight`, immediately before the source-guard block:

```bash
main() {
  parse_args "$@"
  preflight
  local target="$PROJECTS_DIR/$g_name"
  if tmux_session_alive "$g_name"; then
    exec tmux attach -t "$g_name"
  fi
  ensure_scaffolding "$target"
  local session_uuid
  if [[ "$g_fresh" -eq 1 ]]; then
    session_uuid="$(fresh_uuid)"
  else
    session_uuid="$(derive_uuid "$g_name")"
  fi
  local agent_bin; agent_bin="$(agent_binary "$g_agent")"
  cd "$target"
  tmux new-session -d -s "$g_name" -c "$target"
  tmux send-keys -t "$g_name" "$agent_bin --session-id $session_uuid" Enter
  printf 'sb: detached with Ctrl-b d · resume with: sb %s\n' "$g_name" >&2
  exec tmux attach -t "$g_name"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats test/integration_launch.bats`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add bin/sb test/integration_launch.bats
git commit -m "feat: add main (launch/attach/resume, stable session, detach hint)"
```

---

### Task 9: Integration — `--fresh`, `--agent gemini`, error paths

**Files:**
- Modify: `test/integration_launch.bats` (add tests; no `bin/sb` changes expected)

- [ ] **Step 1: Write the tests**

Append to `test/integration_launch.bats`:

```bash
@test "--fresh: session id is a valid uuid and not the stable one" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  run_sb --fresh test
  [ "$status" -eq 0 ]
  ! sb_stub_log_contains 'c24a89d6-d9a4-5122-a1a5-b3a6249b9d0b'
  grep -qE 'claude --session-id [0-9a-f-]{36} Enter' "$SB_STUB_LOG"
}

@test "--agent gemini: launches gemini with a session id" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  run_sb --agent gemini test
  [ "$status" -eq 0 ]
  sb_stub_log_contains 'tmux send-keys -t test gemini --session-id'
}

@test "flag after positional: test --agent gemini" {
  export SB_STUB_TMUX_SESSION_EXISTS=false
  run_sb test --agent gemini
  [ "$status" -eq 0 ]
  sb_stub_log_contains 'tmux send-keys -t test gemini --session-id'
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
```

- [ ] **Step 2: Run to verify pass**

Run: `bats test/integration_launch.bats`
Expected: PASS (9 tests total). If any fail, fix `bin/sb` per the spec (no new behavior should be required — these exercise the `main`/`parse_args` already written).

- [ ] **Step 3: Commit**

```bash
git add test/integration_launch.bats
git commit -m "test: cover --fresh, --agent gemini, and error paths"
```

---

### Task 10: Strip the template to permissions-only

**Files:**
- Modify: `template/settings.local.json`
- Modify: `test/unit_helpers.bats` (add template assertion)

- [ ] **Step 1: Write the failing test**

Append to `test/unit_helpers.bats`:

```bash
@test "template is permissions-only (defaultMode acceptEdits, no skills)" {
  grep -q '"defaultMode": "acceptEdits"' "$SB_REPO_ROOT/template/settings.local.json"
  ! grep -q 'Skill(' "$SB_REPO_ROOT/template/settings.local.json"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats test/unit_helpers.bats`
Expected: FAIL — current template has no `defaultMode` and contains `Skill(` entries.

- [ ] **Step 3: Overwrite `template/settings.local.json`**

```json
{
  "permissions": {
    "defaultMode": "acceptEdits"
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats test/unit_helpers.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add template/settings.local.json test/unit_helpers.bats
git commit -m "feat: strip project template to permissions-only (acceptEdits)"
```

---

### Task 11: Docs, Makefile, and full `make check`

**Files:**
- Modify: `Makefile`
- Rewrite: `README.md`

- [ ] **Step 1: Update the Makefile lint path**

In `Makefile`, change the `lint` recipe line from:

```make
	shellcheck --shell=bash --severity=style bin/ppl test/helpers/common.bash test/helpers/stubs/*
```

to:

```make
	shellcheck --shell=bash --severity=style bin/sb test/helpers/common.bash test/helpers/stubs/*
```

Also update the comment on the `lint` target from `## Run ShellCheck on bin/ppl and test helpers.` to `## Run ShellCheck on bin/sb and test helpers.`

- [ ] **Step 2: Rewrite `README.md`**

Overwrite `README.md`:

```markdown
# springboard (`sb`)

![CI](https://github.com/vinnyp/springboard/actions/workflows/ci.yml/badge.svg)

`sb <name>` — bootstraps and resumes a project workspace, pairing a tmux session
with an AI-agent session under one stable per-project name.

## What it does

```
sb numista
```

1. Validates the name (`^[a-z0-9-]+$`) and checks that `tmux`, the agent (`claude`
   by default), and `python3` are on `PATH`.
2. If a tmux session named `numista` is already running, attaches to it. No disk
   writes. Done.
3. Otherwise, ensures `$SB_PROJECTS_DIR/numista/` (default `~/Projects/numista/`)
   exists with `.claude/settings.local.json` copied from the
   [template](template/settings.local.json).
4. Starts a detached tmux session `numista` and launches the agent inside it,
   resuming the project's stable session:

   ```
   claude --session-id <uuid>
   ```

   The session id is a UUIDv5 derived from `sb:numista`, so `sb numista` always
   resumes the same conversation. Use `--fresh` to start a brand-new session.

The full design lives in
[`docs/superpowers/specs/2026-05-23-springboard-launcher-design.md`](docs/superpowers/specs/2026-05-23-springboard-launcher-design.md).

## Install

```bash
git clone <this-repo> /path/to/springboard
ln -sf /path/to/springboard/bin/sb ~/.local/bin/sb
```

Make sure `~/.local/bin` is on `PATH`. Requirements on `PATH`: `tmux`, your agent
(`claude` and/or `gemini`), `python3`. macOS without GNU coreutils may need
`brew install coreutils` — `bin/sb` uses `readlink -f` to resolve its own symlink.

## Agents

`sb` launches `claude` by default. Choose another agent with `--agent`:

```bash
sb numista --agent gemini
```

Supported: `claude`, `gemini`. Both are launched with `--session-id <uuid>`. The
chosen agent must be installed and on `PATH` (e.g. `--agent gemini` requires
gemini-cli). Adding a new agent is a one-line entry in `agent_binary` in `bin/sb`.

## Sessions

- `sb <name>` resumes the project's stable session every time — attaches if the
  tmux session is live, otherwise relaunches the agent resuming the saved
  conversation.
- `sb <name> --fresh` mints a brand-new session id for this launch (not persisted;
  the next plain `sb <name>` returns to the stable session).
- To step away without ending anything, detach tmux with `Ctrl-b d`; `sb <name>`
  re-attaches. To fully close out, quit the agent and exit the shell; `sb <name>`
  later resumes the saved conversation. `sb` prints this hint on each launch.

## Configuration

Projects live under `~/Projects/` by default. Override with `SB_PROJECTS_DIR`:

```bash
export SB_PROJECTS_DIR="$HOME/code"
sb numista                # now uses ~/code/numista
```

## Behavior matrix

| Project dir | tmux session | Outcome |
|---|---|---|
| any | running | `tmux attach` — warm resume, no relaunch |
| missing | not running | create dir + template, launch with stable session id |
| exists | not running | resume: stable session id, scaffold only what's missing |
| (any of the above) + `--fresh` | not running | launch with a random session id instead |

Names must match `^[a-z0-9-]+$`. There is **no** auto-prefix — `sb numista` uses
`~/Projects/numista` exactly.

## Customizing per-project settings

[`template/settings.local.json`](template/settings.local.json) is **permissions
only** — it sets `permissions.defaultMode` to `acceptEdits` and contains no skills.
Each `sb <name>` copies it into a new project's `.claude/`. Add whatever skills a
project needs by editing that project's `.claude/settings.local.json` yourself;
different projects can have different skills.

## Development

```bash
make help    # list targets
make lint    # shellcheck
make test    # bats
make check   # both (what CI runs)
```

Prerequisites (dev only): `shellcheck`, `bats-core`. macOS: `brew install
shellcheck bats-core coreutils`. Debian/Ubuntu: `sudo apt-get install -y shellcheck
bats`. CI runs `make check` on `ubuntu-latest` and `macos-latest`.

## Layout

```
springboard/
├── bin/sb                          # the launcher
├── template/settings.local.json    # permissions-only project template
├── test/                           # bats-core suite + stubs
├── Makefile                        # lint / test / check targets
├── .github/workflows/ci.yml        # CI on Linux + macOS
├── docs/superpowers/               # specs and plans
├── LICENSE                         # MIT
└── README.md
```

## License

[MIT](LICENSE) © Vinny Pasceri.
```

- [ ] **Step 3: Run the full check suite**

Run: `make check`
Expected: shellcheck clean; all bats tests pass (`test/unit_helpers.bats`, `test/unit_args.bats`, `test/integration_launch.bats`).

- [ ] **Step 4: Commit**

```bash
git add Makefile README.md
git commit -m "docs: rewrite README and Makefile for springboard/sb"
```

---

## Post-implementation (do with the user, not as an automated step)

These are outward-facing / hard to reverse. Surface them to the user; do not run
them unprompted.

- **Rename the GitHub repo** `printing-press-launcher` → `springboard` and update
  the remote:
  ```bash
  git remote set-url origin git@github.com:vinnyp/springboard.git
  ```
  (after renaming in GitHub settings), and rename the local working directory.
- **Re-link the binary:** `ln -sf /path/to/springboard/bin/sb ~/.local/bin/sb`,
  and remove the old `ppl` symlink if present.
- **Open a PR** from `springboard-launcher` once the user confirms.

## Notes for the implementer

- `bin/sb` must stay **bash-3.2-safe** (macOS system bash) — no associative
  arrays, no `${var^^}`, no `mapfile`. CI runs on `macos-latest` and will catch
  regressions.
- bats `run` merges stdout+stderr into `$output`, which is why stderr messages
  (`die`, the detach hint) are asserted via `$output`.
- The agent stubs (`claude`, `gemini`) are only ever found by `command -v` in
  `preflight`; they are not executed (the stubbed `tmux send-keys` just logs the
  command string), so their bodies only need to exist and be executable.
- The repo's own `.claude/settings.local.json` (dev permissions) is intentionally
  left untouched — only `template/settings.local.json` is stripped.
- **Runtime verification (not unit-testable with stubs):** with a real agent,
  confirm that relaunching `<agent> --session-id <known-uuid>` *resumes* the
  existing conversation rather than erroring when the id already exists — first for
  `claude`, then for `gemini`. The test suite stubs the agent, so this can only be
  checked by actually running `sb <name>` twice against a live agent. Do this once
  by hand before relying on resume-by-default.
```
