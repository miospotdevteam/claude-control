# Ship complete locale updates with new user-visible strings

## Rule
When adding user-visible strings, update all locale files in the same
step. English fallbacks and hardcoded default props count as missing
translations, not acceptable placeholders.

Mechanizable check: grep changed files for new `t(` calls and localized
props, list the locale files in scope, and verify every new key exists
in every locale before marking the step done.

## Pattern it prevents
Shipping new UI copy through English fallbacks, shared-component default
labels, or partially updated locale bundles. The feature looks complete
in one language while every other locale silently regresses.

## Evidence
- **Finding cluster**: 14 `MISSING_I18N` findings across 8 plans
- **Example**: `mobile-merchant-ux-polish` step 4 — new section headers
  ship via English fallbacks instead of locale files
- **Example**: `mobile-design-system` step 6 — `DialPickerSheet`
  ships English fallback labels instead of localized props
- **Root cause**: agents treat fallback English as "good enough" and do
  not mechanically audit locale coverage before closing the step

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

Especially important for shared UI components, accessibility labels,
sheet/dialog copy, and any step that introduces new text keys.

## Status
promoted

## Promotion
- **Where**: `look-before-you-leap/skills/engineering-discipline/SKILL.md`
  (`### i18n contract`), `look-before-you-leap/codex-skills/lbyl-verify/SKILL.md`
  (Step 3.5 i18n completeness)
- **Date**: 2026-03-28
- **Plan**: `codex-findings-improvements`
