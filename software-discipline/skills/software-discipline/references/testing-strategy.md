# Testing Strategy Guide

Comprehensive testing guidance for AI-assisted development. Research shows
providing tests first improves AI code quality by 46%. This guide covers
what to test, when, and how.

---

## TDD-Lite for AI-Assisted Development

Full TDD (red-green-refactor) is heavy. TDD-lite is practical: write a small
number of focused tests BEFORE implementation. This works especially well with
AI assistance because:

1. Tests constrain the solution space — the AI has a concrete target
2. Tests catch the most common AI mistakes: off-by-ones, missing edge cases,
   incorrect assumptions about APIs
3. Tests serve as acceptance criteria that verify the implementation is correct

### The TDD-lite workflow

1. **Write 3-5 test cases** covering: happy path (1-2), error path (1), edge case (1-2)
2. **Run them** — they should all fail (if any pass, you're testing the wrong thing)
3. **Implement the feature** — write the minimum code to make tests pass
4. **Run tests again** — all should pass
5. **Add tests for anything the implementation revealed** — new edge cases, boundary conditions

### What makes a good test target

- **Test behavior, not implementation**: "returns sorted results" not "calls Array.sort"
- **Test the public interface**: inputs and outputs, not internal state
- **Test at the right level**: unit for utilities, integration for API routes, E2E for user flows

---

## The Test Pyramid vs Trophy

### Classic pyramid (unit-heavy)

```
     /  E2E  \        Few, slow, expensive
    / Integr. \       Some, moderate speed
   /   Unit    \      Many, fast, cheap
```

### Testing trophy (integration-heavy)

```
     /  E2E  \        Few
    / Integr. \       MOST tests here
   /   Unit    \      Some (for complex logic)
  / Static type \     TypeScript/Flow catches the rest
```

**For most web applications, the trophy is better.** Static types catch many
bugs that unit tests would otherwise need to cover. Integration tests catch
the bugs that actually affect users — wiring errors, data flow issues, API
contract violations.

Use the pyramid when: pure algorithmic code, libraries, complex business logic.
Use the trophy when: web apps, APIs, CRUD operations.

---

## What NOT to Test

Testing everything is as bad as testing nothing — it creates maintenance burden
without proportional value.

**Don't test:**
- Simple getters/setters with no logic
- Framework code you didn't write (don't test that React renders a div)
- Private implementation details that may change
- One-line utility functions with obvious behavior
- Type system guarantees (don't test that a typed function accepts the right types)

**Do test:**
- Complex business logic and calculations
- Data transformations with edge cases
- API route handlers (request in, response out)
- State transitions with multiple possible outcomes
- Anything involving user input parsing or validation
- Error handling paths

---

## Edge Case Systematic Approach

For any function, consider these categories systematically:

### Boundary values
- Zero, negative, maximum values for numbers
- Empty string, very long string for text
- Empty array, single element, very large array for collections
- Null, undefined where the type permits it

### State transitions
- First call vs subsequent calls
- Empty state vs populated state
- Concurrent modifications

### Error conditions
- Network failures (timeout, 404, 500)
- Invalid input format
- Missing required fields
- Permission denied

### Real-world data
- Unicode characters, emoji, RTL text
- Timezone edge cases (DST transitions)
- Large payloads that could cause performance issues

---

## Test Theater Detection

Test theater = tests that exist but prove nothing. They pass regardless of
whether the code works correctly.

### Signs of test theater

1. **Tests that never fail**: If a test has never failed in its history, it may
   not be testing anything meaningful
2. **Tests that pass when the implementation is removed**: Delete the feature
   code — do the tests fail? If not, they're theater
3. **Tests that only check "no error thrown"**: This verifies the code runs but
   not that it's correct
4. **Tests with no assertions**: `expect(fn()).toBeDefined()` on a function
   that always returns something is meaningless
5. **Snapshot tests on everything**: Snapshots catch changes but not correctness.
   Only use them for serializable output with clear expectations

### How to verify test quality

After writing tests:
1. Comment out the key logic in your implementation
2. Run the tests
3. At least one test should fail
4. If no test fails, your tests aren't testing the right thing

---

## Framework-Aware Testing

### React / Next.js
- Use React Testing Library (renders like a user, queries by role/text)
- Test components through user interactions, not implementation
- Use `msw` for API mocking in tests
- For Next.js: test API routes as functions, not through HTTP

### Node.js APIs
- Test route handlers with supertest or direct function calls
- Mock external services, not internal modules
- Test middleware in isolation

### Database
- Use test databases or transactions that roll back
- Seed with deterministic data
- Don't depend on data from other tests

### General
- Check package.json for the test runner (vitest, jest, bun test, pytest)
- Read existing tests to learn the project's patterns before writing new ones
- Use the project's existing test utilities and fixtures
