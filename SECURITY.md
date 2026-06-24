# Security Policy

## Reporting Issues

Please report security issues privately to the maintainer before publishing exploit details.

## Secret Handling

Never commit API keys, bearer tokens, `.env` files, or local private key files.
Use environment variables or local secret files outside the repository.

The script may read `%USERPROFILE%\.codex\secrets\dual-model-collab.key` as a local fallback.
That file must remain private and must not be copied into this repository.
