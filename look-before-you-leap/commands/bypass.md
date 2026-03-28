---
description: "Grant a temporary bypass for plan enforcement. Only the user can run this command — Claude cannot invoke it."
allowed-tools: []
user-invocable: true
---

# Bypass Plan Enforcement

The `capture-user-override.sh` UserPromptSubmit hook already detected
"bypass" in the user's prompt and minted a signed bypass receipt. The
receipt allows code edits without an active plan.

## What to do

Tell the user: **Plan enforcement is temporarily bypassed for this
session.** You can now edit files without an active plan. The bypass
does not persist across sessions.

Do NOT attempt to run `grant-bypass.sh` — the hook already handled it.
