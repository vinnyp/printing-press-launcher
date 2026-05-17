# `pp` launcher — quality pass

**Date:** 2026-05-17
**Status:** Designed
**Supersedes:** nothing. Builds on [`2026-05-17-pp-launcher-design.md`](2026-05-17-pp-launcher-design.md).

## Purpose

Bring the existing `bin/pp` launcher up to a publishable bar without changing its observable behavior: add a license, a permissions flag, a Google-style refactor with comments, ShellCheck linting, a bats-core test suite, a `Makefile`, and a cross-platform GitHub Actions CI workflow.

## Goals

- **No behavior regression.** Every existing invocation continues to work identically.
- **One new feature only.** A `-p` / `--permissions` flag for the five Claude permission modes, with `dontAsk` remaining the default.
- **Code is testable in isolation.** Pure helpers can be sourced and called directly; the launcher path is exercised end-to-end against stub `tmux` / `claude`.
- **CI is the contract.** `make check` is what humans run locally and what CI enforces, on both Linux and macOS.

## Non-goals

- Changes to the launcher contract: slug rules, iteration semantics, deterministic UUID derivation, tmux/claude orchestration, `dontAsk` as the default — all unchanged.
- Deferred items from the v1 spec (`--resume`, `--new`, `git init`, seeded `CLAUDE.md`).
- Refactor of `template/settings.local.json`.
- Cross-shell support (the script is bash; `zsh`/`fish` are not targets).
- Windows support.

---

## Scope summary

| Area | Change |
|---|---|
| `LICENSE` | New — MIT, holder "Vinny Pasceri", year 2026. |
| `bin/pp` | Refactored to the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html); function header comments; new `validate_permission_mode`, `pick_permission_mode`, `parse_args` functions; `BASH_SOURCE`-vs-`$0` guard so tests can source it. |
| Permissions flag | New `-p` / `--permissions` with the five-mode list. |
| `test/` | New bats-core suite — pure-function unit tests + stubbed integration tests. |
| `Makefile` | New — `lint`, `test`, `check`, `help`. |
| ShellCheck | New — invoked by `make lint`. |
| `.github/workflows/ci.yml` | New — `make check` on `ubuntu-latest` and `macos-latest`. |
| `README.md` | Permissions section, Development section, layout block updated, CI badge, License section. |
| `.gitignore` | Unchanged. |
| `template/settings.local.json` | Unchanged. |

---

## `-p` / `--permissions` contract

**Synopsis:** `pp [-p MODE | --permissions[=MODE] | -p | --permissions] <name>`

**Valid modes:** `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`. Validated against this exact list before any side effect.

**Resolution rules.** The parser uses a strict, predictable rule: `-p` / `--permissions` always consumes the next argv element as the mode value when one is present. The picker is invoked by passing the flag with **no following argv element** — i.e. as the last argument on the command line.

- **Equals form (`--permissions=VALUE`):** consume `VALUE`, validate against the five-mode list.
- **Flag followed by another argv:** consume that next element as the mode value (validated). Invalid mode → exit 2 with the invalid-mode message.
- **Flag is the last argv element (bare):** if stdin is a TTY, run the `select` picker; otherwise exit 2 with `pp: --permissions requires a value when stdin is not a tty`.

| Invocation | Resolved mode |
|---|---|
| `pp parcel` (no flag) | `dontAsk` (preserves current default) |
| `pp -p plan parcel`, `pp --permissions=plan parcel`, `pp --permissions plan parcel` | `plan` |
| `pp parcel -p plan` | `plan` (positional may precede the flag) |
| `pp parcel -p` (flag last) | picker |
| `pp -p parcel` | exit 2, `parcel` validated as a mode and rejected |
| `pp -p plan` (no positional) | exit 2, missing positional after consuming `plan` |
| `pp -p bogus parcel` | exit 2, invalid-mode message for `bogus` |
| unknown flag | usage to stderr, exit 2 |

**Argument parsing:** hand-rolled `while` loop over `"$@"`. `--` ends option parsing. Exactly one positional `<name>` is required (unchanged from v1). Options may appear before or after the positional. Multiple `-p` occurrences: last one wins (standard CLI convention).

**Slug/mode collision (no special case needed):** the slug regex `^[a-z0-9-]+$` permits `plan`, `default`, `auto` as project names. Under the strict rule there is no ambiguity:

- `pp plan` — launches the project named `plan` with the `dontAsk` default. Works directly.
- `pp plan -p` — flag last → picker for the project named `plan`.
- `pp -p dontAsk plan` — explicit mode, then positional.

`pp -p plan` is interpreted as "set mode to `plan`, no project given" and errors with the missing-positional usage. The error message is unambiguous about which arg is missing.

**Interaction with the live-attach short-circuit:** when `tmux has-session -t $slug` succeeds, the existing session is attached and Claude is *not* relaunched. `-p` is silently ignored in that branch — its only effect is on the `--permission-mode` value handed to a newly launched Claude. The picker is not shown.

**Picker UI** (bash `select` builtin):

```bash
PS3='Select permission mode: '
select mode in default acceptEdits plan auto dontAsk; do
  [[ -n "$mode" ]] && break
done
```

`select` writes its menu and `PS3` prompt to stderr, keeping stdout clean.

**Wire-through:** the resolved mode replaces the hard-coded `dontAsk` in the `claude --permission-mode ...` `send-keys` line. No other call sites in the script reference the value.

---

## Script structure

After the refactor, `bin/pp` has this shape (top to bottom):

1. `#!/usr/bin/env bash`
2. `set -euo pipefail`
3. **File header comment** (purpose, globals).
4. Globals: `SCRIPT_DIR`, `PP_HOME`, `TEMPLATE`, `PROJECTS_DIR` (as today).
5. Function definitions, each preceded by a Google-format header block.
6. `main` function.
7. **Source guard** (`if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi`).

### Function inventory

| Function | Purpose | Status |
|---|---|---|
| `die`, `usage` | Error helpers. | unchanged |
| `preflight` | Verify `tmux`, `claude`, `python3` on `PATH`; verify projects dir + template exist. | unchanged |
| `compute_slug` | Add `pp-` prefix if missing. | unchanged |
| `validate_slug` | Reject anything outside `^[a-z0-9-]+$`. | unchanged |
| `tmux_session_alive` | Wrap `tmux has-session`. | unchanged |
| `ensure_scaffolding` | `mkdir`, copy template, seed `.iteration=0` (all idempotent). | unchanged |
| `bump_iteration` | Read / increment / write `.iteration`, echo new value. | unchanged |
| `derive_uuid` | Call `python3` for UUIDv5 of `pp:<session_name>`. | unchanged |
| `validate_permission_mode` | Accept-or-die for the five-mode list. | new |
| `pick_permission_mode` | Bash `select` picker on TTY; echo chosen value. | new |
| `parse_args` | Hand-rolled flag parser; populates `g_name`, `g_perm_mode`. | new |
| `main` | Orchestrator. Calls `parse_args`, `preflight`, the short-circuit, scaffolding, and launch. | refactored |

### Comment style

Per the Google Shell Style Guide. File header at the top:

```bash
#
# pp — bootstrap and resume Claude Code projects for the cli-printing-press
# workflow. See README.md and docs/superpowers/specs/ for full design.
#
# Globals:
#   PP_PROJECTS_DIR  Where projects live (default: $HOME/Projects).
#   PP_HOME          Resolved repo root, used to find template/.
```

Per-function header, above every function:

```bash
#######################################
# Brief one-line description.
# Globals:
#   <vars read or written, or "None">
# Arguments:
#   $1 - description
# Outputs:
#   Writes <what> to stdout/stderr.
# Returns:
#   0 on success, non-zero with `die` on failure.
#######################################
```

Dropped fields are written as `None`. Inline comments are added only where the *why* is non-obvious — e.g., why UUIDv5 over `uuidgen`, why `send-keys` instead of passing the command to `tmux new-session`. No restating what the code does.

### Style conformance

The existing script is already close to the guide. The refactor is comments, the new functions, the arg parser, and the source guard. No changes to: 2-space indentation, `[[ ... ]]` over `[ ... ]`, `$( ... )` over backticks, lowercase functions with underscores, uppercase env vars, `local` for function-scope vars.

---

## Testing

**Framework:** [bats-core](https://github.com/bats-core/bats-core). Installed via `brew install bats-core` (macOS) or `apt-get install bats` (Linux).

**Layout:**

```
test/
├── helpers/
│   ├── stubs/        # executable shims placed on PATH for integration tests
│   │   ├── tmux
│   │   └── claude
│   └── common.bash   # setup/teardown helpers
├── unit_helpers.bats
├── unit_permissions.bats
└── integration_launch.bats
```

**Stubs.** Small bash shims that log their argv (one line, NUL-safe) to `"$PP_STUB_LOG"` and exit 0. The `tmux` stub additionally honors `PP_STUB_TMUX_SESSION_EXISTS` (`true` → `has-session` returns 0 so live-attach fires; `false` or unset → returns 1 so the launch path runs). The real `python3` is used as-is — UUIDv5 is deterministic, so tests pin expected values.

**Fixtures per case.** `setup()`:

- Creates a tmpdir, sets `PP_PROJECTS_DIR="$BATS_TEST_TMPDIR/proj"`, `mkdir -p` it.
- Prepends `test/helpers/stubs` to `PATH`.
- Points `PP_STUB_LOG` at a fresh file in the tmpdir.
- For unit tests: sources `bin/pp` (the source guard prevents `main` from running).
- For integration tests: leaves `bin/pp` to be executed as a subprocess.

`teardown()` removes the tmpdir.

### Unit cases — `unit_helpers.bats`

| Case | Assertion |
|---|---|
| `compute_slug` adds prefix | `compute_slug parcel` → `pp-parcel` |
| `compute_slug` keeps prefix | `compute_slug pp-parcel` → `pp-parcel` |
| `validate_slug` accepts | `pp-foo`, `pp-foo-1`, `pp-a-b-c` |
| `validate_slug` rejects | `'foo bar'`, `Foo`, `''`, `pp_foo` |
| `bump_iteration` 0→1 | seed `0\n`, call → `1`, file is `1\n` |
| `bump_iteration` 9→10 | seed `9\n`, call → `10`, file is `10\n` |
| `bump_iteration` errors on non-int | seed `abc\n`, expect non-zero exit and `die` message |
| `derive_uuid pp-parcel-01` | matches the known UUIDv5 of `pp:pp-parcel-01` (pinned constant) |
| `ensure_scaffolding` from missing | creates `.claude/`, copies template, writes `.iteration=0` |
| `ensure_scaffolding` is idempotent | pre-existing template content is preserved on re-run |

### Unit cases — `unit_permissions.bats`

| Case | Assertion |
|---|---|
| `validate_permission_mode` accepts each | all five modes return 0 |
| `validate_permission_mode` rejects | `Plan`, `yolo`, empty string → non-zero with the documented error |
| `parse_args parcel` | `g_name=pp-parcel`, `g_perm_mode=dontAsk` |
| `parse_args -p plan parcel` | mode=`plan` |
| `parse_args parcel -p plan` | name=`pp-parcel`, mode=`plan` (positional before flag) |
| `parse_args --permissions=acceptEdits parcel` | mode=`acceptEdits` |
| `parse_args --permissions auto parcel` | mode=`auto` |
| `parse_args parcel -p </dev/null` | exits 2, bare flag + non-TTY stdin |
| `parse_args -p parcel </dev/null` | exits 2: `parcel` consumed as mode, fails validation |
| `parse_args -p plan` (no positional) | exits 2: `plan` consumed as mode, missing positional |
| `parse_args -p bogus parcel` | exits 2 with the invalid-mode message for `bogus` |
| `parse_args` with no positional | exits 2, prints usage |
| `parse_args --bogus parcel` | exits 2, prints usage (unknown flag) |
| `parse_args plan` | `g_name=pp-plan`, mode=`dontAsk` (slug shares a mode name; works directly) |
| `parse_args -p plan -p auto parcel` | mode=`auto` (last flag occurrence wins) |

### Integration cases — `integration_launch.bats`

Each case runs `bin/pp` as a subprocess with stubs on `PATH`.

1. **Fresh project, no flag.** `PP_STUB_TMUX_SESSION_EXISTS=false`. Assert: `tmux new-session` invoked with the correct `-s`/`-c`; `send-keys` payload contains `--permission-mode dontAsk` and `-n pp-test-01`; `tmux attach` invoked; `.iteration` is `1`.
2. **Live attach.** `PP_STUB_TMUX_SESSION_EXISTS=true`. Assert: `tmux attach` invoked; `tmux new-session` *not* invoked; `.iteration` unchanged from its pre-state.
3. **Bump after kill.** Second invocation with `PP_STUB_TMUX_SESSION_EXISTS=false`, pre-existing `.iteration=1`. Assert: `.iteration=2`, session name `pp-test-02`, UUID matches the pinned UUIDv5 of `pp:pp-test-02`.
4. **`pp -p plan test`.** Assert: payload contains `--permission-mode plan`.
5. **`pp --permissions=acceptEdits test`.** Assert: payload contains `--permission-mode acceptEdits`.
6. **`pp test -p plan`** (positional before flag). Assert: payload contains `--permission-mode plan`.
7. **`pp test -p </dev/null`** (bare flag, non-TTY). Exit 2 with the documented message; no scaffolding created; `tmux` never invoked.
8. **`pp -p bogus test`.** Exit 2 with the invalid-mode message; no scaffolding created; `tmux` never invoked.
9. **`pp 'foo bar'`.** Exits non-zero with the invalid-name message; no files touched.
10. **Missing template.** Point `PP_HOME` at a tmpdir without `template/`. Exits 1 with the template-missing message.

### What is explicitly not tested

- The real `claude` binary's behavior.
- Real tmux session attachment (needs a TTY).
- The picker UI's happy path (interactive `select` on a TTY). The non-TTY error path is covered; the TTY path stays in the manual procedure below.

---

## Lint

**Tool:** [ShellCheck](https://www.shellcheck.net/).

**Command** (also the body of `make lint`):

```
shellcheck --shell=bash --severity=style bin/pp test/helpers/common.bash test/helpers/stubs/*
```

`severity=style` catches everything from style upward. Zero suppressions in the initial pass. Any future suppression goes inline as `# shellcheck disable=SCxxxx` with a comment explaining why.

`.bats` files are not linted by ShellCheck — they use the bats dialect. Their bash helpers (`test/helpers/common.bash`, the stubs) *are* linted.

---

## Makefile

POSIX `make`, tab-indented recipes:

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

No `clean` target — nothing to clean.

---

## CI

**File:** `.github/workflows/ci.yml`.

**Triggers:** `push` (any branch), `pull_request` (any branch).

**Matrix:** `os: [ubuntu-latest, macos-latest]`. Single job `check`.

**Steps (Linux):**

1. `actions/checkout@v4`.
2. `sudo apt-get update && sudo apt-get install -y shellcheck bats`.
3. `make check`.

**Steps (macOS):**

1. `actions/checkout@v4`.
2. `brew install shellcheck bats-core coreutils`.
3. `echo "$(brew --prefix coreutils)/libexec/gnubin" >> "$GITHUB_PATH"` — puts GNU `readlink` ahead of BSD `readlink`, matching the existing README install note ("macOS without GNU coreutils may need `brew install coreutils`"). The script itself stays unchanged.
4. `make check`.

`python3` and `bash` are present on both runner images. No additional Python packages are needed (the script uses only the stdlib `uuid` module).

The macOS runner also ships bash 3.2 at `/bin/bash` and a newer Homebrew bash on `PATH`. The script's bashisms (`[[ ... ]]`, `=~`, `local`, arithmetic, `printf -v`) are 3.2-compatible. If a bash-4-only feature is ever introduced, real-world macOS users running under `/bin/bash` will break and we will hear about it; for CI purposes, exercising the script under Homebrew bash on macOS is sufficient.

---

## LICENSE

`LICENSE` in the repo root. Standard MIT text, holder `Vinny Pasceri`, year `2026`. A "License" section is added to the README pointing at it.

---

## README updates

- New **Permissions** subsection under "Configuration": document the five modes, `-p` / `--permissions`, the default (`dontAsk`), the picker behavior, and the non-TTY error case.
- New **Development** section: `make check`, `make lint`, `make test`, the prereqs (`brew install shellcheck bats-core` or `apt-get install shellcheck bats`).
- A CI status badge near the top.
- The `Layout` block is updated to include `test/`, `Makefile`, `.github/workflows/ci.yml`, `LICENSE`.
- A **License** section pointing at `LICENSE`.

---

## Acceptance criteria

Functional (no regression + new feature works):

1. `pp parcel` (no flag) on a fresh `~/Projects/pp-parcel/` produces the same observable result as today: tmux session `pp-parcel` attached, Claude launched as `pp-parcel-01` with `--permission-mode dontAsk` and the deterministic UUID.
2. `pp -p plan parcel`, `pp --permissions=acceptEdits parcel`, `pp --permissions auto parcel` each launch Claude with the corresponding `--permission-mode` value.
3. `pp parcel -p` on a TTY drops into the `select` picker; the chosen mode is wired through.
4. `pp parcel -p` with non-TTY stdin exits 2 with the documented message; no scaffolding written.
5. `pp -p bogus parcel` exits 2; no scaffolding written; `tmux` never invoked.
6. Live-attach short-circuit ignores `-p`: `pp -p plan parcel` (or `pp parcel -p`) against an already-running `pp-parcel` session attaches with no Claude relaunch and no error.
7. All existing slug validation, iteration bumping, template copying, and resume-by-UUID behavior is unchanged.

Quality:

8. `make lint` passes with zero ShellCheck findings (severity `style` and above).
9. `make test` passes — every bats case in the Testing section green.
10. `make check` is the single command CI runs and it passes on both `ubuntu-latest` and `macos-latest`.
11. Every function in `bin/pp` carries a Google-format header block; the file carries a top-of-file header. No drive-by `# what this line does` comments.

---

## Manual validation procedure

On a throwaway slug after CI is green:

1. `pp test123` → fresh launch, `dontAsk`, attached.
2. Detach. `pp -p plan test123` → still attaches existing session, no relaunch, no error.
3. `tmux kill-session -t pp-test123`. `pp -p plan test123` → iter `02`, payload contains `--permission-mode plan`.
4. `pp test123 -p` → picker appears; pick `acceptEdits`; iter `03` launches with that mode.
5. `pp test123 -p </dev/null` → exit 2, no iter bump.
6. `pp -p bogus test123` → exit 2, no iter bump (invalid-mode rejection).
7. `rm -rf ~/Projects/pp-test123` to clean up.

---

## Out-of-scope reaffirmation

No changes to slug rules, iteration semantics, UUID derivation, or the `dontAsk` default. No new end-user dependencies (`shellcheck` and `bats-core` are dev-time only).
