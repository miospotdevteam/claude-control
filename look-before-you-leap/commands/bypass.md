---
description: "Grant a temporary bypass for plan enforcement. Only the user can run this command — Claude cannot invoke it."
allowed-tools: ["Bash"]
user-invocable: true
---

# Bypass Plan Enforcement

This command grants a temporary bypass receipt that allows code edits
without an active plan. The receipt is HMAC-signed and stored outside
the repo — Claude cannot forge or tamper with it.

## What to do

Run the grant-bypass script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/grant-bypass.sh
```

This will:
1. Detect the current project root
2. Find the active plan (if any) or use a default plan ID
3. Write a signed `bypass` receipt to the external state root
4. Also write the legacy `.no-plan-$PPID` marker for backwards compatibility

After running, tell the user that plan enforcement is temporarily bypassed
for this session. Remind them that the bypass is session-scoped — it does
not persist across sessions.
