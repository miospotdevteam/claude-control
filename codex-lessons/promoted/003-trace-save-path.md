# Trace the save path for every editable field

## Rule
After writing any UI with mutable state, verify every editable field has
a complete path: onChange → state → mutation → API → persistence.

## Pattern it prevents
Building a settings panel where editable fields update local state but
never call an API mutation. The UI looks correct — users edit, see their
changes reflected — then lose everything on navigation because nothing
was ever persisted.

## Evidence
Codex caught this as the highest-severity bug in a 10-step session. The
agent built state loading and display but forgot the auto-save effect.
The agent's own assessment: "most embarrassing bug — users would edit,
see changes, then lose everything on page navigation."

## Scope
Universal — applies to any UI with editable state that needs persistence.

## Promoted to
`engineering-discipline/SKILL.md` Phase 2, "Trace the save path for
every editable field" subsection + red flags table entry.
