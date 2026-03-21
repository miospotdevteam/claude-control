# Match existing operation preconditions when wrapping

## Rule
When building a unified flow that calls existing operations, read each
operation's handler and replicate its precondition checks exactly.

## Pattern it prevents
Building a "publish all" flow that checks `isPro && slug.length > 0`
when the individual publish handler gates on `slugStatus === "available"`
(which requires async validation). The unified flow lets users trigger
operations that the individual handlers would reject.

## Evidence
Codex caught this in a step that built a unified publish flow wrapping
multiple existing operations. The agent invented simpler preconditions
instead of reading the actual handlers. The weaker checks would have
allowed publishing with invalid/unvalidated data.

## Scope
Universal — applies whenever wrapping or orchestrating existing operations.

## Promoted to
`engineering-discipline/SKILL.md` Phase 2, "Match existing operation
preconditions when wrapping" subsection + red flags table entry.
