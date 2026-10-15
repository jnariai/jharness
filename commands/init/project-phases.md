---
description: Read the project description, user stories, database schema, and any design specs, then plan the build into numbered, agent-ready phases with tasks, acceptance criteria, and feature tests at .spec/init/project-phases.md
argument-hint: "[optional focus area or extra context]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# init:project-phases

**ultrathink.** This is a high-stakes planning task: the document you produce is fed to AI agents that build the whole project from it. Engage your maximum reasoning budget. Do not rush. Precision, completeness, and faithful coverage of every source document matter more than brevity.

You are helping a developer turn the project spec into a **complete, phased implementation plan**. This document is the fourth artifact of the project spec. It builds on the first three (and any design specs) and becomes the ordered backlog AI agents implement, phase by phase, referenced by number.

Optional focus or extra context from the developer (may be empty):

```
$ARGUMENTS
```

## Your goal

Read the existing spec and produce a single document at **`.spec/init/project-phases.md`** that:

1. Breaks the entire build into **numbered phases and sub-phases** (`Phase 1`, `Phase 5.3`, …) that can be referenced by number when later handed to an AI agent.
2. Lists **every task** required to implement everything in the project description, user stories, and database schema — nothing implied by the spec is left unplanned.
3. Gives each task concrete **acceptance criteria** and, where the task carries business logic, the **automated feature tests** to be generated as its acceptance gate.
4. Marks tasks **already completed in the codebase** as `[x]`.
5. Orders the work **foundation-first**, then feature flows.

## Process

### 1. Read the sources of truth first

Before asking anything, read the inputs in this order:

- **`.spec/init/project-description.md`** — scope, tech stack, core workflows.
- **`.spec/init/user-stories.md`** — the stories, acceptance criteria, priorities.
- **`.spec/init/database-schema.md`** — every table, lookup, pivot, relationship.
- **`.spec/init/design/`** — if this directory exists, it holds the **UI/design specs** (mockups, screen definitions, component references, images). Read it. Every task that builds a screen or component **must** point at its design reference, and its implementation must be **faithful to the proposed design**. `.spec/init/design/` is always a **manual artifact**: the developer creates and populates it; no `init:*` command writes there. Its absence is never an error.

- *Laravel profile* (the project description's Tech Stack names Laravel) — **`docs/agents/coding_guidelines.md`**, the Laravel convention layer (Laravel + Inertia React/Vue or Livewire). Every task is phrased in its vocabulary: Actions, model transitions and named constructors, FormRequests/Form objects, View DTOs, `Get*` reads, events and listeners, gateways. Absent → read the harness `guidelines/laravel.md` plus the frontend layer from the plugin directory instead, and add to the close-out that `/jharness:ai-context` must seed the file before `/jharness:ralph` runs — the ralph sessions read it before their first edit.

If any of the first three files is missing, stop and tell the developer to run the missing `init:*` command first. Match the **language** of the project description for all prose.

Then verify the chain is internally fresh — line 3 of each generated artifact records the inputs it was built from:

```bash
# prints nothing when fresh; any output = an input changed after that artifact was generated
for doc in user-stories database-schema; do
  for pair in $(sed -n '3p' ".spec/init/$doc.md" | grep -oE '[a-z0-9.-]+\.md@sha256:[0-9a-f]{12}'); do
    [ "$(sha256sum ".spec/init/${pair%%@*}" | cut -c1-12)" = "${pair##*:}" ] \
      || echo "stale: $doc.md predates current ${pair%%@*}"
  done
done
```

Any output → warn the developer ("input changed after this artifact was generated — review before proceeding") and suggest re-running the flagged `init:*` command first. Warn and proceed if the developer chooses; never block. A file without a line-3 stamp predates this mechanism — nothing to verify.

### If the target file already exists (re-run)

Re-running this command must **update** the existing document, never rebuild it from scratch — `.spec` belongs to the developer, and manual edits there are decisions, not noise.

- Read the existing `.spec/init/project-phases.md` **before** interviewing. Every decision recorded in it (ordering, MVP cut, task status) is source of truth.
- Interview only about **deltas**: stories or tables added upstream since the last run, new gaps, contradictions. Never re-ask what the document already answers.
- Update via **Edit**, not a full rewrite. Preserve every existing `Phase N` / `Phase N.M` number: new phases and sub-phases take the next number at the end (see Numbering); never renumber — agents are handed phases by number.
- Never flip a task the developer marked `[x]` back to `[ ]` without explicit confirmation. Codebase re-inspection (step 2) may add new `[x]` marks as usual.
- A phase, task, or section the developer deleted stays deleted — restore it only if the developer explicitly confirms.

Line 3 of the existing file is its **input stamp** (see step 4). Verify it before interviewing:

```bash
# prints nothing when fresh; any output = that input changed after this document was generated
for pair in $(sed -n '3p' .spec/init/project-phases.md | grep -oE '[a-z0-9.-]+\.md@sha256:[0-9a-f]{12}'); do
  [ "$(sha256sum ".spec/init/${pair%%@*}" | cut -c1-12)" = "${pair##*:}" ] \
    || echo "stale: ${pair%%@*} changed after this document was generated"
done
```

Any output → warn the developer ("input changed after this artifact was generated — review before proceeding") and focus the delta interview on what changed in that input. Warn and proceed; never block. A file without a line-3 stamp predates this mechanism — nothing to verify.

### 2. Inspect the codebase to detect what is already done

Scan the project so you can mark completed work:

- Migrations (`database/migrations/`), models (`app/Models/`), seeders/factories.
- Frontend components, pages/screens, routes.
- Existing tests (`tests/`), controllers, services, form requests, policies.
- *Laravel profile*: whether a starter kit is installed (`artisan`, `resources/js/pages/` or `resources/views/pages/`, its auth controllers) and whether the tooling exists (`pint.json`, `phpstan.neon`, `rector.php`, `tests/Arch.php`, `scripts/grep-gates.sh`, a `lint` script in `composer.json`); enums (`app/Enums/`), Actions (`app/Actions/<Context>/`), DTOs (`app/Data/`), events and listeners, gateways; pages and components (`resources/js/pages/`, `resources/js/components/`, or `resources/views/pages/` and `resources/views/components/`).

For each task you define, check whether the code already satisfies it. If it does, mark it `[x]`; otherwise `[ ]`. When partially done, mark `[ ]` and note in the task what remains.

### 3. Interview to close gaps

Derive as much of the plan as you can directly from the docs, then ask the developer only about gaps that change the **shape, ordering, or sizing** of phases — do not interrogate on things the docs already answer. Focus on:

- **Phase priorities / ordering** — which feature flows come first after the foundation.
- **MVP cut line** — which phases are in the first release vs deferred.
- **Ambiguous scope** — flows implied but not fully specified in the stories.
- **Design coverage** — screens with no design reference: build to a sensible default, or wait for design?

Use `AskUserQuestion` for discrete decisions with clear options. Ask real open questions in plain text when the answer is not a menu. Batch related questions; don't drip one at a time. When something stays undecided, mark it as an open question rather than inventing scope.

## Rules for phasing

### Foundation first, always

Order the phases so that **foundation work precedes feature flows**. The early phases build the base the rest stands on:

1. **Database foundation** — all migrations and lookup-table seeders from the schema.
2. **Models & relationships** — every model, with **all relationships wired up front** (belongsTo, hasMany, belongsToMany, etc.), casts, fillables, soft deletes. Do not defer relationships to later feature phases — the models come out of the foundation phase relationship-complete.
3. **Frontend foundation** — the base UI: design-system components, layout, shared/reusable components referenced by the design specs.

Only **after** the foundation is in place do the phases start implementing the **project flows** (auth, then each feature area / core workflow, feature by feature).

### Laravel profile (only when the stack is Laravel)

Applies when the project description's Tech Stack names Laravel (or `composer.json` requires `laravel/framework`); it replaces the generic foundation order above and adds the rules below. For any other stack, skip every part of this command marked *Laravel profile*.

Phase 1 starts from an installed Laravel 13 starter kit (React, Vue or Livewire) inside a git repository, with `docs/agents/coding_guidelines.md` seeded. When the project is still empty, the close-out tells the developer to run `laravel new` with the chosen kit and `/jharness:ai-context` before `/jharness:ralph` — never plan "create the Laravel app" as a phase task.

The early phases build the base the rest stands on, in this order:

1. **Conventions and tooling** — Pint, Larastan level 6, Rector with `rector-laravel`, `tests/Arch.php` from the guidelines' arch preset, `scripts/grep-gates.sh`, `composer lint`; SQLite in-memory in `phpunit.xml`; `Model::shouldBeStrict()`; `App\Exceptions\DomainException` + `App\Enums\DomainErrorKind` + the `withExceptions()` mapping; `HasPublicId`; the shared VOs the schema needs (`Pagination`, `Money`). Inertia projects add the TypeScript transformer, its generated file and `scripts/types-fresh.sh` behind `composer lint` (`@types:fresh`), the shared props (`auth.user`, `auth.can`, `flash`, `locale`), the toast outlet and the i18n helper; Livewire projects add the `x-ui.*` primitives, the toast and `HandlesDomainErrors`. From this phase on every phase must leave `composer lint` and `composer test` green.
2. **Identity** — the starter kit's auth and settings code refactored into `Identity` Actions (`RegisterUser`, `UpdateProfile`, `UpdatePassword`, `DeleteAccount`) with named constructors and transitions on `User`, `public_id` on users, the abilities of the project description as `Gate::define()` entries, roles as a string-backed enum when the project has them. The kit's own tests stay green throughout. Skipped only when the kit was installed without auth — then this phase adds just the abilities and `public_id`.
3. **Database foundation** — every migration from the schema (forward-only, constrained foreign keys with their delete behavior, `public_id` columns) and every string-backed enum with its lookup table seeded from its cases inside the same migration. No seeders for lookup data.
4. **Models** — every model with **all relationships wired up front**, `$fillable`, `casts()`, the memoized lookup `Attribute` for each business enum, `HasPublicId` where exposed, and a factory with named states per model. Transitions, named constructors and scopes arrive with the feature that first needs them, tested there.
5. **Frontend foundation** — layouts, navigation driven by `auth.can` (Inertia) or `@can` (Livewire), and the shared components referenced by the design specs.

Only **after** the foundation do the phases implement the **project flows**, one bounded context and feature area at a time.

**Feature tasks are use-case slices.** A feature task is **one user intent**, cut vertically through the layers the guidelines define — not one layer at a time:

- the model method that guards the invariant (transition or named constructor), plus any scope;
- the Action in `app/Actions/<Context>/` (`PublishPost`, `GetOverdueInvoices`) — writes in a transaction, reads as `Get*` with a `*Filter`;
- the entry point: resource-controller method + FormRequest (Inertia) — every method a resource method; a non-CRUD intent is its own controller (`store` does it, `destroy` undoes it), never `__invoke`, or the component action method + Form object (Livewire); the policy method or ability it checks;
- for Inertia, the View DTOs and the page that consume it; for Livewire, the template;
- the event it dispatches and, as **separate tasks**, each listener + Action that reacts in another context;
- gateways only through a Client + Gateway + Factory task of their own, before the first task that calls the vendor.

Each task lists those pieces in an `**Artifacts:**` line (placed before `**Feature tests:**`) by class or file name, so the agent knows what to build and the verifier knows what to look for.

**Tests follow the guidelines' tiers**, replacing the generic testing bullets below:

- **Tier 1 first**: every Action driven through the entry point that really reaches it — HTTP route, Inertia page (`assertInertia`), Livewire component (`Livewire::test`), console command, job, listener — asserting persisted state, dispatched events, domain exceptions, redirects and flash, validation errors. Each task lists: the happy path, one test per invariant and business rule, one for authorization denied, one for invalid input.
- Events: the emitting task asserts the event is dispatched (and not on a redelivery); each listener task tests its own Action and the wiring (`Event::assertListening`). Webhook and retried flows are tested by **redelivery** — run twice, assert one transition.
- Frontend tests (`assertSee`, browser tests) may be added on top — never as the only test of a business rule. Pest browser tests only for the project's critical journeys.

The document's **Conventions** block adds: `Every task follows docs/agents/coding_guidelines.md; every phase ends with composer lint and composer test green.`

### Phase sizing (one agent session per phase)

Size each phase so a single AI agent can implement it in **one focused session, within one context window** — big enough to be a coherent, shippable slice, small enough to fit comfortably without overflow.

Working heuristic: a phase (parent + all its sub-phases) covers **one feature area or one foundation layer** and stays around **10–15 tasks**. Beyond that, split into more top-level phases.

- **Sub-phases count toward their parent phase's session.** A parent phase plus all its sub-phases together must still fit one session. If the total grows too large, split it into more top-level phases instead of overloading one parent.
- Prefer more, well-scoped phases over a few oversized ones. **Any number of phases is fine** as long as each is detailed enough to implement everything in the description, stories, and schema with high quality and precision.
- Keep each phase independently implementable and, where possible, independently verifiable.

### Numbering

- Top-level phases: `Phase 1`, `Phase 2`, … Sub-phases: `Phase 5.1`, `Phase 5.2`, `Phase 5.3`, … so any unit can be referenced by number when handed to an agent.
- Keep numbers **stable**; don't renumber existing phases when adding new ones.

The heading format is not a style choice — it is a **machine contract** with `scripts/ralph.sh`, which executes this document phase by phase:

- `split_phases` matches top-level headings against the regex `^##[[:space:]]+Phase[[:space:]]+[0-9]+` and cuts the document into **one file — one agent session — per `## Phase N:` heading**. A phase heading that deviates (wrong level, missing number, `Phase` misspelled or translated) silently disappears from the run.
- Sub-phases **must** stay at level 3 (`### Phase N.M:`). Promoting one to `##` makes ralph split it into its own session, breaking the sizing rule that a parent and its sub-phases share one session.
- Any other level-2 heading (`## Overview`, `## Open Questions`) **ends capture**: content under it belongs to no phase and is never handed to an agent. Everything an agent needs to implement a phase must live under that phase's `## Phase N:` heading.

The self-checks in step 5 enforce this format mechanically.

### Tasks, tests, and acceptance criteria

- Every task has **acceptance criteria** — concrete, validatable conditions (states, limits, failure paths), not vague intent.
- **Business-logic tasks** (rules, calculations, state transitions, permissions, validations, workflows) **must** specify the **automated feature tests** to generate. Tests **primarily assert business rules** — the limits, states, and edge cases from the stories and schema.
- Tests assert business rules **at the layer that owns them**: service/domain return values, persisted state, HTTP status and response data, dispatched events/jobs, raised exceptions and validation errors.
- **Test everything, backend features first.** The backend feature tests above come first in every task and are what proves a rule. In Laravel prefer `assertDatabaseHas`, `assertJsonPath`, `assertStatus`, `assertRedirect`, `Event::assertDispatched`; use each stack's equivalents. Frontend tests (rendered output such as `assertSee`, component UI state, browser tests) may be added on top — never as the only test of a business rule.
- One test per rule or edge case. No duplicate coverage across tasks — cite the earlier task instead of restating the case.
- **Frontend-only tasks** (building a screen/component with no business logic) **do not require tests** (rendering tests are optional), but **must** have acceptance criteria that can be validated (matches design reference, renders required elements/states, responsive/interaction behavior), plus a **Design ref** pointing at the relevant `.spec/init/design/` artifact.
- Keep every task traceable to a story (`US-x.y`), a schema table, a workflow, or a design artifact. No invented scope.

### Token economy

Every line of this document is re-read by an agent on **every** phase run, so words here are paid for many times over.

- One line per field. No preamble, no restated context, no adjectives, no "this task will…".
- Cite instead of re-explaining: `US-3.2`, `orders.status`, `.spec/init/design/checkout.md` — never paraphrase the story, schema, or design back into the task.
- Say a thing once. Shared setup goes in the phase `**Goal:**` line, not repeated per task.
- Cut words, never scope: coverage stays complete, prose gets terse.

### 4. Write the document

Write to `.spec/init/project-phases.md` (create the `.spec/init/` directories if missing). Use **exactly** this structure:

````markdown
# <Project Name> — Project Phases

<!-- inputs: project-description.md@sha256:<first 12 chars> user-stories.md@sha256:<first 12 chars> database-schema.md@sha256:<first 12 chars> -->

## Overview

<1–2 paragraphs: the build strategy at a glance — foundation-first, then feature flows. Note how many phases, the MVP cut line, and that phases are referenced by number when handed to agents.>

**Conventions:**
- `[ ]` pending · `[x]` done in the codebase.
- Phases and sub-phases are numbered (`Phase 1`, `Phase 5.3`) for reference by AI agents.
- Business-logic tasks list the **feature tests** to generate; frontend-only tasks list validatable **acceptance criteria** and a **Design ref**.

---

## Phase 1: <Foundation — Name>

**Goal:** <one line.> · **Depends on:** <none / Phase N> · **Covers:** <stories/tables/workflows>

### Phase 1.1: <Sub-phase name>

- [ ] **Task:** <what to build>
  - **Acceptance criteria:**
    - <concrete, validatable condition>
    - ...
  - **Feature tests:** <test name → what business rule it asserts> *(omit for frontend-only tasks)*
  - **Design ref:** <path under .spec/init/design/> *(only for screen/component tasks)*
  - **Traces:** <US-x.y / table / workflow>

- [x] **Task:** <already implemented in the codebase>
  - ...

### Phase 1.2: <Sub-phase name>
...

---

## Phase 2: <Name>
...

## Open Questions

<Only if gaps remain — bullets of undecided scope/ordering. Otherwise omit this section.>
````

Rules for the document:

- **Title** = project name + `— Project Phases`.
- **Line 3** is the machine-owned **input stamp**: `<!-- inputs: project-description.md@sha256:<12 chars> user-stories.md@sha256:<12 chars> database-schema.md@sha256:<12 chars> -->`, each checksum being `sha256sum <file> | cut -c1-12` over the files as read in step 1. Refresh it on **every** run, including re-run Edits — the chain status uses it to detect drift. Never preserve a stale stamp as a "developer edit".
- Foundation phases come first; models are relationship-complete out of the foundation.
- Every phase (parent + its sub-phases) fits one agent session (see Phase sizing).
- Every task is traceable; every business-logic task has feature tests; every screen task has a design ref (or an open question if design is missing).
- Cover **everything** in the description, stories, and schema. Completeness of *scope*, never of prose (see Token economy).

### 5. Self-checks (run until green)

After writing, run these checks. Any failure → fix the document via Edit and re-run until all pass. Never report completion with a failing check.

```bash
F=.spec/init/project-phases.md
test -f "$F"
head -1 "$F" | grep -qE '^# .+ — Project Phases$'
# line 3 input stamp present and fresh
[ "$(sed -n '3p' "$F")" = "<!-- inputs: project-description.md@sha256:$(sha256sum .spec/init/project-description.md | cut -c1-12) user-stories.md@sha256:$(sha256sum .spec/init/user-stories.md | cut -c1-12) database-schema.md@sha256:$(sha256sum .spec/init/database-schema.md | cut -c1-12) -->" ]
grep -Fq '**Conventions:**' "$F"
[ "$(grep -cE '^## Phase [0-9]+: ' "$F")" -ge 1 ]
# phase heading format is a hard contract — scripts/ralph.sh splits phases by regex
# (both loops must print nothing)
grep -E '^## Phase' "$F" | grep -vE '^## Phase [0-9]+: ' || true
grep -E '^### Phase' "$F" | grep -vE '^### Phase [0-9]+\.[0-9]+: ' || true
TASKS=$(grep -cE '^- \[[ x]\] \*\*Task:\*\*' "$F"); [ "$TASKS" -ge 1 ]
[ "$TASKS" -eq "$(grep -c '\*\*Acceptance criteria:\*\*' "$F")" ]   # every task has criteria
[ "$TASKS" -eq "$(grep -c '\*\*Traces:\*\*' "$F")" ]                # every task is traceable
# coverage: every story ID in the user-stories appendix appears in >=1 **Traces:** line
# (loop must print nothing; the ([^0-9]|$) guard keeps US-1.1 from matching US-1.10)
for id in $(grep -oE '^\| US-[0-9]+\.[0-9]+ ' .spec/init/user-stories.md | grep -oE 'US-[0-9]+\.[0-9]+' | sort -u); do
  grep -F '**Traces:**' "$F" | grep -qE "${id//./\\.}([^0-9]|$)" || echo "story not traced: $id"
done
# coverage: every table declared in the schema appears in >=1 task (loop must print nothing)
for t in $(grep -E '^Table [a-z0-9_]+ \{' .spec/init/database-schema.md | awk '{print $2}' | sort -u); do
  grep -qw "$t" "$F" || echo "table not covered: $t"
done
```

*Laravel profile* — run these as well when the project description's Tech Stack names Laravel:

```bash
F=.spec/init/project-phases.md
if awk '/^## Tech Stack/{f=1;next} /^## /{f=0} f' .spec/init/project-description.md | grep -qi laravel; then
  TASKS=$(grep -cE '^- \[[ x]\] \*\*Task:\*\*' "$F")
  [ "$TASKS" -eq "$(grep -c '\*\*Artifacts:\*\*' "$F")" ]             # every task names what it builds
  # the conventions/tooling foundation is planned (or already done) somewhere (prints nothing)
  for piece in 'tests/Arch.php' 'grep-gates' 'DomainErrorKind' 'HasPublicId'; do
    grep -Fq "$piece" "$F" || echo "foundation piece not planned: $piece"
  done
fi
```

The two coverage loops are the enforcement of "cover everything": a story with no `**Traces:**` hit or a schema table mentioned nowhere in the plan means work was left unplanned. Fix by adding the missing tasks (or asking the developer) — never by deleting the story or the table from the upstream docs to silence the check.

### 6. Close out

After writing, report:

- The path written.
- Phase count, task count, and how many tasks are already `[x]`.
- Coverage: confirm every story ID and every schema table passed the mechanical coverage loops (green), or list what was added to close the gaps.
- The MVP cut line (which phase completes the first release).
- *Laravel profile*: what must exist before `/jharness:ralph` — the starter kit installed, a clean git tree, `docs/agents/coding_guidelines.md` (run `/jharness:ai-context` when absent) — and that ralph should run with `--test-cmd "composer lint && composer test"` so gate 2 checks both.
- Self-checks: all green — list any check that initially failed and how it was fixed (Red → Green).
- Any open questions still needing the developer's decision.
