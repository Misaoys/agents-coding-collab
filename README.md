# Agents Coding Collab

[简体中文](README.zh-CN.md) | English

Agents Coding Collab is a Codex plugin for tool-aware, multi-model coding collaboration.
It packages a set of skills that help Codex gather fresh project evidence, route work across
multiple OpenAI-compatible models, run a write-review-revise loop, and perform a final Codex-owned
delivery review.

## What It Includes

- `agents-coding-collab`: main workflow and script documentation.
- `agents-coding-research`: local project, docs, internet, and skill freshness checks.
- `agents-coding-model-router`: model, endpoint, and API-key routing guidance.
- `agents-coding-long-edit`: context-packet guidance for large projects.
- `agents-coding-runner`: safe script execution, timeouts, artifacts, and process hygiene.
- `agents-coding-final-review`: final Codex audit before delivery.

## Highlights

- Supports OpenAI-compatible APIs.
- Supports separate writer, reviewer, reviser, and validator models.
- Supports per-reviewer model arrays, base URL arrays, and API key arrays.
- Supports quick mode for small isolated tasks.
- Supports long-edit mode for large projects and cross-file implementation work.
- Prints a Codex-terminal model trace for each writer, reviewer, reviser, and validator call.
- Requires Codex to use tools, official docs, internet search, and relevant skills for stale-prone facts.
- Keeps Codex responsible for final review instead of blindly trusting generated output.

## Repository Layout

```text
.codex-plugin/plugin.json
skills/
  agents-coding-collab/
    SKILL.md
    scripts/collab.ps1
  agents-coding-research/
  agents-coding-model-router/
  agents-coding-long-edit/
  agents-coding-runner/
  agents-coding-final-review/
```

## Install From Source

Clone this repository, then add it to a local Codex marketplace or copy the plugin folder into a
marketplace-managed plugin directory. The plugin manifest lives at `.codex-plugin/plugin.json`.

For local development, the expected plugin root is the repository root.

## Basic Script Usage

From `skills/agents-coding-collab`:

```powershell
.\scripts\collab.ps1 -Task "Write a debounce function" -Language javascript -Quick
```

Limit terminal preview size:

```powershell
.\scripts\collab.ps1 -Task "Write an add function" -Language python -Quick -ModelTraceChars 500
```

Long-edit example:

```powershell
.\scripts\collab.ps1 -Task "<context packet>" -Language typescript -ReviewerCount 4 -MaxRounds 5 -RequestTimeoutSec 0
```

Mixed reviewer routing example:

```powershell
.\scripts\collab.ps1 -Task "<context packet>" -Language typescript -ReviewerCount 4 `
  -WriterModel model-writer -WriterBaseUrl "https://writer.example" -WriterApiKey $env:WRITER_KEY `
  -ReviewerModels model-bug,model-security,model-performance,model-requirements `
  -ReviewerBaseUrls "https://review-a.example","https://review-b.example" `
  -ReviewerApiKeys $env:REVIEW_A_KEY,$env:REVIEW_B_KEY `
  -ValidatorModel model-validator -ValidatorBaseUrl "https://validator.example" -ValidatorApiKey $env:VALIDATOR_KEY
```

## API Keys

Do not commit API keys. The script reads keys from:

- `-ApiKey`
- `XD_API_KEY`
- role-specific parameters such as `-WriterApiKey`, `-ReviewerApiKey`, and `-ValidatorApiKey`
- role-specific environment variables such as `AGENTS_CODING_WRITER_API_KEY`
- `%USERPROFILE%\.codex\secrets\dual-model-collab.key` as a local private fallback

The private fallback path is intentionally outside this repository.

## Validation

Useful local checks:

```powershell
python <path-to-skill-creator>\scripts\quick_validate.py .\skills\agents-coding-collab
python <path-to-plugin-creator>\scripts\validate_plugin.py .
```

```powershell
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  ".\skills\agents-coding-collab\scripts\collab.ps1",
  [ref]$tokens,
  [ref]$errors
) | Out-Null
if ($errors.Count -gt 0) { $errors } else { "PowerShell syntax OK" }
```

## License

MIT.
