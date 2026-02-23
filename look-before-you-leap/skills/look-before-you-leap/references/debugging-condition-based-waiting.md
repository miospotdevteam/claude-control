# Condition-Based Waiting

Flaky tests often use arbitrary delays to wait for async operations. This
creates race conditions: tests pass on fast machines, fail under load or
in CI.

**Core principle:** Wait for the actual condition you care about, not a
guess about how long it takes.

---

## When to Use

- Tests have arbitrary delays (`setTimeout`, `sleep`, `time.sleep()`)
- Tests are flaky — pass sometimes, fail under load
- Tests timeout when run in parallel
- Waiting for async operations to complete

**Don't use when** testing actual timing behavior (debounce, throttle).
In that case, document WHY the timeout is necessary.

---

## The Pattern

```typescript
// BAD: Guessing at timing
await new Promise(r => setTimeout(r, 500));
expect(getResult()).toBeDefined();

// GOOD: Waiting for condition
await waitFor(() => getResult() !== undefined, 'result to be available');
expect(getResult()).toBeDefined();
```

---

## Implementation

Generic polling function:

```typescript
async function waitFor<T>(
  condition: () => T | undefined | null | false,
  description: string,
  timeoutMs = 5000,
): Promise<T> {
  const start = Date.now();

  while (true) {
    const result = condition();
    if (result) return result;

    if (Date.now() - start > timeoutMs) {
      throw new Error(
        `Timeout waiting for ${description} after ${timeoutMs}ms`,
      );
    }

    await new Promise(r => setTimeout(r, 10)); // poll every 10ms
  }
}
```

### Domain-specific helpers

Build on the generic `waitFor` for your project's needs:

```typescript
// Wait for a specific event
async function waitForEvent(
  events: Event[],
  type: string,
  timeoutMs = 5000,
): Promise<Event> {
  return waitFor(
    () => events.find(e => e.type === type),
    `${type} event`,
    timeoutMs,
  );
}

// Wait for a count of events
async function waitForEventCount(
  events: Event[],
  type: string,
  count: number,
  timeoutMs = 5000,
): Promise<Event[]> {
  return waitFor(
    () => {
      const matching = events.filter(e => e.type === type);
      return matching.length >= count ? matching : undefined;
    },
    `${count} ${type} events`,
    timeoutMs,
  );
}
```

---

## Quick Reference

| Scenario | Pattern |
|---|---|
| Wait for event | `waitFor(() => events.find(e => e.type === 'DONE'))` |
| Wait for state | `waitFor(() => machine.state === 'ready')` |
| Wait for count | `waitFor(() => items.length >= 5)` |
| Wait for file | `waitFor(() => existsSync(path))` |
| Complex condition | `waitFor(() => obj.ready && obj.value > 10)` |

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Polling too fast (`setTimeout(check, 1)`) | Poll every 10ms — fast enough, doesn't waste CPU |
| No timeout | Always include timeout with clear error message |
| Caching state before the loop | Call the getter inside the loop for fresh data |
| No description in timeout error | Include what you were waiting for |

---

## When Arbitrary Timeout IS Correct

```typescript
// Tool ticks every 100ms — need 2 ticks to verify partial output
await waitForEvent(events, 'TOOL_STARTED');     // first: wait for condition
await new Promise(r => setTimeout(r, 200));      // then: wait for timed behavior
// 200ms = 2 ticks at 100ms intervals — documented and justified
```

Requirements:
1. First wait for the triggering condition
2. Timeout based on known timing, not guessing
3. Comment explaining WHY
