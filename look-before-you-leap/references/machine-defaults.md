# Machine Defaults

Status: verified on 2026-04-24.

This repository relies on machine-level defaults for Claude and Codex model
selection. Dispatch scripts and skill prompts must rely on those defaults
instead of passing explicit model flags.

## Expected State

### Claude

Configuration file: `~/.claude/settings.json`

Expected values:

```json
{
  "model": "claude-opus-4-7",
  "effortLevel": "high"
}
```

`effortLevel` is the Claude settings field used for the required reasoning
level.

### Codex

Configuration file: `~/.codex/config.toml`

Expected values:

```toml
model = "gpt-5.5"
model_reasoning_effort = "high"
service_tier = "fast"
```

`model_reasoning_effort` is the Codex config field used for the required
reasoning effort.

## Verification Commands

Use read-only checks when confirming the machine default state:

```bash
python3 - <<'PY'
import json
from pathlib import Path

data = json.loads((Path.home() / ".claude/settings.json").read_text())
print(f"model={data.get('model')!r}")
print(f"effortLevel={data.get('effortLevel')!r}")
PY
```

```bash
python3 - <<'PY'
from pathlib import Path

for line in (Path.home() / ".codex/config.toml").read_text().splitlines():
    if line.startswith(("model =", "model_reasoning_effort =", "service_tier =")):
        print(line)
PY
```

## No-Downgrade Rule

Never pass explicit model flags that downgrade the configured defaults to weaker
models. In particular, do not pass flags or wrapper arguments that force Claude
to `sonnet` or `haiku`, and do not pass flags or wrapper arguments that force
Codex to `gpt-5`.

If a dispatch script needs a model, it must rely on the machine defaults above
unless a future plan explicitly changes this document and the machine config in
the same verified step.
