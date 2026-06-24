---
name: agents-coding-research
description: "Research and freshness-gathering companion for Agents Coding Collab. Use before model-assisted coding when current external facts may matter: SDK/API docs, framework versions, cloud services, security guidance, package behavior, browser/OS changes, release notes, or when project-local rules and skills must be loaded before implementation."
---

# Agents Coding Research

Use this before `agents-coding-collab` when the implementation may depend on facts that can become stale.

## Workflow

1. Read project-local truth first: `AGENTS.md`, README/docs, package manifests, lockfiles, config, tests, release scripts, and nearby code.
2. Load relevant Codex skills when they clearly match the target stack, platform, file type, or workflow.
3. Use official documentation or primary sources for SDK/API/framework behavior. Use internet search when the current source URL or current guidance is uncertain.
4. Build a short `Freshness Evidence` block for the model context packet:

```text
Freshness Evidence:
- Source: <official doc URL or local file path>
  Fact: <short verified fact>
  Date checked: <current date>
```

## Rules

- Prefer official docs, primary specs, source repositories, or release notes over blog posts.
- For OpenAI product/API questions, use the OpenAI docs skill or official OpenAI docs.
- Do not let the external models invent current facts. If a fact cannot be verified, say so in the context packet and ask reviewers to flag the risk.
- Keep the evidence compact; include only facts that affect implementation choices.
