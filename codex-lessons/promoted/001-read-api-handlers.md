# Read API handlers before typing response shapes

## Rule
Before writing any typed API call, grep for the endpoint path and read
the handler's return statement. Never guess what an API returns.

## Pattern it prevents
Typing a response as `{ imageUrl }` when the API actually returns
`{ settings, uploadedKey }`. These bugs are invisible until the user
saves data and it silently fails or gets lost.

## Evidence
Codex caught this in a 10-step feature build. The agent guessed the
response shape from the field name instead of reading the route handler.
Fix took 2 minutes; the bug would have shipped without Codex.

## Scope
Universal — applies to any project with typed API calls.

## Promoted to
`engineering-discipline/SKILL.md` Phase 2, "Read API handlers before
typing response shapes" subsection + red flags table entry.
