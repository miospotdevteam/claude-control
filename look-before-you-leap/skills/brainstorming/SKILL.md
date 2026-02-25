---
name: brainstorming
description: "Use before any creative work — new features, components, behavior changes. Turns vague ideas into concrete designs through collaborative dialogue before any code is written. Do NOT use for: implementation planning (use writing-plans), debugging (use systematic-debugging), refactoring (use refactoring), or pure codebase exploration without a design goal."
---

# Brainstorming

Turn ideas into designs before writing code. Understand what you're
building, explore approaches, get approval, then plan.

**Announce at start:** "I'm using the brainstorming skill to explore the
design before any code is written."

**No code until the design is approved.** No exceptions, no matter how
simple the task seems. Simple tasks are where unexamined assumptions
waste the most time.

---

## The Steps

### 1. Understand the context

Follow engineering-discipline Phase 1 (Orient Before You Touch Anything)
to build a picture of the relevant codebase:

- Read CLAUDE.md / README for project conventions
- Read files in the feature area and their imports
- Check recent commits touching relevant modules
- Find sibling files to learn existing patterns

If this is a **greenfield project** with no existing codebase, skip the
reads and note the greenfield context — proceed directly to questions.

### 2. Ask questions — one at a time

Explore the idea through conversation. One question per message. Prefer
multiple choice when the options are clear, open-ended when they're not.

Focus on:
- What problem does this solve?
- Who is it for?
- What does success look like?
- What are the constraints?

Keep going until you could explain the feature to another engineer.

If the user **can't answer** a question (doesn't know constraints yet,
hasn't decided), propose reasonable defaults and flag them explicitly as
assumptions that can be revised later.

### 3. Propose approaches

Present 2-3 different ways to build it. For each one: what it looks like,
what it's good at, what the trade-offs are. Lead with your recommendation
and say why.

### 4. Present the design

Walk through the design section by section. Scale detail to complexity —
a few sentences for straightforward parts, more for nuanced ones. After
each section, check: does this look right?

Cover what's relevant: architecture, components, data flow, error
handling, testing. Skip sections that don't apply.

### 5. Save and transition

Once approved:

1. Initialize the plan directory:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/init-plan-dir.sh
   mkdir -p .temp/plan-mode/active/<plan-name>
   ```
2. Write the design to `.temp/plan-mode/active/<plan-name>/design.md`
   using the structure below
3. Invoke `look-before-you-leap:writing-plans` to create `masterPlan.md`
   in the same directory — the design feeds directly into the plan's
   Context and Discovery Summary

**Stop here.** The next step is the implementation plan, not code.

#### design.md structure

Use these sections (skip any that don't apply):

```markdown
# Design: <Title>

## Problem
What problem this solves and for whom.

## Constraints
Hard requirements, technical limitations, compatibility needs.

## Chosen Approach
The selected approach and why it was chosen over alternatives.

## Alternatives Considered
Other approaches explored and why they were rejected.

## Key Decisions
Important design choices made during brainstorming with rationale.

## Open Questions
Anything unresolved or flagged as an assumption.
```

---

## Principles

- **One question at a time** — don't overwhelm
- **YAGNI** — cut anything that isn't clearly needed
- **Explore before committing** — always consider alternatives
- **Validate incrementally** — get approval as you go, not all at once
- **Stay flexible** — circle back when something doesn't add up
