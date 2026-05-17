# `pp` launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `pp <name>` shell command that bootstraps and resumes Claude Code projects on per-iteration tmux sessions, idempotent across re-runs.

**Architecture:** Single Bash script at `bin/pp` symlinked into `~/.local/bin/`. Each run validates the slug, short-circuits to `tmux attach` if a live session exists, otherwise scaffolds the project from a canonical template at `template/settings.local.json`, bumps a `.iteration` counter, derives a deterministic UUID for `claude --session-id`, and launches Claude inside a fresh tmux session.

**Tech Stack:** Bash, `tmux`, `claude` CLI, `python3` (for UUIDv5).

**Spec:** [`docs/superpowers/specs/2026-05-17-pp-launcher-design.md`](../specs/2026-05-17-pp-launcher-design.md). Read it before starting — the algorithm, behavior matrix, and error-handling rules are the contract.

**Conventions for this plan:**
- Working directory for all commands: the cloned `pp-setup` repo.
- "Manually verify" steps are inspection commands you can paste in another shell. No automated test suite — the spec's Testing plan is the acceptance check, run end-to-end in Task 5.

---

## File Structure

| Path | Action | Purpose |
|---|---|---|
| `main.py` | Delete | leftover uv scaffolding |
| `pyproject.toml` | Delete | leftover uv scaffolding |
| `.python-version` | Delete | leftover uv scaffolding |
| `.gitignore` | Modify | drop python-specific entries, keep generic ones |
| `template/settings.local.json` | Create | canonical Claude permissions |
| `bin/pp` | Create | the launcher script |
| `README.md` | Modify | usage + install instructions |

---

## Task 1: Remove uv scaffolding

**Files:**
- Delete: `main.py`, `pyproject.toml`, `.python-version`
- Modify: `.gitignore`

- [ ] **Step 1: Inspect what's there**

Run: `cat .gitignore main.py pyproject.toml .python-version`

Expected: `.gitignore` is python-flavored (mentions `__pycache__`, `.venv`, etc.); the other three are minimal `uv init` output.

- [ ] **Step 2: Delete the uv scaffolding files**

Run: `rm main.py pyproject.toml .python-version`

- [ ] **Step 3: Replace `.gitignore` with a minimal version**

Overwrite `.gitignore` with:

```
.DS_Store
*.swp
*.bak
.claude/settings.local.json
```

(No Python venvs to ignore anymore; keep the macOS/editor noise. The last line keeps Vinny's per-developer Claude permissions for *this* repo out of git — distinct from `template/settings.local.json`, which is the canonical file that *gets* committed.)

- [ ] **Step 4: Verify the working tree**

Run: `ls -la`

Expected: no `main.py`, no `pyproject.toml`, no `.python-version`. `README.md`, `.gitignore`, `.claude/`, `docs/`, `.git/` remain.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove uv init scaffolding"
```

---

## Task 2: Seed the settings template

**Files:**
- Create: `template/settings.local.json`

- [ ] **Step 1: Create the template directory**

Run: `mkdir -p template`

- [ ] **Step 2: Copy the canonical settings from an existing project**

Run: `cp /path/to/source-project/.claude/settings.local.json template/settings.local.json`

(One-time seed from any existing project's `.claude/settings.local.json`. Once committed, no future user needs to repeat this step — the template lives in the repo.)

- [ ] **Step 3: Verify the contents**

Run: `cat template/settings.local.json`

Expected: a JSON object with a `permissions.allow` array containing `"Bash"`, `"Write"`, several `"Skill(...)"` entries including `Skill(cli-printing-press:printing-press)`, etc.

- [ ] **Step 4: Commit**

```bash
git add template/settings.local.json
git commit -m "feat: seed canonical settings.local.json template"
```

---

## Task 3: Launcher script — preflight, validation, scaffolding

This task lands a runnable `bin/pp` that handles everything up to (but not including) tmux/claude launch. After this task, `pp parcel` should create `~/Projects/pp-parcel/.claude/{settings.local.json,.iteration}` and print what it *would* launch, then exit.

**Files:**
- Create: `bin/pp`

- [ ] **Step 1: Create `bin/` and stub the script**

Run: `mkdir -p bin`

Create `bin/pp` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve this script's own dir so we can find the template no matter how `pp` is invoked.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PP_HOME="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$PP_HOME/template/settings.local.json"
PROJECTS_DIR="${PP_PROJECTS_DIR:-$HOME/Projects}"

die()   { printf 'pp: %s\n' "$*" >&2; exit 1; }
usage() { printf 'usage: pp <name>\n' >&2; exit 2; }

preflight() {
    command -v tmux    >/dev/null 2>&1 || die "tmux not found on PATH"
    command -v claude  >/dev/null 2>&1 || die "claude not found on PATH"
    command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH"
    [[ -d "$PROJECTS_DIR" ]] || die "$PROJECTS_DIR does not exist"
    [[ -f "$TEMPLATE" ]]     || die "template missing at $TEMPLATE — see README"
}

compute_slug() {
    local name="$1"
    if [[ "$name" == pp-* ]]; then
        printf '%s' "$name"
    else
        printf 'pp-%s' "$name"
    fi
}

validate_slug() {
    local slug="$1"
    [[ "$slug" =~ ^[a-z0-9-]+$ ]] || die "invalid name, must match ^[a-z0-9-]+\$ (got: $slug)"
}

main() {
    [[ $# -eq 1 ]] || usage
    preflight
    local slug; slug="$(compute_slug "$1")"
    validate_slug "$slug"
    local target="$PROJECTS_DIR/$slug"
    printf 'pp: slug=%s target=%s\n' "$slug" "$target"
}

main "$@"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x bin/pp`

- [ ] **Step 3: Manually verify validation**

Run each and confirm:

| Command | Expected |
|---|---|
| `./bin/pp` | prints `usage: pp <name>` to stderr, exits 2 |
| `./bin/pp 'foo bar'` | prints `pp: invalid name, must match ...`, exits 1 |
| `./bin/pp parcel` | prints `pp: slug=pp-parcel target=$HOME/Projects/pp-parcel` (with `$HOME` expanded), exits 0 |
| `./bin/pp pp-parcel` | same as above — no double-prefixing |

- [ ] **Step 4: Add the live-attach short-circuit**

Insert a helper above `main()`:

```bash
tmux_session_alive() {
    tmux has-session -t "$1" 2>/dev/null
}
```

Add this block in `main()` after `validate_slug`, before the final `printf`:

```bash
    if tmux_session_alive "$slug"; then
        cd "$target"
        exec tmux attach -t "$slug"
    fi
```

(No tmux session exists yet for `pp-parcel`, so this is dormant code until Task 4 lands the launch path. We add it here so the order matches the spec algorithm.)

- [ ] **Step 5: Add the scaffolding helper**

Insert above `main()`:

```bash
ensure_scaffolding() {
    local target="$1"
    mkdir -p "$target/.claude"
    if [[ ! -f "$target/.claude/settings.local.json" ]]; then
        cp "$TEMPLATE" "$target/.claude/settings.local.json"
    fi
    if [[ ! -f "$target/.claude/.iteration" ]]; then
        printf '0\n' > "$target/.claude/.iteration"
    fi
}
```

Call it in `main()` after the live-attach block:

```bash
    ensure_scaffolding "$target"
```

Replace the final `printf` with a scaffolding-state report (temporary, removed in Task 4):

```bash
    printf 'pp: scaffolded %s (iteration=%s)\n' "$target" "$(cat "$target/.claude/.iteration")"
```

- [ ] **Step 6: Manually verify scaffolding on a throwaway slug**

`~/Projects/pp-parcel/` already exists but is empty. Use a fresh slug for this verification:

```bash
./bin/pp test-pp-scaffold
ls -la ~/Projects/pp-test-pp-scaffold/.claude/
cat ~/Projects/pp-test-pp-scaffold/.claude/.iteration
diff template/settings.local.json ~/Projects/pp-test-pp-scaffold/.claude/settings.local.json
```

Expected:
- `pp: scaffolded $HOME/Projects/pp-test-pp-scaffold (iteration=0)` (with `$HOME` expanded)
- The directory contains `.claude/settings.local.json` and `.claude/.iteration` containing `0`.
- `diff` exits 0 (template was copied verbatim).

- [ ] **Step 7: Verify idempotency on existing-but-empty `pp-parcel`**

```bash
./bin/pp parcel
ls -la ~/Projects/pp-parcel/.claude/
cat ~/Projects/pp-parcel/.claude/.iteration
```

Expected: `.claude/` is created, `settings.local.json` is copied, `.iteration` contains `0`. The pre-existing empty `~/Projects/pp-parcel/` is reused, not re-created.

- [ ] **Step 8: Clean up test scaffolds**

Run: `rm -rf ~/Projects/pp-test-pp-scaffold ~/Projects/pp-parcel`

(Removing `pp-parcel` too — Task 5 will recreate it as part of full end-to-end smoke testing.)

- [ ] **Step 9: Commit**

```bash
git add bin/pp
git commit -m "feat: pp launcher — preflight, validation, scaffolding"
```

---

## Task 4: Launcher script — iteration bump, UUID, tmux launch

After this task, `pp <name>` is fully functional: it bumps the iteration counter, derives a deterministic UUID, opens a tmux session, sends the Claude command, and attaches.

**Files:**
- Modify: `bin/pp`

- [ ] **Step 1: Add the iteration-bump helper**

Insert above `main()`:

```bash
bump_iteration() {
    local target="$1"
    local current; current="$(cat "$target/.claude/.iteration")"
    local next=$((current + 1))
    printf '%d\n' "$next" > "$target/.claude/.iteration"
    printf '%d' "$next"
}
```

- [ ] **Step 2: Add the UUIDv5 helper**

Insert above `main()`:

```bash
derive_uuid() {
    python3 -c 'import sys, uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "pp:" + sys.argv[1]))' "$1"
}
```

- [ ] **Step 3: Replace the temporary report line with the launch sequence**

In `main()`, replace:

```bash
    printf 'pp: scaffolded %s (iteration=%s)\n' "$target" "$(cat "$target/.claude/.iteration")"
```

with:

```bash
    local iter; iter="$(bump_iteration "$target")"
    local session_name; session_name="$(printf '%s-%02d' "$slug" "$iter")"
    local session_uuid; session_uuid="$(derive_uuid "$session_name")"

    cd "$target"
    tmux new-session -d -s "$slug" -c "$target"
    tmux send-keys -t "$slug" \
        "claude --permission-mode dontAsk -n $session_name --session-id $session_uuid" Enter
    exec tmux attach -t "$slug"
```

- [ ] **Step 4: Sanity-check UUID derivation**

Run:

```bash
python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "pp:pp-parcel-01"))'
python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, "pp:pp-parcel-01"))'
```

Expected: the same UUID printed twice (determinism). It should be a v5 UUID — the third hex group will start with `5`.

- [ ] **Step 5: Commit**

```bash
git add bin/pp
git commit -m "feat: pp launcher — iteration bump, deterministic UUID, tmux launch"
```

Full integration testing happens in Task 5 — don't attach to tmux/claude yet from inside this task's execution context.

---

## Task 5: Install symlink and end-to-end smoke test

This task installs `pp` onto your `PATH` and walks the entire Testing plan from the spec. After this task, `pp` is the canonical way to launch a `cli-printing-press` project.

**Files:**
- Create: `~/.local/bin/pp` (symlink)

- [ ] **Step 1: Install the symlink**

Run: `ln -sf ~/Projects/pp-setup/bin/pp ~/.local/bin/pp`

- [ ] **Step 2: Verify `pp` resolves on PATH**

Run: `which pp && pp` (no args)

Expected: `which` prints `$HOME/.local/bin/pp` (with `$HOME` expanded). The `pp` call with no args prints `usage: pp <name>` to stderr.

> **Note:** Steps 3–6 below launch real tmux sessions. After confirming each expected outcome, detach from tmux with `prefix + d` (default prefix is `Ctrl+B`, so `Ctrl+B` then `d`) before running the next step. Do **not** quit Claude — let the iteration counters reflect natural detach/reattach.

- [ ] **Step 3: Scenario 1 — fresh launch**

Run: `pp test123`

Expected:
- A tmux session named `pp-test123` is created and attached.
- Inside it, Claude is starting up with the prompt name `pp-test123-01`.
- On disk: `~/Projects/pp-test123/.claude/settings.local.json` exists and matches `template/settings.local.json`; `.iteration` contains `1`.

Verify on disk from another shell:

```bash
cat ~/Projects/pp-test123/.claude/.iteration
diff ~/Projects/pp-setup/template/settings.local.json ~/Projects/pp-test123/.claude/settings.local.json
```

Then detach: `Ctrl+B` then `d`.

- [ ] **Step 4: Scenario 2 — re-attach (idempotent)**

Run: `pp test123`

Expected: you are immediately attached back to the existing `pp-test123` tmux session. Same Claude session, same prompt name `pp-test123-01`. `.iteration` is still `1`.

Verify: `cat ~/Projects/pp-test123/.claude/.iteration` → `1`.

Detach again: `Ctrl+B` then `d`.

- [ ] **Step 5: Scenario 3 — next iteration**

Kill the tmux session: `tmux kill-session -t pp-test123`

Run: `pp test123`

Expected:
- A new tmux session `pp-test123` is created.
- Claude starts with prompt name `pp-test123-02`.
- `.iteration` is now `2`.

Verify: `cat ~/Projects/pp-test123/.claude/.iteration` → `2`.

Detach.

- [ ] **Step 6: Scenario 4 — template propagation**

In another shell:

```bash
cd ~/Projects/pp-setup
# Add a marker entry to the template
python3 -c 'import json, pathlib; p = pathlib.Path("template/settings.local.json"); d = json.loads(p.read_text()); d["permissions"]["allow"].append("Skill(pp-template-marker)"); p.write_text(json.dumps(d, indent=2) + "\n")'
```

Then run: `pp test456`

Verify the marker propagated:

```bash
grep pp-template-marker ~/Projects/pp-test456/.claude/settings.local.json
```

Expected: the grep finds the marker line in the new project. (The existing `pp-test123` keeps its old copy — by design.)

Detach from the `pp-test456` tmux session.

Revert the template marker:

```bash
cd ~/Projects/pp-setup
python3 -c 'import json, pathlib; p = pathlib.Path("template/settings.local.json"); d = json.loads(p.read_text()); d["permissions"]["allow"] = [x for x in d["permissions"]["allow"] if x != "Skill(pp-template-marker)"]; p.write_text(json.dumps(d, indent=2) + "\n")'
git diff template/settings.local.json
```

Expected: `git diff` shows no changes (the marker is gone, template is back to what was committed in Task 2).

- [ ] **Step 7: Scenario 5 — invalid name rejection**

Run: `pp 'foo bar'`

Expected: `pp: invalid name, must match ...` printed to stderr, exit code 1. No directory created.

Verify: `ls ~/Projects/ | grep foo` → no match.

- [ ] **Step 8: Scenario 6 — cleanup**

```bash
tmux kill-session -t pp-test123 2>/dev/null || true
tmux kill-session -t pp-test456 2>/dev/null || true
rm -rf ~/Projects/pp-test123 ~/Projects/pp-test456
tmux ls 2>/dev/null | grep -E 'pp-test(123|456)' && echo 'leftover!' || echo 'clean'
```

Expected: prints `clean`.

- [ ] **Step 9: Commit any fixes**

If you discovered bugs during smoke testing and fixed them in `bin/pp`, commit:

```bash
git add bin/pp
git commit -m "fix: <one-line summary of what smoke testing caught>"
```

If smoke testing surfaced no issues, skip this step.

---

## Task 6: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the empty README with usage docs**

Overwrite `README.md` with:

````markdown
# pp-setup

`pp <name>` — bootstraps and resumes Claude Code projects intended for the [cli-printing-press](https://github.com/mvanhorn/cli-printing-press/) workflow.

## What it does

```
pp parcel
```

1. Ensures `~/Projects/pp-parcel/` exists, with `.claude/settings.local.json` copied from the canonical [template](template/settings.local.json) and a `.iteration` counter.
2. If a tmux session named `pp-parcel` is already running, attaches to it. Done.
3. Otherwise, bumps `.iteration`, starts a new tmux session `pp-parcel`, and inside it launches:

   ```
   claude --permission-mode dontAsk -n pp-parcel-NN --session-id <deterministic-uuid>
   ```

   The session ID is a UUIDv5 derived from `pp:pp-parcel-NN`, so the same iteration is always the same Claude session — a killed tmux can be revived by re-running `pp parcel` after rolling `.iteration` back by hand.

The full design lives in [`docs/superpowers/specs/2026-05-17-pp-launcher-design.md`](docs/superpowers/specs/2026-05-17-pp-launcher-design.md).

## Install

```bash
git clone <this-repo> ~/Projects/pp-setup    # if not already there
ln -sf ~/Projects/pp-setup/bin/pp ~/.local/bin/pp
```

`~/.local/bin` is on `PATH` already; `pp` is then available in every shell.

Requirements on `PATH`: `tmux`, `claude`, `python3`.

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
~/Projects/pp-setup/
├── bin/pp                          # the launcher
├── template/settings.local.json    # canonical Claude permissions
├── docs/superpowers/
│   ├── specs/                      # design docs
│   └── plans/                      # implementation plans
└── README.md
```
````

- [ ] **Step 2: Verify the README renders cleanly**

Run: `cat README.md | head -50`

Expected: well-formed markdown, no `<` brackets in headings, no broken code fences.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: pp launcher usage and install"
```

---

## Done

Final state:
- `bin/pp` is executable and symlinked from `~/.local/bin/pp`.
- `template/settings.local.json` is the single source of truth for new-project Claude permissions.
- `README.md` documents usage, install, and the behavior matrix.
- All 6 scenarios from the spec's Testing plan have been verified end-to-end.
- The repo's git history has 6 small commits, one per task.
