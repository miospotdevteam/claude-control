# Root Cause Tracing

Bugs manifest deep in the call stack — wrong directory, wrong path, wrong
value. Your instinct is to fix where the error appears. That's treating a
symptom.

**Core principle:** Trace backward through the call chain until you find
the original trigger. Fix at the source.

---

## When to Use

- Error happens deep in execution, not at the entry point
- Stack trace shows a long call chain
- Unclear where invalid data originated
- Need to find which test or code path triggers the problem

---

## The Process

### 1. Observe the symptom

```
Error: ENOENT — file not found: /tmp/build/output.js
```

### 2. Find the immediate cause

What code directly produces this error?

```typescript
const content = readFileSync(outputPath);
// outputPath is wrong — but WHY?
```

### 3. Trace one level up

What called this function? What value did it pass?

```typescript
buildProject(config)
  → compile(config.outputDir)      // outputDir = '/tmp/build'
    → writeOutput(outputDir)
      → readFileSync(outputPath)   // outputPath constructed from outputDir
```

### 4. Keep tracing until you find the source

```typescript
const config = loadConfig();       // Returns { outputDir: '/tmp/build' }
// But the file is at '/tmp/build/dist/output.js'
// Config is missing the 'dist' subdirectory
```

### 5. Fix at the source

Fix `loadConfig()` or the config file — not the `readFileSync` call.

---

## Adding Instrumentation

When you can't trace manually, add temporary logging:

```typescript
async function writeOutput(directory: string) {
  console.error('DEBUG writeOutput:', {
    directory,
    cwd: process.cwd(),
    exists: existsSync(directory),
    stack: new Error().stack,
  });
  // ... original code
}
```

**Tips:**
- Use `console.error()` in tests — `console.log` and loggers may be
  suppressed
- Log BEFORE the failing operation, not after
- Include the full `new Error().stack` for the call chain
- Include relevant context: directory, cwd, env vars, timestamps

**Capture and filter:**
```bash
npm test 2>&1 | grep 'DEBUG writeOutput'
```

---

## Finding Which Test Pollutes State

When something appears during tests but you don't know which test causes
it, use bisection — run tests one-by-one and check after each:

```bash
#!/usr/bin/env bash
# Usage: ./find-polluter.sh <artifact_to_check> <test_pattern>
# Example: ./find-polluter.sh '.git' 'src/**/*.test.ts'

set -e
ARTIFACT="$1"
PATTERN="$2"

for TEST_FILE in $(find . -path "$PATTERN" | sort); do
  [ -e "$ARTIFACT" ] && echo "Pollution exists before: $TEST_FILE" && continue
  npm test "$TEST_FILE" > /dev/null 2>&1 || true
  if [ -e "$ARTIFACT" ]; then
    echo "FOUND: $TEST_FILE creates $ARTIFACT"
    exit 1
  fi
done
echo "No polluter found"
```

For regressions in the codebase itself, use `git bisect` (documented in
the main systematic-debugging skill).

---

## Key Principle

**Never fix where the error appears.** Trace back to the original trigger.
Then fix at the source AND add defense-in-depth validation at each layer
the bad value passed through (see `debugging-defense-in-depth.md`).
