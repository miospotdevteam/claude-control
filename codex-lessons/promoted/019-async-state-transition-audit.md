# Audit async and state transitions, not just the first render

## Rule
After implementing any UI with async data or multi-entity selection,
fill in an async/state-transition matrix. Cover at minimum: switch
item, request in flight, request fails, close/reopen, stale response
arrives late, and cosmetic defaults versus persisted state.

Mechanizable check: list each producer path (`effect`, URL init, wizard
navigation, event source), then record the pending, success, failure,
and switched-away outcome for every transition before marking done.

## Pattern it prevents
Features that work on initial load but break when the user switches
entities, closes and reopens a modal, triggers overlapping requests, or
receives a late response that overwrites newer state.

## Evidence
- **Finding cluster**: state-transition bugs account for most of the
  36 `OTHER` findings in the analyzed set
- **Example**: `monorepo-audit` step 11 — status changes from booking
  modal fail silently
- **Example**: `beach-editor-ui-review` step 2 — season-price loading
  is not request-scoped, so stale data can win the race
- **Root cause**: agents verify loading and save flows once, but do not
  enumerate producer paths and transition outcomes under async churn

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

Applies to modals, sheets, wizards, tabs, pickers, dashboards, and any
UI that mixes async fetching with selection or navigation state.

## Status
promoted

## Promotion
- **Where**: `look-before-you-leap/skills/engineering-discipline/SKILL.md`
  (`### Async/state-transition matrix`), `look-before-you-leap/codex-skills/lbyl-verify/SKILL.md`
  (Step 3.5 state transitions)
- **Date**: 2026-03-28
- **Plan**: `codex-findings-improvements`
