---
name: copilot-hidden-models
description: Enumerate the live GitHub Copilot /models endpoint and add models that pi's static catalog doesn't expose (1M-context Opus, internal previews, newer Gemini, larger context windows) to ~/.pi/agent/models.json. Also patches pi's model picker to show context window and thinking levels per row. Use when the user asks what models are actually available on Copilot, mentions hidden/internal/preview Copilot models, wants 1M context on Copilot, asks why a model isn't in /model, wants to diff live vs static Copilot catalog, or after running `pi update --self` (re-apply the picker patch).
---

# Copilot Hidden Models

Pi ships a static catalog of GitHub Copilot models in `@earendil-works/pi-ai/dist/models.generated.js`. The live `/models` endpoint on the user's actual Copilot proxy usually exposes more — 1M-context variants, internal previews, newer families, and sometimes larger context windows than what's advertised. This skill bridges the gap.

## Quick start

Run the enumeration script:

```bash
python scripts/enumerate.py
```

It reads `~/.pi/agent/auth.json`, extracts the live API host from the token's `proxy-ep`, queries `/models`, and prints:
- All live models with context/output/thinking/endpoints
- A `MISSING` list — models present on the live API but absent from pi's static `github-copilot` catalog
- A `DIFFERS` list — models in both, but with a different `contextWindow`

To patch the interactive model picker so each row shows context window + top thinking level (and the bottom hint shows full thinking levels + vision):

```bash
python scripts/patch-picker.py
```

Idempotent and writes a `.bak` next to the patched file. Re-run after `pi update --self` since updates overwrite bundled files.

## Workflow

1. **Run the script** to see what's available.
2. **Pick a model to add.** Note its `vendor` and `supported_endpoints` — these decide `api` type:
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
4. **Set `thinkingLevelMap`** from the live API's `supports.reasoning_effort`. Map `off: null` if thinking can't be disabled, and `xhigh: "xhigh"` if the model lists xhigh.
5. **Save and `/model`** — no restart needed; `models.json` reloads on each picker open.

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
- Internal/preview models can disappear or change shape without notice. If a previously-working model starts 404ing, re-run the script.
- `model_picker_enabled: false` in the live response means GitHub doesn't surface the model in its own UI, but it's usually still usable via direct API call.
