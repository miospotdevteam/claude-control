---
description: "Refresh the installed plugin cache from the local source checkout."
allowed-tools: ["Bash"]
user-invocable: true
---

# Refresh Plugin Cache

Run the refresh script from the installed plugin root:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-from-source.sh"
```

Report the script output to the user. If it fails, report the failure message
and do not retry automatically.
