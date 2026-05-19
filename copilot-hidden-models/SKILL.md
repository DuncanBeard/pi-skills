---
name: copilot-hidden-models
description: Enumerate the live GitHub Copilot /models endpoint and add models that pi's static catalog doesn't expose (1M-context Opus, internal previews, newer Gemini, larger context windows) to ~/.pi/agent/models.json. Use when the user asks what models are actually available on Copilot, mentions hidden/internal/preview Copilot models, wants 1M context on Copilot, asks why a model isn't in /model, or wants to diff live vs static Copilot catalog.
---

# Copilot Hidden Models

Pi ships a static catalog of GitHub Copilot models in `@earendil-works/pi-ai/dist/models.generated.js`. The live `/models` endpoint on the user's actual Copilot proxy usually exposes more — 1M-context variants, internal previews, newer families, and sometimes larger context windows than what's advertised. This skill bridges the gap.

## Quick start

Run the enumeration script:

```bash
node --experimental-strip-types scripts/enumerate.ts
```

It reads `~/.pi/agent/auth.json`, extracts the live API host from the token's `proxy-ep`, queries `/models`, and prints:
- All live models with context/output/thinking/endpoints
- A `MISSING` list — models present on the live API but absent from pi's static `github-copilot` catalog
- A `DIFFERS` list — models in both, but with a different `contextWindow`

### Optional: Picker patch

There is also `scripts/patch-picker.py` which enriches the `/model` picker rows with context window and thinking level badges. This is **purely cosmetic** and does not survive container restarts (it patches files inside the container image). Skip it unless you specifically want the visual enrichment for the current session.

## Workflow

1. **Run the enumeration** (`node --experimental-strip-types scripts/enumerate.ts`) to see what's available.
2. **Pick models to add.** Note `vendor` and `supported_endpoints` — these decide `api` type:
   - `vendor: Anthropic` → `api: "anthropic-messages"`
   - `vendor: Google` (Gemini) → `api: "openai-completions"` + `compat: { supportsStore: false, supportsDeveloperRole: false, supportsReasoningEffort: false }`
   - GPT-5.x with `/responses` in endpoints → `api: "openai-responses"`
   - Older GPT (4.x, 4o) → `api: "openai-completions"`
3. **Add to `~/.pi/agent/models.json`** under the `github-copilot` provider's `models` array. Always include the Copilot impersonation headers, or you'll get `400 missing Editor-Version header`:
   ```json
   "headers": {
     "User-Agent": "GitHubCopilotChat/0.35.0",
     "Editor-Version": "vscode/1.107.0",
     "Editor-Plugin-Version": "copilot-chat/0.35.0",
     "Copilot-Integration-Id": "vscode-chat"
   }
   ```
4. **Set `thinkingLevelMap`** from the live API's `supports.reasoning_effort`:
   - Map `off: null` if thinking can't be disabled, and `xhigh: "xhigh"` if the model lists xhigh.
   - For **single-level models** (e.g. `claude-opus-4.7-xhigh` only supports `xhigh`), map ALL levels to that value so pi doesn't send an unsupported default:
     ```json
     "thinkingLevelMap": { "low": "xhigh", "medium": "xhigh", "high": "xhigh", "xhigh": "xhigh" }
     ```
5. **Use `modelOverrides`** for existing models that need context window or maxTokens corrections (no need to redefine the full model):
   ```json
   "modelOverrides": {
     "gpt-5.2": { "contextWindow": 400000, "maxTokens": 128000 }
   }
   ```
6. **Save and `/model`** — no restart needed; `models.json` reloads on each picker open.
7. **Ask the user if they want to test** each new model with `pi --model github-copilot/<id> --no-tools --no-session -p "Say hello"` to confirm they respond.

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
- The picker patch (`scripts/patch-picker.py`) is cosmetic only and does NOT survive container restarts — it modifies files inside the ephemeral container filesystem. The models work fine without it.
