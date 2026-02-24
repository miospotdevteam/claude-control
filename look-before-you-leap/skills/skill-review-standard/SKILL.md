---
name: skill-review-standard
description: "Strict review rubric for any new or updated skill before you consider it done. Catches ambiguity before runtime, enforces deterministic workflows, and keeps skills lean, discoverable, and testable. Use when authoring, editing, or reviewing a SKILL.md file. Do NOT use for reviewing application code or non-skill files."
---

# Skill Review Standard (for Skills You Author)

Use this file as a strict review rubric for any new or updated skill before you consider it done.

Primary goals:
- Catch ambiguity before runtime
- Enforce deterministic workflows where needed
- Keep skills lean, discoverable, and testable

---

## 1. Review Outcome Contract (required)

A review is complete only if all of the following are true:
1. Trigger conditions are explicit and non-overlapping.
2. Workflow is executable end-to-end with no missing steps.
3. Safety constraints and boundaries are clear.
4. Verification steps are concrete and runnable.
5. Output format and success criteria are testable.

If any item fails, the skill is not review-approved.

---

## 2. Metadata Quality Checks (`name`, `description`)

Check `SKILL.md` frontmatter first.

Pass criteria:
- `name` is short, action-oriented, and stable.
- `description` clearly states:
  - What the skill does
  - When to use it
  - When not to use it
- Trigger language includes concrete user intents (not vague keywords only).
- Description avoids overlaps with adjacent skills unless boundaries are explicit.

Common failures:
- Description is too generic ("helps with coding tasks")
- No negative trigger guidance ("do not use when...")
- Scope overlaps with another skill without tie-break rules

---

## 3. Workflow Integrity Checks

The body must define an operational sequence, not just advice.

Pass criteria:
1. Ordered steps exist (discovery -> execution -> verification).
2. Each step has an input, an action, and an output artifact.
3. External dependencies are declared before use.
4. Failure paths are handled ("if X fails, do Y").
5. Steps can be followed without hidden project knowledge.

Common failures:
- "Use best practices" without concrete procedure
- Missing prerequisite checks (auth, env vars, tools)
- No fallback behavior when required tools are unavailable

---

## 4. Scope and Safety Boundaries

Every skill should constrain blast radius and define autonomy limits.

Pass criteria:
- Explicit "must not" list exists.
- Interaction levels are defined (explicitly states where user confirmation is required vs. where the agent may proceed autonomously).
- Destructive actions require confirmation.
- Out-of-scope areas are listed.
- File/path boundaries are specified when relevant.
- Security/privacy constraints are explicit for sensitive data.

Common failures:
- Silent schema/dependency changes
- Unbounded refactors in "quick fix" workflows
- No policy for handling secrets or credentials

---

## 5. Verification and Acceptance Criteria

Do not accept "looks good."

Pass criteria:
1. The skill defines exactly how to validate success.
2. Verification includes concrete commands when relevant (test/lint/typecheck/build).
3. Expected outcomes are explicit (what must pass, what artifacts must exist).
4. If verification cannot run, the required reporting format is defined.

Recommended acceptance block in each skill:
```md
## Acceptance Criteria
- [ ] Required commands executed: `<cmd1>`, `<cmd2>`
- [ ] Expected artifacts produced: `<files/reports>`
- [ ] No unexpected files changed
- [ ] Any unresolved risks documented
```

---

## 6. Progressive Disclosure and Context Efficiency

Keep `SKILL.md` focused; move detail to references/scripts.

Pass criteria:
- Core workflow is in `SKILL.md`.
- Large domain details live in `references/` and are linked from `SKILL.md`.
- Repeated deterministic logic is implemented in `scripts/`.
- No duplicate content across `SKILL.md` and references.

Common failures:
- Bloated `SKILL.md` with rarely needed detail
- Missing links to important reference files
- Rewriting script logic in prose repeatedly

---

## 7. Output Contract Quality

The skill must constrain response format for downstream reliability.

Pass criteria:
- Expected response structure is specified.
- Verbosity expectations are clear.
- Required evidence is explicit (file refs, command results, risk notes).
- For reviews, severity ordering is specified.

Common failures:
- No output schema
- Mixed summary/findings order
- Missing evidence requirements

---

## 8. Reviewer Output Template (use for every review)

```md
# Skill Review Report

## Verdict
- Status: PASS | PASS WITH CONDITIONS | FAIL
- Skill: `<skill-name>`
- Reviewer confidence: High | Medium | Low

## Findings (ordered by severity)
1. [Severity] `<file:line>` - issue
   - Why it matters:
   - Suggested fix:

## Acceptance Criteria Check
- [ ] Trigger quality
- [ ] Workflow integrity
- [ ] Scope/safety boundaries
- [ ] Verification clarity
- [ ] Output contract

## Residual Risks
- `<risk or "none">`

## Required Changes Before Approval
1. `<change>`
2. `<change>`
```

---

## 9. Severity Rubric

Use this severity model consistently:
- Critical: likely to cause unsafe/destructive behavior or major incorrect outcomes.
- High: likely to produce wrong results or repeated failures.
- Medium: quality/reliability gap that causes rework.
- Low: clarity/style issue with limited runtime impact.

---

## 10. Fast Review Checklist (copy/paste)

```md
- [ ] Frontmatter has precise trigger boundaries
- [ ] Step-by-step workflow is executable
- [ ] Preconditions/fallbacks are documented
- [ ] Safety, autonomy boundaries, and "must not" rules are explicit
- [ ] Verification commands and expected outcomes are defined
- [ ] Output format is deterministic
- [ ] References/scripts are used for heavy detail
- [ ] No contradictory or duplicated instructions
```

---

## 11. Design Rules for Future Skill Authoring

When writing new skills, default to:
1. Specific triggers over broad descriptions.
2. Ordered procedures over general advice.
3. Deterministic scripts for repetitive fragile tasks.
4. Explicit acceptance criteria over implicit expectations.
5. Minimal context footprint with linked references.

If a skill cannot be reviewed against this document in under 10 minutes, it is too ambiguous or too bloated.

---

## 12. Standard Skill Skeleton

Use this template when authoring a new `SKILL.md` to ensure it passes the rubric above.

```md
# [Action-oriented Name]

**Description:** [What it does, when to use it]
**Do NOT use when:** [Explicit negative boundaries]
**Prerequisites:** [Required states or contexts]

## Execution Workflow
1. **Pre-flight Check:** [Verify prerequisites]
2. **Action [Step Name]:** [What to do, input needed, tool to use]
   - *On Failure:* [Fallback action]
3. **Action [Step Name]:** [Next step...]
   - *Requires User Confirmation before proceeding.*

## Acceptance Criteria
- [ ] Required commands executed: `<cmd1>`, `<cmd2>`
- [ ] Expected artifacts produced: `<files/reports>`
- [ ] No unexpected files changed

## Reference Links & Scripts
- Deterministic script: `scripts/task.sh`
- Domain context: `references/domain.md`
```
