---
description: Read the project description and user stories, then derive a suggested database schema in DBML at .spec/init/database-schema.md
argument-hint: "[optional focus area or extra context]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# init:database-schema

You are helping a developer turn a **project description** and its **user stories** into a **suggested database schema** written in **DBML** (Database Markup Language). This document is the third artifact of the project spec. It builds directly on the first two and becomes the reference the team uses to write migrations and models.

Optional focus or extra context from the developer (may be empty):

```
$ARGUMENTS
```

## Your goal

Read the existing project description and user stories, then produce a single document at **`.spec/init/database-schema.md`** that:

1. Models every **entity** implied by the core concepts and stories as a DBML `Table`.
2. Defines **columns** with concrete types, nullability, defaults, and uniqueness.
3. Declares **relationships** (foreign keys) and the **lookup tables** that back every categorical field.
4. Follows the **conventions of the detected stack** (framework/ORM from the project description) and the universal DB guidelines below.

## Process

### 1. Read the source of truth first

Before asking anything, read **`.spec/init/project-description.md`** and **`.spec/init/user-stories.md`**. These are the inputs to this command.

- If either file is missing, stop and tell the developer to run `init:project-description` and/or `init:user-stories` first.
- Extract: the core concepts (the nouns → tables), the workflows and stories (the fields, states, and relationships), the user types (auth/roles), and any limits or numbers stated (→ column constraints).
- Extract the **framework and ORM** from the project description's Tech Stack section — they drive the naming conventions below. Confirm against the codebase manifest (`composer.json`, `package.json`, `pyproject.toml`, `go.mod`, `Gemfile`, …) when one exists.
- Also scan any other files already under `.spec/` for schema decisions already made, and inspect the project for an existing schema (migrations directory, ORM models/entities, `schema.prisma`, `*.sql` files) so you extend rather than contradict what's there.
- *Laravel profile* (the Tech Stack names Laravel — see **DB Guidelines → Laravel profile**): also extract the **bounded contexts** and the concept → context mapping — every table lands in the context that owns its concept. Inspect `database/migrations/` and `app/Models/`. The starter kit's own tables (`users`, `password_reset_tokens`, `sessions`, `cache`, `jobs`, `failed_jobs`) already exist: model them exactly as their migrations declare them (keys, columns) and only add what the project needs (`public_id` on `users`, roles).

Match the **language** of the project description for prose and comments (keep table/column identifiers in English, snake_case).

Then verify the chain is internally fresh — line 3 of each generated artifact records the inputs it was built from:

```bash
# prints nothing when fresh; any output = an input changed after user-stories was generated
for pair in $(sed -n '3p' .spec/init/user-stories.md | grep -oE '[a-z0-9.-]+\.md@sha256:[0-9a-f]{12}'); do
  [ "$(sha256sum ".spec/init/${pair%%@*}" | cut -c1-12)" = "${pair##*:}" ] \
    || echo "stale: user-stories.md predates current ${pair%%@*}"
done
```

Any output → warn the developer ("input changed after this artifact was generated — review before proceeding") and suggest re-running `init:user-stories` first. Warn and proceed if the developer chooses; never block. A file without a line-3 stamp predates this mechanism — nothing to verify.

### If the target file already exists (re-run)

Re-running this command must **update** the existing document, never rebuild it from scratch — `.spec` belongs to the developer, and manual edits there are decisions, not noise.

- Read the existing `.spec/init/database-schema.md` **before** interviewing. Every decision recorded in it (tables, columns, seeds, notes) is source of truth.
- Interview only about **deltas**: new concepts or stories since the last run, new gaps, contradictions. Never re-ask what the document already answers.
- Update via **Edit**, not a full rewrite. Keep tables and columns the developer added or edited; extend the DBML block in place. Renaming or dropping an existing table requires explicit developer confirmation — `project-phases` references tables by name in its coverage check.
- A table, column, or note the developer deleted stays deleted — restore it only if the developer explicitly confirms.

Line 3 of the existing file is its **input stamp** (see step 3). Verify it before interviewing:

```bash
# prints nothing when fresh; any output = that input changed after this document was generated
for pair in $(sed -n '3p' .spec/init/database-schema.md | grep -oE '[a-z0-9.-]+\.md@sha256:[0-9a-f]{12}'); do
  [ "$(sha256sum ".spec/init/${pair%%@*}" | cut -c1-12)" = "${pair##*:}" ] \
    || echo "stale: ${pair%%@*} changed after this document was generated"
done
```

Any output → warn the developer ("input changed after this artifact was generated — review before proceeding") and focus the delta interview on what changed in that input. Warn and proceed; never block. A file without a line-3 stamp predates this mechanism — nothing to verify.

### 2. Interview to close gaps

Derive as much of the schema as you can directly from the docs, then find what's undefined. Ask the developer only about gaps that change the shape of the schema — do not interrogate on things the docs already answer. Focus on:

- **Cardinality** — one-to-many vs many-to-many; where a pivot table is needed.
- **Ownership & tenancy** — who owns a record; whether data is scoped per user/team/tenant.
- **Soft deletes vs hard deletes** — which entities need `deleted_at`.
- **Categorical fields** — every status/type/category/priority/role → which values seed the lookup table.
- **Uniqueness & required fields** — which columns are `unique`, which are `not null`.

*Laravel profile* — also, replacing the generic soft-delete and categorical bullets:

- **Cardinality** — whether a many-to-many link carries data of its own (then it is an entity table, not a pivot).
- **Ownership & tenancy** — `tenant_id` only when the project description declares tenancy.
- **End of life** — for each entity: a status transition (archived), a hard delete, or — only when restoring is a real feature — soft deletes.
- **Delete behavior** — for each foreign key: cascade (owned child), restrict (reference) or set null (optional link).
- **Exposure** — which entities appear in a URL, a page or an API response; they get a `public_id`, and its prefix (`ord_`).
- **Business enums** — every status/type/category/kind/role → the lookup table and its values.

Use `AskUserQuestion` for discrete decisions with clear options. Ask real open questions in plain text when the answer is not a menu. Batch related questions; don't drip one at a time. When something stays undecided, mark it as an open question rather than inventing a column.

### 3. Write the document

Write to `.spec/init/database-schema.md` (create the `.spec/init/` directories if missing). The file is Markdown that wraps a single DBML code block plus supporting notes. Use **exactly** this structure:

````markdown
# <Project Name> — Database Schema

<!-- inputs: project-description.md@sha256:<first 12 chars> user-stories.md@sha256:<first 12 chars> -->

## Overview

<1–2 paragraphs: the data model at a glance — the main entities and how they connect. Bold the key entities. Note the conventions in force (detected framework/ORM, lookup tables for enums, soft deletes where used).>

## Schema (DBML)

```dbml
// Lookup tables first, then domain tables, then pivots.

Table statuses {
  id bigint [pk, increment]
  name varchar [not null]
  slug varchar [unique, not null]
  description text [null]
  is_active boolean [not null, default: true]
  created_at timestamp
  updated_at timestamp
}

Table users {
  id bigint [pk, increment]
  name varchar [not null]
  email varchar [unique, not null]
  avatar_path varchar [null]
  status_id bigint [ref: > statuses.id, not null]
  created_at timestamp
  updated_at timestamp
  deleted_at timestamp [null]
}

// ... one Table per entity, one Table per lookup, pivots for many-to-many
```

## Relationships

<Bullet list summarizing each relationship in plain language: "A **user** has many **projects**", "A **project** belongs to one **status**", "**users** and **roles** are many-to-many via **role_user**". One line per relationship.>

## Lookup Table Seeds

<For each lookup table, list the initial rows that should be seeded (the values that would otherwise be enum cases). Table name → the concrete values.>

## Notes & Conventions

<Bullets calling out: tables using soft deletes, pivots, indexes worth adding, any denormalization, and anything traceable to a specific user story or limit.>
````

Rules for the document:

- **Title** = project name + `— Database Schema`.
- **Line 3** is the machine-owned **input stamp**: `<!-- inputs: project-description.md@sha256:<12 chars> user-stories.md@sha256:<12 chars> -->`, each checksum being `sha256sum <file> | cut -c1-12` over the files as read in step 1. Refresh it on **every** run, including re-run Edits — downstream commands use it to detect drift. Never preserve a stale stamp as a "developer edit".
- The DBML must be valid: every `ref` points at a real `table.column`; every foreign key column exists on its table.
- Keep every table traceable to a core concept, workflow, or story. No invented entities — if you need one to make a relationship work, note why.
- If gaps remain unresolved, add a short `## Open Questions` section at the end. Otherwise omit it.
- *Laravel profile*: the DBML is ordered per context (lookup tables first, then domain tables, then link tables) and every context closes with its `TableGroup`; **Lookup Table Seeds** lists table → the enum it mirrors → its values, in `snake_case`, exactly as the string-backed enum's backing values (`invoice_status` → `InvoiceStatus` → `draft`, `issued`, `paid`, `void`) — the migration that creates the table inserts these from the enum's cases; **Notes & Conventions** also lists the exposed tables with their `public_id` prefixes and, for each soft-deleted table, the story that needs restoring. A table in the Laravel shape:

```dbml
Table invoice_status {
  id bigint [pk, increment]
  label varchar [unique, not null]
}

Table invoices {
  id bigint [pk, increment]
  public_id varchar(40) [unique, not null, note: 'prefix inv_']
  customer_id bigint [ref: > customers.id, not null, note: 'on delete restrict']
  invoice_status_id bigint [ref: > invoice_status.id, not null, note: 'on delete restrict']
  number varchar [unique, not null]
  total_cents bigint [not null]
  currency varchar(3) [not null]
  pdf_path varchar [null]
  issued_at timestamp [null]
  created_at timestamp
  updated_at timestamp
}

TableGroup Billing {
  invoice_status
  invoices
}
```

## DB Guidelines

### Stack conventions (detect, then apply)

Apply the naming and column conventions of the **framework/ORM detected in step 1** — table naming, primary key shape, foreign key naming, timestamp columns, join/pivot table naming, soft-delete column. Follow that stack's documented defaults (e.g. Eloquent, ActiveRecord, Django ORM, Prisma, TypeORM, GORM, Ecto). Never mix conventions from two stacks in one schema.

When no framework/ORM is detected, use this default profile:

- Table names **plural, snake_case** (`projects`, `project_attachments`). Join/pivot names are the two singular table names **alphabetically ordered, snake_case** (`role_user`, not `user_role`).
- Every table has `id bigint [pk, increment]` unless it's a pivot with a composite key.
- Foreign keys are `<singular>_id` (`user_id`, `status_id`) typed `bigint`.
- Include `created_at` and `updated_at timestamp` on domain tables. Add `deleted_at timestamp [null]` where the entity uses soft deletes.

### Enums & Lookup Tables (universal — any stack)

- **Do not use enum DB fields or string-based enum columns.**
- For any field that represents a set of predefined values (status, type, category, priority, role, level, etc.), **always create a lookup/auxiliary table** with a foreign key relationship.
  - Instead of a `status` string/enum column, create a `statuses` table (`id`, `name`, …) and reference it as `status_id` (foreign key).
  - The lookup table includes `id`, `name`, and optionally `slug`, `description`, `is_active`, and timestamps as needed.
  - Applies to **all** categorical/enumerable fields: statuses, types, categories, priorities, levels, domain roles, etc.

### File / Image Uploads (universal — any stack)

- Store the file path as a **string column** directly in the table (e.g. `avatar_path`, `document_path`, `attachment_path`).
- Use a descriptive `_path` suffix to signal it holds a file path.
- If a record can have **multiple** files, create a related table (e.g. `project_attachments`) with a `file_path` string column and a foreign key to the parent.

### Laravel profile (only when the stack is Laravel)

Applies when the project description's Tech Stack names Laravel (or `composer.json` requires `laravel/framework`); it replaces the generic stack conventions and lookup-table shape above. These mirror the *Data conventions*, *Public ids*, *Enums and lookup tables* and *Relations* sections of the Laravel coding guidelines. When the project already carries `docs/agents/coding_guidelines.md`, it wins over this list.

#### Naming and keys (Eloquent defaults)

- Tables **plural, snake_case** (`invoices`, `invoice_lines`). Columns snake_case.
- Every domain, lookup and link table the project adds has `id bigint [pk, increment]`. No UUID or ULID primary keys. Framework-owned tables keep the keys their migrations declare — `sessions.id varchar`, `cache.key varchar`, `password_reset_tokens.email varchar` — never rewrite them to fit this rule.
- Foreign keys are `<singular>_id bigint`, always declared with `ref:` and a `note: 'on delete cascade|restrict|set null'` — cascade for an owned child, restrict for a reference, set null for an optional link. No unconstrained id column.
- `created_at` / `updated_at` on every domain table. `deleted_at` only on tables whose entity is restorable by a story.

#### Public ids

- Every entity that appears in a URL, a page, an API response or a webhook gets `public_id varchar(40) [unique, not null]` with a `note: 'prefix <xxx>_'` — a short lowercase prefix unique per table (`ord_`, `inv_`, `usr_`). The value is generated by the model (prefix + base58 ULID); the schema only declares the column.
- Internal tables (lookups, ledger lines, link tables) have no `public_id`.

#### Business enums: lookup tables

- **No enum columns, ever.** A value the business names — status, type, category, kind, priority, role — gets a lookup table and a foreign key.
- The lookup table is named after the concept, **singular**: `<entity>_<concept>` (`invoice_status`, `product_type`). It has exactly two columns: `id bigint [pk, increment]` and `label varchar [unique, not null]`. No timestamps, no `name`, `slug`, `description` or `is_active` — anything beyond `id` + `label` makes it a real entity.
- The referencing column is `<lookup_table>_id` (`invoice_status_id`), `on delete restrict`.
- `label` holds the enum's backing value verbatim (`paid`); display text is translated in code, never stored.
- A closed **technical** set nobody joins on — currency, locale, timezone — stays a plain `varchar` column (`currency varchar(3)`).

#### Link tables

- A many-to-many link that is only two foreign keys is a pivot named after both singular tables, alphabetical (`product_tag`).
- The moment the link carries anything else — a role, a status, a date, a position — or has a lifecycle, it is an **entity table** named after what it is (`family_members`, `enrollments`), with its own `id`, timestamps and, if exposed, `public_id`.

#### Money, files and tenancy

- Money is `<name>_cents bigint` plus `currency varchar(3)`; never `decimal` or `float`.
- A file is a `<name>_path varchar` column; several files per record → a child table with `file_path`.
- `tenant_id bigint [ref: > tenants.id, not null, note: 'on delete cascade']` on every tenant-owned table, only when the project description declares tenancy.

#### Contexts

- One `TableGroup <Context> { … }` per bounded context of the project description, named exactly like it.
- Every table belongs to exactly one group; a lookup table sits in the group of the entity it qualifies. Infrastructure tables from the framework (`sessions`, `cache`, `jobs`, `failed_jobs`, `password_reset_tokens`) go in `TableGroup Infrastructure`.

### 4. Coverage check (key concepts → tables)

Every Key Concept in the project description must be either persisted by the schema or explicitly declared not persisted. List the concepts mechanically:

```bash
grep -E '^- \*\*[^*]+:\*\*' .spec/init/project-description.md
```

For each concept, name the table(s) that persist it, or record it as **not persisted** with a one-line reason in `## Notes & Conventions` (e.g. derived at runtime, lives in config, out of MVP). A concept with no table and no note is a gap: add the table or the note before closing out.

Build the coverage table for the close-out report:

| Key Concept | Table(s) |
|-------------|----------|
| <Concept> | users, user_profiles |
| <Concept> | — not persisted: <reason> |

### 5. Self-checks (run until green)

After writing, run these checks. Any failure → fix the document via Edit and re-run until all pass. Never report completion with a failing check.

```bash
F=.spec/init/database-schema.md
test -f "$F"
head -1 "$F" | grep -qE '^# .+ — Database Schema$'
# line 3 input stamp present and fresh
[ "$(sed -n '3p' "$F")" = "<!-- inputs: project-description.md@sha256:$(sha256sum .spec/init/project-description.md | cut -c1-12) user-stories.md@sha256:$(sha256sum .spec/init/user-stories.md | cut -c1-12) -->" ]
grep -Fq '## Schema (DBML)' "$F"
grep -q '^```dbml' "$F"
grep -Fq '## Relationships' "$F"
grep -Fq '## Lookup Table Seeds' "$F"
grep -Fq '## Notes & Conventions' "$F"
[ "$(grep -cE '^Table [a-z0-9_]+ \{' "$F")" -ge 1 ]     # >=1 table declared
! grep -iqE '^ +[a-z0-9_]+ +enum' "$F"                  # house rule: no enum columns
# every ref target must be a declared Table (loop must print nothing)
for t in $(grep -oE 'ref: *[<>-]+ *[a-z0-9_]+\.' "$F" | grep -oE '[a-z0-9_]+\.' | tr -d '.' | sort -u); do
  grep -qE "^Table $t \{" "$F" || echo "ref target without table: $t"
done
```

*Laravel profile* — run these as well when the project description's Tech Stack names Laravel:

```bash
F=.spec/init/database-schema.md
if awk '/^## Tech Stack/{f=1;next} /^## /{f=0} f' .spec/init/project-description.md | grep -qi laravel; then
  # every foreign key declares its delete behavior (prints nothing)
  grep -E '\[ref:' "$F" | grep -vE "note: 'on delete (cascade|restrict|set null)'" | sed 's/^/fk without delete behavior: /'
  # lookup tables are id + label only (prints nothing)
  awk '/^Table [a-z0-9_]+_(status|type|kind|category|priority|role|level) \{/{t=$2;f=1;next} f&&/^\}/{f=0} f&&NF&&$1!="id"&&$1!="label"{print "lookup column not allowed: " t "." $1}' "$F"
  # every table sits in exactly one TableGroup, and every group is a declared context (prints nothing)
  for t in $(grep -oE '^Table [a-z0-9_]+' "$F" | awk '{print $2}'); do
    n=$(awk '/^TableGroup /{f=1;next} f&&/^\}/{f=0} f{print $1}' "$F" | grep -cx "$t")
    [ "$n" -eq 1 ] || echo "table in $n groups: $t"
  done
  for g in $(grep -oE '^TableGroup [A-Za-z]+' "$F" | awk '{print $2}' | grep -vx Infrastructure); do
    grep -Eq "^\| $g \|" .spec/init/project-description.md || echo "group is not a declared context: $g"
  done
fi
```

### 6. Close out

After writing, report:

- The path written.
- A count of tables broken down as: domain tables, lookup tables, pivots (*Laravel profile*: and per context).
- *Laravel profile*: the exposed tables with their `public_id` prefixes.
- The coverage table from step 4 (Key Concept | Table(s)) — every concept persisted or noted as not persisted.
- Self-checks: all green — list any check that initially failed and how it was fixed (Red → Green).
- Any open questions still needing the developer's decision.
