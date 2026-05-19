#!/usr/bin/env python3
"""
Enumerate live GitHub Copilot models and diff against pi's static catalog.

Reads ~/.pi/agent/auth.json for the Copilot OAuth token, extracts the live API
host from the token's proxy-ep field, queries GET /models, and prints:
  - Full live model table (id, context, max-out, thinking, endpoints, vendor)
  - MISSING: models on the live API but not in pi's static github-copilot catalog
  - DIFFERS: models in both, where contextWindow disagrees
"""

import json
import os
import re
import ssl
import subprocess
import sys
import urllib.request
from pathlib import Path

AUTH_PATH = Path.home() / ".pi" / "agent" / "auth.json"

COPILOT_HEADERS = {
    "User-Agent": "GitHubCopilotChat/0.35.0",
    "Editor-Version": "vscode/1.107.0",
    "Editor-Plugin-Version": "copilot-chat/0.35.0",
    "Copilot-Integration-Id": "vscode-chat",
    "Accept": "application/json",
}


def load_token() -> str:
    if not AUTH_PATH.exists():
        sys.exit(f"auth.json not found at {AUTH_PATH} — run /login in pi first")
    auth = json.loads(AUTH_PATH.read_text())
    copilot = auth.get("github-copilot")
    if not copilot or not copilot.get("access"):
        sys.exit("no github-copilot OAuth token in auth.json — run /login -> GitHub Copilot")
    return copilot["access"]


def base_url_from_token(token: str) -> str:
    m = re.search(r"proxy-ep=([^;]+)", token)
    if not m:
        return "https://api.individual.githubcopilot.com"
    return f"https://{m.group(1).replace('proxy.', 'api.', 1)}"


def fetch_live_models(base_url: str, token: str) -> list[dict]:
    headers = {**COPILOT_HEADERS, "Authorization": f"Bearer {token}"}
    req = urllib.request.Request(f"{base_url}/models", headers=headers)
    with urllib.request.urlopen(req, context=ssl.create_default_context(), timeout=15) as resp:
        return json.loads(resp.read()).get("data", [])


def fetch_static_catalog() -> dict[str, dict] | None:
    """Use node to load the static catalog. Returns None if not resolvable."""
    # Try to find models.generated.js by walking common global install locations.
    candidate_roots = [
        Path(os.environ.get("ProgramData", "C:/ProgramData")) / "global-npm" / "node_modules",
        Path(os.environ.get("APPDATA", "")) / "npm" / "node_modules" if os.environ.get("APPDATA") else None,
        Path.home() / ".npm-global" / "lib" / "node_modules",
        Path("/usr/local/lib/node_modules"),
        Path("/opt/homebrew/lib/node_modules"),
    ]
    rel_paths = [
        Path("@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/models.generated.js"),
        Path("@earendil-works/pi-ai/dist/models.generated.js"),
        Path("@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/models.generated.js"),
        Path("@mariozechner/pi-ai/dist/models.generated.js"),
    ]
    models_js = None
    for root in candidate_roots:
        if not root:
            continue
        for rel in rel_paths:
            p = root / rel
            if p.exists():
                models_js = p
                break
        if models_js:
            break
    if not models_js:
        return None

    script = (
        f"const m = require({json.dumps(str(models_js))});"
        "process.stdout.write(JSON.stringify(m.MODELS['github-copilot'] || {}));"
    )
    for cmd in (["node", "-e", script], ["node.exe", "-e", script]):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=True)
            return json.loads(out.stdout)
        except (FileNotFoundError, subprocess.CalledProcessError, json.JSONDecodeError):
            continue
    return None


def fmt_n(n) -> str:
    if not isinstance(n, int):
        return "?"
    if n >= 1_000_000:
        return f"{n / 1_000_000:g}M"
    if n >= 1_000:
        return f"{n / 1_000:g}K"
    return str(n)


def summarize(model: dict) -> dict:
    caps = model.get("capabilities", {})
    limits = caps.get("limits", {})
    supports = caps.get("supports", {})
    return {
        "id": model["id"],
        "vendor": model.get("vendor", "?"),
        "ctx": limits.get("max_context_window_tokens"),
        "out": limits.get("max_output_tokens"),
        "thinking": supports.get("reasoning_effort", []),
        "vision": supports.get("vision", False),
        "endpoints": model.get("supported_endpoints", []),
        "picker": model.get("model_picker_enabled", True),
    }


def main() -> int:
    token = load_token()
    base_url = base_url_from_token(token)
    print(f"# Live API: {base_url}\n")

    live_raw = fetch_live_models(base_url, token)
    live = {m["id"]: summarize(m) for m in live_raw}

    # Full table
    print(f"{'model':<38} {'vendor':<12} {'ctx':<7} {'out':<7} {'thinking':<22} {'endpoints'}")
    print("-" * 130)
    for s in sorted(live.values(), key=lambda x: x["id"]):
        flag = "" if s["picker"] else " (hidden)"
        thinking = ",".join(s["thinking"]) if s["thinking"] else "no"
        eps = ", ".join(s["endpoints"]) or "-"
        print(
            f"{s['id'] + flag:<38} {s['vendor']:<12} {fmt_n(s['ctx']):<7} "
            f"{fmt_n(s['out']):<7} {thinking:<22} {eps}"
        )

    # Diff against static catalog
    static = fetch_static_catalog()
    if static is None:
        print("\n(could not load pi's static catalog via node - skipping diff)")
        return 0

    static_ids = set(static.keys())
    live_ids = set(live.keys())
    missing = sorted(live_ids - static_ids)
    differs = []
    for mid in sorted(live_ids & static_ids):
        live_ctx = live[mid]["ctx"]
        static_ctx = static[mid].get("contextWindow")
        if live_ctx and static_ctx and live_ctx != static_ctx:
            differs.append((mid, static_ctx, live_ctx))

    print(f"\n## MISSING from pi catalog ({len(missing)})")
    for mid in missing:
        s = live[mid]
        thinking = ",".join(s["thinking"]) if s["thinking"] else "no"
        print(f"  {mid:<38} {s['vendor']:<12} ctx={fmt_n(s['ctx']):<7} thinking={thinking}")

    print(f"\n## DIFFERS context window ({len(differs)})")
    for mid, static_ctx, live_ctx in differs:
        print(f"  {mid:<38} static={fmt_n(static_ctx):<7} live={fmt_n(live_ctx)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
