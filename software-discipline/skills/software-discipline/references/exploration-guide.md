# Exploration Guide

Deep guidance for thorough codebase exploration. Read this when the
exploration-protocol.md checklist isn't enough — when you need techniques
for complex or unfamiliar codebases.

---

## Why Exploration Matters

The #1 cause of plan failures is shallow exploration. You read one file,
assume you understand the system, then discover halfway through implementation
that:

- A shared utility already does what you're building
- The naming convention is different from what you assumed
- There are 15 consumers you didn't check
- The test framework has helpers you didn't use
- The project has patterns you violated

**Every minute exploring saves five minutes fixing.**

## Scope Discovery Techniques

### Start wide, then narrow

1. **Directory scan**: `ls` the relevant directories to see the full picture
2. **File count**: How many files in the scope area? This tells you plan sizing
3. **Grep for keywords**: Search for terms from the user's request
4. **Read the neighborhood**: For each file you'll modify, read its directory siblings

### Trace the dependency graph

For every file you plan to modify:

```
File you're changing
  ├── What it imports (upstream dependencies)
  ├── What imports it (downstream consumers)
  └── What it shares with siblings (common patterns)
```

Use `Grep` to trace both directions. Don't stop at the first level — if
you're changing a utility that's imported by a component that's imported
by a page, you need to know about the page too.

### Check for feature flags and configuration

Before building a feature, check if the project uses:

- Feature flags (LaunchDarkly, env-based, config files)
- A/B testing frameworks
- Environment-specific behavior
- Build-time vs runtime configuration

These constraints change implementation approach significantly.

## Shallow vs Thorough Exploration

### Shallow (causes failures)

- Read only the file you're about to edit
- Assume naming conventions without checking
- Skip searching for existing utilities
- Don't count consumers
- Don't read tests
- Don't check CLAUDE.md or README

### Thorough (prevents failures)

- Read the file AND its imports AND its consumers
- Search for existing solutions before implementing
- Count consumers of any shared code you'll modify
- Read at least one test file to understand patterns
- Read project docs for conventions
- Check for configuration that affects your work
- Verify packages you need are actually installed

## Anti-patterns

### "I'll figure it out as I go"

This leads to mid-implementation discoveries that force plan rewrites.
Explore first — it's faster overall.

### "This file is self-explanatory"

No file exists in isolation. Its imports, consumers, and sibling patterns
all constrain how you should modify it.

### "The user said it's simple"

Even simple changes can have wide blast radius. A one-line type change
can break 20 consumers. Always check.

### "I've seen this pattern before"

Every codebase has its own conventions. What worked in the last project
may violate patterns in this one. Verify, don't assume.

## When Exploration Reveals Problems

If during exploration you discover:

- **The task is larger than expected**: Tell the user before planning. "I
  found 45 consumers of this utility. This is bigger than a quick fix."
- **A better approach exists**: Suggest it. "The codebase already has a
  similar utility at src/lib/format.ts. Should we extend that instead?"
- **Blockers exist**: Flag them. "The API endpoint this depends on doesn't
  exist yet. Should I create it or is that a separate task?"
- **Requirements are ambiguous**: Ask. Don't guess and build the wrong thing.

## Confidence Calibration

| Confidence | What it means | What to do |
|---|---|---|
| **Low** | Missing answers to 2+ protocol questions | Keep exploring |
| **Medium** | All questions answered but some based on inference | Proceed, flag unknowns |
| **High** | All questions answered with concrete evidence | Proceed with confidence |

If you're at Low confidence after 10 minutes of exploration, tell the user
what's blocking you rather than guessing.
