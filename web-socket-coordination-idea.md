# WebSocket Multi-Agent Coordination

Design notes from brainstorming session (2026-03-23). Not a build plan — a
design exploration for real-time multi-agent coordination via shared context.

---

## The Problem

Current multi-agent orchestration (e.g., Ruflo) is just dispatch: spawn
isolated processes, write to a shared store, poll results. Each agent is
blind to what others are doing in real time. "Shared memory" is just a
database they poll.

LBYL's CC+Codex model is sequential: `codex exec` gets a fresh prompt with
step context, Codex has no awareness of what other agents are doing.

Real collaboration needs real-time awareness — agents observing each other's
changes as they happen, not discovering conflicts after the fact.

---

## Core Idea

A WebSocket room scoped to the **project** (not the plan). Multiple plans
can join the same room. Agents broadcast what they're changing, and a
filtering layer ensures each agent only sees what's relevant to its scope.

The room is a broadcast channel with tier-based visibility. All intelligence
lives in supervisors and the filter script, not the server.

---

## Architecture

```
                    ┌─────────────┐
                    │   Human     │
                    │  (observer) │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  WS Server  │
                    │  (room state│
                    │   + signal  │
                    │   log +     │
                    │   overlap   │
                    │   sets)     │
                    └──────┬──────┘
                           │
            ┌──────────────┼──────────────┐
            │                             │
     ┌──────▼───────┐              ┌───────▼─────┐
     │ Supervisor A │              │Supervisor B │
     │ (Plan A)     │◄────────────►│(Plan B)     │
     │              │  tier 2:     │             │
     │              │  overlap     │             │
     │              │  negotiation │             │
     └──────┬───┬───┘              └──┬───┬──────┘
            │   │                     │   │
        ┌───▼┐ ┌▼─────┐           ┌───▼┐ ┌▼───┐
        │ MCP │ │MCP  │           │MCP │ │MCP │
        │Brdg │ │Brdg │           │Brdg│ │Brdg│
        │+Flt │ │+Flt │           │+Flt│ │+Flt│
        └─┬───┘ └──┬──┘           └─┬──┘ └──┬─┘
          │        │                │       │
        ┌─▼───┐ ┌──▼─┐            ┌─▼──┐ ┌──▼─┐
        │Ag 1 │ │Ag 2│            │Ag 3│ │Ag 4│
        └─────┘ └────┘            └────┘ └────┘
```

### Components

- **WS Server**: One room per project (keyed by project root hash). Dumb
  broadcast with tier-based visibility and overlap set computation. Stateless
  — room dies when last plan disconnects. ~200 lines.

- **Supervisors**: Agents spawned by CC when a plan starts executing. They
  join the room, register their plan's file scopes, and watch. They see all
  tier 1 signals and tier 2 plan context. They steer their own subagents
  via directives. They negotiate with other supervisors about overlapping
  scope.

- **MCP Bridge + Filter**: One instance per subagent. Exposes tools:
  `signal`, `get_updates`, `wait_for`. Filters tier 1 signals using dep
  maps — only passes signals relevant to the agent's file scope. Also
  delivers directives from the agent's supervisor.

- **PreToolUse Hook**: Calls `get_updates` before each Edit/Write. Injects
  relevant signals + any pending directive into the agent's context.

---

## Three Message Tiers

| Tier | Who sees it | What it contains | Filtering |
|---|---|---|---|
| **1: Signals** | Subagents (filtered) + supervisors | Plan-agnostic file changes: type mutations, new exports, renamed fields, deleted code | Dep-map based for subagents; overlap-set based for supervisors |
| **2: Plan Context** | Supervisors only | Plan overlap notifications, coordination decisions, constraints, intent | Only flows between supervisors of plans with overlapping file scopes |
| **3: Directives** | Targeted subagent | Course corrections from its own supervisor | Direct delivery by agent ID |

### Signal granularity

Signals are file-level, not function-level. False positives are acceptable —
with 1M context, supervisors can afford noise. Missing a signal that causes
a conflict costs a rollback. The filter is simple: if a file appears in both
plans' scopes, everything about it flows to both supervisors.

---

## Message Types

| Type | Direction | Purpose |
|---|---|---|
| **signal** | agent -> room | "Here's what I just did/found" (tier 1) |
| **plan_overlap** | supervisor -> supervisor | "My plan touches these shared files, here's my intent" (tier 2) |
| **plan_coordination** | supervisor -> supervisor | "Compatible / needs sequencing / conflict" (tier 2) |
| **directive** | supervisor -> its own subagent | "Change course" / "wait for X" (tier 3) |
| **wait** | agent -> room | "I need X before I can continue" (tier 1) |
| **resolve** | supervisor -> agent | "Here's the X you need" (tier 3) |

---

## File Ownership

Decided at **planning time**, not runtime. No claims, no work stealing,
no runtime negotiation. LBYL's plan.json already assigns files to steps
and steps to owners. The room doesn't arbitrate — it informs.

---

## Multi-Plan Coordination

### What happens when Plan B joins mid-execution of Plan A

1. Plan B supervisor connects to the room
2. Reads registered plans — sees Plan A is active with its file scopes
3. Compares: do Plan B's files overlap with Plan A's?
4. If overlap exists, Plan B supervisor sends tier 2 message:

```json
{
  "type": "plan_overlap",
  "from_plan": "rate-limiting",
  "overlapping_files": ["src/api.ts", "src/auth.ts"],
  "my_intent": "adding rate limiting middleware, will modify request pipeline in api.ts, will read AuthToken from auth.ts (no writes)",
  "my_steps_summary": ["step 1: middleware layer", "step 2: config"],
  "read_only": ["src/auth.ts"],
  "read_write": ["src/api.ts"]
}
```

5. Plan A supervisor evaluates overlap severity and responds:

```json
{
  "type": "plan_coordination",
  "decision": "compatible",
  "constraints": "agent-a2 is modifying route handlers in api.ts, avoid touching the router setup until step 3 completes. auth.ts AuthResponse type is being extended — refreshToken field landing soon.",
  "notify_me_before": ["src/api.ts router section"]
}
```

6. Plan B supervisor translates this into directives for its subagents:
   "AuthResponse is in flux, expect a refreshToken field. Don't type
   against the current shape — wait for signal."

**Subagents never see the negotiation.** They see:
- Tier 1 signals (filtered): "auth.ts changed, AuthResponse now has refreshToken"
- Tier 3 directives from their supervisor: "wait for AuthResponse to stabilize"

---

## Room State

```
Room State:
├── registered_plans[]
│   ├── plan_id, title, status
│   ├── file_scopes (public — any supervisor can read)
│   └── supervisor_id
│
├── overlap_sets
│   └── computed intersection of file scopes across plans
│
├── signals[] (tier 1)
│   └── {agent, plan, files, change_type, description, timestamp}
│
├── plan_context[] (tier 2 — supervisors only)
│   ├── overlap notifications
│   ├── coordination decisions
│   └── constraints
│
└── directives[] (tier 3 — per agent queue)
    └── {target_agent, supervisor, message, priority}
```

---

## Filter Logic

### For subagents (dep-map based)

```python
def should_forward_to_subagent(signal, agent_scope):
    # agent_scope = set of assigned files + their deps (from dep maps)
    touched_files = set(signal.files)
    return bool(touched_files & agent_scope)
```

### For supervisors (overlap-set based)

```python
def should_forward_to_supervisor(signal, supervisor_plan, overlap_sets):
    # supervisor sees all signals from its own plan's agents (always)
    if signal.plan == supervisor_plan:
        return True
    # plus signals from other plans that touch overlapping files
    touched_files = set(signal.files)
    overlap = overlap_sets.get((signal.plan, supervisor_plan), set())
    return bool(touched_files & overlap)
```

---

## Steering Mechanism

Directives reach running agents via the **PreToolUse hook**. Before every
Edit/Write, the hook calls the MCP bridge for pending directives. If one
exists, it's injected into the tool context. The agent sees it and adjusts.

Latency: one tool call. Agent might make one wrong edit before seeing the
directive, but the next tool call catches it. For automated supervisors,
this is effectively real-time.

---

## What This Unlocks

**Intentionally overlapping plans.** Today you avoid concurrent plans on
shared files because it causes chaos. With the room, you can run "Plan A
builds the auth system" and "Plan B builds the API layer that consumes it"
concurrently. Signals keep them in sync as types evolve.

This isn't parallel execution of independent work — it's **collaborative
concurrent development** on interdependent features. Nobody has this yet.
Every existing agent framework assumes agents work on independent tasks
and coordinate results.

---

## Integration with LBYL

Existing pieces that slot in directly:
- **plan.json** with file assignments per step -> room registration
- **dep maps** (deps-query.py) -> subagent filter
- **Hook infrastructure** -> PreToolUse injection of signals + directives
- **MCP tooling** -> bridge server

New pieces needed:
- WS server (~200 lines, Bun/Node)
- MCP bridge server (3-4 tools: `join_plan`, `signal`, `get_updates`, `wait_for`)
- Supervisor skill (the hard part — teaching an agent to watch signals,
  evaluate overlap, negotiate with other supervisors, steer subagents)
- `/room` command to show live signal stream in terminal

---

## Open Questions

- **Supervisor skill design**: The hardest part. How to teach an agent to
  watch a signal stream, evaluate overlap severity, and translate
  coordination decisions into precise subagent directives.

- **Supervisor context management**: A supervisor watching 2+ plans with
  5-8 agents each — how to keep it focused. Overlap-set filtering helps,
  but the supervisor skill needs to be disciplined about what it tracks
  vs ignores.

- **Plan scope changes**: If a plan discovers mid-execution that it needs
  to touch a file not in its original scope, the room's overlap sets need
  updating and the other supervisor needs notification.

- **Error propagation**: If an agent fails and its step gets re-routed,
  how does the room handle the agent swap? Probably just: old agent
  disconnects, new agent connects with same scope.

- **Human override**: The human should be able to send directives too —
  a `/steer` command that pushes a directive to any agent or supervisor
  in the room.
