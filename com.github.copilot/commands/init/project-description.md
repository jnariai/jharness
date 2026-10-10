---
description: Interview the developer, discover the stack, and produce a structured project description at .spec/init/project-description.md
argument-hint: "[one-line idea of the project]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, WebSearch
---

# init:project-description

You are helping a developer turn a rough idea into a **clear, structured project description**. 
This document is the first artifact of the project spec. It is written *before* code and becomes the shared source 
of truth for what is being built and why.

The developer's initial idea (may be empty):

```
$ARGUMENTS
```

## Your goal

Produce a single document at **`.spec/init/project-description.md`** that:

1. Sharpens the idea — turns a vague concept into concrete scope.
2. Surfaces **definition gaps** — the ambiguities and unmade decisions that would block development — and resolves them *with the developer*.
3. Structures the **tech stack** — normally discovered from the project environment, not guessed.
4. Extracts the **core concepts** (the domain vocabulary).
5. Defines the **core workflows** (the main flows the system performs).

## Process

### 1. Discover the environment first

Before asking anything, inspect the project so you don't ask what you can detect. Look for stack signals:

- Manifests / lockfiles: `composer.json`, `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `pom.xml`, `*.csproj`, etc.
- Framework markers: `artisan`, `manage.py`, `next.config.*`, `nuxt.config.*`, `vite.config.*`, `docker-compose.yml`, `Dockerfile`.
- Config/env: `.env.example`, CI files, test runner config.
- Existing docs: `README*`, any files already under `.spec/`.

Read enough to name the stack with real versions. If the directory is empty or pre-code, note that and derive the stack from the developer's stated intent instead (still confirm it).

### Laravel profile (only when the stack is Laravel)

The profile applies when `composer.json` requires `laravel/framework`, or — in an empty or pre-code directory — when the developer chooses Laravel. For any other stack, skip every part of this command marked *Laravel profile*; the generic rules stand alone. When it applies, it wins over the generic rules wherever they differ.

- **Detect more** — `composer.json`: `laravel/framework` version, `livewire/livewire`, `inertiajs/inertia-laravel`, `laravel/sail`, `laravel/sanctum`, `laravel/horizon`, Pest. `package.json`: `@inertiajs/react` or `@inertiajs/vue3`, TypeScript, Wayfinder. `artisan`, `bootstrap/app.php`, `routes/`, `app/Actions/`, `resources/js/pages/`, `resources/views/pages/`: whether a starter kit is installed and whether its auth is present. `.env.example` (`DB_CONNECTION`, `QUEUE_CONNECTION`), `phpunit.xml`, `docs/agents/coding_guidelines.md`.
- **Pre-code Laravel** — the stack is **Laravel 13 + PHP 8.4** with an official starter kit: ask which frontend (React, Vue, Livewire) and whether the kit ships with auth; record `laravel new` with that kit as the first step.
- **Conventions are settled** — the project's coding guidelines (`docs/agents/coding_guidelines.md`, or the harness `guidelines/laravel.md` + frontend layer) are the conventions this document assumes. Never ask about what they settle: Actions, DTOs, queue driver, test framework, tooling, folder layout.
- **Bounded contexts** — name the areas of the business with their own vocabulary (`Billing`, `Catalog`, `Identity`) and which concepts each one owns; every later artifact places its tables, Actions and pages in one of them.

### If the target file already exists (re-run)

Re-running this command must **update** the existing document, never rebuild it from scratch — `.spec` belongs to the developer, and manual edits there are decisions, not noise.

- Read the existing `.spec/init/project-description.md` **before** interviewing. Every decision recorded in it is source of truth.
- Interview only about **deltas**: new gaps, new scope, contradictions between the doc and what you detected in the environment. Never re-ask what the document already answers.
- Update via **Edit**, not a full rewrite. Preserve the numbering of `## Core Workflows` (`### 1.`, `### 2.` …): new workflows take the next number at the end; never renumber existing ones — downstream artifacts reference them by number in their coverage tables.
- A section, workflow, or concept the developer deleted stays deleted — restore it only if the developer explicitly confirms.

### 2. Interview to close gaps

Understand the idea, then find what's undefined. Ask the developer about the gaps that actually matter — do not interrogate on things you can infer or that don't change the shape of the system. Focus on:

- **Purpose & audience** — who uses it, what problem it solves.
- **Scope / MVP boundary** — what is in the first version vs deferred.
- **Core domain concepts** — the nouns and rules that define the game/product/API.
- **Core workflows** — the main flows, step by step.
- **Constraints** — auth model, integrations, platform, non-goals.

*Laravel profile* — also cover, replacing the generic *auth model* and *integrations* bullets:

- **Bounded contexts** — propose them from the concepts and confirm with the developer; every concept belongs to exactly one. A small app may have one context — it is still named. Auth and the user account always live in `Identity`.
- **Core workflows** name the context each step happens in.
- **Frontend** — React, Vue or Livewire (only when not detected); starter kit with or without auth.
- **Abilities** — who may do what, as named abilities (`viewBilling`, `manageUsers`), not as role checks. Roles, if any, are a closed list.
- **Integrations** — every external vendor (payments, email, storage, fiscal) and whether it calls back through webhooks.
- **Public API** — is there a JSON API for mobile or third parties (`/v1`, Sanctum)? Default: no.
- **Tenancy** — single customer, or many isolated tenants? Default: none.

Use `AskUserQuestion` for discrete decisions with clear options. Ask real open questions in plain text when the answer is not a menu. Batch related questions; don't drip one at a time. Keep going until you can write each section without hand-waving. When something stays undecided, mark it explicitly as an open question rather than inventing an answer.

### 3. Write the document

Write to `.spec/init/project-description.md` (create the `.spec/init/` directories if missing). Match the developer's language. Use **exactly** this structure:

```markdown
# <Project Name> — Project Description

## Overview

<2–4 paragraphs: what it is, who it's for, the core loop/value, the MVP boundary. Bold the key ideas.>

### Key Concepts

- **<Concept>:** <definition, including rules/limits/numbers where they exist>
- ...

## Tech Stack

<A table (Layer | Technology) or grouped bullets, whichever fits. Use real detected versions. One row/line per meaningful layer: backend, frontend, database, testing, dev env, tooling, integrations.>

## Core Workflows

### 1. <Workflow Name>

<Numbered steps or prose describing the flow. Include request/response examples in fenced code blocks where the workflow is an API. Be concrete about rules, limits, and edge cases.>

### 2. <Workflow Name>
...
```

Rules for the document:

- **Title** = project name + `— Project Description`.
- **Overview** carries the "what & why"; **Key Concepts** is the domain glossary; **Tech Stack** is concrete and detected; **Core Workflows** is the numbered list of main flows.
- Prefer specific numbers, limits, and rules over vague description. If the domain has quantities (counts, tiers, scoring), state them.
- Keep every claim traceable to something the developer confirmed or you detected. No invented features.
- If gaps remain unresolved, add a short `## Open Questions` section at the end listing them. Otherwise omit it.

*Laravel profile* — the **Tech Stack** is this table, and two sections follow it, before `## Core Workflows`:

```markdown
## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Laravel 13, PHP 8.4 <detected versions when code exists> |
| Frontend | <Inertia 3 + React 19 + TypeScript / Inertia 3 + Vue 3 + TypeScript / Livewire 4 (no Flux)> |
| Starter kit | <react / vue / livewire> — <with auth / without auth> |
| Database | <MySQL / PostgreSQL / SQLite>; tests on SQLite in-memory |
| Queue | database driver (Redis + Horizon when volume demands) |
| API | <none / REST `/v1` with Sanctum> |
| Tenancy | <none / single database, `tenant_id`> |
| Testing | Pest 4 (+ browser plugin for critical journeys) |
| Tooling | Pint, Larastan level 6, Rector (rector-laravel), Pest arch preset, `scripts/grep-gates.sh` |
| Dev env | <Sail / Herd / native> |
| Integrations | <vendor — purpose — webhooks yes/no, one per line; or none> |

## Bounded Contexts

| Context | Owns | Purpose |
|---|---|---|
| Identity | users, auth, profile, settings | who the user is and how they sign in |
| <Context> | <concepts from Key Concepts> | <one line> |

## Abilities

| Ability | Who | Unlocks |
|---|---|---|
| <abilityName> | <persona or role> | <area or action it gates> |

<Roles, when the project has them: one line listing the closed set.>
```

- **Bounded Contexts** assigns every key concept to exactly one context; **Abilities** names what the UI and policies gate.
- **Key Concepts** entries end with the owning context in parentheses: `- **Invoice:** … (Billing)`.
- Context names are PascalCase singular-or-collective nouns used verbatim as folder names (`app/Actions/Billing/`). `Identity` always exists.
- Each workflow names the contexts it crosses; a step that changes another context's data says whether it happens together (same transaction) or as a reaction (event).

### 4. Self-checks (run until green)

After writing, run these checks. Any failure → fix the document via Edit and re-run until all pass. Never report completion with a failing check.

```bash
F=.spec/init/project-description.md
test -f "$F"
head -1 "$F" | grep -qE '^# .+ — Project Description$'
grep -Fq '## Overview' "$F"
grep -Fq '### Key Concepts' "$F"
grep -Fq '## Tech Stack' "$F"
grep -Fq '## Core Workflows' "$F"
[ "$(grep -cE '^### [0-9]+\. ' "$F")" -ge 1 ]      # >=1 numbered workflow
[ "$(grep -cE '^- \*\*[^*]+:\*\*' "$F")" -ge 1 ]   # >=1 key concept entry
```

*Laravel profile* — run these as well when the Tech Stack names Laravel:

```bash
F=.spec/init/project-description.md
if awk '/^## Tech Stack/{f=1;next} /^## /{f=0} f' "$F" | grep -qi laravel; then
  grep -Eq '^\| Backend \| Laravel ' "$F"
  grep -Eq '^\| Frontend \| (Inertia [0-9]+(\.[0-9]+)* \+ (React|Vue)|Livewire)' "$F"
  grep -Fq '## Bounded Contexts' "$F"
  grep -Eq '^\| Identity \|' "$F"
  grep -Fq '## Abilities' "$F"
  # every key concept ends with (Context), and that context is in the Bounded Contexts table
  # (both loops print nothing)
  CONCEPTS=$(awk '/^### Key Concepts/{f=1;next} /^#/{f=0} f' "$F" | grep -E '^- \*\*[^*]+:\*\*')
  grep -vE '\([A-Z][A-Za-z]+\)$' <<< "$CONCEPTS" | sed 's/^/concept without context: /'
  for c in $(grep -oE '\([A-Z][A-Za-z]+\)$' <<< "$CONCEPTS" | tr -d '()' | sort -u); do
    grep -Eq "^\| $c \|" "$F" || echo "context not declared: $c"
  done
fi
```

### 5. Close out

After writing, report:

- The path written.
- A 3–5 line summary of the project as captured.
- *Laravel profile*: the stack line (Laravel version + frontend + kit auth) and the bounded contexts.
- Self-checks: all green — list any check that initially failed and how it was fixed (Red → Green).
- Any open questions still needing the developer's decision.
