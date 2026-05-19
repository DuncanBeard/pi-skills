#!/usr/bin/env node
// @ts-check
/**
 * Enumerate live GitHub Copilot models and diff against pi's static catalog.
 *
 * Reads ~/.pi/agent/auth.json for the Copilot OAuth token, extracts the live API
 * host from the token's proxy-ep field, queries GET /models, and prints:
 *   - Full live model table (id, context, max-out, thinking, endpoints, vendor)
 *   - MISSING: models on the live API but not in pi's static github-copilot catalog
 *   - DIFFERS: models in both, where contextWindow disagrees
 */

import fs from "node:fs";
import https from "node:https";
import path from "node:path";

interface LiveModel {
  id: string;
  vendor?: string;
  capabilities?: {
    limits?: { max_context_window_tokens?: number; max_output_tokens?: number };
    supports?: { reasoning_effort?: string[]; vision?: boolean };
  };
  supported_endpoints?: string[];
  model_picker_enabled?: boolean;
}

interface ModelSummary {
  id: string;
  vendor: string;
  ctx: number | undefined;
  out: number | undefined;
  thinking: string[];
  vision: boolean;
  endpoints: string[];
  picker: boolean;
}

const AUTH_PATH: string = path.join(process.env.HOME || "~", ".pi/agent/auth.json");

const COPILOT_HEADERS = {
  "User-Agent": "GitHubCopilotChat/0.35.0",
  "Editor-Version": "vscode/1.107.0",
  "Editor-Plugin-Version": "copilot-chat/0.35.0",
  "Copilot-Integration-Id": "vscode-chat",
  Accept: "application/json",
};

function loadToken(): string {
  if (!fs.existsSync(AUTH_PATH)) {
    console.error(`auth.json not found at ${AUTH_PATH} — run /login in pi first`);
    process.exit(1);
  }
  const auth = JSON.parse(fs.readFileSync(AUTH_PATH, "utf8"));
  const copilot = auth["github-copilot"];
  if (!copilot || !copilot.access) {
    console.error("no github-copilot OAuth token in auth.json — run /login -> GitHub Copilot");
    process.exit(1);
  }
  return copilot.access;
}

function baseUrlFromToken(token: string): string {
  const m = token.match(/proxy-ep=([^;]+)/);
  if (!m) return "https://api.individual.githubcopilot.com";
  return "https://" + m[1].replace("proxy.", "api.");
}

function fetchModels(baseUrl: string, token: string): Promise<LiveModel[]> {
  return new Promise((resolve, reject) => {
    const url = new URL("/models", baseUrl);
    const opts = {
      hostname: url.hostname,
      path: url.pathname,
      method: "GET",
      headers: { ...COPILOT_HEADERS, Authorization: "Bearer " + token },
    };
    https
      .get(opts, (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          if (res.statusCode !== 200) {
            reject(new Error(`${res.statusCode}: ${data}`));
            return;
          }
          resolve(JSON.parse(data).data || []);
        });
      })
      .on("error", reject);
  });
}

function fmtN(n: number | undefined): string {
  if (typeof n !== "number") return "?";
  if (n >= 1_000_000) return n / 1_000_000 + "M";
  if (n >= 1_000) return n / 1_000 + "K";
  return String(n);
}

function loadStaticCatalog(): Record<string, { contextWindow?: number }> | null {
  const candidates = [
    "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/models.generated.js",
    "/usr/local/lib/node_modules/@earendil-works/pi-ai/dist/models.generated.js",
    "/usr/local/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist/models.generated.js",
    "/usr/local/lib/node_modules/@mariozechner/pi-ai/dist/models.generated.js",
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      const m = require(c);
      return m.MODELS && m.MODELS["github-copilot"] ? m.MODELS["github-copilot"] : null;
    }
  }
  return null;
}

function summarize(model: LiveModel): ModelSummary {
  const caps = model.capabilities || {};
  const limits = caps.limits || {};
  const supports = caps.supports || {};
  return {
    id: model.id,
    vendor: model.vendor || "?",
    ctx: limits.max_context_window_tokens,
    out: limits.max_output_tokens,
    thinking: supports.reasoning_effort || [],
    vision: supports.vision || false,
    endpoints: model.supported_endpoints || [],
    picker: model.model_picker_enabled !== false,
  };
}

(async () => {
  const token = loadToken();
  const baseUrl = baseUrlFromToken(token);
  console.log(`# Live API: ${baseUrl}\n`);

  const liveRaw = await fetchModels(baseUrl, token);
  const live = {};
  for (const m of liveRaw) {
    live[m.id] = summarize(m);
  }

  // Full table
  const hdr =
    "model".padEnd(42) +
    "vendor".padEnd(12) +
    "ctx".padEnd(8) +
    "out".padEnd(8) +
    "thinking".padEnd(24) +
    "vision  endpoints";
  console.log(hdr);
  console.log("-".repeat(140));

  const sorted = Object.values(live).sort((a, b) => a.id.localeCompare(b.id));
  for (const s of sorted) {
    const flag = s.picker ? "" : " (hidden)";
    const thinking = s.thinking.length ? s.thinking.join(",") : "no";
    const eps = s.endpoints.join(", ") || "-";
    console.log(
      (s.id + flag).padEnd(42) +
        s.vendor.padEnd(12) +
        fmtN(s.ctx).padEnd(8) +
        fmtN(s.out).padEnd(8) +
        thinking.padEnd(24) +
        (s.vision ? "yes" : "no").padEnd(8) +
        eps
    );
  }

  // Diff against static catalog
  const staticCatalog = loadStaticCatalog();
  if (!staticCatalog) {
    console.log("\n(could not load pi's static catalog — skipping diff)");
    return;
  }

  const staticIds = new Set(Object.keys(staticCatalog));
  const liveIds = new Set(Object.keys(live));

  const missing = [...liveIds].filter((x) => !staticIds.has(x)).sort();
  const differs = [];
  for (const mid of [...liveIds].filter((x) => staticIds.has(x)).sort()) {
    const liveCtx = live[mid].ctx;
    const staticCtx = staticCatalog[mid] && staticCatalog[mid].contextWindow;
    if (liveCtx && staticCtx && liveCtx !== staticCtx) {
      differs.push([mid, staticCtx, liveCtx]);
    }
  }

  console.log(`\n## MISSING from pi catalog (${missing.length})`);
  for (const mid of missing) {
    const s = live[mid];
    const thinking = s.thinking.length ? s.thinking.join(",") : "no";
    console.log(
      "  " +
        mid.padEnd(42) +
        s.vendor.padEnd(12) +
        "ctx=" +
        fmtN(s.ctx).padEnd(8) +
        "thinking=" +
        thinking +
        (s.vision ? "  vision" : "")
    );
  }

  console.log(`\n## DIFFERS context window (${differs.length})`);
  for (const [mid, sCtx, lCtx] of differs) {
    console.log("  " + mid.padEnd(42) + "static=" + fmtN(sCtx).padEnd(8) + "live=" + fmtN(lCtx));
  }
})();
