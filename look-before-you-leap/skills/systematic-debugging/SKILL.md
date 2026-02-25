---
name: systematic-debugging
description: "Use when encountering any bug, test failure, or unexpected behavior. Enforces root cause investigation before fixes. Four phases: investigate, analyze patterns, form hypotheses, implement. Prevents guess-and-check thrashing. Use ESPECIALLY when under pressure or when 'just one quick fix' seems obvious. Do NOT use for: learning unfamiliar APIs (use exploration), performance optimization without a specific regression, or code review without a reported bug."
---

# Systematic Debugging

Random fixes waste time and create new bugs. Quick patches mask root causes.

**Core principle:** Find root cause before attempting fixes. Symptom fixes
are failure.

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

## When to Use

**Always** — for any technical issue: test failures, bugs, unexpected
behavior, performance problems, build failures, integration issues.

**Especially** when:
- Under time pressure (emergencies make guessing tempting)
- "Just one quick fix" seems obvious
- You've already tried multiple fixes
- You don't fully understand the issue

## Boundaries & Safety

**Must not:**
- Commit debug instrumentation (temporary logs, print statements). Remove
  all before declaring done.
- Make destructive changes to reproduce a bug without user confirmation
  (dropping data, deleting files, resetting state, truncating tables).
- Modify shared infrastructure, production config, or environment files
  as part of debugging without user confirmation.
- Scope-creep fixes beyond the root cause — no "while I'm here" cleanup.

**User confirmation required before:**
- Attempting a 4th fix (existing rule in Phase 4.5 — elevated here)
- Adding persistent instrumentation (logging that stays in production code)
- Modifying database schema, environment config, or CI pipelines to debug
- Reverting commits or resetting branches

**Agent may proceed autonomously:**
- Adding and removing temporary debug logging within a single session
- Reading any file, running any read-only diagnostic command
- Running existing tests, build commands, type checkers
- Making the single fix that addresses the confirmed root cause

---

## Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

### 1. Read error messages completely

Don't skip past errors or warnings. Read stack traces top to bottom.
Note file paths, line numbers, error codes. Error messages often contain
the exact solution.

### 2. Reproduce consistently

- Can you trigger it reliably?
- What are the exact steps?
- Does it happen every time?
- If not reproducible, gather more data — don't guess

### 3. Check recent changes

- `git diff` and `git log` — what changed?
- New dependencies, config changes, environment differences?
- Use `git bisect` for regression hunting:

```bash
git bisect start
git bisect bad              # current commit is broken
git bisect good <commit>    # last known good commit
# git runs binary search — test each commit it offers
git bisect good/bad         # repeat until it finds the culprit
git bisect reset            # done
```

### 4. Use a debugger when appropriate

Before adding print statements everywhere, consider whether a debugger
would be faster:
- Set breakpoints at the error site and step backward through the call stack
- Watch variable values change through execution
- Inspect closure scope, `this` binding, prototype chains
- Most editors and runtimes have built-in debugger support

Use print/log debugging when: CI failures, distributed systems, timing-
sensitive bugs where pausing changes behavior.

### 5. Gather evidence in multi-component systems

When the system has multiple layers (API → service → database, CI → build
→ deploy), add diagnostic instrumentation at each boundary BEFORE
proposing fixes:

```
For EACH component boundary:
  - Log what data enters the component
  - Log what data exits the component
  - Verify environment/config propagation

Run once to gather evidence showing WHERE it breaks.
Then investigate that specific component.
```

### 6. Trace data flow to the source

When the error is deep in the call stack, trace backward. Don't fix where
the error appears — find where the bad value originates.

See `references/debugging-root-cause-tracing.md` for the full backward
tracing technique.

---

## Phase 2: Pattern Analysis

### 1. Find working examples

Locate similar working code in the same codebase. What works that's
similar to what's broken?

### 2. Compare against references

If implementing a pattern, read the reference implementation COMPLETELY.
Don't skim — read every line. Partial understanding guarantees bugs.

### 3. Identify differences

What's different between working and broken? List every difference,
however small. Don't assume "that can't matter."

### 4. Understand dependencies

What other components does this need? What settings, config, environment?
What assumptions does it make?

---

## Phase 3: Hypothesis and Testing

### 1. Form a single hypothesis

State clearly: "I think X is the root cause because Y." Be specific, not
vague. Write it down.

### 2. Test minimally

Make the SMALLEST possible change to test the hypothesis. One variable at
a time. Don't fix multiple things at once.

### 3. Evaluate and iterate

- Hypothesis confirmed? → Phase 4
- Hypothesis wrong? → Form a NEW hypothesis based on what you learned
- Don't stack fixes on top of failed attempts

### 4. When you don't know

Say "I don't understand X." Don't pretend. Research more, ask for help,
or add more instrumentation.

---

## Phase 4: Implementation

### 1. Create a failing test

Write the simplest possible test that reproduces the bug. Use the Red
phase from `look-before-you-leap:test-driven-development` to write a
failing test that captures the bug.

A test proves the bug exists, proves the fix works, and prevents
regression. Never fix bugs without a test.

### 2. Implement a single fix

Address the root cause — not the symptom. ONE change at a time. No
"while I'm here" improvements.

### 3. Verify

- Test passes?
- Other tests still pass?
- No new warnings or errors?

### 4. Add defense-in-depth

After fixing the root cause, add validation at multiple layers to make
the bug structurally impossible to recur.

See `references/debugging-defense-in-depth.md` for the multi-layer
validation pattern.

### 5. If the fix doesn't work

- Count: how many fixes have you tried?
- If < 3: return to Phase 1, re-analyze with new information
- **If 3+: STOP and question the architecture**

Three failed fixes is a pattern. It means the problem isn't a bug — it's
a design issue. Each fix revealing new problems in different places is
the signature of an architectural mismatch.

Discuss with the user before attempting more fixes. This is not a failed
hypothesis — this is a wrong architecture.

### Acceptance Criteria

Before declaring a debugging task done, ALL must be true:

- [ ] Root cause identified and documented (not just "it works now")
- [ ] Failing test written that reproduces the original bug
- [ ] Fix addresses root cause, not symptom
- [ ] All existing tests pass (including the new regression test)
- [ ] No debug instrumentation left in code
- [ ] Defense-in-depth validation added where appropriate
- [ ] No unrelated changes introduced

---

## Red Flags — STOP and Return to Phase 1

| What you're thinking | What to do |
|---|---|
| "Quick fix for now, investigate later" | Investigate now — "later" never comes |
| "Just try changing X and see" | Form a hypothesis first |
| "Add multiple changes, run tests" | One change at a time |
| "It's probably X, let me fix that" | Probably ≠ confirmed. Investigate. |
| "I don't fully understand but this might work" | Understand first |
| "Here are the fixes: [list]" without investigation | You're guessing. Phase 1 first. |
| "One more fix attempt" (after 2+ failures) | Question the architecture |
| Each fix reveals problems in a different place | Architectural issue, not a bug |

---

## Supporting References

All paths relative to `${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/`.

| Reference | When to use |
|---|---|
| `references/debugging-root-cause-tracing.md` | Bug deep in call stack — trace backward to source |
| `references/debugging-defense-in-depth.md` | After fixing — add multi-layer validation |
| `references/debugging-condition-based-waiting.md` | Flaky tests with timing issues — replace `sleep()` with conditions |

**Related skills:**
- `look-before-you-leap:test-driven-development` — for creating the failing test (Phase 4)
- `look-before-you-leap:engineering-discipline` — for verification after fix
