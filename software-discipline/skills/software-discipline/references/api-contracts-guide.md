# API Contracts Guide

The #1 source of vibe-coding bugs: the frontend sends one shape, the backend
expects another, and nobody finds out until runtime. This guide prevents that
by establishing a shared package as the single source of truth.

---

## The Core Principle

**Define once in the shared package, import everywhere.** Every API boundary
has exactly ONE schema definition in `packages/api`. Every app imports from
there. If you find yourself writing the same field list in an app, you're
creating a future bug.

---

## Monorepo Structure

```
monorepo/
  packages/
    api/                        # @repo/api — THE single source of truth
      src/
        schemas/                # Zod schemas organized by domain
          user.ts
          post.ts
          comment.ts
          common.ts             # Shared primitives (pagination, id, dates)
        index.ts                # Barrel export
      package.json              # name: "@repo/api"
      tsconfig.json
  apps/
    web/                        # Next.js frontend — imports from @repo/api
    backend/                    # API server — imports from @repo/api
    admin/                      # Admin panel — imports from @repo/api
```

### Why `packages/api/`?

- **Not `packages/shared/`** — "shared" is a junk drawer. `api` signals
  exactly what's in it: API contracts.
- **Not `packages/types/`** — types are derived from schemas, not the other
  way around. The package contains Zod schemas; types are a byproduct.
- **Not inside any app** — schemas inside `apps/web/` can't be imported by
  `apps/backend/`. The shared package sits above all apps.

### Package Setup

```jsonc
// packages/api/package.json
{
  "name": "@repo/api",
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
// apps/web/package.json
{
  "dependencies": {
    "@repo/api": "workspace:*"
  }
}
```

---

## tRPC + Zod Pattern

tRPC gives you end-to-end type safety — but only if schemas live in the
shared package. The schema IS the contract.

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
  createdAt: z.date(),
});

// Derive TypeScript types — never define separately
export type CreateUserInput = z.infer<typeof createUserInput>;
export type UpdateUserInput = z.infer<typeof updateUserInput>;
export type UserOutput = z.infer<typeof userOutput>;
```

### Using Schemas in tRPC Routers (Backend App)

```typescript
// apps/backend/src/trpc/routers/user.ts
import { createUserInput, updateUserInput, userOutput } from "@repo/api";

export const userRouter = createTRPCRouter({
  create: protectedProcedure
    .input(createUserInput)
    .output(userOutput)
    .mutation(async ({ input, ctx }) => {
      // 'input' is fully typed as CreateUserInput
      const user = await ctx.db.user.create({ data: input });
      return user; // must match userOutput schema
    }),

  update: protectedProcedure
    .input(updateUserInput.extend({ id: z.string().uuid() }))
    .output(userOutput)
    .mutation(async ({ input, ctx }) => {
      const { id, ...data } = input;
      return ctx.db.user.update({ where: { id }, data });
    }),
});
```

### Client-Side (Automatic with tRPC)

```typescript
// apps/web/src/components/UserForm.tsx
// With tRPC, client types are inferred from the router.
// No need to import schemas here — tRPC does it.
const createUser = trpc.user.create.useMutation();

// TypeScript error if you pass wrong shape:
createUser.mutate({ name: "Alice", email: "alice@example.com" });
// createUser.mutate({ wrong: "field" }); // ← compile error
```

### When the Client DOES Need the Schema

Sometimes the client needs the schema directly — for form validation:

```typescript
// apps/web/src/components/UserForm.tsx
import { createUserInput, type CreateUserInput } from "@repo/api";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";

function UserForm() {
  const form = useForm<CreateUserInput>({
    resolver: zodResolver(createUserInput), // same schema validates the form
  });
  const createUser = trpc.user.create.useMutation();

  return (
    <form onSubmit={form.handleSubmit((data) => createUser.mutate(data))}>
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

## Next.js Route Handlers (When Not Using tRPC)

If an app has Next.js API routes without tRPC, you lose automatic type
inference. You still import schemas from `@repo/api`.

```typescript
// apps/web/src/app/api/posts/route.ts
import { createPostInput } from "@repo/api";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const parsed = createPostInput.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const post = await db.post.create({ data: parsed.data });
  return NextResponse.json(post);
}
```

```typescript
// apps/web/src/lib/api/posts.ts — client-side caller
import { createPostInput, type CreatePostInput } from "@repo/api";

export async function createPost(data: CreatePostInput) {
  const validated = createPostInput.parse(data);
  const res = await fetch("/api/posts", {
    method: "POST",
    body: JSON.stringify(validated),
  });
  return res.json();
}
```

Both sides import from `@repo/api`. Zero duplication.

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
  from: z.date(),
  to: z.date(),
}).refine(d => d.from <= d.to, "from must be before to");

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
  createdAt: z.date(),
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
// BAD: schema in apps/web/src/schemas/user.ts — can't be imported by apps/backend
const createUserInput = z.object({ name: z.string(), email: z.string() });
```

**Fix:** Move to `packages/api/src/schemas/user.ts`. All apps import from there.

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

**Fix:** `type UserFormData = z.infer<typeof createUserInput>` — import from `@repo/api`.

### 3. Untyped Fetch Responses

```typescript
// BAD: response.data is 'any'
const res = await fetch("/api/users");
const users = await res.json(); // any

// GOOD: validate with shared schema
import { userListResponse } from "@repo/api";
const res = await fetch("/api/users");
const users = userListResponse.parse(await res.json());
```

### 4. Client-Side Type Assertions

```typescript
// BAD: lying to the compiler
const data = await res.json() as UserResponse;

// GOOD: runtime validation proves the type
import { userResponse } from "@repo/api";
const data = userResponse.parse(await res.json());
```

### 5. Inline Schemas in Routers

```typescript
// BAD: schema only exists inside the router — can't share
export const userRouter = createTRPCRouter({
  create: protectedProcedure
    .input(z.object({ name: z.string(), email: z.string() }))
    .mutation(async ({ input }) => { ... }),
});

// GOOD: import from shared package
import { createUserInput } from "@repo/api";
export const userRouter = createTRPCRouter({
  create: protectedProcedure
    .input(createUserInput)
    .mutation(async ({ input }) => { ... }),
});
```

### 6. App-Local Schema That Shadows the Shared One

```typescript
// BAD: apps/web/src/schemas/user.ts exists AND packages/api/src/schemas/user.ts exists
// Which one is correct? Nobody knows. They will drift.
```

**Fix:** Delete the app-local copy. Import from `@repo/api`.

---

## Migration Strategy

Already have schemas scattered across apps? Migrate incrementally:

1. **Create `packages/api/`** with package.json, tsconfig, and `src/schemas/`
2. **Pick the highest-traffic endpoint** — the one that breaks most often
3. **Move its schema** to `packages/api/src/schemas/` and export from index.ts
4. **Update imports** in all apps: `import { ... } from "@repo/api"`
5. **Delete the old schema files** from the app directories
6. **Add `.output()` to tRPC procedures** for full round-trip validation
7. **Run `tsc --noEmit`** across the whole monorepo — fix anything that breaks
8. **Repeat** for the next endpoint, working outward from the most-used ones

---

## Verification

After making API boundary changes, always:

1. `tsc --noEmit` across the whole monorepo — catches type mismatches
2. Check that schemas are exported from `packages/api/src/index.ts`
3. `grep` for the schema name — is it imported from `@repo/api` everywhere?
4. Check no app has a local duplicate of the same schema
5. Test with invalid input — does the server reject correctly?
