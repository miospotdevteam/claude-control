# Reject invalid enum values — never silently coerce

## Rule
When handling external input that maps to an enum or closed set, reject
unknown values with an explicit error. Never silently coerce an invalid
value to a default.

`if (!validPlatforms.includes(input)) return error(400, "Invalid platform")`
— correct.

`const platform = validPlatforms.includes(input) ? input : "both"` —
wrong. Hides contract drift, makes debugging impossible, and teaches
callers that any string is accepted.

This also applies to "mandatory" protocol requirements: if a rule says
"no exceptions," do not add an opt-out path. A "mandatory" step with a
skip clause is the protocol equivalent of silently coercing an invalid
enum to a default.

## Evidence
- **Session**: paroola-gap-closure, 2026-03-23
- **Codex findings**:
  - `step-3.json` — unknown platform strings silently rewritten to
    `'both'` instead of validation error (WRONG_PATTERN)
- **Session**: deepen-codex-collaboration, 2026-03-23
- **Codex findings**:
  - `step-5.json` — codexVerify section says "no exceptions" but
    immediately allows CLI-unavailable skip (SILENT_SCOPE_CUT)
  - `step-6.json` — "mandatory" Codex design review made optional by
    skip path (SILENT_SCOPE_CUT)
  - `step-2.json` — routing table contradicts design spec, keeping
    categories on claude-impl (SILENT_SCOPE_CUT)
- **Bug**: Claude defaults to "make it work" over "make it strict."
  When validation feels inconvenient, it adds a fallback that quietly
  defeats the requirement.
- **Root cause**: Claude's instinct is to avoid errors. When it sees
  invalid input, it "helpfully" converts to something valid rather than
  rejecting. When a requirement feels impractical, it adds an escape
  hatch rather than flagging the conflict.

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

## Status
promoted

## Promotion
- **Where**: `engineering-discipline/SKILL.md` — new Phase 2 section "No silent coercion on external input" + red flags table entry
- **Date**: 2026-03-23
- **Plan**: promote-codex-lessons
