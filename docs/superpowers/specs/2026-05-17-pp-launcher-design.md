# `pp` launcher — design

**Date:** 2026-05-17
**Status:** Implemented

## Purpose

A single shell command, `pp <name>`, that bootstraps and resumes Claude Code projects intended for the [`cli-printing-press`](https://github.com/mvanhorn/cli-printing-press/) workflow. Running `pp parcel` should always land me in a working tmux + Claude session for `~/Projects/pp-parcel`, whether it's the first run or the tenth.

## Goals

- **One command, one mental model.** `pp <name>` works from any cwd.
- **Idempotent.** Re-running attaches to an existing session if one is alive; otherwise starts the next iteration.
- **Resumable.** Each `<slug>-NN` iteration maps to a deterministic Claude `--session-id`, so a killed tmux can be revived by re-running the same iteration.
- **Single source of truth** for the Claude permission template — edit once, applied to every new project.

## Non-goals (v1)

- `git init` / initial commit
- Seeded `CLAUDE.md`
- Auto-invoking the `/printing-press` skill on iteration 01
- Cross-machine sync, dotfiles integration, package install

All easy to add later; deliberately scoped out to keep v1 small.

## Repository layout

This `pp-setup` repo becomes the home of the tool:

```
~/Projects/pp-setup/
├── bin/pp                          # the launcher script
├── template/
│   └── settings.local.json         # canonical Claude settings, copied into each new project
├── docs/superpowers/
│   ├── specs/                      # design docs
│   └── plans/                      # implementation plans
└── README.md                       # usage + install
```

**Cleanup:** the existing `main.py`, `pyproject.toml`, and `.python-version` are leftover `uv init` scaffolding and will be deleted as part of the implementation.

## Install

One-time, after cloning this repo:

```bash
ln -sf /path/to/pp-setup/bin/pp ~/.local/bin/pp
```

`~/.local/bin` must be on `PATH`. To create projects somewhere other than `~/Projects`, export `PP_PROJECTS_DIR=/some/other/dir`.

The template is seeded once from an existing project's `.claude/settings.local.json`, then committed to this repo. After install, edits to `template/settings.local.json` are the only place to change the per-project Claude permissions.

## Command contract

```
pp <name>
```

- `<name>` may or may not include the `pp-` prefix. `pp parcel` and `pp pp-parcel` both target `~/Projects/pp-parcel`.
- Post-prefix, the slug must match `^[a-z0-9-]+$`. Anything else is rejected with a usage message.
- No flags in v1. `pp` with no args prints usage and exits non-zero.

## Algorithm

Let `PROJECTS_DIR = ${PP_PROJECTS_DIR:-$HOME/Projects}`, `slug` = `pp-<name>` (or the input if already prefixed), and `target = $PROJECTS_DIR/$slug`.

1. **Preflight.** Verify `tmux`, `claude`, `python3` are on `PATH`. Verify `$PROJECTS_DIR` and the template file exist. Any failure → clear error, no side effects.
2. **Validate** the slug against `^[a-z0-9-]+$`.
3. **Live-attach short-circuit.** If `tmux has-session -t $slug` succeeds, `tmux attach -t $slug` and exit. Pure resume — no scaffolding, no iteration bump.
4. **Ensure scaffolding** (idempotent — handles fresh projects and existing-but-empty directories alike):
   - `mkdir -p $target/.claude`
   - If `$target/.claude/settings.local.json` is missing, copy from `~/Projects/pp-setup/template/settings.local.json`. Never overwrite.
   - If `$target/.claude/.iteration` is missing, write `0`.
5. **Bump iteration.** Read the integer from `.iteration`, add 1, write it back. That value is `iter`.
6. Compute:
   - `session_name = "${slug}-$(printf '%02d' $iter)"` — e.g. `pp-parcel-03`
   - `session_uuid = $(python3 -c "import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, 'pp:$session_name'))")`
7. **Launch:**
   - `cd $target`
   - `tmux new-session -d -s $slug -c $target`
   - `tmux send-keys -t $slug "claude --permission-mode dontAsk -n $session_name --session-id $session_uuid" Enter`
   - `tmux attach -t $slug`

The reorganization (live-attach first, then ensure-scaffolding, then bump) means iteration `01` is the first launch regardless of whether the directory pre-existed empty or `pp` created it — a fresh project and an empty-but-existing one converge on the same state.

## State and files

| Path | Purpose | Owner |
|------|---------|-------|
| `<pp-setup>/bin/pp` | Launcher script | this repo |
| `<pp-setup>/template/settings.local.json` | Canonical Claude permissions | this repo, edited by hand |
| `$PROJECTS_DIR/pp-<name>/.claude/settings.local.json` | Per-project copy of the template | written by `pp` |
| `$PROJECTS_DIR/pp-<name>/.claude/.iteration` | Integer iteration counter | written by `pp` |
| `~/.local/bin/pp` | Symlink to `bin/pp` | install step |

`.iteration` is plain text holding a single integer. Editable by hand to override the next iteration number.

## Why a deterministic UUID

Claude's `--session-id` requires a UUID. By deriving it from `session_name` (`pp-parcel-03`) via UUIDv5, the same iteration is always the same session — if tmux gets killed mid-iteration, re-running `pp parcel` (with `.iteration` rolled back manually) lands me in the exact same Claude session. Without determinism, every relaunch would be a new history.

`python3` is the cleanest tool for v5 — `uuidgen` is v4 only, and Python ships on macOS.

## Error handling

All errors print a one-line reason and exit non-zero. No partial state:

- Missing dependency (`tmux`/`claude`/`python3`) → `pp: <name> not found on PATH`
- Missing template → `pp: template missing at <path> — see README`
- Invalid slug → `pp: invalid name, must match ^[a-z0-9-]+$`
- No args → usage to stderr, exit 2

The "create dir + copy template + write iteration" steps in the fresh-project branch happen in that order; if any fail the user can re-run after fixing — the next run will see whichever state landed and continue from there.

## Behavior matrix

| Project dir | `.claude/` scaffolding | tmux session `$slug` | Outcome |
|---|---|---|---|
| any | any | running | `tmux attach` only, no Claude relaunch |
| missing | n/a | not running | create dir + template + `.iteration=0`, bump to `1`, launch iter `01` |
| exists | missing | not running | scaffold in place, `.iteration=0`, bump to `1`, launch iter `01` |
| exists | present | not running | bump `.iteration`, launch next iter |

## Testing plan

Manual verification on a throwaway slug (`pp test123`):

1. First run from clean state → directory, `.claude/`, template, `.iteration=1`, tmux session attached, Claude running with `-n pp-test123-01`.
2. Detach (`prefix + d`), re-run `pp test123` → immediately reattaches, no new iteration.
3. `tmux kill-session -t pp-test123`, re-run `pp test123` → `.iteration` becomes `2`, new Claude session named `pp-test123-02`.
4. Edit `template/settings.local.json`, create a new project → confirm the edit propagated to the new project's settings.
5. Invalid name (`pp 'foo bar'`) → rejected, no files created.
6. `rm -rf $PROJECTS_DIR/pp-test123` when done.

## Open questions / future work

- Should `.iteration` ever be checked into the project's git history? Currently it lives under `.claude/` which is typically gitignored — fine.
- A `--resume <NN>` flag to revisit an earlier iteration without bumping the counter.
- A `--new` flag to force a new iteration even when tmux is alive.
- Optional `git init` and seeded `CLAUDE.md` (already discussed, deferred).
