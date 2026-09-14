---
description: Update jharness from its GitHub source and sync the harness coding guidelines into the current project (docs/agents/coding_guidelines.md). Never overwrites hand-edited guidelines without asking; never commits.
argument-hint: "[path] [--check] [--ref <branch|tag>] [--repo <git-url>] [--force] [--skip-plugin]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# update

You bring two things up to date from the harness's GitHub source:

1. **The harness itself** — the installed jharness plugin (commands, agents,
   scripts, guidelines), through Claude Code's own plugin updater.
2. **The project's convention layer** — the stack coding guidelines the harness
   ships (`guidelines/<stack>.md`), copied into the target project as
   `docs/agents/coding_guidelines.md`.

You orchestrate and report. `scripts/sync-guidelines.sh` owns every guidelines
decision; Claude Code's `claude plugin` CLI owns the plugin install.

## Input — `$ARGUMENTS`

```
$ARGUMENTS
```

| Token | Meaning |
|---|---|
| path | target project root (default: current working directory) |
| `--check` | report only — update nothing, write nothing |
| `--ref <branch\|tag>` | upstream ref to sync from (default: `main`) |
| `--repo <git-url>` | upstream repository (default: `https://github.com/jnariai/jharness.git`) — for forks |
| `--force` | overwrite a hand-edited `coding_guidelines.md` without asking |
| `--skip-plugin` | sync guidelines only; leave the installed plugin alone |

## Flow

### 1 — Resolve target

Resolve the target to an absolute path, then:

```bash
git -C <target> rev-parse --is-inside-work-tree
```

Fails → abort with `Target <path> is not a git repository — aborting.` Write
nothing. The guidelines land in the project's tree; git is what lets the
developer review and undo them.

### 2 — Fetch upstream

Clone the upstream into a throwaway directory. Full history is required — the
sync script uses it to prove a local copy is unedited.

```bash
SRC=$(mktemp -d)
git clone --quiet --branch <ref> <repo> "$SRC/jharness"
```

Clone fails → abort naming the repo, the ref, and git's one-line error. Write
nothing. Remove `$SRC` at the end of the run, on every path, including aborts
after this step.

Compare installed and upstream:

| Signal | Command |
|---|---|
| installed version | `version` in `${PLUGIN_ROOT}/plugin.json` |
| upstream version + commit | `version` in `$SRC/jharness/plugin.json`; `git -C "$SRC/jharness" rev-parse --short=12 HEAD` |
| content drift | `diff -rq --exclude=.git "${PLUGIN_ROOT}" "$SRC/jharness"` — empty = identical |

### 3 — Update the harness

Skip this step with `--check` (report the two versions only) or `--skip-plugin`.

Find the install: the `jharness@<marketplace>` entry in `claude plugin list --json`
gives the marketplace name and the scope. Not listed (e.g. loaded with
`--plugin-dir` from a local checkout) → do not touch it; say the plugin is not
managed by Claude Code, and that a local checkout updates with `git pull` in
`${PLUGIN_ROOT}`. Continue with step 4.

Listed, no content drift → `up to date`, continue with step 4.

Listed and the content drifts:

```bash
claude plugin marketplace update <marketplace>
claude plugin update jharness@<marketplace> --scope <scope>
```

- Either command fails → report its one-line error and continue with step 4.
  If it asks for confirmation it cannot get from a non-interactive shell, give
  the developer the line to run as `! claude plugin update jharness@<marketplace> --scope <scope>`.
- Success → the new version loads only after a restart. Say so in the summary.
- Content drifts but both versions are equal → the updater keys installs on
  `version`, so it may report nothing to do. Report that the upstream carries
  unreleased changes (the maintainer has not bumped `version`).

Never edit, pull, or copy files inside `${PLUGIN_ROOT}` or
`~/.claude/plugins/` by hand.

### 4 — Sync the coding guidelines

Run the **installed** script against the **fresh** upstream — never execute
scripts from the clone:

```bash
"${PLUGIN_ROOT}/scripts/sync-guidelines.sh" --source "$SRC/jharness" --check <target>
```

Output records: `STACK <id>|none`, `UPSTREAM <sha>`, `GUIDELINES <status> <path>`.

| `--check` status | Meaning | Action |
|---|---|---|
| `none` | the harness ships no guidelines for this stack | nothing to add; point at `/jharness:ai-context`, which documents the conventions the code already follows |
| `current` | byte-identical to upstream | nothing |
| `absent` | no `docs/agents/coding_guidelines.md` yet | add it (run without `--check`) → `seeded` |
| `outdated` | matches an older upstream revision exactly — never edited | show the diff (below), then refresh it (run without `--check`) → `updated` |
| `modified` | matches no upstream revision — edited by hand | show the diff, then ask (below) |

With `--check`, stop after reporting the status and the diff.

Diff, local vs upstream:

```bash
diff -u <target>/docs/agents/coding_guidelines.md \
  <("${PLUGIN_ROOT}/scripts/sync-guidelines.sh" --source "$SRC/jharness" --print-upstream <target>)
```

Show `diff --stat`-style counts (lines added/removed) plus the first ~80 lines of
the diff; offer the rest on request.

**`modified`** — with `--force`, run the script with `--force` (→ `forced`).
Otherwise ask with AskUserQuestion:

| Option | Effect |
|---|---|
| Keep mine (Recommended) | nothing written (→ `kept-modified`) |
| Write upstream beside it | write the `--print-upstream` output to `docs/agents/coding_guidelines.upstream.md` for a manual merge; the developer deletes it afterwards |
| Overwrite with upstream | run the script with `--force` — the local edits survive only in git |

### 5 — Wire-up check

When the status is anything but `none`, the project's agents must be told the
file is mandatory:

```bash
grep -Fq 'docs/agents/coding_guidelines.md' <target>/AGENTS.md
grep -Fq 'docs/agents/coding_guidelines.md' <target>/CLAUDE.md
```

Either missing → tell the developer to run `/jharness:ai-context +AGENTS +CLAUDE`,
which adds the mandatory-conventions block to `AGENTS.md` §2 and the pointer line
to `CLAUDE.md`. Do not write those files yourself.

### 6 — Summary

| Item | Result |
|---|---|
| harness | `updated <old> → <new> (restart to load)` / `up to date` / `unreleased upstream changes` / `skipped` / `not managed` / `failed: <cause>` |
| guidelines | `<status>` from the script, plus the stack id |
| wire-up | `ok` / `run /jharness:ai-context +AGENTS +CLAUDE` |

Close with: review with `git diff`, commit manually.

## Hard rules

- **No git writes** in the target — never stage, commit, or reset.
- **Only one project file** — `docs/agents/coding_guidelines.md`, plus
  `docs/agents/coding_guidelines.upstream.md` when the developer picks it. Nothing
  else in the project is written.
- **Hand-edited guidelines are never overwritten** without `--force` or the
  developer's explicit choice.
- **Never run code from the clone** — the clone is data; the installed plugin's
  script reads it.
- **Never hand-edit the plugin install** — updates go through `claude plugin`.
- **No secrets** — `.env` is never read.
