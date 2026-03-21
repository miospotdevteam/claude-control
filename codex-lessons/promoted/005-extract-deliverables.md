# Extract a deliverables checklist before coding

## Rule
Before writing code for any step, extract every deliverable from the
description and acceptance criteria into a numbered checklist. Verify
each item before marking done.

## Pattern it prevents
Focusing on the primary feature and silently dropping secondary
deliverables. Example: a step description lists a tab content area,
an adaptive label, and a translation section — the agent builds the
complex content area and forgets the label adaptation and translation
section entirely.

## Evidence
Codex caught two instances of this in the same session: a tab label
that should have adapted based on context (acceptance criteria said so
explicitly), and an entire translation UI section that was listed in
the plan description but never implemented. Both were silent scope
cuts — the agent didn't flag them as deferred, just forgot.

## Scope
Universal — applies to any multi-deliverable step.

## Promoted to
`engineering-discipline/SKILL.md` Phase 2, "Extract a deliverables
checklist before coding" subsection + red flags table entry.
Also added "Pre-step deliverables checklist" to conductor Step 3 and
updated persistent-plans execution loop diagram.
