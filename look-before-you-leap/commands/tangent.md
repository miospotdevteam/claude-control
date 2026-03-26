---
description: "Load discovery context from another session's active plan to continue exploring a tangent. Usage: /tangent [--<PPID>]"
allowed-tools: ["Bash", "Read", "Glob", "Grep"]
---

# Tangent — Cross-Session Discovery Sharing

Load discovery context from another session's active plan so you can
continue brainstorming or exploring a related area without starting
from zero.

## Step 1: Find the source plan

The user may provide a `--<PPID>` flag to target a specific session.

```bash
PLAN_UTILS="${CLAUDE_PLUGIN_ROOT}/scripts/plan_utils.py"
PROJECT_ROOT="$(pwd)"
```

**If a PPID was provided** (e.g., `/tangent --24399`):
```bash
python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" <PPID>
```

**If no PPID was provided**, list all active plans with their owners:
```bash
bash .temp/plan-mode/scripts/plan-status.sh
```

If there's only one active plan (that isn't owned by this session), use
it. If there are multiple, show the list to the user and ask which one
to read from.

If the only active plan is owned by the current session ($PPID), tell
the user there are no other sessions to read from.

## Step 2: Read the discovery context

Once you have the source plan.json path, read these files from its
directory (all are optional — read whatever exists):

1. **plan.json** — read the `discovery` object and `context` field.
   These contain the structured exploration findings: scope, entry
   points, consumers, blast radius, patterns, and confidence.

2. **discovery.md** — free-form exploration notes, often including
   cross-agent findings and detailed file:line evidence.

3. **design.md** — if brainstorming produced a design document, this
   contains the problem framing, chosen approach, alternatives
   considered, and critically the **Out of scope** and **Assumptions**
   sections.

4. **masterPlan.md** — the approved plan showing what the other session
   IS building (helps you understand the boundary of their work vs
   yours).

## Step 3: Extract tangent-worthy items

From the materials above, pull out everything relevant to continued
exploration. Pay special attention to:

- **Out of scope** items from design.md — these are explicitly deferred
  ideas that the other session chose not to pursue. They are the most
  likely tangent targets.
- **Assumptions** from design.md — unvalidated decisions that might
  need their own exploration.
- **Open questions** from discovery.md — things the other session
  flagged but didn't resolve.
- **Adjacent systems** mentioned in the discovery object — consumers,
  blast radius areas, or patterns that touch the tangent area.
- **"We could also..." or "Future work" notes** — anything that
  signals a related but deferred idea.

Don't be rigid about this — not every plan will have all of these.
Extract whatever context exists that's relevant to continued exploration.

## Step 4: Present the context

Show the user a concise summary:

```
## Tangent Context (from session <PPID>, plan: <plan-name>)

### What that session is building
<1-2 sentence summary from context field>

### Tangent-worthy items found
<bulleted list of out-of-scope items, open questions, assumptions>

### Relevant discovery context
<key findings from discovery that apply to the tangent area>
```

Then ask: **"Which of these would you like to explore? Or describe the
tangent you have in mind."**

## Step 5: Continue normally

From here, proceed with normal brainstorming or exploration. The user
is now in a fresh session with the relevant context loaded. They can:

- Brainstorm a tangent feature (invoke `look-before-you-leap:brainstorming`)
- Explore the codebase further
- Create their own plan for the tangent work

The tangent session's plan will be independent — owned by this session's
PPID, with no interference with the source session.
