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
(`claude` and/or `agy`), `python3`. macOS without GNU coreutils may need
`brew install coreutils` — `bin/sb` uses `readlink -f` to resolve its own symlink.

## Agents

`sb` launches `claude` by default. Choose another agent with `--agent`:

```bash
sb numista --agent agy
```

Supported: `claude` (launched with `--session-id <uuid>`) and `agy`
(antigravity-cli, launched with `--conversation <uuid>`). Each agent carries its
own session flag, so the same stable id resumes a project regardless of agent. The
chosen agent must be installed and on `PATH` (e.g. `--agent agy` requires
antigravity-cli). Adding a new agent is a one-line entry in `agent_cmd` in `bin/sb`.

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
