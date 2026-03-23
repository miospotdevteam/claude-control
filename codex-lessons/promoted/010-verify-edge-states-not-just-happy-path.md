# Verify edge states, not just the happy path

## Rule
After implementing any UI component or API handler, systematically ask:
"What if this data is null? Empty array? Error response? Single item
instead of many?" For each conditional render path, verify the output
when the condition is false — not just when it's true.

Mechanizable check: for every `{data && ...}` or `data?.length > 1`
guard in your code, mentally (or actually) test: what renders when
the guard fails? If the answer is "nothing" and the acceptance criteria
expect something visible, you have a bug.

## Evidence
- **Session**: paroola-gap-closure, 2026-03-23
- **Codex findings**:
  - `step-17.json` — audience pie chart silently disappears when
    demographics data is null (SILENT_SCOPE_CUT)
  - `step-17-reverify-1.json` — reach-over-waves chart suppressed
    for single-wave campaigns (`waveChartData.length > 1`)
  - `step-20.json` — campaign detail shows permanent loading skeleton
    on API error (loading/error state conflated)
  - `step-20.json` — brand profile form sends `undefined` instead of
    `null` for cleared fields (empty-string edge case)
  - `step-16.json` — content cards render no thumbnails, only
    emoji + hostname
- **Bug**: Claude builds the success path, tests it mentally, and
  declares done. Null, empty, error, and single-item states are never
  checked.
- **Root cause**: Claude optimizes for "does the feature work?" rather
  than "does every render path produce correct output?" The acceptance
  criteria say "chart shows data" — Claude verifies the chart shows
  data when data exists, but never checks what happens when it doesn't.

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

Frontend-heavy but applies to any conditional logic: API error responses,
empty query results, partial data, single-item collections.

## Status
promoted

## Promotion
- **Where**: `engineering-discipline/SKILL.md` — new Phase 2 section "Verify edge states, not just the happy path" + acceptance criteria checklist item + red flags table entry
- **Date**: 2026-03-23
- **Plan**: promote-codex-lessons
