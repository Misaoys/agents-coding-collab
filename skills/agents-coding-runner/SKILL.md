---
name: agents-coding-runner
description: Execution companion for Agents Coding Collab. Use when running scripts/collab.ps1, choosing quick vs long-edit command flags, setting long timeouts, handling output artifacts, and avoiding leftover background processes.
---

# Agents Coding Runner

Use this to run the collaboration script safely.

## Quick Mode

Use for isolated low-risk tasks:

```powershell
.\scripts\collab.ps1 -Task "..." -Language <stack> -Quick
```

## Long Edit Mode

Use for project-scale work:

```powershell
.\scripts\collab.ps1 -Task "<context packet>" -Language <stack> -ReviewerCount 4 -MaxRounds 5 -RequestTimeoutSec 0
```

## Artifact Handling

Read these after completion:

- `summary-*.json`
- `2-review-*.md`
- latest `3-final-roundN-*.md`
- latest `4-validation-roundN-*.md`

## Process Hygiene

- Give the shell/tool timeout enough time for the full model workflow.
- Do not interrupt active model generation unless the user asks or the run is clearly stuck beyond configured timeout.
- Do not leave local servers, Node.js processes, or helper processes running unless explicitly needed and reported.
- If a command starts a process for validation, close only the process started by the current agent.
