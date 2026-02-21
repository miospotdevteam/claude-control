# API Contracts Checklist

Single source of truth for request/response types. Schemas live in the
shared package (`@miospot/api`), never inside individual apps. If the
frontend and backend disagree on a type, there's a bug — the only question
is when you'll find it.

## Before

- [ ] Locate the shared API package (`packages/api/` with `@miospot/api` imports)
- [ ] For the endpoint you're touching: find the Zod schema in `@miospot/api`
- [ ] If no shared schema exists: STOP — create it in `@miospot/api` before writing any handler or client code
- [ ] Check that the schema is exported from the package barrel
- [ ] Check that the schema is imported by BOTH the Hono route handler AND the client call site from `@miospot/api`
- [ ] Read the existing schema — understand what fields exist, which are optional, what validations run

## During

- [ ] Define input/output types as Zod schemas in `@miospot/api`, NOT as TypeScript interfaces in an app
- [ ] Use `z.infer<typeof Schema>` to derive TypeScript types — never duplicate the type manually
- [ ] In Hono handlers: use `schema.safeParse()` to validate request bodies, or `@hono/zod-openapi` `createRoute` for OpenAPI integration
- [ ] For form validation: use the same `@miospot/api` schema with `zodResolver` — one schema, two enforcement points
- [ ] When adding a field: add it to the schema in `@miospot/api` FIRST, then update Hono handler, then client
- [ ] When removing a field: check all app consumers FIRST, update apps, then remove from schema

## After

- [ ] Verify the schema is the single source of truth — `grep` for the type name and confirm it's only defined in `@miospot/api`
- [ ] Check that no app has a local `interface` or `type` that duplicates the schema's shape
- [ ] Run `tsc --noEmit` across the whole monorepo — if schema and usage disagree, `tsc` catches it
- [ ] Confirm the schema is exported from the barrel file
- [ ] Test the endpoint with invalid input — does the Hono handler reject it correctly via `safeParse`?

## Red Flags

| Pattern | Problem |
|---|---|
| Schema defined inside an app instead of `@miospot/api` | Can't be imported by other apps — move to the shared package |
| Same field list in a Zod schema AND a TypeScript interface | Duplicate source of truth — they WILL drift |
| `as any` or type assertion on API response data | Hiding a contract mismatch |
| App defines its own request/response types instead of importing from `@miospot/api` | Types will diverge across apps |
| `fetch()` with manually typed response | No runtime validation — wrong types at runtime |
| Different Zod schemas for the same endpoint in different apps | Multiple sources of truth |
| Schema exists in `@miospot/api` but an app also has a local copy | Shadow schema — which one is correct? |
| Inline `z.object(...)` inside a Hono route handler instead of importing | Can't be shared — extract to `@miospot/api` |
| `req.json()` without `safeParse` | Unvalidated input — runtime type errors waiting to happen |

## Deep Guidance

For comprehensive patterns including Hono + Zod schema organization,
`@hono/zod-openapi` integration, migration strategies, and advanced
validation, read `api-contracts-guide.md`.
