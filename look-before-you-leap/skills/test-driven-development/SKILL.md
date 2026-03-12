---
name: test-driven-development
description: "Test-Driven Development workflow enforcing red-green-refactor cycles. Use when writing new features, adding behavior, or implementing functions where tests should drive design. Requires explicit test-first prompting because Claude naturally writes implementation first. Integrates with writing-plans (TDD rhythm in Progress items) and engineering-discipline (verification). Do NOT use when: fixing a bug in existing tested code (use systematic-debugging), writing tests for existing untested code (characterization tests are a different workflow), refactoring without behavior change (use refactoring), or the project has no test infrastructure."
---

# Test-Driven Development

Claude naturally writes implementation first, then tests. TDD requires the
inverse: tests drive design. This skill enforces the red-green-refactor
cycle through explicit structure.

**Announce at start:** "I'm using the TDD skill to write tests before
implementation."

**Prerequisite:** The project must have test infrastructure (a test runner,
a test framework). If none exists, set it up first or ask the user.

---

## The Cycle

Every feature unit follows this cycle. No shortcuts, no combining phases.

```
RED  ->  GREEN  ->  REFACTOR
test     implement   clean up
fails    minimally   tests stay green
```

### Phase 1: Red (Write Failing Test)

Write a test that describes the desired behavior. The test MUST fail because
the implementation doesn't exist yet.

1. **Create or open the test file** following the project's test naming
   convention (`.test.ts`, `.spec.ts`, `_test.go`, `test_*.py`, etc.)
2. **Write test cases** using Arrange-Act-Assert:
   - Arrange: set up inputs and expected state
   - Act: call the function/method that doesn't exist yet
   - Assert: verify the expected outcome
3. **Run the tests** — they must fail with a clear error (module not found,
   function not defined, etc.). If they pass, the test isn't testing
   anything new.

**Test naming:** Describe behavior, not implementation. Use
`should_<behavior>_when_<condition>` or the project's existing convention.

**What to test:**
- Happy path (expected inputs produce expected outputs)
- Edge cases (empty inputs, boundary values, null/undefined)
- Error cases (invalid inputs produce appropriate errors)
- One logical assertion per test — multiple assertions are acceptable only
  when testing a single cohesive behavior

**Do NOT:**
- Write implementation code during this phase
- Write tests that test framework internals or trivial getters/setters
- Write tests that couple to implementation details (mock every dependency,
  test private methods)

### Phase 2: Green (Deliberately Minimal Implementation)

Write the **dumbest possible code** that makes the failing tests pass. This
is the hardest phase for Claude — your instinct is to write correct, general
code. Fight that instinct. The goal is to let tests drive generalization,
not to anticipate it.

1. **Create or open the implementation file**
2. **Write only enough code** to satisfy the current test cases
3. **Run the tests** — they must all pass
4. If tests still fail, fix the implementation until green

**The Minimality Test:** After writing your GREEN code, ask: "Would this
implementation also pass tests I haven't written yet?" If yes, you're being
too general. Scale back. Use hardcoded values, if/else chains, early
returns — anything that handles only the tested cases. Generalization
happens in REFACTOR or when the next RED cycle's tests demand it.

**Rules:**
- **Hardcode first, generalize later.** If the test expects `[{status: "todo", tasks: [task1]}]`,
  return exactly that structure with a hardcoded key — don't write a generic
  loop that handles all statuses. The loop comes when the next test demands it.
- **If/else before data structures.** If two tests check two transitions,
  write two `if` checks — don't create a transition map. The map comes
  in REFACTOR after all transitions are tested.
- Resist the urge to over-engineer. If a test expects `return true`, write
  `return true` — you can generalize when more tests demand it.
- Do not add error handling, validation, or features that no test requires.
- Do not add types or interfaces beyond what the tests exercise.
- If the minimal implementation feels wrong, that's a signal to write more
  tests in the next Red phase — not to preemptively build more now.

**Why this matters:** If your Cycle 1 GREEN is already general enough to
pass Cycle 2 and Cycle 3 tests, then those later cycles are hollow — they
confirm existing behavior rather than driving new implementation. The
feedback loop that makes TDD valuable (test reveals a gap → implementation
fills the gap → next test reveals the next gap) only works when each GREEN
is deliberately constrained to the current tests.

### Phase 3: Refactor (Clean Up)

Improve code quality while keeping all tests green.

1. **Identify improvements**: duplication, unclear names, unnecessary
   complexity, missing type safety
2. **Make one change at a time**
3. **Run tests after each change** — if a test fails, revert immediately
   and reconsider
4. **Stop when the code is clean enough** — don't gold-plate

**Common refactoring targets:**
- Extract repeated logic into helper functions
- Rename variables/functions for clarity
- Simplify conditionals (guard clauses, early returns)
- Add proper types (now that you understand the shape of the data)
- Remove dead code or unnecessary temporaries

**After refactoring**, commit the working state before starting the next
Red phase.

---

## Integration with Plans

When the writing-plans skill creates a masterPlan, each step's **Progress**
items encode the TDD rhythm:

```markdown
- **Progress**:
  - [ ] Write failing test
  - [ ] Run test — verify it fails
  - [ ] Implement minimal code to pass
  - [ ] Run tests — verify they pass
  - [ ] Commit
```

Follow these Progress items mechanically. Update the plan after each phase
(the checkpoint rule from persistent-plans still applies).

---

## Handling Multiple Test Cases (THE CORE OF TDD)

This is where TDD either works or degrades into test-first waterfall.
The difference: in TDD, you write tests for **one behavior at a time**,
implement it, then move to the next. In test-first waterfall, you write
all tests upfront then implement everything at once — that defeats the
purpose because you're guessing about edge cases before the implementation
teaches you what matters.

**The incremental cycle (minimum 3 cycles per feature):**

1. **Red**: Write 1-3 tests for the **simplest** behavior (e.g., basic
   percentage discount on a $100 order)
2. **Green**: Implement the minimum to pass — **deliberately narrowly**.
   Maybe just `return price * 0.9` (hardcoded 10% discount). Don't write
   a generic `applyDiscount(type, amount)` yet.
3. **Run tests** — confirm green
4. **Red**: Add 1-3 tests for the **next** behavior (e.g., fixed dollar
   discounts). These MUST fail — if they pass, your previous GREEN was
   too general.
5. **Green**: Extend the implementation to handle both types — maybe add
   an if/else, not a polymorphic strategy pattern.
6. **Run tests** — confirm all green (old AND new)
7. **Red**: Add tests for **edge cases and interactions** (e.g., discount
   exceeding price, minimum thresholds). Again, these SHOULD fail.
8. **Green**: Handle the edge cases with targeted code
9. **Refactor**: NOW generalize. Replace the if/else chain with a clean
   abstraction. The accumulated implementation tells you what the right
   abstraction is — you couldn't have guessed it in Cycle 1.

**Cycle quality check:** After each RED phase, before moving to GREEN,
verify: "Did at least one new test fail?" If all new tests passed
immediately, pause and consider:
- Your previous GREEN was too general — note this and commit to being
  more constrained in future GREEN phases
- OR the tests aren't testing genuinely new behavior — reconsider what
  would actually break and write tests for that instead

A cycle where tests pass immediately with zero implementation changes is
a wasted cycle — it confirms existing behavior rather than driving design.
Two consecutive hollow cycles means you've lost the TDD feedback loop.

**Why this matters:** Each green phase teaches you something about the
implementation that makes the next red phase's tests better. Writing all
29 tests upfront means you're guessing about boundary conditions before
you've written a single line of implementation. The first few cycles are
easy to predict, but by cycle 3-4 you'll discover edge cases you never
would have thought of from the outside. But this only works if each GREEN
is constrained enough that the next RED actually breaks something.

**Plan integration:** When the writing-plans skill creates steps with TDD,
the progress items encode these cycles explicitly (Cycle 1 RED, Cycle 1
GREEN, Cycle 2 RED, etc.). Follow them mechanically — each RED item adds
tests for one behavior slice, each GREEN item extends the implementation.

---

## Advanced Patterns

### Characterization Tests (Legacy Code)

When modifying untested legacy code, write characterization tests first:

1. Write tests that capture the **current behavior** (even if buggy)
2. Run them — they must pass against the existing code
3. Now refactor or fix bugs with confidence

This is the inverse of normal TDD: you're not driving new design, you're
documenting existing behavior as a safety net.

### Property-Based Testing

For functions with mathematical properties (sort, serialize/deserialize,
encode/decode), consider property-based tests:

- Output length equals input length (sort)
- Round-trip: `decode(encode(x)) === x`
- Idempotency: `f(f(x)) === f(x)`

Use the project's property testing library (fast-check, hypothesis,
proptest, etc.) if available.

---

## Anti-Patterns

| Anti-Pattern | Why It Fails | Correct Approach |
|---|---|---|
| Write implementation + tests together | Tests validate existing code, don't drive design | Separate Red and Green into distinct phases |
| Write all tests upfront in one batch | Speculative — you'll guess wrong about edge cases, and you lose the feedback loop that makes TDD valuable | Iterate: 1-3 tests per cycle, implement, repeat for at least 3 cycles |
| Over-general GREEN implementation | Later cycles pass immediately with zero code changes — the feedback loop is hollow, tests confirm existing behavior instead of driving design | Hardcode first, use if/else chains, constrain to tested cases. Generalize in REFACTOR, not GREEN |
| Test implementation details | Brittle — breaks on any refactor | Test behavior (inputs -> outputs) |
| Skip the Red phase verification | You don't know if the test actually tests anything | Always run and confirm failure first |
| Skip the Refactor phase | Technical debt accumulates silently | Always refactor after Green |
| Over-mock everything | Tests pass but integration is broken | Mock at boundaries, not within units |
| One giant test per feature | Hard to diagnose failures | One behavior per test |

---

## Boundaries

### When TDD applies
- New functions, classes, modules, or components
- Adding behavior to existing code that already has tests
- API endpoints with request/response contracts
- Data transformations and business logic
- Utility functions

### When TDD doesn't apply
- Configuration files (no behavior to test)
- Pure UI layout without logic (use visual review instead)
- One-off scripts or migrations
- Glue code that only wires dependencies together (test at integration level)
- Third-party API wrappers where the behavior is "call the API" (test at
  integration level with mocks)

### When to stop testing
- When adding another test wouldn't change the implementation
- When the remaining untested paths are framework internals
- When the cost of a test exceeds the cost of the bug it would catch
