# pp-setup

`pp <name>` — bootstraps and resumes Claude Code projects intended for the [cli-printing-press](https://github.com/mvanhorn/cli-printing-press/) workflow.

## What it does

```
pp parcel
```

1. Validates the name and checks that `tmux`, `claude`, and `python3` are on `PATH`.
2. If a tmux session named `pp-parcel` is already running, attaches to it immediately. No disk writes. Done.
3. Otherwise, ensures `$PP_PROJECTS_DIR/pp-parcel/` (default `~/Projects/pp-parcel/`) exists with `.claude/settings.local.json` copied from the canonical [template](template/settings.local.json) and a `.iteration` counter.
4. Bumps `.iteration`, starts a new tmux session `pp-parcel`, and inside it launches:

   ```
   claude --permission-mode dontAsk -n pp-parcel-NN --session-id <deterministic-uuid>
   ```

   The session ID is a UUIDv5 derived from `pp:pp-parcel-NN`, so the same iteration is always the same Claude session — a killed tmux can be revived by re-running `pp parcel` after rolling `.iteration` back by hand.

The full design lives in [`docs/superpowers/specs/2026-05-17-pp-launcher-design.md`](docs/superpowers/specs/2026-05-17-pp-launcher-design.md).

## Install

```bash
# Clone wherever you keep your tools
git clone <this-repo> /path/to/pp-setup
ln -sf /path/to/pp-setup/bin/pp ~/.local/bin/pp
```

Make sure `~/.local/bin` is on `PATH`; `pp` is then available in every shell.

Requirements on `PATH`: `tmux`, `claude`, `python3`. macOS without GNU coreutils may need `brew install coreutils` — `bin/pp` uses `readlink -f` to resolve its own symlinked location.

## Configuration

By default, `pp <name>` creates projects under `~/Projects/`. Override with the `PP_PROJECTS_DIR` env var:

```bash
export PP_PROJECTS_DIR="$HOME/code"   # e.g. in your shell rc
pp parcel                              # now creates ~/code/pp-parcel
```

## Customizing per-project settings

Edit [`template/settings.local.json`](template/settings.local.json). Every subsequent `pp <name>` run copies it into the new project's `.claude/`. Existing projects keep whatever was copied at their creation time.

## Behavior matrix

| Project dir | `.claude/` scaffolding | tmux session | Outcome |
|---|---|---|---|
| any | any | running | `tmux attach` — no Claude relaunch |
| missing | n/a | not running | create dir + template + `.iteration=0`, bump to `1`, launch iter `01` |
| exists | missing | not running | scaffold in place, `.iteration=0`, bump to `1`, launch iter `01` |
| exists | present | not running | bump `.iteration`, launch next iter |

Name is auto-prefixed with `pp-` if not already present. `pp parcel` and `pp pp-parcel` are equivalent. Names must match `^[a-z0-9-]+$`.

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
