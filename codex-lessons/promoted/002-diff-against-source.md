# Diff against source when reimplementing behavior

## Rule
When a new component reimplements existing behavior, read the source and
verify parity: same validation, same save paths, same error handling,
same preconditions.

## Pattern it prevents
Writing a simpler validation regex from memory instead of copying the
existing one. Example: the existing flow enforces structural rules
(no leading/trailing hyphens) but the reimplementation only strips
invalid characters — a weaker check that accepts invalid input.

## Evidence
Codex caught this in a step that reimplemented a settings hook. The agent
wrote new validation logic from memory of the original instead of reading
it. The regression was subtle — both "worked" but the new version accepted
inputs the old one rejected.

## Scope
Universal — applies whenever reimplementing or adapting existing behavior.

## Promoted to
`engineering-discipline/SKILL.md` Phase 2, "Diff against source when
reimplementing behavior" subsection + red flags table entry.
