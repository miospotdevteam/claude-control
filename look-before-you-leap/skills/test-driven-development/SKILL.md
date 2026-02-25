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

### Phase 2: Green (Minimal Implementation)

Write the minimum code to make the failing tests pass. Nothing more.

1. **Create or open the implementation file**
2. **Write only enough code** to satisfy the current test cases
3. **Run the tests** — they must all pass
4. If tests still fail, fix the implementation until green

**Rules:**
- Resist the urge to over-engineer. If a test expects `return true`, write
  `return true` — you can generalize when more tests demand it.
- Do not add error handling, validation, or features that no test requires.
- Do not add types or interfaces beyond what the tests exercise.
- If the minimal implementation feels wrong, that's a signal to write more
  tests in the next Red phase — not to preemptively build more now.

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

## Handling Multiple Test Cases

For features with many behaviors, don't write all tests at once. Iterate:

1. **Red**: Write 1-3 tests for the simplest behavior
2. **Green**: Implement minimally
3. **Red**: Add tests for the next behavior or edge case
4. **Green**: Extend the implementation
5. Repeat until all behaviors are covered
6. **Refactor**: Clean up the accumulated implementation

This incremental approach prevents test-writing from becoming a speculative
exercise where you guess behaviors before understanding the implementation
constraints.

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
| Write all tests upfront | Speculative — you'll guess wrong about edge cases | Iterate: small Red, small Green, repeat |
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
