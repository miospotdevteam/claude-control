# Respect step ownership — never override codex-impl

## Rule
When a plan step has `owner: "codex"` (codex-impl), dispatch Codex via
`run-codex-implement.sh`. Do NOT implement it yourself, regardless of
how "trivially small" the change seems.

The ownership model exists so that a different agent with fresh context
does the work, and you verify independently. When you implement a
codex-impl step yourself:
1. You lose independent verification (Codex can't verify its "own" work)
2. You bypass the direction-locked script's sandbox enforcement
3. You break the symmetric verification model (Claude verifies Codex,
   Codex verifies Claude — never self-verification)

When caught, do NOT work around the verification rejection by calling
`codex exec` directly. The direction-locked scripts exist for a reason.

Mechanizable check: before starting any step, read `owner` and `mode`
from plan.json. If `owner !== "claude"`, dispatch — do not implement.

## Evidence
- **Session**: merchant-parity (miospot), 2026-03-23
- **Bug**: Step 1 is codex-impl. Claude sees the change is "trivially
  small" (add `"beach"` to a union type + update exhaustive switches),
  implements it directly, then tries to mark it done with
  self-verification. `run-codex-verify.sh` correctly rejects because
  step is codex-impl. Claude then:
  1. Tries to mark done anyway with "Claude: verified"
  2. User catches it: "codex is supposed to implement the steps"
  3. Claude acknowledges, then runs `codex exec` directly — bypassing
     the direction-locked script
- **Root cause**: Claude judges task complexity and overrides the plan
  when it deems the work "too simple for Codex." This is the same
  pattern as silent scope cuts — Claude substitutes its judgment for
  the agreed-upon process. The ownership assignment was decided during
  planning for structural reasons (independent verification), not
  because the task is complex.

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

Applies to any plan with mixed ownership (claude-impl + codex-impl
steps).

## Status
promoted

## Promotion
- **Where**: `look-before-you-leap/SKILL.md` (conductor) — new inline warning "Do NOT implement codex-impl steps yourself" in Owner-based dispatch section
- **Date**: 2026-03-23
- **Plan**: promote-codex-lessons
