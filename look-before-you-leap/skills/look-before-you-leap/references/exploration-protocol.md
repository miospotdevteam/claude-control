# Exploration Protocol

Answer ALL 8 questions before writing a plan. If a question doesn't apply,
write "N/A" — do not skip it. You are NOT ready to plan until all 8 have
concrete answers and your confidence is Medium or higher.

---

## Step 0: Run deps-query FIRST (when configured)

**Before answering any question below**, check the project profile for dep
maps. If dep maps are configured, your very first exploration action is to
run `deps-query.py` on every file you expect to modify. Do this before
reading files, before grepping, before anything else.

**Why first**: The deps-query output tells you which files matter — it
reveals consumers, cross-module dependencies, and blast radius upfront.
This shapes every subsequent exploration step. Without it, you'll waste
time reading files that turn out to be irrelevant and miss files that are
critical.

```bash
# Run this for each file you plan to modify:
python3 <scripts_dir>/deps-query.py <project_root> <file_path>
```

(The project profile has the full command with resolved paths.)

Record all deps-query output — you'll need it for Q3, Q7, and the
discovery.md. If dep maps are NOT configured, skip this step and proceed
to Q1.

---

## 1. What is the scope?

Which files and directories will this change touch?

**How to answer**: `Glob` for likely file patterns. Read the user's request
word by word — identify every noun that maps to a file or module.

**Output**: List of file paths with boundaries ("ONLY these files, NOT those").

## 2. What are the entry points?

Which files will you directly modify?

**How to answer**: Read each candidate file. Note its current state, key
functions, exports, and line count.

**Output**: File path + brief description of contents for each entry point.

## 3. Who are the consumers?

Who imports or uses the files you're changing?

**HARD GATE**: If dep maps are configured in the project profile, you MUST
run `deps-query.py` for every file you plan to modify. Do NOT use `Grep` as
a substitute — `Grep` for import patterns is the fallback ONLY when dep maps
are not configured. Dep maps give you complete, cross-module consumer data
instantly; ad-hoc grep is slower, less reliable, and misses transitive
consumers.

**How to answer (dep maps configured)**: Run `deps-query.py` for each entry
point file. Record the DEPENDENTS output. See `references/dependency-mapping.md`.

**How to answer (no dep maps)**: `Grep` for import/require statements
referencing each entry point file. Example: `Grep pattern="from ['\"].*auth" type="ts"`

**Output**: List of consumer files with count. If >10, list count + examples.
When dep maps are configured, include the exact deps-query output for each
file queried.

## 4. What patterns already exist?

How does this codebase solve similar problems?

**How to answer**: Read 2-3 sibling files in the same directory. Check for
shared utilities via `Grep`. Read CLAUDE.md, README.md for conventions.

**Output**: Naming patterns, error handling approach, data flow conventions.

## 5. What test infrastructure exists?

Where do tests live? What framework? Any test utilities?

**How to answer**: `Glob` for `**/*.test.*`, `**/*.spec.*`, `**/test/**`,
`**/__tests__/**`. Read one test file to identify the framework and patterns.
Check package.json for test scripts.

**Output**: Framework name, test file location pattern, how to run tests.

## 6. What are the project conventions?

Style, structure, tooling preferences?

**How to answer**: Read CLAUDE.md (if exists), check for .eslintrc, tsconfig,
prettier config. Note import ordering, naming style, file organization.

**Output**: Key conventions that constrain implementation choices.

## 7. What is the blast radius?

What could break if you get this wrong?

**How to answer (dep maps configured)**: You MUST use `deps-query.py` —
its DEPENDENTS section with count IS the direct blast radius. Do NOT
estimate blast radius from ad-hoc grep when dep maps are available.

**How to answer (no dep maps)**: For each entry point, count its consumers
(from Q3). For shared types/utilities, grep for all usages. Identify any
public API surfaces.

**Output**: List of risk areas with consumer counts.

## 8. What is your confidence?

Can you write a complete plan right now?

**How to answer**: Review questions 1-7. Any gaps? Any "I assume..." statements
that should be verified?

**Output**: Low / Medium / High with justification.

- **Low**: Stop. Explore more before planning.
- **Medium**: Proceed but flag unknowns in the plan.
- **High**: Proceed with full confidence.
