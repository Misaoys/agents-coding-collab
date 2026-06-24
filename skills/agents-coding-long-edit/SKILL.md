---
name: agents-coding-long-edit
description: Long-edit planning companion for Agents Coding Collab. Use for large projects, cross-file changes, architecture work, migrations, UI flows, release/update paths, security-sensitive work, or any task where Codex should inspect the repo and create a compact context packet before running multi-agent coding.
---

# Agents Coding Long Edit

Use this when the task is more than a small isolated change.

## Context Packet

Before calling the model workflow, inspect the repo and write a compact packet with:

- Goal and acceptance criteria in product terms.
- Relevant project rules: `AGENTS.md`, README/docs, package scripts, lint/test commands.
- Target files/modules and nearby implementation patterns.
- Constraints: compatibility, style, performance, security, migration, release behavior.
- Freshness evidence from tools/search/docs/skills when current facts matter.
- Required validation and known risk areas.
- Instruction to keep changes scoped and avoid unrelated refactors.

## Recommended Command

```powershell
.\scripts\collab.ps1 -Task "<context packet>" -Language <stack> -ReviewerCount 4 -MaxRounds 5 -RequestTimeoutSec 0
```

Set the outer Codex tool timeout long enough to let the script finish. After artifacts are produced,
Codex applies or adapts the output into the repo, runs focused validation, and then uses
`agents-coding-final-review`.
