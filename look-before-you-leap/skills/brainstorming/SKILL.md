---
name: brainstorming
description: "Use before any creative work — new features, components, behavior changes. Turns vague ideas into concrete designs through collaborative dialogue before any code is written. Adapted from superpowers by Jesse Vincent (github.com/obra/superpowers, MIT License)."
---

# Brainstorming

Turn ideas into designs before writing code. Understand what you're
building, explore approaches, get approval, then plan.

**No code until the design is approved.** No exceptions, no matter how
simple the task seems. Simple tasks are where unexamined assumptions
waste the most time.

---

## The Steps

### 1. Understand the context

Read the codebase before asking anything. Check files, docs, recent
commits — build a picture of what exists and how things work. You need
this context to ask good questions.

### 2. Ask questions — one at a time

Explore the idea through conversation. One question per message. Prefer
multiple choice when the options are clear, open-ended when they're not.

Focus on:
- What problem does this solve?
- Who is it for?
- What does success look like?
- What are the constraints?

Keep going until you could explain the feature to another engineer.

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
1. Write the design to `.temp/plan-mode/active/<plan-name>/design.md`
2. Create `masterPlan.md` in the same directory using the persistent-plans
   skill — the design feeds directly into the plan's Context and Discovery
   Summary

**Stop here.** The next step is the implementation plan, not code.

---

## Principles

- **One question at a time** — don't overwhelm
- **YAGNI** — cut anything that isn't clearly needed
- **Explore before committing** — always consider alternatives
- **Validate incrementally** — get approval as you go, not all at once
- **Stay flexible** — circle back when something doesn't add up
