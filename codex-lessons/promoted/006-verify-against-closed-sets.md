# Verify against closed sets

## Rule
Before declaring a step done, re-read the source definition for every
closed-set value your work produces (enums, schema fields, function
signatures, tool parameters, file paths) and verify character-for-character.
Never verify from memory.

## Pattern it prevents
Claude implements from its memory of a specification rather than re-reading
the source. Memory drifts during implementation: the spec says `"claude-impl"`
but memory says `"dynamic"` seems reasonable; the spec says `step` is a
number but memory says `"{step.id}"` is fine because other fields use that
syntax. The result is values that violate closed constraints — invented enum
members, wrong field names, mismatched signatures, assumed tool parameters.

## Evidence
9 findings across 2 plans:
- **codex-integration** (6 findings): invented enum values (`"dynamic"` for
  mode), assumed `codex-reply` accepts `developer-instructions` (it doesn't),
  wrote relative paths without resolving from the consumer's directory, used
  string where number was required in schema.
- **settings-account-email-otp** (3 findings): implemented function from
  memory instead of re-reading spec (wrong transport, wrong signature),
  tests that skip the suite entirely.

## Scope
Universal — applies to any work that produces values conforming to a
defined set (enums, schemas, signatures, tool schemas, file paths).

## Promoted to
- `engineering-discipline/SKILL.md` Phase 3: new "Verify against closed
  sets" subsection (between "No pre-existing exemptions" and "Self-audit
  after corrections")
- `engineering-discipline/SKILL.md` acceptance checklist: new item for
  closed-set verification
- `engineering-discipline/SKILL.md` red flags table: broadened row for
  all closed-set values from memory + 2 new rows (tool parameter schemas,
  file path resolution)
