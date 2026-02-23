# Defense-in-Depth Validation

When you fix a bug caused by invalid data, adding validation at one place
feels sufficient. But that single check can be bypassed by different code
paths, refactoring, or mocks.

**Core principle:** Validate at EVERY layer data passes through. Make the
bug structurally impossible.

---

## Why Multiple Layers

Single validation: "We fixed the bug."
Multiple layers: "We made the bug impossible."

Different layers catch different cases:
- Entry validation catches most bugs
- Business logic catches edge cases
- Environment guards prevent context-specific dangers
- Debug instrumentation helps when other layers fail

---

## The Four Layers

### Layer 1: Entry point validation

Reject obviously invalid input at the API/function boundary.

```typescript
function createProject(name: string, directory: string) {
  if (!directory?.trim()) {
    throw new Error('directory cannot be empty');
  }
  if (!existsSync(directory)) {
    throw new Error(`directory does not exist: ${directory}`);
  }
  // ... proceed
}
```

### Layer 2: Business logic validation

Ensure data makes sense for this specific operation.

```typescript
function initializeWorkspace(projectDir: string) {
  if (!projectDir) {
    throw new Error('projectDir required for workspace initialization');
  }
  // ... proceed
}
```

### Layer 3: Environment guards

Prevent dangerous operations in specific contexts.

```typescript
async function dangerousOperation(directory: string) {
  if (process.env.NODE_ENV === 'test') {
    const resolved = resolve(directory);
    if (!resolved.startsWith(tmpdir())) {
      throw new Error(
        `Refusing operation outside temp dir during tests: ${directory}`
      );
    }
  }
  // ... proceed
}
```

### Layer 4: Debug instrumentation

Capture context for forensics when the other layers aren't enough.

```typescript
async function riskyOperation(directory: string) {
  logger.debug('About to run risky operation', {
    directory,
    cwd: process.cwd(),
    stack: new Error().stack,
  });
  // ... proceed
}
```

---

## Applying the Pattern

After finding and fixing a root cause:

1. **Map the data flow** — where does the bad value originate? Where is
   it consumed?
2. **List every checkpoint** — every function boundary the data passes
   through
3. **Add validation at each layer** — entry, business logic, environment,
   instrumentation
4. **Test each layer independently** — try to bypass layer 1, verify
   layer 2 catches it

---

## Key Insight

All four layers are often necessary. During testing, each layer catches
bugs the others miss:
- Different code paths bypass entry validation
- Mocks bypass business logic checks
- Edge cases on different platforms need environment guards
- Debug instrumentation identifies structural misuse

**Don't stop at one validation point.** Add checks at every layer.
