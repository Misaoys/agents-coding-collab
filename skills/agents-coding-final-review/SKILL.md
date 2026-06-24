---
name: agents-coding-final-review
description: Final Codex review companion for Agents Coding Collab. Use after multi-agent coding artifacts are produced to personally inspect requirements, stability, project rules, freshness evidence, tests, and upgrade opportunities before final delivery.
---

# Agents Coding Final Review

Use this after the model workflow finishes and before final delivery.

## Inputs

Review:

- Original user request and follow-up constraints.
- Latest `summary-*.json`.
- `2-review-*.md`.
- Latest `3-final-roundN-*.md`.
- Latest `4-validation-roundN-*.md`.
- Freshness evidence and source links, if any.
- Project rules and nearby code patterns.

## Checklist

Check:

- Requirement omissions or semantic drift.
- Stability risks, edge cases, error handling, resource cleanup, and concurrency hazards.
- Whether generated code follows project writing rules and style.
- Current API/library usage against gathered evidence.
- Missing or weak tests/verification.
- Useful upgrades that are in scope and not bloated.

If concrete issues are fixable and the user asked for implementation, apply the smallest safe fix,
rerun relevant validation, then review again. If issues remain or require product judgment, report
them clearly before calling the work done.
