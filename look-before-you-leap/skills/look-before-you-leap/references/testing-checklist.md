# Testing Checklist

## Before

- [ ] Identify the test framework (check package.json scripts, test config files)
- [ ] Locate existing tests for the code you're changing (`Glob` for `*.test.*`, `*.spec.*`)
- [ ] Read at least one existing test to learn patterns (imports, utilities, fixtures)
- [ ] Check for test helpers, factories, or mocking utilities in `test/`, `__tests__/`, or `src/test-utils`
- [ ] For new features: write 3-5 test cases BEFORE implementation (what should pass, what should fail, edge cases)

## During

- [ ] Write tests alongside code, not after — test the behavior you just built
- [ ] Cover the happy path, at least one error path, and one edge case
- [ ] Use existing test utilities and patterns — don't reinvent
- [ ] Test behavior, not implementation details (don't test private internals)
- [ ] If modifying shared code: run the existing tests FIRST to establish a baseline

## After

- [ ] Run the full test suite (or at minimum the affected test files)
- [ ] Verify new tests actually fail when the feature is removed (not test theater)
- [ ] Check coverage of edge cases: empty inputs, null/undefined, boundary values
- [ ] Ensure tests are deterministic — no time-dependent, order-dependent, or flaky tests

## Red Flags

| Pattern | Problem |
|---|---|
| Tests only check happy path | Missing error and edge case coverage |
| Tests mock everything | Testing mocks, not behavior |
| Tests pass when feature code is removed | Test theater — tests prove nothing |
| Copy-pasting test bodies with minor changes | Extract a parameterized test |
| No tests for shared utility changes | Consumers could break silently |
| Tests depend on execution order | Flaky tests waiting to happen |

## Deep Guidance

For comprehensive testing strategy including TDD with LLMs, test pyramid
guidance, and what NOT to test, read `testing-strategy.md`.

Look for installed skills about "testing" or "TDD" for framework-specific
guidance and automated test generation.
