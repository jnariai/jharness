---
description: Interview the developer, settle the Laravel stack (React, Vue or Livewire starter kit) and the bounded contexts, and produce a structured project description at .spec/init/project-description.md
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
3. Fixes the **tech stack** — Laravel first, always: Laravel 13 + PHP 8.4 with the React, Vue or Livewire starter kit, discovered from the environment when code exists.
4. Extracts the **core concepts** (the domain vocabulary).
5. Names the **bounded contexts** and which concepts each one owns — every later artifact places its tables, Actions and pages in one of them.
6. Defines the **core workflows** (the main flows the system performs).

The project's coding guidelines (`docs/agents/coding_guidelines.md`, or the harness `guidelines/laravel.md` + frontend layer) are the conventions this document assumes. Do not re-decide what they already decide — architecture, layering, testing, tooling — in the interview.

## Process

### 1. Discover the environment first

Before asking anything, inspect the project so you don't ask what you can detect:

- `composer.json` — `laravel/framework` version, `livewire/livewire`, `inertiajs/inertia-laravel`, `laravel/sail`, `laravel/sanctum`, `laravel/horizon`, Pest.
- `package.json` — `@inertiajs/react` or `@inertiajs/vue3`, TypeScript, Wayfinder.
- `artisan`, `bootstrap/app.php`, `routes/`, `app/Actions/`, `resources/js/pages/`, `resources/views/pages/` — whether a starter kit is installed and whether its auth is present.
- Config/env: `.env.example` (`DB_CONNECTION`, `QUEUE_CONNECTION`), `phpunit.xml`, `docker-compose.yml`, CI files.
- Existing docs: `README*`, `docs/agents/coding_guidelines.md`, any files already under `.spec/`.

Three outcomes:

| Environment | What to do |
|---|---|
| Laravel project | name the stack with the real detected versions; the frontend layer is whatever the kit installed |
| empty or pre-code | the stack is **Laravel 13 + PHP 8.4** with an official starter kit — ask which frontend (React, Vue, Livewire) and whether the kit ships with auth; record `laravel new` with that kit as the first step |
| another framework | stop: this harness plans Laravel projects only. Tell the developer and write nothing |

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
- **Core domain concepts** — the nouns and rules that define the product.
- **Bounded contexts** — the areas of the business with their own vocabulary (`Billing`, `Catalog`, `Identity`). Propose them from the concepts and confirm with the developer; every concept belongs to exactly one. A small app may have one context — it is still named. Auth and the user account always live in `Identity`.
- **Core workflows** — the main flows, step by step, naming the context each step happens in.
- **Frontend** — React, Vue or Livewire (only when not detected); starter kit with or without auth.
- **Abilities** — who may do what, as named abilities (`viewBilling`, `manageUsers`), not as role checks. Roles, if any, are a closed list.
- **Integrations** — every external vendor (payments, email, storage, fiscal) and whether it calls back through webhooks.
- **Public API** — is there a JSON API for mobile or third parties (`/v1`, Sanctum)? Default: no.
- **Tenancy** — single customer, or many isolated tenants? Default: none.
- **Constraints** — platform, languages the UI must support, non-goals.

Never ask about what the guidelines settle: Actions, DTOs, queue driver, test framework, tooling, folder layout.

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

## Core Workflows

### 1. <Workflow Name>

<Numbered steps or prose describing the flow. Include request/response examples in fenced code blocks where the workflow is an API. Be concrete about rules, limits, and edge cases.>

### 2. <Workflow Name>
...
```

Rules for the document:

- **Title** = project name + `— Project Description`.
- **Overview** carries the "what & why"; **Key Concepts** is the domain glossary; **Tech Stack** is concrete and detected; **Bounded Contexts** assigns every key concept to exactly one context; **Abilities** names what the UI and policies gate; **Core Workflows** is the numbered list of main flows.
- **Key Concepts** entries end with the owning context in parentheses: `- **Invoice:** … (Billing)`.
- Context names are PascalCase singular-or-collective nouns used verbatim as folder names (`app/Actions/Billing/`). `Identity` always exists.
- Each workflow names the contexts it crosses; a step that changes another context's data says whether it happens together (same transaction) or as a reaction (event).
- Prefer specific numbers, limits, and rules over vague description. If the domain has quantities (counts, tiers, scoring), state them.
- Keep every claim traceable to something the developer confirmed or you detected. No invented features.
- If gaps remain unresolved, add a short `## Open Questions` section at the end listing them. Otherwise omit it.

### 4. Self-checks (run until green)

After writing, run these checks. Any failure → fix the document via Edit and re-run until all pass. Never report completion with a failing check.

```bash
F=.spec/init/project-description.md
test -f "$F"
head -1 "$F" | grep -qE '^# .+ — Project Description$'
grep -Fq '## Overview' "$F"
grep -Fq '### Key Concepts' "$F"
grep -Fq '## Tech Stack' "$F"
grep -Eq '^\| Backend \| Laravel ' "$F"                                    # Laravel-first
grep -Eq '^\| Frontend \| (Inertia [0-9]+(\.[0-9]+)* \+ (React|Vue)|Livewire)' "$F"
grep -Fq '## Bounded Contexts' "$F"
grep -Eq '^\| Identity \|' "$F"
grep -Fq '## Abilities' "$F"
grep -Fq '## Core Workflows' "$F"
# every key concept ends with (Context), and that context is in the Bounded Contexts table
# (both loops print nothing)
CONCEPTS=$(awk '/^### Key Concepts/{f=1;next} /^#/{f=0} f' "$F" | grep -E '^- \*\*[^*]+:\*\*')
grep -vE '\([A-Z][A-Za-z]+\)$' <<< "$CONCEPTS" | sed 's/^/concept without context: /'
for c in $(grep -oE '\([A-Z][A-Za-z]+\)$' <<< "$CONCEPTS" | tr -d '()' | sort -u); do
  grep -Eq "^\| $c \|" "$F" || echo "context not declared: $c"
done
[ "$(grep -cE '^### [0-9]+\. ' "$F")" -ge 1 ]      # >=1 numbered workflow
[ "$(grep -cE '^- \*\*[^*]+:\*\*' "$F")" -ge 1 ]   # >=1 key concept entry
```

### 5. Close out

After writing, report:

- The path written.
- A 3–5 line summary of the project as captured.
- The stack line (Laravel version + frontend + kit auth) and the bounded contexts.
- Self-checks: all green — list any check that initially failed and how it was fixed (Red → Green).
- Any open questions still needing the developer's decision.
