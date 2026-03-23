# Ship tests alongside new behavior — no exceptions

## Rule
Every new API route, webhook handler, contract change, or aggregation
function MUST ship with at least one targeted test. "Existing tests
still pass" is not test coverage — it means you didn't break unrelated
code, not that your new code works.

When Codex flags MISSING_TEST, treat it as equal priority to code bugs.
Do not fix the code finding and ignore the test finding in the same
reverify cycle.

Mechanizable check: after implementing new behavior, grep for a test
file that imports or calls the new function/route. If none exists,
write one before marking the step done.

## Evidence
- **Session**: paroola-gap-closure, 2026-03-23
- **Codex findings**:
  - `step-2-reverify-1.json` — MioSpot contract fixes have no targeted
    test coverage (MISSING_TEST)
  - `step-3.json` — request-shape handling changes untested
  - `step-5-reverify-1.json` — webhook behaviors untested at
    route/contract level
  - `step-17.json` — analytics aggregation path untested
  - `step-17-reverify-1.json` — STILL untested after reverification
    (same gap flagged twice)
  - `step-24.json` (paroola) — Stripe client with no test coverage
  - `step-25.json` (paroola) — Stripe Connect routes untested
- **Bug**: Claude fixes code bugs Codex finds but consistently ignores
  MISSING_TEST findings in the same reverify round. The test gap
  persists across multiple verification cycles.
- **Root cause**: Claude treats tests as lower priority than code
  correctness. When a reverify round contains both a code bug and a
  test gap, Claude fixes the code and skips the test, hoping the next
  round won't flag it again.

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

## Status
promoted

## Promotion
- **Where**: `engineering-discipline/SKILL.md` — broadened "New endpoints need tests and docs" → "New behavior needs tests and docs" (webhooks, aggregation, contracts) + MISSING_TEST priority rule + red flags table entry
- **Date**: 2026-03-23
- **Plan**: promote-codex-lessons
