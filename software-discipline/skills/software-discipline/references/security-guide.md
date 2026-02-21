# Security Guide

Comprehensive security guidance for AI-assisted development. Research indicates
AI-generated code has 1.7x more security issues than human-written code.
This guide addresses the most common vulnerabilities.

---

## OWASP Top 10 for AI-Generated Code

AI code generation commonly introduces these vulnerability patterns:

### 1. Injection (SQL, NoSQL, Command)
**Pattern**: Building queries with string concatenation instead of parameterization.
**Fix**: Always use parameterized queries, prepared statements, or ORM methods.
```
Bad:  db.query("SELECT * FROM users WHERE id = " + userId)
Good: db.query("SELECT * FROM users WHERE id = $1", [userId])
```

### 2. Broken Authentication
**Pattern**: Implementing custom auth instead of using proven libraries.
**Fix**: Use established auth libraries (NextAuth, Passport, Auth.js). Never
store passwords in plaintext. Use bcrypt/argon2 for hashing.

### 3. Sensitive Data Exposure
**Pattern**: Returning full database records instead of selected fields.
**Fix**: Explicitly select returned fields. Never return password hashes,
internal IDs, or admin flags to non-admin users.

### 4. Broken Access Control
**Pattern**: Checking authentication but not authorization.
**Fix**: For every endpoint: who can access this? Check role/permission, not
just "is logged in." Verify resource ownership (can this user see THIS item?).

### 5. Security Misconfiguration
**Pattern**: Leaving debug mode on, using default credentials, exposing
configuration endpoints.
**Fix**: Check environment-specific config. Ensure error pages don't leak
stack traces. Verify CORS settings.

### 6. Cross-Site Scripting (XSS)
**Pattern**: Rendering user-provided content without sanitization.
**Fix**: Use framework auto-escaping (React JSX is safe by default). When
rendering raw HTML is necessary, sanitize with DOMPurify or equivalent.

### 7. Insecure Dependencies
**Pattern**: Installing packages without verifying their authenticity.
**Fix**: Verify package names on the official registry. Check publisher.
Review download counts. Use lock files.

---

## The S.E.C.U.R.E. Framework

A systematic approach for security review of every change:

**S** — **Secrets**: Are any secrets hardcoded? Check for API keys, tokens,
passwords in source files. They belong in environment variables only.

**E** — **Endpoints**: Do all new endpoints have proper auth middleware?
Check both authentication (who are you?) and authorization (can you do this?).

**C** — **Configuration**: Is the security config appropriate for the
environment? Debug off in production, CORS restricted, CSP headers set.

**U** — **User Input**: Is all user input validated and sanitized? Check
form data, URL parameters, headers, file uploads.

**R** — **Resources**: Are you protecting access to resources? Can user A
see user B's data? Check for IDOR (Insecure Direct Object Reference).

**E** — **Errors**: Do error responses hide internal details? Stack traces,
file paths, and database error messages should be logged server-side only.

---

## Slopsquatting Prevention

Slopsquatting is when AI recommends package names that don't exist, and
attackers register those names with malicious code. Research shows ~20% of
AI-recommended packages are hallucinated.

### Prevention steps

1. **Verify on the registry**: Before installing, check npm/pypi/crates.io
   that the package exists AND is the one you intend
2. **Check the publisher**: Is the package from the expected organization?
3. **Check download counts**: Legitimate popular packages have thousands
   of weekly downloads
4. **Read the README**: Does it describe the functionality you expect?
5. **Check first publish date**: If the package was published very recently,
   be extra cautious

### High-risk patterns

- Package names that are close to but not exactly a popular package
- Packages with very few downloads
- Packages where the README doesn't match the expected functionality
- AI suggesting a package you've never heard of for common functionality

---

## Concrete Security Patterns

### Input validation at boundaries

```typescript
// Validate at the API boundary, then trust internally
const schema = z.object({
  email: z.string().email(),
  name: z.string().min(1).max(100),
  role: z.enum(["user", "admin"]),
});

export async function POST(req: Request) {
  const body = schema.parse(await req.json()); // throws on invalid input
  // From here, body is typed and validated
}
```

### Auth + authz pattern

```typescript
// Auth: who are you?
const session = await getSession(req);
if (!session) return Response.json({ error: "Unauthorized" }, { status: 401 });

// Authz: can you do this?
const resource = await db.getResource(params.id);
if (resource.ownerId !== session.userId && session.role !== "admin") {
  return Response.json({ error: "Forbidden" }, { status: 403 });
}
```

### Error handling without leaking details

```typescript
try {
  const result = await riskyOperation();
  return Response.json(result);
} catch (error) {
  console.error("Operation failed:", error); // Full details in server logs
  return Response.json(
    { error: "An internal error occurred" }, // Generic message to client
    { status: 500 }
  );
}
```

### Environment variable safety

```typescript
// Validate required env vars at startup, not at usage time
const requiredEnvVars = ["DATABASE_URL", "AUTH_SECRET", "API_KEY"];
for (const name of requiredEnvVars) {
  if (!process.env[name]) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
}
```
