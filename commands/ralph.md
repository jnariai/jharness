---
description: Run the ralph orchestrator over a phase document — one fresh agent session per phase, four mechanical gates, one commit per completed phase. Launches scripts/ralph.sh unattended and reports; never writes application code itself.
argument-hint: "[path-to-phases-file] [--engine claude|codex] [--from N] [--max-cycles N] [--test-cmd \"<cmd>\"] [--keep-going] [--no-verify] [--dashboard] [--print]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# ralph

You are the launcher for `scripts/ralph.sh`. You resolve the input, verify the
preconditions the script would abort on, start the run, and report. You never
implement phases yourself — `ralph.sh` owns every session, every gate and every
commit.

## Objective

Execute a phase document autonomously. Each phase becomes a new engine session
with a self-contained prompt; a phase is only complete when it passes four
mechanical gates; each completed phase lands as one commit.

## Input — `$ARGUMENTS`

```
$ARGUMENTS
```

| Token | Meaning |
|---|---|
| path | the phase document to execute |
| (no path) | let `ralph.sh` resolve: `.spec/init/project-phases.md`, then `.spec/project-phases.md` |
| `--engine claude\|codex` | implementation engine (default here: `claude`) |
| `--from N` | start at phase N (clears progress for phases >= N) |
| `--max-cycles N` | fix cycles per phase (default 3) |
| `--test-cmd "<cmd>"` | gate 2 test command |
| `--keep-going` | continue after a phase fails |
| `--no-verify` | turn gate 3 off |
| `--dashboard` | live panel in the terminal (foreground only) |
| `--print` | do not run — print the exact command line and stop |

Every flag other than `--print` is passed to `ralph.sh` verbatim. `--print` is
this command's own flag and is never forwarded.

**Engine default**: `ralph.sh` alone defaults to `codex`. This command defaults
to `--engine claude`, because that engine emits per-task progress. If the
developer passes `--engine` explicitly, honor it.

## Preconditions

Check these before launching. Each maps to an abort inside `ralph.sh` — catching
them here costs nothing, catching them there costs a confusing exit.

| Check | Command | On failure |
|---|---|---|
| git repo | `git rev-parse --is-inside-work-tree` | stop: ralph commits per phase and requires a repo |
| clean tree | `git status --porcelain` | stop and show the dirty files: ralph's `git add -A` would swallow them |
| phase document exists | `test -f <path>` | stop, name the resolution order, suggest `/init:project-phases` |
| format contract | `grep -cE '^## Phase [0-9]+: ' <path>` >= 1, and no `^## Phase` line outside that shape | stop and list the malformed headings — a crooked heading silently disappears from the run |
| engine CLI present | `command -v claude` / `command -v codex` | stop with the install line for that engine |

Report every failed check in one message, with the fix, and do not launch.

Do not re-implement the script's other preflight logic (test-command detection,
Sail containers, `--from` bounds). `ralph.sh` owns those and aborts with
actionable messages of its own.

## Script path

The script ships with the plugin:

```
${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh
```

Use that path. Fall back to a repo-local `scripts/ralph.sh` only when the plugin
path does not resolve, and say which one you used.

`ralph-watch.sh` must sit next to the script for `--dashboard` to work; it does
in the plugin. When it does not, `ralph.sh` warns and degrades to log mode.

## Flow

### 1 — Resolve and confirm

Parse `$ARGUMENTS`. Resolve the path (or let the script resolve it — then say
which file it will pick, from the same order). Build the full command line.

Count the phases (`grep -cE '^## Phase [0-9]+: '`) and state, in two lines,
what is about to happen: how many phases, which engine, which document, whether
progress from a previous run exists (`.phases/.progress`).

This is an unattended run that writes code and commits. Show the command line
and get the developer's go-ahead before starting it — unless they already said
to run it without asking, or passed `--print`.

With `--print`: output the command line, say nothing else, stop.

### 2 — Launch

Run in the background, with output captured:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" --engine claude <flags> <path> \
  > .phases/logs/ralph.run.log 2>&1
```

Use `run_in_background: true`. A run spans hours: never run it in the foreground,
and never wrap it in a timeout.

Do not pass `--dashboard` to a background run — the panel needs a real terminal.
If the developer asked for `--dashboard`, do not launch: print the command line
and tell them to run it in their own terminal, since the panel owns the screen.

### 3 — Report while it runs

State is always published to `.phases/state/run.tsv`, with or without a panel.
Read it when the developer asks how the run is going, or when the background
task reports it exited:

| Row | Meaning |
|---|---|
| `META status` | `running` \| `waiting` (usage limit) \| `finished` \| `failed` |
| `META phase_cur` / `cycle` / `gate` / `activity` | where the run is right now |
| `PHASE <n> <status> <attempt> <g0 g1 g2 g3> <title>` | per phase |
| `TASK <phase> <n> <status> <title>` | per task |

Tell the developer they can watch it live from another terminal:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/ralph-watch.sh" <repo-path>
```

Do not poll in a loop. Report on request, and when the run ends.

### 4 — Final report

On exit, read `.phases/state/run.tsv` and the tail of `.phases/logs/ralph.run.log`,
then report:

- exit code (0 = every phase green; 1 = something failed or aborted)
- completed / skipped / failed phases, by title
- for each failed phase: the gate that failed and the one-line cause, plus the
  log path `.phases/logs/phase-NN.*`
- whether partial work is sitting in the tree — if so, repeat the script's own
  instruction: commit it (ralph re-validates the phase on the next run) or
  `git checkout -- . && git clean -fd` to discard

## Hard rules

- **Never implement a phase yourself.** If a phase fails after its cycles, report
  it. Fixing it by hand is the developer's call, not this command's.
- **Never commit, revert or reset.** `ralph.sh` is the only thing that commits
  here, one commit per validated phase.
- **Never edit the phase document** to get past a format abort. Report the
  malformed headings and let the developer (or `/plan`) fix the source.
- **Never re-run a failed run automatically.** Progress is on disk; a re-run
  resumes from it, and that decision is the developer's.
- The run is unattended and the engine sessions run with permissions skipped.
  Say so once, at launch, when the working tree is not on a disposable branch.
