# API Contracts Guide

The #1 source of vibe-coding bugs: the frontend sends one shape, the backend
expects another, and nobody finds out until runtime. This guide prevents that
by establishing a shared package as the single source of truth.

---

## The Core Principle

**Define once in the shared package, import everywhere.** Every API boundary
has exactly ONE schema definition in `@miospot/api`. Every app imports from
there. If you find yourself writing the same field list in an app, you're
creating a future bug.

---

## Monorepo Structure

```
monorepo/
  packages/
    api/                        # @miospot/api — THE single source of truth
      src/
        schemas/                # Zod schemas organized by domain
          user.ts
          post.ts
          comment.ts
          common.ts             # Shared primitives (pagination, id, dates)
        index.ts                # Barrel export
      package.json              # name: "@miospot/api"
      tsconfig.json
  apps/
    api/                        # Hono + Cloudflare Workers — imports from @miospot/api
    web/                        # Frontend app — imports from @miospot/api
    admin/                      # Admin panel — imports from @miospot/api
```

### Why `packages/api/`?

- **Not `packages/shared/`** — "shared" is a junk drawer. `api` signals
  exactly what's in it: API contracts.
- **Not `packages/types/`** — types are derived from schemas, not the other
  way around. The package contains Zod schemas; types are a byproduct.
- **Not inside any app** — schemas inside `apps/web/` can't be imported by
  `apps/api/`. The shared package sits above all apps.

### Package Setup

```jsonc
// packages/api/package.json
{
  "name": "@miospot/api",
  "private": true,
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "dependencies": {
    "zod": "^3.x"
  }
}
```

```typescript
// packages/api/src/index.ts — barrel export
export * from "./schemas/user";
export * from "./schemas/post";
export * from "./schemas/comment";
export * from "./schemas/common";
```

Apps reference it via workspace protocol:

```jsonc
// apps/api/package.json (Hono worker)
{
  "dependencies": {
    "@miospot/api": "workspace:*"
  }
}
```

---

## Hono + Zod Pattern

Hono doesn't give you automatic end-to-end type inference like tRPC. You
build it yourself with shared Zod schemas and `safeParse`.

### Defining Schemas in the Shared Package

```typescript
// packages/api/src/schemas/user.ts
import { z } from "zod";

export const createUserInput = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email(),
  role: z.enum(["admin", "user"]).default("user"),
});

export const updateUserInput = createUserInput.partial();

export const userOutput = z.object({
  id: z.string().uuid(),
  name: z.string(),
  email: z.string(),
  role: z.enum(["admin", "user"]),
  createdAt: z.string().datetime(),
});

// Derive TypeScript types — never define separately
export type CreateUserInput = z.infer<typeof createUserInput>;
export type UpdateUserInput = z.infer<typeof updateUserInput>;
export type UserOutput = z.infer<typeof userOutput>;
```

### Using Schemas in Hono Route Handlers

```typescript
// apps/api/src/routes/user.ts
import { Hono } from "hono";
import { createUserInput, updateUserInput, userOutput } from "@miospot/api";

const app = new Hono();

app.post("/users", async (c) => {
  const body = await c.req.json();
  const parsed = createUserInput.safeParse(body);

  if (!parsed.success) {
    return c.json({ error: parsed.error.flatten() }, 400);
  }

  // parsed.data is fully typed as CreateUserInput
  const user = await db.user.create({ data: parsed.data });
  return c.json(user, 201);
});

app.put("/users/:id", async (c) => {
  const body = await c.req.json();
  const parsed = updateUserInput.safeParse(body);

  if (!parsed.success) {
    return c.json({ error: parsed.error.flatten() }, 400);
  }

  const user = await db.user.update({
    where: { id: c.req.param("id") },
    data: parsed.data,
  });
  return c.json(user);
});

export default app;
```

### Using @hono/zod-openapi

For automatic OpenAPI documentation, use `@hono/zod-openapi` with the
same shared schemas:

```typescript
// apps/api/src/routes/user.ts
import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import { createUserInput, userOutput } from "@miospot/api";

const app = new OpenAPIHono();

const createUserRoute = createRoute({
  method: "post",
  path: "/users",
  request: {
    body: {
      content: { "application/json": { schema: createUserInput } },
    },
  },
  responses: {
    201: {
      content: { "application/json": { schema: userOutput } },
      description: "User created",
    },
    400: {
      description: "Validation error",
    },
  },
});

app.openapi(createUserRoute, async (c) => {
  // c.req.valid("json") is typed as CreateUserInput — validated automatically
  const data = c.req.valid("json");
  const user = await db.user.create({ data });
  return c.json(user, 201);
});

export default app;
```

The schemas in `createRoute` come from `@miospot/api`. The OpenAPI docs and
the runtime validation use the same source of truth.

### Client-Side

```typescript
// apps/web/src/lib/api/users.ts
import { createUserInput, userOutput, type CreateUserInput, type UserOutput } from "@miospot/api";
import { z } from "zod";

export async function createUser(data: CreateUserInput): Promise<UserOutput> {
  // Optional: validate on client for early feedback
  const validated = createUserInput.parse(data);

  const res = await fetch("/api/users", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(validated),
  });

  if (!res.ok) {
    throw new Error(`API error: ${res.status}`);
  }

  // Validate the response matches the expected shape
  return userOutput.parse(await res.json());
}
```

Both sides import from `@miospot/api`. Zero duplication.

### Form Validation (Same Schema)

```typescript
// apps/web/src/components/UserForm.tsx
import { createUserInput, type CreateUserInput } from "@miospot/api";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";

function UserForm() {
  const form = useForm<CreateUserInput>({
    resolver: zodResolver(createUserInput), // same schema validates the form
  });

  return (
    <form onSubmit={form.handleSubmit((data) => createUser(data))}>
      {/* form fields */}
    </form>
  );
}
```

The form validation and the API validation use the exact same schema. One
source of truth, two enforcement points.

### Key Rule

**Never define a separate TypeScript type that mirrors a Zod schema.** Use
`z.infer<typeof schema>` to derive the type. Two definitions = two sources
of truth = eventual drift.

---

## Common Schema Patterns

### Shared Primitives

```typescript
// packages/api/src/schemas/common.ts
import { z } from "zod";

export const paginationInput = z.object({
  cursor: z.string().optional(),
  limit: z.number().min(1).max(100).default(20),
});

export const idParam = z.object({
  id: z.string().uuid(),
});

export const dateRange = z.object({
  from: z.string().datetime(),
  to: z.string().datetime(),
});

export const sortOrder = z.enum(["asc", "desc"]).default("desc");
```

### Extending and Composing Schemas

```typescript
// packages/api/src/schemas/user.ts
const baseUser = z.object({
  name: z.string(),
  email: z.string().email(),
});

// Create (requires password)
export const createUser = baseUser.extend({
  password: z.string().min(8),
});

// Update (all fields optional)
export const updateUser = baseUser.partial();

// Response (server fields, no password)
export const userResponse = baseUser.extend({
  id: z.string().uuid(),
  createdAt: z.string().datetime(),
});

// List response (with pagination)
export const userListResponse = z.object({
  users: z.array(userResponse),
  nextCursor: z.string().optional(),
  total: z.number(),
});
```

### Discriminated Unions

```typescript
// packages/api/src/schemas/notification.ts
export const notification = z.discriminatedUnion("type", [
  z.object({ type: z.literal("email"), subject: z.string(), body: z.string() }),
  z.object({ type: z.literal("sms"), phone: z.string(), message: z.string() }),
  z.object({ type: z.literal("push"), title: z.string(), data: z.record(z.unknown()) }),
]);
```

---

## Anti-Patterns

### 1. Schema Defined Inside an App

```typescript
// BAD: schema in apps/web/src/schemas/user.ts — can't be imported by apps/api
const createUserInput = z.object({ name: z.string(), email: z.string() });
```

**Fix:** Move to `packages/api/src/schemas/user.ts`. All apps import from `@miospot/api`.

### 2. Duplicate Type Definitions

```typescript
// BAD: Two sources of truth
// packages/api/src/schemas/user.ts
const createUserInput = z.object({ name: z.string(), email: z.string() });

// apps/web/src/components/UserForm.tsx
interface UserFormData {
  name: string;
  email: string;
  // Someone adds 'phone' here but not in the schema...
}
```

**Fix:** `type UserFormData = z.infer<typeof createUserInput>` — import from `@miospot/api`.

### 3. Unvalidated Request Bodies

```typescript
// BAD: no runtime validation — body could be anything
app.post("/users", async (c) => {
  const body = await c.req.json();
  // body is 'any' — no safeParse, no type safety
  await db.user.create({ data: body });
});

// GOOD: validate with shared schema
import { createUserInput } from "@miospot/api";
app.post("/users", async (c) => {
  const body = await c.req.json();
  const parsed = createUserInput.safeParse(body);
  if (!parsed.success) return c.json({ error: parsed.error.flatten() }, 400);
  await db.user.create({ data: parsed.data });
});
```

### 4. Untyped Fetch Responses

```typescript
// BAD: response is 'any'
const res = await fetch("/api/users");
const users = await res.json(); // any

// GOOD: validate with shared schema
import { userListResponse } from "@miospot/api";
const res = await fetch("/api/users");
const users = userListResponse.parse(await res.json());
```

### 5. Client-Side Type Assertions

```typescript
// BAD: lying to the compiler
const data = await res.json() as UserResponse;

// GOOD: runtime validation proves the type
import { userResponse } from "@miospot/api";
const data = userResponse.parse(await res.json());
```

### 6. Inline Schemas in Route Handlers

```typescript
// BAD: schema only exists inside the handler — can't share
app.post("/users", async (c) => {
  const parsed = z.object({ name: z.string(), email: z.string() }).safeParse(body);
  ...
});

// GOOD: import from shared package
import { createUserInput } from "@miospot/api";
app.post("/users", async (c) => {
  const parsed = createUserInput.safeParse(body);
  ...
});
```

### 7. App-Local Schema That Shadows the Shared One

```typescript
// BAD: apps/web/src/schemas/user.ts exists AND packages/api/src/schemas/user.ts exists
// Which one is correct? Nobody knows. They will drift.
```

**Fix:** Delete the app-local copy. Import from `@miospot/api`.

---

## Migration Strategy

Already have schemas scattered across apps? Migrate incrementally:

1. **Create `packages/api/`** with package.json (`@miospot/api`), tsconfig, and `src/schemas/`
2. **Pick the highest-traffic endpoint** — the one that breaks most often
3. **Move its schema** to `packages/api/src/schemas/` and export from index.ts
4. **Update imports** in all apps: `import { ... } from "@miospot/api"`
5. **Delete the old schema files** from the app directories
6. **Add `safeParse` calls** in Hono handlers that are missing validation
7. **Run `tsc --noEmit`** across the whole monorepo — fix anything that breaks
8. **Repeat** for the next endpoint, working outward from the most-used ones

---

## Verification

After making API boundary changes, always:

1. `tsc --noEmit` across the whole monorepo — catches type mismatches
2. Check that schemas are exported from `packages/api/src/index.ts`
3. `grep` for the schema name — is it imported from `@miospot/api` everywhere?
4. Check no app has a local duplicate of the same schema
5. Test the endpoint with invalid input — does the Hono handler reject correctly via `safeParse`?
