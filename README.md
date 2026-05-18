# ppl (printing-press-launcher)

![CI](https://github.com/vinnyp/printing-press-launcher/actions/workflows/ci.yml/badge.svg)

> Previously named `pp`. Renamed to `ppl` to avoid collision with PAR Packager (`/usr/bin/pp`).

`ppl <name>` — bootstraps and resumes Claude Code projects intended for the [cli-printing-press](https://github.com/mvanhorn/cli-printing-press/) workflow.

## What it does

```
ppl parcel
```

1. Validates the name and checks that `tmux`, `claude`, and `python3` are on `PATH`.
2. If a tmux session named `pp-parcel` is already running, attaches to it immediately. No disk writes. Done.
3. Otherwise, ensures `$PPL_PROJECTS_DIR/pp-parcel/` (default `~/Projects/pp-parcel/`) exists with `.claude/settings.local.json` copied from the canonical [template](template/settings.local.json) and a `.iteration` counter.
4. Bumps `.iteration`, starts a new tmux session `pp-parcel`, and inside it launches:

   ```
   claude --permission-mode dontAsk -n pp-parcel-NN --session-id <deterministic-uuid>
   ```

   The session ID is a UUIDv5 derived from `pp:pp-parcel-NN`, so the same iteration is always the same Claude session — a killed tmux can be revived by re-running `ppl parcel` after rolling `.iteration` back by hand.

The full design lives in [`docs/superpowers/specs/2026-05-17-pp-launcher-design.md`](docs/superpowers/specs/2026-05-17-pp-launcher-design.md).

## Install

```bash
# Clone wherever you keep your tools
git clone <this-repo> /path/to/printing-press-launcher
ln -sf /path/to/printing-press-launcher/bin/ppl ~/.local/bin/ppl
```

Make sure `~/.local/bin` is on `PATH`; `ppl` is then available in every shell.

Requirements on `PATH`: `tmux`, `claude`, `python3`. macOS without GNU coreutils may need `brew install coreutils` — `bin/ppl` uses `readlink -f` to resolve its own symlinked location.

## Configuration

By default, `ppl <name>` creates projects under `~/Projects/`. Override with the `PPL_PROJECTS_DIR` env var:

```bash
export PPL_PROJECTS_DIR="$HOME/code"   # e.g. in your shell rc
ppl <name>                             # now creates ~/code/pp-<name>
```

## Permissions

By default, `ppl` launches Claude with `--permission-mode dontAsk`. Override per-invocation with `-p` / `--permissions`:

```bash
ppl <name> -p plan                    # plan mode
ppl <name> --permissions=acceptEdits  # accept-edits mode
ppl <name> -p auto                    # auto mode
ppl <name> -p                         # interactive picker (TTY only)
```

Valid modes: `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`.

The flag follows a strict rule: `-p` always consumes the next argument as the mode value when one is present. To launch the picker, put `-p` as the last argument (`ppl <name> -p`). On non-TTY stdin, the picker is unavailable and bare `-p` errors out.

If your project name collides with a mode (`plan`, `default`, `auto`):
- `ppl plan` works directly with the `dontAsk` default.
- `ppl plan -p` launches the picker for the project named `plan`.
- `ppl -p dontAsk plan` is an explicit form.

## Development

```bash
make help    # list targets
make lint    # shellcheck
make test    # bats
make check   # both (what CI runs)
```

Prerequisites (dev only): `shellcheck`, `bats-core`. On macOS: `brew install shellcheck bats-core coreutils`. On Debian/Ubuntu: `sudo apt-get install -y shellcheck bats`.

CI runs `make check` on both `ubuntu-latest` and `macos-latest` on every push and pull request.

## Customizing per-project settings

Edit [`template/settings.local.json`](template/settings.local.json). Every subsequent `ppl <name>` run copies it into the new project's `.claude/`. Existing projects keep whatever was copied at their creation time.

## Behavior matrix

| Project dir | `.claude/` scaffolding | tmux session | Outcome |
|---|---|---|---|
| any | any | running | `tmux attach` — no Claude relaunch |
| missing | n/a | not running | create dir + template + `.iteration=0`, bump to `1`, launch iter `01` |
| exists | missing | not running | scaffold in place, `.iteration=0`, bump to `1`, launch iter `01` |
| exists | present | not running | bump `.iteration`, launch next iter |

Name is auto-prefixed with `pp-` if not already present. `ppl <name>` and `ppl pp-<name>` are equivalent. Names must match `^[a-z0-9-]+$`.

## Layout

```
ppl/
├── bin/ppl                         # the launcher
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

## License

[MIT](LICENSE) © Vinny Pasceri.
