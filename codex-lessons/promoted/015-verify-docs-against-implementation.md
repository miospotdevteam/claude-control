# Verify documentation against actual implementation

## Rule
When writing documentation, examples, or instructions that reference
CLI flags, function signatures, or behavior: read the actual `--help`
output, function declaration, or source code. Never document from
assumption.

"This runs in a read-only sandbox" must be verified by checking what
`--sandbox read-only` actually does when combined with other flags.

"This function is called `update_step()`" must be verified by reading
the module's exports.

Mechanizable check: for every CLI flag, function name, or behavior
claim in docs, find the source that proves it. If you can't find it,
the claim is unverified and should not be written.

## Evidence
- **Session**: deepen-codex-collaboration, 2026-03-23
- **Codex findings**:
  - `step-3.json` — conductor SKILL.md claims "read-only sandbox"
    in examples that use `--dangerously-bypass-approvals-and-sandbox`
    which disables sandbox entirely (WRONG_PATTERN)
  - `step-7.json` — codex-dispatch SKILL.md has the same contradiction
    (HIGH, WRONG_PATTERN)
  - `step-1.json` — hook calls `plan_utils.update_step()` but the
    API actually exports `update_step_status()` (MISSED_CONSUMER)
- **Session**: paroola-gap-closure, 2026-03-23
- **Codex finding**:
  - `step-11.json` — plan metadata lists module path that doesn't
    match actual import path in code
- **Bug**: Claude writes documentation from its understanding of
  intent rather than from reading the source. It documents what it
  thinks a flag does, not what it actually does.
- **Root cause**: Documentation feels like a "finishing touch" where
  precision matters less than code. But wrong docs are worse than no
  docs — they teach incorrect patterns that propagate.

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

## Status
promoted

## Promotion
- **Where**: `engineering-discipline/SKILL.md` — new Phase 2 section "Verify documentation against implementation" + red flags table entry
- **Date**: 2026-03-23
- **Plan**: promote-codex-lessons
