# GitHub Copilot Instructions

## Purpose

This repository follows a specification-first, plan-driven development workflow.

Copilot must help move work from a confirmed requirement to an implemented, tested, and reviewable change. Do not skip clarification, architecture analysis, acceptance criteria, or validation.

## Source of truth

Before making changes, inspect the repository's actual documentation and implementation:

1. `AGENTS.md`
2. `CLAUDE.md`, if present
3. `docs/agents/`
4. `.spec/`
5. Project manifests, configuration, CI workflows, and existing tests

Treat the codebase, manifests, CI configuration, and maintained documentation as authoritative descriptions of the current system. Do not invent architecture, conventions, dependencies, endpoints, data models, or business rules.

If required information cannot be verified, state the uncertainty and ask for clarification rather than guessing.

## Operating workflow

### 1. Understand the request

- Normalize the requested outcome.
- Identify affected components, constraints, dependencies, and risks.
- Separate confirmed requirements from assumptions.
- Identify ambiguities that could change the implementation.
- Do not implement until the intended behavior is sufficiently clear.

### 2. Inspect the architecture

Before editing:

- Locate the relevant modules, layers, services, models, interfaces, and tests.
- Read the applicable files completely enough to understand their contracts.
- Follow existing dependency direction and naming conventions.
- Prefer extending existing abstractions over introducing parallel mechanisms.
- Avoid unrelated refactoring.

### 3. Define acceptance criteria

Convert the request into binary, testable criteria.

Acceptance criteria must describe observable behavior, including:

- Expected successful behavior
- Validation and error behavior
- Authorization and security behavior
- Persistence and data-integrity behavior
- Compatibility requirements
- Relevant edge cases

When appropriate, document the criteria in the relevant `.spec/` feature directory before implementation.

### 4. Plan the change

Create a concise implementation plan before editing. The plan should include:

- Files to create or modify
- The responsibility of each change
- Dependencies between tasks
- Migration or compatibility concerns
- Tests and validation commands
- Risks and rollback considerations

Keep the plan proportional to the change. Do not create unnecessary process overhead for trivial edits.

### 5. Implement

- Make the smallest coherent change that satisfies the acceptance criteria.
- Preserve public APIs unless the requirement explicitly authorizes a breaking change.
- Follow the repository's established style and conventions.
- Keep responsibilities separated and interfaces focused.
- Validate all external input at trust boundaries.
- Apply least privilege and avoid exposing secrets, credentials, tokens, or sensitive data.
- Do not add dependencies without a demonstrated need.
- Do not weaken tests, security controls, type checks, lint rules, or CI requirements to obtain a passing result.
- Do not modify generated files manually when a supported generator exists.
- Do not alter unrelated files.

### 6. Validate

Run the narrowest relevant checks first, then broader checks as appropriate:

1. Formatting
2. Static analysis or type checking
3. Unit tests
4. Integration or feature tests
5. Build and other repository-defined checks

Use the commands documented in `AGENTS.md`, `docs/agents/`, project manifests, and CI workflows.

Never claim that a check passed unless it was actually run and its result is known. Report:

- Command executed
- Result
- Relevant failure details
- Any checks that could not be run and why

### 7. Review the result

Before finishing:

- Compare the implementation against every acceptance criterion.
- Inspect the final diff.
- Check for accidental changes, debug output, temporary files, and secrets.
- Check backward compatibility and failure handling.
- Confirm that tests cover the changed behavior.
- Update documentation when behavior, configuration, APIs, or operational procedures changed.

## Task execution rules

- Work on one coherent task at a time.
- Keep progress explicit with a short checklist.
- Mark a task complete only after its implementation and validation are complete.
- If a task is already implemented, verify it rather than rewriting it.
- If validation fails, diagnose the actual cause and fix it; do not merely rerun commands without analysis.
- If a requirement conflicts with repository conventions or documented architecture, stop and report the conflict.
- If a change requires a decision from the developer, present the decision clearly before proceeding.

## Git and change hygiene

- Do not create commits, branches, tags, releases, or pull requests unless explicitly requested.
- Do not reset, discard, or overwrite user changes.
- Preserve unrelated work in the working tree.
- Keep diffs focused and reviewable.
- Do not include generated artifacts, logs, credentials, or local environment files unless explicitly required.

## Communication format

For implementation work, report:

1. **Plan** — concise list of intended changes
2. **Changes** — files and behavior changed
3. **Validation** — commands and results
4. **Remaining issues** — unresolved uncertainty, skipped checks, or follow-up decisions

Use precise language. Distinguish verified facts from assumptions. Do not claim completion when acceptance criteria or validation remain incomplete.

## Important limitation

This file adapts the repository's specification-first principles to GitHub Copilot's repository-instruction format. It does not reproduce Claude Code plugin commands, agents, hooks, or the `ralph.sh` autonomous execution mechanism. Those mechanisms require separate tooling and must not be implied to be available to Copilot.
