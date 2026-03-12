---
name: brainstorming
description: "Use before any creative work — new features, components, behavior changes. Turns vague ideas into concrete designs through collaborative dialogue before any code is written. Make sure to use this skill whenever the user wants to think through design options, is torn between approaches, wants to brainstorm or explore tradeoffs, is unsure about data models or system design, or describes a feature idea with multiple possible solutions and hasn't decided on the approach yet. Do NOT use for: implementation planning (use writing-plans), debugging (use systematic-debugging), refactoring (use refactoring), or pure codebase exploration without a design goal."
---

# Brainstorming

Turn ideas into designs before writing code. Your job is not to produce a
plan — it's to make sure the RIGHT thing gets built. That means challenging
assumptions, shrinking scope, and finding the approach that solves the
actual problem with the least complexity.

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

### 2. Challenge the framing

Before diving into how to build it, question whether the request is the
right thing to build. This is the step that separates brainstorming from
just planning.

Ask yourself (and the user when appropriate):

- **Is this the right problem?** Sometimes the user describes a solution
  ("add notifications") when the actual problem is different ("users miss
  deadline changes"). The solution to the real problem might be simpler.
- **Does something already exist?** Check if the codebase already has
  partial solutions, utilities, or patterns that cover part of the need.
  Building on what exists is almost always better than starting fresh.
- **What's the smallest version that's useful?** The user's description
  often includes v2 and v3 features mixed in with the core need. Identify
  the minimum that solves the actual problem. You can always add more
  later — you can't easily remove complexity.

If you realize the framing should change, say so directly: "The way I see
it, the core problem is X. The simplest thing that solves X is Y. The
other parts you mentioned (A, B, C) could come later. Does that match
your thinking?"

### 3. Ask questions — one at a time

Explore the idea through conversation. One question per message. Prefer
multiple choice when the options are clear, open-ended when they're not.

Go beyond surface-level requirements. The most valuable questions are the
ones the user hasn't thought about yet:

- **What breaks?** "If 50 users get this notification at once, what
  happens? If the board has 200 tasks, does it still work?"
- **What's the user's actual workflow?** "Walk me through what happens
  after they see this notification. What do they do next?"
- **What are you NOT building?** Explicitly naming what's out of scope
  prevents scope creep during implementation.
- **What would make you regret this design in 3 months?** This surfaces
  constraints the user knows but hasn't articulated.

Keep going until you could explain the feature to another engineer.

If the user **can't answer** a question (doesn't know constraints yet,
hasn't decided), propose reasonable defaults and flag them explicitly as
assumptions that can be revised later.

### 4. Propose approaches

Present 2-3 genuinely different ways to solve the problem. "Different"
means different in concept, not just in technology choice.

Bad alternatives (same idea, different library):
- "Use @dnd-kit for drag-and-drop"
- "Use react-beautiful-dnd for drag-and-drop"
- "Use native HTML5 drag-and-drop"

Good alternatives (different concepts):
- "Kanban board with drag-and-drop status changes"
- "Inline status dropdown on each task card (no board needed)"
- "Automated status transitions based on activity (task auto-moves to
  'In Progress' when someone starts a timer)"

For each approach: what it looks like, what it's good at, what could go
wrong, and how complex it is to build. Lead with your recommendation and
say why — don't be neutral. Have an opinion.

**Always include a "do less" option.** One approach should be the smallest
possible change that still solves the problem. This anchors the discussion
and forces the other options to justify their additional complexity.

### 5. Stress-test the chosen approach

Before finalizing, pressure-test the design against real-world scenarios:

- **Scale:** What happens with 10x the expected data? 100x users?
- **Failure modes:** What happens when the API call fails? When the user
  has no network? When two users edit the same thing?
- **Edge cases:** Empty states, maximum values, unusual inputs, permission
  boundaries.
- **Migration:** How does existing data/behavior change? Is there a
  transition period?

Don't just list these as "open questions" — make a decision for each one
(even if the decision is "defer to v2") and explain why. The design should
be specific enough that an engineer could start building without asking
follow-up questions about these scenarios.

### 6. Present the design

Walk through the design section by section. Scale detail to complexity —
a few sentences for straightforward parts, more for nuanced ones. After
each section, check: does this look right?

Cover what's relevant: architecture, components, data flow, error
handling, testing. Skip sections that don't apply.

### 7. Save and transition

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

Use these sections. **Problem, Scope, Chosen Approach, and Failure Modes
are required** — do not scatter their content into other sections. The
rest can be skipped if they don't apply.

```markdown
# Design: <Title>

## Problem
What problem this solves, for whom, and why it matters now. If the
problem framing changed during brainstorming, note what the original
request was and why the reframing is better.

## Scope
**Required section — do not skip or scatter.** Two subsections:
- **In scope**: What this version delivers (bullet list).
- **Out of scope**: What this version explicitly does NOT deliver, and
  why. Every "we could add X later" thought belongs here, not buried
  in other sections.

## Chosen Approach
The selected approach, how it works, and why it won over alternatives.
Include enough detail that an engineer could start building: data model
changes, API surface, component structure, key interactions.

## Alternatives Considered
Other approaches explored and why they were rejected. Include the
"do less" option and why it was or wasn't sufficient.

## Failure Modes
**Required section — do not skip.** What can go wrong and how the design
handles it. Network failures, concurrent edits, scale limits, permission
edge cases. For each one: what happens and what the user sees. This
section must appear in design.md, not just in the transcript.

## Key Decisions
Important design choices with rationale. Format as a table:
| Decision | Rationale |

## Assumptions
Items flagged during brainstorming where the user deferred to your
judgment. Each should be specific enough to validate or invalidate
later.
```

---

## Principles

- **Challenge, then build** — question the framing before solving it
- **One question at a time** — don't overwhelm
- **Always include "do less"** — the simplest option anchors complexity
- **Decide, don't defer** — open questions are for unknowables, not for
  things you can reason about now
- **Name what you're NOT building** — explicit scope prevents creep
- **Have an opinion** — recommend, don't just present options neutrally
