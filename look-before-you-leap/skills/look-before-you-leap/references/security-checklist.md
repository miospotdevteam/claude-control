# Security Checklist

## Before

- [ ] Identify security boundaries: what data is user-controlled? What's trusted?
- [ ] Check for existing auth/authz patterns (middleware, guards, decorators)
- [ ] Check for existing input validation patterns (Zod, Valibot, Joi, etc.)
- [ ] Check for existing sanitization utilities
- [ ] Review `.env` handling — are secrets loaded safely?

## During

- [ ] Never hardcode secrets, API keys, or credentials — use environment variables
- [ ] Validate ALL user input at the boundary (API routes, form handlers, URL params)
- [ ] Use parameterized queries for database access — never string concatenation
- [ ] Sanitize output to prevent XSS (HTML encoding, Content-Security-Policy)
- [ ] Check auth AND authz — authenticated doesn't mean authorized
- [ ] Verify new dependencies are real packages, not typosquats (check npm/pypi, verify publisher)
- [ ] Don't expose internal errors to users — log details server-side, return generic messages

## After

- [ ] Grep for hardcoded secrets: API keys, passwords, tokens in source files
- [ ] Verify `.env` files are in `.gitignore`
- [ ] Check that error responses don't leak stack traces or internal paths
- [ ] Verify auth checks exist on all new routes/endpoints
- [ ] If adding dependencies: verify package names match the intended library

## Red Flags

| Pattern | Problem |
|---|---|
| String-concatenated SQL queries | SQL injection |
| Rendering raw user HTML without sanitization | XSS vulnerability |
| Hardcoded API keys or tokens in source | Credential exposure |
| Missing auth middleware on new route | Unauthenticated access |
| Dynamic code execution with user input | Code injection |
| Nullable userId on authenticated routes | Auth bypass potential |
| Installing unfamiliar packages without verification | Slopsquatting risk |

## Deep Guidance

For comprehensive security strategy including OWASP Top 10, the S.E.C.U.R.E.
framework, and slopsquatting prevention, read `security-guide.md`.

Look for installed skills about "security" or "authentication" for
project-specific security guidance.
