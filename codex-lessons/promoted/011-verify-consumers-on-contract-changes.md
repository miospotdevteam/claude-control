# Verify ALL consumers when changing API/webhook contracts

## Rule
Before renaming, reshaping, or removing any field in an API response,
webhook payload, function signature, or shared type export: grep for
every consumer of that contract — including consumers in OTHER repos,
webhook receivers, and downstream services. Update all consumers in the
same step. Never change a producer without checking its consumers.

This extends the existing "track blast radius" rule to cross-repo and
event-driven boundaries (webhooks, postMessage, queue payloads) where
consumers are not discoverable by in-repo grep alone.

Mechanizable check: when you rename a field from `fooId` to `id` in
a payload, grep ALL repos that receive that payload. If you can't grep
the receiver (different repo), read the receiver's handler before
changing the producer.

## Evidence
- **Session**: paroola-gap-closure, 2026-03-23
- **Codex findings**:
  - `step-5.json` — wave completion webhooks renamed `presenzaId` →
    `id`, MioSpot receiver still reads `presenzaId` → silent exit,
    broken sync (HIGH)
  - `step-5.json` — `campagna.completed` renamed `campagnaId` → `id`,
    MioSpot completion sync broken (HIGH)
  - `step-2.json` — GET presenza drops `inquiryId` on campaign-ID
    fetch path (consumer expects it)
  - `step-2-reverify-1.json` — PATCH fallback missing `queryType`
    guard, can update wrong records
- **Session**: deepen-codex-collaboration, 2026-03-23
- **Codex findings**:
  - `step-1.json` — hook calls `plan_utils.update_step()` but API
    exports `update_step_status()` (HIGH, MISSED_CONSUMER)
  - `step-4.json` — codex-dispatch still branches on removed
    `claude-solo` mode after playbook was updated
- **Bug**: Claude changes the producer's field names or removes a mode
  without checking every consumer. Cross-repo webhooks are the worst
  case — the consumer is invisible to local grep.
- **Root cause**: Claude's "check consumers" habit applies to in-file
  and in-repo imports. It does not extend to webhook receivers, queue
  consumers, or shared types consumed by other repositories.

## Scope
- [x] Universal (applies to all projects)
- [ ] Project-specific (applies to specific stacks/patterns)

Especially critical for: webhook payloads, event-driven architectures,
monorepo cross-package types, public API responses.

## Status
promoted

## Promotion
- **Where**: `engineering-discipline/SKILL.md` — strengthened "Track blast radius" section with webhook payloads, cross-repo contracts, postMessage shapes + red flags table entry
- **Date**: 2026-03-23
- **Plan**: promote-codex-lessons
