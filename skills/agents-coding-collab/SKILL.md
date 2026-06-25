---
name: agents-coding-collab
description: Plugin entrypoint for tool-aware multi-agent coding over OpenAI-compatible APIs. Use when the user wants model collaboration, parallel review, write-review-revise workflows, multiple models or gateways, large project implementation, quick vs long edit selection, internet/docs/skill freshness checks, and a Codex-owned final review before delivery.
---

# Agents Coding Collab

## Overview

This is the main entrypoint for the Agents Coding Collab plugin. It coordinates a
write-review-revise workflow over one or more OpenAI-compatible API gateways:

- A writer model drafts the implementation.
- One to four reviewer roles inspect bug/edge cases, security, performance, and requirements.
- A reviser model updates the draft from the merged review.
- A validator model checks PASS/FAIL and residual issues.
- The current Codex agent then performs the final delivery review.

The script can run with the default GLM/Kimi pair, but it is not limited to two models.
Each role can use its own model, base URL, and API key. Reviewer roles can also be split
across multiple models/providers in a single run.

Important limitation: the external chat models do not receive Codex tools directly.
Codex must use tools, internet search, official docs, repo inspection, and relevant skills
before running the script, then put verified evidence into the task/context packet. Treat
the external models as code writers/reviewers that work from the context Codex supplies.

## Built-In Skills

Use the plugin skills as a small suite:

- `$agents-coding-research`: gather local/project/current external evidence before coding.
- `$agents-coding-model-router`: choose writer/reviewer/reviser/validator models, endpoints, and API keys.
- `$agents-coding-long-edit`: build a compact context packet for large projects.
- `$agents-coding-runner`: run `scripts/collab.ps1`, wait properly, and manage artifacts/process hygiene.
- `$agents-coding-final-review`: make Codex personally audit the generated output before delivery.

Recommended order for non-trivial work:

1. Use `$agents-coding-research` when current facts or project rules matter.
2. Use `$agents-coding-model-router` when more than one provider/model/key may be used.
3. Choose quick or long edit. Use `$agents-coding-long-edit` for large or risky work.
4. Use `$agents-coding-runner` to run the script and collect artifacts.
5. Use `$agents-coding-final-review` before applying or delivering the result.

## Architecture

```text
Step 1 [serial]   Writer model drafts code
Step 2 [parallel] Reviewer roles inspect bug/edge, security, performance, requirements
Step 3 [script]   Merge reviews into one prioritized list
Step 4 [serial]   Reviser model updates from the merged review
Step 5 [serial]   Validator model checks PASS/FAIL and residual issues
Step 6 [Codex]    Current Codex agent reviews artifacts, project rules, gaps, stability, and upgrades
```

Default models are `glm-5.2` for writing/revision and `kimi-k2.7-code-highspeed` for
review/validation. Parallel HTTP uses .NET `HttpClient` and waits for all reviewer jobs.

## Prerequisites

- At least one OpenAI-compatible API gateway URL. Default: `https://inference.xd.ci`.
- API key from `-ApiKey`, `XD_API_KEY`, a role-specific API key parameter/env var, or
  `%USERPROFILE%\.codex\secrets\dual-model-collab.key`.
- One or more available model names. You can route all roles to one model, use the default
  writer/reviewer pair, or assign separate models and gateways per role.

## Mode Selection

Before running the script, Codex must classify the request as either `quick` or `long edit`.
Make this choice from product intent, project size, risk, touched files, and required
verification. If unsure, choose `long edit`.

Use `quick` for isolated, low-risk work that likely fits in one small file or one standalone
function:

```powershell
.\scripts\collab.ps1 -Task "..." -Language python -Quick
```

Use `long edit` for large projects, cross-file changes, repo-specific behavior, UI flows,
release/update paths, migrations, architecture changes, security-sensitive work, or when the
user says the task is a large engineering/project implementation.

For `long edit`, Codex must inspect the project before calling the model. Build a compact
context packet with:

- Goal and acceptance criteria in product terms.
- Relevant project rules: `AGENTS.md`, README/docs, package scripts, lint/test commands.
- Target files/modules and nearby implementation patterns.
- Constraints: compatibility, style, performance, security, migration, release behavior.
- Required verification and known risk areas.
- Freshness evidence from tools/search/docs/skills when current facts matter.
- Instruction to keep changes scoped and avoid unrelated refactors.

Recommended long edit command shape:

```powershell
.\scripts\collab.ps1 -Task "<context packet>" -Language <stack> -ReviewerCount 4 -MaxRounds 5 -RequestTimeoutSec 0
```

For long edit runs from Codex tools, set the outer tool timeout high enough for the full
model workflow and wait for completion. After artifacts are produced, Codex applies or
adapts the result into the repo with normal engineering judgment, runs relevant checks, and
then performs the required Codex final review.

## Tool And Freshness Policy

Before giving work to the collaboration script, Codex must decide whether current external
knowledge is needed. Use tools, internet search, official documentation, repo search, and
relevant skills proactively when the task depends on information that may be stale.

Always gather fresh evidence for:

- Framework, library, SDK, API, CLI, cloud platform, browser, OS, package-manager, or build
  tool behavior that may have changed.
- Security, privacy, auth, deployment, pricing, rate-limit, compatibility, migration, or
  release-process guidance.
- Third-party service integration, product-specific docs, model/API usage, or generated code
  that must match current documentation.
- Large project work where project-local rules, package scripts, tests, conventions, or
  architecture must guide implementation.

Use these sources in order:

- Local project truth first: `AGENTS.md`, README/docs, package manifests, lockfiles, config,
  nearby code, tests, release scripts, and existing patterns.
- Relevant Codex skills next. If another skill clearly applies, load and follow it before
  building the context packet.
- Official/primary documentation next. For technical questions, prefer official docs,
  primary specs, package docs, release notes, or source repositories.
- Internet search when the answer may be time-sensitive or official docs must be located or
  confirmed. Include source links or a short source summary in the context packet.

Do not ask the external writer/reviewer models to rely on memory for current facts. Put a
`Freshness Evidence` section in long edit context packets when external facts matter:

```text
Freshness Evidence:
- Source: <official doc URL or local file path>
  Fact: <short verified fact>
  Date checked: <today's date>
```

If Codex cannot verify a current fact, state the uncertainty in the context packet and ask
the reviewers to flag risk instead of inventing details. If a model output uses unsupported
or suspicious current-fact claims, Codex must verify them before applying code.

## Model Routing

The script supports global defaults, role-specific routing, and per-reviewer routing.

Global fallback:

```powershell
.\scripts\collab.ps1 -Task "..." -BaseUrl "https://inference.xd.ci" -ApiKey $env:XD_API_KEY
```

Role-specific routing:

```powershell
.\scripts\collab.ps1 -Task "<context packet>" -Language typescript `
  -WriterModel glm-5.2 -WriterBaseUrl "https://gateway-a.example" -WriterApiKey $env:WRITER_KEY `
  -ReviserModel glm-5.2 -ReviserBaseUrl "https://gateway-a.example" -ReviserApiKey $env:REVISER_KEY `
  -ReviewerModel kimi-k2.7-code-highspeed -ReviewerBaseUrl "https://gateway-b.example" -ReviewerApiKey $env:REVIEWER_KEY `
  -ValidatorModel kimi-k2.7-code-highspeed -ValidatorBaseUrl "https://gateway-b.example" -ValidatorApiKey $env:VALIDATOR_KEY
```

Mixed reviewer routing:

```powershell
.\scripts\collab.ps1 -Task "<context packet>" -Language typescript -ReviewerCount 4 `
  -ReviewerModels model-bug,model-security,model-performance,model-requirements `
  -ReviewerBaseUrls "https://gateway-a.example","https://gateway-b.example" `
  -ReviewerApiKeys $env:KEY_A,$env:KEY_B
```

Reviewer arrays map to `bug`, `security`, `performance`, and `requirements` in that order.
When an array is shorter than the reviewer count, the last value is reused. If validator
settings are omitted, the validator inherits the last reviewer model/base URL/API key when
reviewer arrays are present, otherwise it inherits the reviewer default.

Do not hardcode secrets in plugin files, task packets, reports, or final answers.

## Codex Final Review

After `scripts/collab.ps1` finishes, do not immediately deliver the generated code. The
current Codex agent must personally review the artifacts. This is not another API/model
call inside the script.

Review at least:

- The original user request and follow-up constraints.
- The latest `summary-*.json`.
- `2-review-*.md`.
- The latest `3-final-roundN-*.md` and `4-validation-roundN-*.md`.
- Project rules and conventions for the target files, especially `AGENTS.md`, local docs,
  package scripts, lint/test config, and nearby code patterns.
- Freshness evidence and cited sources used in the context packet, if any.

Check and report:

- Requirement omissions or semantic drift.
- Stability risks, edge cases, error handling, resource cleanup, and concurrency hazards.
- Whether the result follows project writing rules and existing style.
- Missing or weak tests/verification.
- Useful upgrades that are clearly in scope, without bloating the implementation.
- Any generated API/library usage that appears stale, undocumented, or unsupported by the
  gathered sources.

If the Codex review finds concrete fixable issues and the user asked for implementation,
apply the smallest safe fix, rerun relevant validation, then review again. If issues remain
or require product judgment, report them clearly before calling the work done.

## Runtime Waiting Policy

When running `scripts/collab.ps1` from Codex tools, set the outer shell/tool timeout
generously. Use at least 2 hours for normal mode and longer for `long edit`. Do not
interrupt an in-progress run unless the user asks to stop or the script is clearly stuck
beyond the configured request timeout.

## Quick Start

```powershell
.\scripts\collab.ps1 -Task "your development request" -Language python
```

Outputs:

- `1-draft-*.md`: initial code.
- `2-review-*.md`: merged multi-dimension review.
- `3-final-roundN-*.md`: revised code for each round.
- `4-validation-roundN-*.md`: PASS/FAIL validation.
- `summary-*.json`: run report.

By default, the script also prints a `MODEL START` / `MODEL END` trace to the Codex terminal
for every writer, reviewer, reviser, and validator call. The trace shows role, model, action,
base URL, token counts, artifact file, and a bounded output preview. API keys are never printed.
Use `-ModelTraceDemo` to print a simulated trace without calling any model API.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Task` | required | Development task or long edit context packet |
| `-Language` | `python` | Target stack: `python`, `javascript`, `go`, `java`, etc. |
| `-BaseUrl` | `https://inference.xd.ci` | Global OpenAI-compatible API gateway URL |
| `-ApiKey` | env/file | Reads `XD_API_KEY`, then `%USERPROFILE%\.codex\secrets\dual-model-collab.key` |
| `-WriterModel` | `glm-5.2` | Model for the first draft |
| `-WriterBaseUrl` | `-BaseUrl` | Writer gateway URL |
| `-WriterApiKey` | writer env/global | Writer API key |
| `-ReviewerModel` | `kimi-k2.7-code-highspeed` | Default model for all reviewer roles |
| `-ReviewerModels` | empty | Per-reviewer model array |
| `-ReviewerBaseUrl` | `-BaseUrl` | Default reviewer gateway URL |
| `-ReviewerBaseUrls` | empty | Per-reviewer gateway array |
| `-ReviewerApiKey` | reviewer env/global | Default reviewer API key |
| `-ReviewerApiKeys` | empty | Per-reviewer API key array |
| `-ReviserModel` | `-WriterModel` | Model for revising from merged review |
| `-ReviserBaseUrl` | writer URL | Reviser gateway URL |
| `-ReviserApiKey` | writer key | Reviser API key |
| `-ValidatorModel` | last reviewer/default reviewer | Model for PASS/FAIL validation |
| `-ValidatorBaseUrl` | last reviewer/default reviewer URL | Validator gateway URL |
| `-ValidatorApiKey` | last reviewer/default reviewer key | Validator API key |
| `-ReviewerCount` | `4` | Parallel review dimensions, 1-4 |
| `-OutDir` | current dir | Output directory for artifact files |
| `-MaxRounds` | `3` | Max revise-validate iterations on FAIL, 1-5 |
| `-RequestTimeoutSec` | `3600` | Per API-call wait time; pass `0` to disable local request timeout |
| `-ModelTraceChars` | `1200` | Max terminal preview chars per model output; `0` disables content previews |
| `-NoModelTrace` | switch | Disable terminal model dispatch trace |
| `-ModelTraceDemo` | switch | Print a simulated terminal trace and exit without API calls |
| `-Quick` | switch | Quick mode: 1 reviewer and 1 revise-validate round |

## Environment Variables

- `XD_API_KEY`
- `AGENTS_CODING_WRITER_BASE_URL`, `AGENTS_CODING_WRITER_API_KEY`
- `AGENTS_CODING_REVIEWER_BASE_URL`, `AGENTS_CODING_REVIEWER_API_KEY`
- `AGENTS_CODING_REVISER_BASE_URL`, `AGENTS_CODING_REVISER_API_KEY`
- `AGENTS_CODING_VALIDATOR_BASE_URL`, `AGENTS_CODING_VALIDATOR_API_KEY`

## Examples

```powershell
# Quick isolated task
.\scripts\collab.ps1 -Task "Write a debounce function" -Language javascript -Quick

# Quick task with shorter Codex terminal previews
.\scripts\collab.ps1 -Task "Write an add function" -Language python -Quick -ModelTraceChars 500

# Terminal-only trace demo, no model API call
.\scripts\collab.ps1 -Task "trace demo" -ModelTraceDemo -ModelTraceChars 300

# Long edit / large engineering task
.\scripts\collab.ps1 -Task "<context packet>" -Language typescript -ReviewerCount 4 -MaxRounds 5 -RequestTimeoutSec 0

# Use one custom gateway and swap models
.\scripts\collab.ps1 -Task "..." -BaseUrl "https://gateway.example" -ApiKey $env:API_KEY `
  -WriterModel model-writer -ReviewerModel model-reviewer

# Mix reviewer models/providers
.\scripts\collab.ps1 -Task "<context packet>" -Language typescript -ReviewerCount 4 `
  -WriterModel model-writer -WriterBaseUrl "https://writer.example" -WriterApiKey $env:WRITER_KEY `
  -ReviewerModels model-bug,model-security,model-performance,model-requirements `
  -ReviewerBaseUrls "https://review-a.example","https://review-b.example" `
  -ReviewerApiKeys $env:REVIEW_A_KEY,$env:REVIEW_B_KEY `
  -ValidatorModel model-validator -ValidatorBaseUrl "https://validator.example" -ValidatorApiKey $env:VALIDATOR_KEY
```

## Troubleshooting

- Empty content or `finish_reason: length`: model exhausted tokens on reasoning. Increase
  token settings in the script if needed.
- Long model writing gets interrupted: default request timeout is 3600 seconds per API call.
  Increase with `-RequestTimeoutSec 7200`, or pass `-RequestTimeoutSec 0`.
- `invalid temperature`: some reasoning models only accept `temperature=1`; serial calls
  auto-retry with `temperature=1`, and parallel calls default to `temperature=1`.
- Request body parse errors: JSON must be UTF-8 without BOM. The script uses
  `UTF8Encoding($false)` for temp files.
- Reviewer content empty but reasoning present: the script falls back to `reasoning_content`.
- Parallel review all fail: check network/proxy and gateway routing. The script uses .NET
  `HttpClient` instead of fragile `Start-Process curl.exe` argument passing.
- Validator key missing with mixed reviewers: pass `-ValidatorApiKey`, or ensure
  `-ReviewerApiKeys` has at least one value so the validator can inherit the last reviewer key.
- Terminal output too noisy: lower `-ModelTraceChars`, pass `-ModelTraceChars 0` to keep only
  role/model/token trace, or pass `-NoModelTrace` to disable model trace output.

## Script

`scripts/collab.ps1` is self-contained PowerShell. It is compatible with Windows PowerShell
5.1+ and PowerShell 7. No SDK dependencies are required.
