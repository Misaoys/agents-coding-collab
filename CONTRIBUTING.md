# Contributing

Contributions are welcome.

## Development Rules

- Keep plugin skills small and focused.
- Prefer official documentation and primary sources for current API behavior.
- Do not add hardcoded secrets, tokens, or local machine paths beyond documented examples.
- Validate the plugin before publishing changes.
- Validate `scripts/collab.ps1` with the PowerShell parser after script edits.

## Suggested Checks

```powershell
python <path-to-plugin-creator>\scripts\validate_plugin.py .
```
