# springboard — generic project launcher (design)

Date: 2026-05-23

## Summary

Generalize the `printing-press-launcher` (`ppl`) into **springboard** — a generic
project launcher that pairs a tmux session with an AI-agent session under a single
stable, per-project name. Bootstraps the project workspace on first use and resumes
it thereafter.

- **Repo:** `springboard`
- **Binary:** `bin/sb` (symlinked to `~/.local/bin/sb`)
- **Agents:** `claude` (default) and `gemini`, selected with `--agent`.

This removes everything specific to the printing-press workflow: the `pp-` name
prefix, the per-iteration counter, the permission-mode flag, and the skill list
baked into the project template.

## Goals

- Launch or resume a project by name: `sb <name>` opens `~/Projects/<name>` in a
  tmux session with an AI agent, resuming the same agent conversation by default.
- Keep tmux session names and agent session ids aligned per project (the property
  the current tool is valued for).
- Support multiple agents via a thin, data-driven abstraction; `claude` now,
  `gemini` wired alongside it.
- Keep the project template minimal: permissions only, no skills.
- Stay portable: bash-3.2-safe (macOS system bash), passing `make check` on Linux
  and macOS CI.

## Non-goals (YAGNI)

- No nameless / cwd-based invocation.
- No `SB_AGENT` default-override env var (default agent is hardcoded `claude`).
- No per-project agent persistence.
- No skill profiles/presets or interactive skill picker — skills are configured
  per-project by hand.

## CLI surface

```
sb [--agent <name>] [--fresh] <name>
```

- `<name>` — required. Validated against `^[a-z0-9-]+$`. **No auto-prefix** — the
  `compute_slug` `pp-` behavior is removed. `sb numista` → `~/Projects/numista`.
- `--agent <name>` / `--agent=<name>` — default `claude`. Validated against the
  agent table; unknown agent → exit 2.
- `--fresh` — boolean. Forces a brand-new session id instead of resuming the
  stable one.
- `--` ends option parsing.
- `-h` / `--help` — print usage to stdout, exit 0.
- Unknown flags → usage, exit 2.
- Flags may appear before or after the positional (current behavior preserved).

**Removed from the CLI:** `-p` / `--permissions` / `--permissions=`, the
interactive permission-mode picker, and the `--permission-mode` argument passed to
the agent. Permissions now live in `.claude/settings.local.json`.

## Main flow

1. `parse_args` — populate globals `g_name`, `g_agent` (default `claude`),
   `g_fresh` (`0`/`1`).
2. `preflight` — `command -v` for `tmux`, the selected agent's binary, and
   `python3`; assert `$SB_PROJECTS_DIR` exists and the template file exists. All
   checks run before any side effect.
3. `target = $PROJECTS_DIR/$g_name`.
4. **Live session?** `tmux has-session -t <name>` succeeds → `exec tmux attach -t
   <name>` (warm resume). `--fresh` does not apply to an already-running agent.
5. **Cold launch** (no live tmux session):
   - `ensure_scaffolding(target)` — `mkdir -p target/.claude`; copy the template
     `settings.local.json` if absent. **No `.iteration` file.**
   - Compute session id:
     - stable (default): `uuid5(NAMESPACE_URL, "sb:" + name)`.
     - `--fresh`: `uuid4()` — random, one-off, not persisted. The next plain
       `sb <name>` returns to the stable id.
   - `tmux new-session -d -s <name> -c target`.
   - `tmux send-keys -t <name> "<agent> --session-id <uuid>" Enter`.
   - Print detach hint to stderr: `sb: detached with Ctrl-b d · resume with: sb <name>`.
   - `exec tmux attach -t <name>`.

### Collision & resume behavior

| State | Outcome |
|---|---|
| tmux `<name>` live | attach — warm resume |
| `~/Projects/<name>` exists, no tmux | resume: stable id, scaffold only what is missing, relaunch agent |
| `~/Projects/<name>` missing | create dir + template, launch with stable id |
| any of the above + `--fresh` | cold path uses a random session id instead of the stable one |

Existing-directory handling is silent (no prompt): exists → open/resume; missing →
create.

## Agent abstraction

Single source of truth — one `case` statement (bash-3.2-safe; no associative
arrays). Adding an agent is one new arm here.

```bash
# Bare binary name for an agent; dies on unknown.
agent_binary() {
  case "$1" in
    claude) printf 'claude' ;;
    gemini) printf 'gemini' ;;
    *) die "unknown agent '$1' (valid: claude, gemini)" 2 ;;
  esac
}
```

`main` composes the launch command as
`"$(agent_binary "$g_agent") --session-id $uuid"`.

**Documented assumption:** all supported agents accept `--session-id <uuid>` (true
for both Claude Code and gemini-cli). If a future agent diverges, that single arm
grows to carry its own flags. `claude` is the default and primary path; `gemini`
works for anyone with gemini-cli installed (otherwise preflight fails cleanly with
"gemini not found on PATH").

## Session id derivation

- stable: `python3 -c 'import sys, uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "sb:" + sys.argv[1]))' "$name"`
  — namespace string changes from `pp:` to `sb:`, derived from the project name
  (not `name-NN`, since iterations are gone).
- fresh: `python3 -c 'import uuid; print(uuid.uuid4())'`.

## Filesystem & environment

- `SB_PROJECTS_DIR` — where projects live (default `$HOME/Projects`). Renamed from
  `PPL_PROJECTS_DIR`.
- `SB_HOME` — resolved repo root, used to find the template. Renamed from
  `PPL_HOME`.
- `template/settings.local.json`:

  ```json
  {
    "permissions": {
      "defaultMode": "acceptEdits"
    }
  }
  ```

  Permissions only — zero skills.
- Per-project `~/Projects/<name>/.claude/settings.local.json` — copied once from
  the template, never overwritten. No `.iteration` file.

## Error handling

- `die "<msg>" [code]` → writes `sb: <msg>` to stderr (prefix changes `ppl:` →
  `sb:`), exits with `code` (default 1).
- Exit codes: usage / unknown-flag / invalid-agent → 2; invalid name / missing
  template / missing projects dir → 1.
- No partial side effects on bad input — every validation precedes scaffolding and
  tmux. Preserves the guarantee the current tests assert.

## Build-time verification (not a design fork)

Confirm `<agent> --session-id <known-uuid>` *resumes* an existing session rather
than erroring when the id already exists. The current tool already relies on this
for Claude; the same assumption is carried to Gemini.

## Testing (bats, Linux + macOS CI)

Harness: rename `PPL_*` → `SB_*` in `test/helpers/common.bash` (`SB_REPO_ROOT`,
`SB_PROJECTS_DIR`, `SB_STUB_LOG`, `SB_STUB_TMUX_SESSION_EXISTS`). Keep the tmux and
claude stubs; add a gemini stub (same shape — log argv to `$SB_STUB_LOG`, exit 0).

Integration tests:

- fresh project → creates dir + `settings.local.json` from template; `tmux
  new-session -s <name>`; `send-keys 'claude --session-id <stable-uuid>'`; attach.
  No `.iteration` assertions.
- existing dir, no tmux → resumes with the **same stable uuid**, scaffolds nothing
  new.
- live tmux → attach only; no `new-session`, no `send-keys`.
- `--fresh` → `--session-id` present, valid UUID, and **≠ stable uuid**.
- `--agent gemini` → launches `gemini --session-id …` (gemini stub on PATH).
- `--agent bogus` → exit 2, "unknown agent", no side effects.
- invalid name → exit 1, no dir created.
- missing template → exit 1.
- detach hint printed on cold launch (assert on stderr).
- flag-before and flag-after positional both work.

Unit tests:

- `derive_uuid` returns the known uuid5 for `"sb:<name>"` (recomputed expected
  value).
- `validate_name` accepts valid slugs, rejects invalid.
- `agent_binary` returns `claude` / `gemini`, dies on unknown.
- `ensure_scaffolding` is idempotent and creates **no** `.iteration`.

Deleted tests: all permission-mode/picker tests, all `.iteration`-bump tests, all
`pp-` prefix tests.

## Docs & build

- **README.md** rewritten for springboard/sb: what it does, install (symlink
  `bin/sb`), config (`SB_PROJECTS_DIR`), agents (`--agent`, default claude, gemini
  needs gemini-cli), sessions (resume-by-default, `--fresh`, detach `Ctrl-b d`),
  simplified behavior matrix, template note ("permissions only — add skills
  per-project yourself"), layout, license.
- **Makefile / CI** — update lint paths `bin/ppl` → `bin/sb`; CI still runs `make
  check` on ubuntu + macos.
- Prior `docs/superpowers/` pp-launcher docs remain as historical record; this
  spec lands beside them.

## Repo rename & migration (separate; confirm before acting)

- Rename the GitHub repo `printing-press-launcher` → `springboard`, update the
  `origin` remote, and rename the local working directory. Outward-facing /
  hard-to-reverse — done only on explicit go-ahead, with exact commands shown
  first, likely as the final step.
- Re-link the binary: `ln -sf …/springboard/bin/sb ~/.local/bin/sb`. The old `ppl`
  symlink is the user's to remove.
- Existing `~/Projects/pp-*` projects are untouched — `sb` simply stops prefixing.
  `sb numista` opens `~/Projects/numista`, not `pp-numista`. Noted in the README.
- The repo's own `.claude/settings.local.json` (dev permissions, with skills) is
  left alone — only `template/settings.local.json` is stripped to permissions-only.
