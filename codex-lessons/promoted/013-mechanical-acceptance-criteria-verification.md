# Verify each acceptance criterion mechanically, not by recall

## Rule
Before marking a step done, re-read its acceptance criteria word by
word. For each criterion, perform a mechanical check — run a command,
read a file, or trace a code path. Never verify by recalling what you
think you implemented.

"I added idempotency keys" is recall. `grep -n "Idempotency-Key"
client.ts` is mechanical verification.

"The migration creates the column" is recall. `grep "event_type"
migration.sql` is mechanical verification.

"Deep links work" is recall. Reading the onClick handler and confirming
it navigates to `applicationId` is mechanical verification.

## Evidence
- **Session**: paroola-gap-closure, 2026-03-23
- **Codex findings**:
  - `step-24.json` (paroola) — idempotency keys required on all POSTs
    but not added (acceptance criteria said "idempotency keys on all
    POST helpers")
  - `step-24.json` (paroola) — schema adds `event_type` column but
    migration SQL doesn't create it (HIGH — runtime crash)
  - `step-10.json` — admin notifications don't deep-link to
    application despite criteria requiring it
  - `step-16.json` — content cards don't render thumbnails despite
    criteria requiring visual preview
  - `step-11.json` — file listed in step's files array never actually
    modified (plan metadata drift)
- **Bug**: Claude satisfies the spirit of acceptance criteria ("I built
  the feature") without checking each specific condition. Secondary
  criteria (idempotency, deep-links, thumbnails) are forgotten while
  primary functionality works.
- **Root cause**: Claude reads acceptance criteria during planning but
  verifies from memory during execution. Memory drifts — especially
  for secondary criteria that aren't the step's main deliverable.

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

## Status
promoted

## Promotion
- **Where**: `engineering-discipline/SKILL.md` — new acceptance criteria checklist item "verified mechanically (grep, read file, run command) — not by recall" + red flags table entry
- **Date**: 2026-03-23
- **Plan**: promote-codex-lessons
