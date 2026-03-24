# Sub-plan Format (Deprecated)

Sub-plans are now **inline in plan.json** as the `subPlan` field on steps.
There are no longer separate sub-plan markdown files.

See `references/plan-schema.md` for the inline sub-plan format:

```json
{
  "subPlan": {
    "groups": [
      {"name": "Dashboard pages", "owner": "claude", "files": ["a.tsx", "b.tsx"]},
      {"name": "Modal components", "owner": "codex", "files": ["c.tsx", "d.tsx"]}
    ]
  }
}
```

**Note:** Group `status` and `notes` are mutable fields stored in
`progress.json`, not in plan.json. The `name`, `owner`, and `files`
fields are immutable plan definition.

Groups should have 3-8 files each. A step gets a sub-plan when ANY of:
- It touches **more than 10 files**
- It's a **repetitive sweep** across many files
- It has **more than 5 independently completable sub-tasks**
- It requires **reading more than 8 files** to understand what to change

See the `writing-plans` skill for the full evaluation criteria.
