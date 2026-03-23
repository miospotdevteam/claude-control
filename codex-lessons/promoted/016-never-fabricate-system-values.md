# Never fabricate values at system boundaries

## Rule
When a function requires a real system value (email, user ID, API key,
resource identifier), trace to where that value actually lives in the
system and use it. Never construct a plausible-looking value from other
fields.

`user.email` — correct (reads the actual value).
`${user.fullName}@company.com` — wrong (fabricated, breaks with spaces,
unicode, long names, or when the domain doesn't accept mail).

Mechanizable check: when you write a value for a field that will be
sent to an external system (Stripe, email provider, auth service),
ask: "Did I READ this value from a data source, or did I CONSTRUCT
it?" If constructed, find the real source.

## Evidence
- **Session**: paroola-gap-closure, 2026-03-23
- **Codex finding**:
  - `step-25.json` (paroola) — Stripe Connect account created with
    fabricated email `${profileRow?.fullName ?? "creator"}@paroola.it`.
    Full names with spaces produce invalid addresses like
    `Mario Rossi@paroola.it`. Blocks onboarding, routes Stripe comms
    to nonexistent address (HIGH, WRONG_PATTERN)
  - `step-25.json` (paroola) — payout page exists at
    `/profilo/pagamenti` but no navigation entry reaches it —
    route was created but never wired to the UI (MISSED_CONSUMER)
- **Bug**: Claude needs an email for Stripe account creation. Instead
  of reading the user's actual email from Supabase auth, it constructs
  one from the full name + company domain. The constructed email is
  invalid for names with spaces and routes Stripe communications to
  a nonexistent address.
- **Root cause**: Claude fills in "obvious" values to unblock itself
  rather than pausing to find the real data source. The fabricated
  value looks correct in the code and passes type checking, making
  the bug invisible until runtime.

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

Especially critical for: payment systems, auth, email, any external
service that validates or acts on the value.

## Status
promoted

## Promotion
- **Where**: `engineering-discipline/SKILL.md` — new Phase 2 section "Never fabricate values at system boundaries" + red flags table entry
- **Date**: 2026-03-23
- **Plan**: promote-codex-lessons
