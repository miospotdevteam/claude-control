# Exploration Protocol

Answer ALL 8 questions before writing a plan. If a question doesn't apply,
write "N/A" — do not skip it. You are NOT ready to plan until all 8 have
concrete answers and your confidence is Medium or higher.

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

**How to answer**: `Grep` for import/require statements referencing each entry
point file. Example: `Grep pattern="from ['\"].*auth" type="ts"`

**Output**: List of consumer files with count. If >10, list count + examples.

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

**How to answer**: For each entry point, count its consumers (from Q3). For
shared types/utilities, grep for all usages. Identify any public API surfaces.

**Output**: List of risk areas with consumer counts.

## 8. What is your confidence?

Can you write a complete plan right now?

**How to answer**: Review questions 1-7. Any gaps? Any "I assume..." statements
that should be verified?

**Output**: Low / Medium / High with justification.

- **Low**: Stop. Explore more before planning.
- **Medium**: Proceed but flag unknowns in the plan.
- **High**: Proceed with full confidence.
