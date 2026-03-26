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
to build a picture of the relevant codebase.

**For existing codebases** — use the co-exploration protocol. First,
initialize the plan directory so discovery.md has a place to live:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plan-dir.sh
mkdir -p .temp/plan-mode/active/<plan-name>
```

Then dispatch Codex in the background to explore in parallel:

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  "Explore the codebase for the task: <task-description>. Focus on: \
   1. All consumers of files in the feature area \
   2. Blast radius — what breaks if these files change? \
   3. Test infrastructure covering this area \
   4. Edge cases and constraints in the current implementation \
   5. Cross-module dependencies \
   Write findings to <plan-dir>/discovery.md using append (>>)."
```

While Codex explores consumers and blast radius, Claude focuses on:
- Read CLAUDE.md / README for project conventions
- Read files in the feature area and their imports
- Check recent commits touching relevant modules
- Find sibling files to learn existing patterns

Write your findings to the same `discovery.md` using append (`>>`),
under `## [Claude: <topic>]` headings — both agents share the file.

After both finish, read all of discovery.md and run a convergence round
(see conductor's co-exploration protocol for the full flow).

If `codex` CLI is not available, Claude explores solo.

**For greenfield projects** with no existing codebase, skip the reads and
note the greenfield context — proceed directly to questions.

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

#### Classify: is this a creative task?

While challenging the framing, also determine whether the task is
**creative** — meaning its output has visual, tonal, or experiential
qualities that matter beyond functional correctness.

Signals that a task is creative:
- UI design, illustration, animation, generative art
- Copy-heavy flows (onboarding, marketing, landing pages)
- Branding, visual identity, style direction
- Multi-step experiences where emotional arc matters
- The user used words like "beautiful", "premium", "feels like", "mood",
  "vibe", "tone", "polished", "distinctive"

If creative: your dialogue in Step 3 should explore intent, feeling,
references, and tone — not just architecture and data flow. And Step 7
will include a Creative Brief in `design.md`.

If not creative: proceed normally. A refactor, API integration, or data
pipeline doesn't need a creative brief.

### 3. Ask questions — one at a time

Explore the idea through conversation. One question per message. When
presenting options or multiple-choice questions, use the `AskUserQuestion`
tool — it gives the user a structured selection UI instead of plain text.
Use open-ended text only when the question has no clear set of choices.

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

**For creative tasks** (identified in Step 2), also explore these
dimensions. These questions surface the intent and soul that downstream
skills (svg-art, frontend-design, immersive-frontend, react-native-mobile)
need to produce work with genuine creative direction rather than
defaulting to generic patterns:

- **What should this feel like?** Not what it should do — what feeling
  should someone have when they experience it? "Calm and trustworthy"
  produces very different work than "energetic and playful."
- **Is there a reference, metaphor, or story?** A pricing page inspired
  by "a curated gallery" will look nothing like one inspired by "a
  transparent handshake." The conceptual thread doesn't need to be
  obvious to the end user — it guides decisions invisibly.
- **What's the voice?** If this page/app/experience could talk, how would
  it speak? Formal and precise? Warm and conversational? Witty and
  concise? This applies to all copy — headlines, CTAs, microcopy, error
  messages, empty states.
- **What would make someone pause and think this was made with care?**
  This is the craftsmanship question. The answer is always specific to the
  piece — for a landing page it might be "the typography rhythm between
  sections", for an illustration it might be "the way shapes overlap with
  purpose, not just decoration."

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

### 7. Save, review with Codex, and transition

Once approved:

1. Initialize the plan directory:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plan-dir.sh
   mkdir -p .temp/plan-mode/active/<plan-name>
   ```
2. Write the design to `.temp/plan-mode/active/<plan-name>/design.md`
   using the structure below
3. **Run a mandatory Codex review of design.md** before writing-plans:
   ```bash
   codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
     "Read the design at <plan-dir>/design.md and the discovery at <plan-dir>/discovery.md. \
      Review for: \
      1. Technical feasibility — can this actually be built as described? \
      2. Missed constraints — what does the design not account for? \
      3. Blast radius — does the design underestimate what will break? \
      4. Existing patterns — does the design conflict with codebase conventions? \
      5. Failure modes — are the listed failure modes complete? \
      Return specific, actionable findings."
   ```
   If Codex raises issues, address them: fix the design or document why
   the concern doesn't apply. This ensures even creative work gets a
   technical sanity check before planning begins.

   If `codex` CLI is not available, skip the review and proceed.
4. **Call `Skill(skill: "look-before-you-leap:writing-plans")` to produce
   the plan.** Do NOT write plan.json or masterPlan.md yourself — the
   writing-plans skill sets `codexVerify: true` on every step and applies
   rules you cannot replicate by hand. The design.md feeds directly into
   the plan's Context and Discovery Summary.

**Stop here.** The next step is the implementation plan, not code.
The Skill tool call above is mandatory — do not skip it.

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

## Creative Brief
**Include this section only for creative tasks** (identified in Step 2).
Omit entirely for non-creative work. Each subsection should be written
expressively — this is where you prime downstream skills to treat the
work as craft, not just code. Research the direction fresh for each
task; never fall back on generic presets.

### Intent
What this piece is *about* — the feeling, the meaning, the story it
tells. Not what it does functionally, but what it communicates
emotionally. Write this section as if you're briefing a designer who
needs to understand the soul of the project before touching a single
pixel or choosing a single word.

### Conceptual Thread
The subtle reference, metaphor, or narrative woven into the work.
Someone familiar with the reference should feel it intuitively; everyone
else simply experiences quality. Can be "none" for purely functional
creative work, but consider it for anything with visual or emotional
ambition.

### Visual Direction
Mood, texture, composition approach, color temperature, density, rhythm.
Not specific hex codes or font names — those come later in
frontend-design's Decision Matrix or the implementing skill's own
process. This is the *why* behind those choices. Think in terms of
feeling, not specification.

### Copy Voice
Tone (authoritative? playful? intimate?), vocabulary level (technical?
conversational? poetic?), emotional register (calm? urgent? warm?),
sentence rhythm (short punchy? flowing? varied?). This applies to
every piece of text in the experience — headlines, CTAs, microcopy,
empty states, error messages, onboarding steps.

### Craftsmanship Standard
What "done well" looks like for this specific piece. What details would
make someone pause and think "this was made with care"? Be concrete —
not "high quality" but "the way the illustration's negative space
mirrors the content hierarchy" or "the microcopy that acknowledges the
user's context instead of being generic." This section primes
implementation toward mastery-level output.
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
