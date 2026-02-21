# API Contracts Checklist

Single source of truth for request/response types. Schemas live in the
shared package (`packages/api/`), never inside individual apps. If the
frontend and backend disagree on a type, there's a bug — the only question
is when you'll find it.

## Before

- [ ] Locate the shared API package (typically `packages/api/` with `@repo/api` imports)
- [ ] For the endpoint you're touching: find the Zod schema in `packages/api/src/schemas/`
- [ ] If no shared schema exists: STOP — create it in the shared package before writing any handler or client code
- [ ] Check that the schema is exported from the package barrel (`packages/api/src/index.ts`)
- [ ] Check that the schema is imported by BOTH the server handler AND the client call site from `@repo/api`
- [ ] Read the existing schema — understand what fields exist, which are optional, what validations run

## During

- [ ] Define input/output types as Zod schemas in `packages/api/`, NOT as TypeScript interfaces in an app
- [ ] Use `z.infer<typeof Schema>` to derive TypeScript types — never duplicate the type manually
- [ ] In tRPC: use `.input(schema)` and `.output(schema)` on procedures — schemas come from `@repo/api`
- [ ] For form validation: use the same `@repo/api` schema with `zodResolver` — one schema, two enforcement points
- [ ] When adding a field: add it to the schema in `packages/api/` FIRST, then update server, then client
- [ ] When removing a field: check all app consumers FIRST, update apps, then remove from schema

## After

- [ ] Verify the schema is the single source of truth — `grep` for the type name and confirm it's only defined in `packages/api/`
- [ ] Check that no app has a local `interface` or `type` that duplicates the schema's shape
- [ ] Run `tsc --noEmit` across the whole monorepo — if schema and usage disagree, `tsc` catches it
- [ ] Confirm the schema is exported from the barrel file (`packages/api/src/index.ts`)
- [ ] If using tRPC: confirm the client gets proper TypeScript errors when calling with wrong input

## Red Flags

| Pattern | Problem |
|---|---|
| Schema defined inside an app (`apps/web/src/schemas/`) | Can't be imported by other apps — move to `packages/api/` |
| Same field list in a Zod schema AND a TypeScript interface | Duplicate source of truth — they WILL drift |
| `as any` or type assertion on API response data | Hiding a contract mismatch |
| App defines its own request/response types instead of importing from `@repo/api` | Types will diverge across apps |
| `fetch()` with manually typed response | No runtime validation — wrong types at runtime |
| Different Zod schemas for the same endpoint in different apps | Multiple sources of truth |
| Schema exists in `packages/api/` but an app also has a local copy | Shadow schema — which one is correct? |
| Optional fields added "just in case" | Unclear contract — is the field used or not? |
| Inline `z.object(...)` inside a tRPC router instead of importing | Can't be shared — extract to `packages/api/` |

## Deep Guidance

For comprehensive patterns including monorepo setup, tRPC schema organization,
migration strategies, and advanced validation, read `api-contracts-guide.md`.
