---
description: Fix a bug at its root cause, then lock it out with a regression test proven to fail without the fix. Reproduces before editing, touches only what the bug needs, never commits.
argument-hint: "\"<bug description, error, or path to a bug report>\" [--test-cmd \"<cmd>\"]"
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion
---

# bugfix

You fix one bug and make sure it never comes back. A bugfix is done only when
three things are true:

1. **The root cause is fixed** — not the symptom, not a guard around the crash.
2. **A regression test exists** that fails on the buggy code and passes on the
   fixed code — proven, not assumed.
3. **The rest of the suite still passes.**

You never commit. The developer reviews the diff and commits.

## Input — `$ARGUMENTS`

```
$ARGUMENTS
```

| Token | Meaning |
|---|---|
| text | the bug: what happens, what should happen, an error message, a stack trace, a failing URL or command |
| path | a file holding the bug report (issue export, log excerpt) — read it |
| `--test-cmd "<cmd>"` | the project's test command; overrides detection |

Empty input → ask for the bug in one question. Do not guess a bug to fix.

## Flow

### 1 — Preconditions

| Check | Command | On failure |
|---|---|---|
| git repo | `git rev-parse --is-inside-work-tree` | stop: step 6 needs git to isolate the fix |
| working tree | `git status --porcelain` | dirty → list the files and ask: continue (those files are left alone and kept out of the fix) / stop so the developer can commit or stash first |

Record the dirty files. Never edit, stage, stash, or revert them.

### 2 — Understand the bug

Read the project's context before the code: `AGENTS.md`, then
`docs/agents/coding_guidelines.md` and `docs/agents/tech_stack.md` when present.
The guidelines decide how the fix and the test are written.

Normalize the report into:

| Field | Content |
|---|---|
| actual | what happens (exact error text when there is one) |
| expected | what should happen |
| trigger | the input, route, command, or state that causes it |
| scope | who or what is affected |

A field you cannot fill from the report or the code → ask with AskUserQuestion,
at most 3 questions, all in one call. Do not invent the expected behavior: when
the code and the report disagree on what is correct, the developer decides.

### 3 — Resolve the test command

First rule that resolves wins:

1. `--test-cmd`
2. the test command in `AGENTS.md` §1 (commands)
3. manifest detection — the same order `scripts/ralph.sh` uses:
   Laravel Sail (`artisan` + `vendor/bin/sail`) → `vendor/bin/sail test`;
   `composer.json` with `scripts.test` → `composer test`; `artisan` →
   `php artisan test`; `package.json` with `scripts.test` → `npm test`;
   `pytest.ini` / `pyproject.toml` `[tool.pytest]` → `pytest`; `go.mod` →
   `go test ./...`; `Cargo.toml` → `cargo test`

Nothing resolved → stop and ask for the command. A bugfix without a runnable
test is not done.

Also find how to run **one** test file or filter (e.g. `php artisan test --filter`,
`vendor/bin/pest <file>`, `npm test -- <file>`, `pytest <file>::<name>`,
`go test -run`). Steps 5–6 run the regression test alone before the full suite.

### 4 — Find the root cause

Reproduce first, edit second. Trace from the trigger to the line that produces
the wrong behavior: read the entry point, follow the calls, check the data.

- Rank hypotheses by evidence; confirm one by reading code or running a command
  (a tinker one-liner, a quick script in a temp dir, the failing request) before
  acting on it.
- The cause is the **first** place the behavior goes wrong, not where it
  surfaces. A null that crashes in a view but is wrong in the query gets fixed in
  the query.
- Can't reproduce and can't locate it → stop and report what you checked and
  what you need (logs, data, steps). Do not ship a speculative fix.

Before editing, tell the developer in a few lines: the root cause
(`file:line`), why it produces the bug, and the fix you intend.

### 5 — Fix

Change the narrowest layer that owns the cause.

- Fix only this bug. No refactors, renames, formatting sweeps, or drive-by
  changes — note them in the summary instead.
- Follow `docs/agents/coding_guidelines.md` for anything you write.
- Keep the fix and the test in separate files (tests under the project's test
  directory) — step 6 relies on it.

Record every non-test file you changed: these are the **fix files**.

### 6 — Regression test

Write a test that reproduces the original trigger and asserts the expected
behavior.

| Rule | Detail |
|---|---|
| level | the highest level that reaches the bug cheaply — through the real entry point (route, command, job, component) when the bug is reachable there. On a project following the harness Laravel guidelines this is a tier-1 Pest feature test |
| location | next to the existing tests for that code, matching their naming and style; a new file only when none fits |
| name | states the behavior, not the bug ticket — `it('keeps the discount when the cart is re-priced')`, not `it('fixes bug 42')` |
| assertion | asserts the **expected** outcome from step 2, specific enough that the buggy behavior cannot pass (exact value, status, persisted row, thrown exception — not "no error") |
| edge | when the cause was an edge (empty, null, boundary, duplicate, concurrency/redelivery), test that edge exactly |
| deterministic | no real network, no real clock, no shared fixture data, no sleeps |

**Prove it guards the bug.** A regression test that passes without the fix guards
nothing:

```bash
# 1. green with the fix
<run the regression test alone>

# 2. red without the fix — take the fix out, keep the test
git diff -- <fix files> > "$TMP/bugfix.patch"
git checkout -- <fix files>
<run the regression test alone>        # must FAIL, for the reason the bug describes

# 3. put the fix back
git apply "$TMP/bugfix.patch"
<run the regression test alone>        # green again
```

`$TMP` is a scratch directory outside the repo (`mktemp -d`). A fix file that is
new (untracked) is moved aside and back instead of checked out.

| Result of 2 | Action |
|---|---|
| fails with the bug's symptom | proven — continue |
| passes | the test does not reach the bug — rewrite it, repeat the proof |
| fails for another reason (setup error, missing class) | not proof — fix the test, repeat the proof |

Always restore the fix, on every path, and confirm with `git diff --stat` that
the fix files match what step 5 left.

### 7 — Full suite

Run the full test command. Then run the project's lint/static-analysis command
when `AGENTS.md` §1 names one (on a harness Laravel project: `composer lint`).

| Result | Action |
|---|---|
| green | done |
| a failure your fix caused | fix it within the bug's scope, re-run the step-6 proof if the fix files changed |
| a failure that also fails on the untouched code | pre-existing — leave it, report it with its test name |

Check pre-existing failures by re-running that test with the fix taken out, the
same way as step 6.

### 8 — Summary

| Item | Result |
|---|---|
| root cause | one sentence + `file:line` |
| fix | files changed, one line each |
| regression test | `file` + test name |
| proof | `red without fix, green with fix` |
| suite | `green` / `pre-existing failures: <names>` |
| lint | `green` / `n/a` / `<failures>` |
| noted, not done | out-of-scope issues spotted on the way |

Close with: review with `git diff`, commit manually — fix and test in the same
commit, so the test never lands without the code it guards.

## Hard rules

- **Root cause, not symptom.** No try/catch swallowing, no null-guard hiding a
  wrong value upstream, no skipped or loosened test.
- **No fix without a regression test, no test without the red/green proof.**
- **Never edit an existing test to make it pass** unless the test asserted the
  buggy behavior — then say so explicitly in the summary.
- **Only the bug's files** — fix files plus the regression test. Pre-existing
  dirty files are never touched.
- **No git writes** — never stage, commit, stash, or reset. The only git commands
  that change the tree are the step-6 `checkout` / `apply` of the fix files, and
  the fix is always restored.
- **No secrets** — `.env` is never read.
