# Codex Lessons Pipeline

Behavioral rules derived from Codex verification findings. When Codex
catches a pattern that existing engineering-discipline rules should have
prevented, the lesson is captured here before being promoted to a plugin
rule.

## Directory Structure

```
codex-lessons/
  proposals/    # New lessons awaiting review
  promoted/     # Lessons that became plugin rules
```

## Workflow

1. **Analyze** — After a session where Codex found genuine bugs, analyze
   root causes. If a bug reveals a behavioral gap (a habit that would
   have prevented it), write a proposal.
2. **Write proposal** — Create a `.md` file in `proposals/` using the
   format below.
3. **Periodic review** — During plugin maintenance, review proposals.
   Promote to plugin rules (move to `promoted/`) or discard with reason.

## Proposal Format

```markdown
# [Short rule name]

## Rule
[The behavioral rule — mechanizable, not vague]

## Evidence
- **Session**: [plan name, date]
- **Codex finding**: [file reference]
- **Bug**: [what went wrong]
- **Root cause**: [why it went wrong]

## Scope
- [ ] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

## Status
pending | promoted | discarded

## Promotion
[When promoted: which file was updated, what rule was added]
```

## What Belongs Here

- Behavioral habits that prevent classes of bugs (not one-off fixes)
- Rules that are mechanizable (Claude can check them, not just "be careful")
- Patterns that Codex catches repeatedly across sessions

## What Does NOT Belong Here

- One-off bugs with obvious fixes
- Project-specific knowledge (goes in CLAUDE.md or project docs)
- Declarative facts about code (goes nowhere — re-discover by reading)
