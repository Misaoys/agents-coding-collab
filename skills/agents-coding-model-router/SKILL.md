---
name: agents-coding-model-router
description: Model and gateway routing companion for Agents Coding Collab. Use when selecting writer, reviewer, reviser, and validator models; configuring multiple OpenAI-compatible base URLs and API keys; or mixing multiple reviewer models/providers in one run.
---

# Agents Coding Model Router

Use this to decide which model, endpoint, and API key each role should use.

## Roles

- `writer`: drafts the first implementation.
- `reviewer`: parallel review dimensions. Can use one model for all dimensions or separate models per dimension.
- `reviser`: rewrites the draft from the merged review. Defaults to writer.
- `validator`: checks the revised code against review findings. Defaults to reviewer.

## Parameters

The runner supports global defaults:

```powershell
-BaseUrl "https://inference.xd.ci" -ApiKey $env:XD_API_KEY
```

It also supports role-specific routing:

```powershell
-WriterModel glm-5.2 -WriterBaseUrl "https://gateway-a.example" -WriterApiKey $env:WRITER_KEY
-ReviserModel glm-5.2 -ReviserBaseUrl "https://gateway-a.example" -ReviserApiKey $env:REVISER_KEY
-ReviewerModel kimi-k2.7-code-highspeed -ReviewerBaseUrl "https://gateway-b.example" -ReviewerApiKey $env:REVIEWER_KEY
-ValidatorModel kimi-k2.7-code-highspeed -ValidatorBaseUrl "https://gateway-b.example" -ValidatorApiKey $env:VALIDATOR_KEY
```

For mixed reviewer models/providers, pass arrays. Values are mapped to `bug`, `security`,
`performance`, and `requirements` in that order; if a list is shorter, the last item is reused:

```powershell
-ReviewerModels model-a,model-b,model-c,model-d `
-ReviewerBaseUrls "https://gateway-a.example","https://gateway-b.example" `
-ReviewerApiKeys $env:KEY_A,$env:KEY_B
```

## Environment Variables

The script also reads:

- `XD_API_KEY` for global fallback.
- `AGENTS_CODING_WRITER_BASE_URL`, `AGENTS_CODING_WRITER_API_KEY`.
- `AGENTS_CODING_REVIEWER_BASE_URL`, `AGENTS_CODING_REVIEWER_API_KEY`.
- `AGENTS_CODING_REVISER_BASE_URL`, `AGENTS_CODING_REVISER_API_KEY`.
- `AGENTS_CODING_VALIDATOR_BASE_URL`, `AGENTS_CODING_VALIDATOR_API_KEY`.

Do not hardcode secrets in plugin files, task packets, or final answers.
