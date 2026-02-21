# API Contracts Checklist

Single source of truth for request/response types. Schemas live in a
shared package (not inside individual apps). If the frontend and backend
disagree on a type, there's a bug — the only question is when you'll find it.

> **Config-aware**: The `check-api-contracts` hook reads your project's
> `.claude/software-discipline.local.md` for `structure.shared_api_package`,
> `stack.backend`, and `stack.validation`. The advice below uses generic
> terms — substitute your project's actual values.

## Before

- [ ] Locate the shared API package (check `structure.shared_api_package` in your config)
- [ ] For the endpoint you're touching: find the validation schema in the shared package
- [ ] If no shared schema exists: STOP — create it in the shared package before writing any handler or client code
- [ ] Check that the schema is exported from the package barrel
- [ ] Check that the schema is imported by BOTH the route handler AND the client call site
- [ ] Read the existing schema — understand what fields exist, which are optional, what validations run

## During

- [ ] Define input/output types as validation schemas in the shared package, NOT as TypeScript interfaces in an app
- [ ] Derive TypeScript types from schemas (e.g. `z.infer<>` for Zod, `InferOutput<>` for Valibot) — never duplicate the type manually
- [ ] In route handlers: use the schema's parse/validate function for request body validation
- [ ] For form validation: use the same shared schema — one schema, two enforcement points (server + client)
- [ ] When adding a field: add it to the schema in the shared package FIRST, then update handler, then client
- [ ] When removing a field: check all consumers FIRST, update apps, then remove from schema

## After

- [ ] Verify the schema is the single source of truth — `grep` for the type name and confirm it's only defined in the shared package
- [ ] Check that no app has a local `interface` or `type` that duplicates the schema's shape
- [ ] Run the type checker across the whole project — if schema and usage disagree, it catches it
- [ ] Confirm the schema is exported from the barrel file
- [ ] Test the endpoint with invalid input — does the handler reject it correctly?

## Red Flags

| Pattern | Problem |
|---|---|
| Schema defined inside an app instead of the shared package | Can't be imported by other apps — move to the shared package |
| Same field list in a validation schema AND a TypeScript interface | Duplicate source of truth — they WILL drift |
| `as any` or type assertion on API response data | Hiding a contract mismatch |
| App defines its own request/response types instead of importing from shared | Types will diverge across apps |
| `fetch()` with manually typed response | No runtime validation — wrong types at runtime |
| Different schemas for the same endpoint in different apps | Multiple sources of truth |
| Schema exists in shared package but an app also has a local copy | Shadow schema — which one is correct? |
| Inline schema definition inside a route handler instead of importing | Can't be shared — extract to the shared package |
| Parsing request body without validation | Unvalidated input — runtime type errors waiting to happen |

## Deep Guidance

For comprehensive patterns including schema organization, OpenAPI
integration, migration strategies, and advanced validation, read
`api-contracts-guide.md`.
