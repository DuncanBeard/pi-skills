---
name: copilot-hidden-models
description: Enumerate the live GitHub Copilot /models endpoint and add models that pi's static catalog doesn't expose (1M-context Opus, internal previews, newer Gemini, larger context windows) to ~/.pi/agent/models.json. Use when the user asks what models are actually available on Copilot, mentions hidden/internal/preview Copilot models, wants 1M context on Copilot, asks why a model isn't in /model, or wants to diff live vs static Copilot catalog.
---

# Copilot Hidden Models

Pi ships a static catalog of GitHub Copilot models in `@earendil-works/pi-ai/dist/models.generated.js`. The live `/models` endpoint on the user's actual Copilot proxy usually exposes more — 1M-context variants, internal previews, newer families, and sometimes larger context windows than what's advertised. This skill bridges the gap.

## IMPORTANT: Execute immediately — do NOT prompt the user for choices

When this skill is activated, execute the entire workflow below autonomously in sequence. Do not present menus, options, or ask "what would you like to do?" — just run every step.

## Step 1: Enumerate live models

Run this immediately:

```bash
node --experimental-strip-types scripts/enumerate.ts
```

This queries the live Copilot `/models` endpoint and prints all available models with context/output/thinking/endpoints.

## Step 2: Diff against pi's static catalog

Read pi's static catalog from the `models.generated.js` file (find it under `@earendil-works/pi-ai/dist/`) and compare the `github-copilot` provider's models against what the live API returned. Identify:
- **MISSING**: models in live API but not in pi's static catalog
- **DIFFERS**: models in both but with different `contextWindow` or `maxTokens`

## Step 3: Read existing models.json

Check `~/.pi/agent/models.json` — if it exists, preserve any models/overrides already there.

## Step 4: Write the updated models.json

Add **all** missing non-hidden models and apply **all** context/maxTokens overrides. Use these rules to determine `api` type:
- `vendor: Anthropic` → `api: "anthropic-messages"`
- `vendor: Google` (Gemini) → `api: "openai-completions"` + `compat: { supportsStore: false, supportsDeveloperRole: false, supportsReasoningEffort: false }`
- GPT-5.x with `/responses` in endpoints → `api: "openai-responses"`
- Older GPT (4.x, 4o) → `api: "openai-completions"`

The file **must** have this structure:
```json
{
  "providers": {
    "github-copilot": {
      "models": [ ... ],
      "modelOverrides": { ... }
    }
  }
}
```

Every new model entry **must** include the Copilot impersonation headers:
```json
"headers": {
  "User-Agent": "GitHubCopilotChat/0.35.0",
  "Editor-Version": "vscode/1.107.0",
  "Editor-Plugin-Version": "copilot-chat/0.35.0",
  "Copilot-Integration-Id": "vscode-chat"
}
```

Set `thinkingLevelMap` from the live API's `supports.reasoning_effort`:
- Map `off: null` if thinking can't be disabled, and `xhigh: "xhigh"` if the model lists xhigh.
- For **single-level models** (e.g. only supports `xhigh`), map ALL levels to that value:
  ```json
  "thinkingLevelMap": { "low": "xhigh", "medium": "xhigh", "high": "xhigh", "xhigh": "xhigh" }
  ```

Use `modelOverrides` for existing models that only need context/maxTokens corrections.

## Step 5: Report what you did

After writing, summarize: new models added, overrides applied, and offer to test with:
```bash
pi --model github-copilot/<id> --no-tools --no-session -p "Say hello"
```

## Checklist for each new model entry

- [ ] `id` matches the live API exactly (e.g. `claude-opus-4.7-1m-internal`)
- [ ] `api` matches vendor/endpoint rules above
- [ ] `headers` block included (4 Copilot headers)
- [ ] `contextWindow` and `maxTokens` from live `limits`
- [ ] `reasoning: true` if `supports.reasoning_effort` has any entries
- [ ] `thinkingLevelMap` reflects which levels are actually supported
- [ ] `input: ["text", "image"]` if `supports.vision: true`
- [ ] `cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }` (Copilot subscription)

## Notes

- The base URL is derived dynamically from the Copilot token (`proxy-ep` field, with `proxy.` rewritten to `api.`). Enterprise tokens resolve to `api.enterprise.githubcopilot.com`; individual tokens to `api.individual.githubcopilot.com`. The OAuth `modifyModels` hook applies the right baseUrl automatically — do NOT hardcode `baseUrl` per model.
- Internal/preview models can disappear or change shape without notice. If a previously-working model starts 404ing, re-run the enumeration.
- `model_picker_enabled: false` in the live response means GitHub doesn't surface the model in its own UI, but it's usually still usable via direct API call.
- `models.json` persists in `~/.pi/agent/` (bind-mounted from host) and survives container restarts. No image rebuild needed.
- There is also `scripts/patch-picker.py` for cosmetic picker badges, but it's optional and doesn't survive container restarts.
