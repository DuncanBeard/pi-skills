#!/usr/bin/env node
// search-sessions.js — Search pi chat history for relevant past conversations
//
// Usage:
//   node search-sessions.js --cwd /path/to/project --terms "term1,term2,term3"
//   node search-sessions.js --all --terms "fairfax,monitoringGcsAuthId"
//   node search-sessions.js --cwd . --terms "EtwSession" --limit 50 --verbose

const fs = require("fs");
const path = require("path");

// ── CLI args ────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
function flag(name) {
  return args.includes(`--${name}`);
}
function opt(name, fallback) {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

const searchAll = flag("all");
const cwd = opt("cwd", process.cwd());
const termsRaw = opt("terms", "");
const limit = parseInt(opt("limit", "20"), 10);
const verbose = flag("verbose");

if (!termsRaw) {
  console.error("Usage: node search-sessions.js --terms term1,term2,... [--cwd path] [--all] [--limit N] [--verbose]");
  process.exit(1);
}

const terms = termsRaw
  .split(",")
  .map((t) => t.trim().toLowerCase())
  .filter(Boolean);

// ── Locate sessions dir ─────────────────────────────────────────────────────
const SESSIONS_ROOT = path.join(
  process.env.HOME || process.env.USERPROFILE || "~",
  ".pi",
  "agent",
  "sessions"
);

function cwdToSessionDir(dir) {
  // pi encodes cwd by replacing : \ / with -, then wrapping in --
  // C:\Users\foo -> C--Users-foo -> --C--Users-foo--
  const encoded =
    "--" +
    dir
      .replace(/[\\\/]/g, "-") // slashes -> -
      .replace(/:/g, "-") // colon -> -
      .replace(/-+$/g, "") + // trim trailing dashes before suffix
    "--";
  return encoded;
}

function findSessionDirs() {
  if (!fs.existsSync(SESSIONS_ROOT)) {
    console.error(`Sessions directory not found: ${SESSIONS_ROOT}`);
    process.exit(1);
  }

  const allDirs = fs
    .readdirSync(SESSIONS_ROOT)
    .filter((d) => fs.statSync(path.join(SESSIONS_ROOT, d)).isDirectory());

  if (searchAll) {
    return allDirs.map((d) => path.join(SESSIONS_ROOT, d));
  }

  // Find the directory matching the current cwd
  const encoded = cwdToSessionDir(cwd);
  // Try exact match first, then prefix match
  let match = allDirs.find((d) => d === encoded);
  if (!match) {
    // Fuzzy: find dirs whose name contains distinctive path segments
    const segments = cwd
      .replace(/[\\\/]/g, "-")
      .replace(/:/g, "-")
      .split("-")
      .filter((s) => s.length > 2);
    // Pick the most specific segment (longest, skip drive letter and username)
    const specific = segments.slice(-2).join("-").toLowerCase();
    match = allDirs.find((d) => d.toLowerCase().includes(specific));
  }

  if (!match) {
    console.error(`No session directory found for cwd: ${cwd}`);
    console.error(`Encoded as: ${encoded}`);
    console.error(`Available: ${allDirs.join(", ")}`);
    process.exit(1);
  }

  return [path.join(SESSIONS_ROOT, match)];
}

// ── Parse and search sessions ───────────────────────────────────────────────

/** Extract messages from a JSONL session file */
function parseSession(filepath) {
  const content = fs.readFileSync(filepath, "utf8");
  const lines = content.split("\n").filter(Boolean);
  const messages = [];
  let sessionMeta = null;

  for (const line of lines) {
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }

    if (entry.type === "session") {
      sessionMeta = {
        id: entry.id,
        timestamp: entry.timestamp,
        cwd: entry.cwd,
      };
      continue;
    }

    if (entry.type === "message") {
      const msg = entry.message;
      const role = msg.role;
      let text = "";

      if (typeof msg.content === "string") {
        text = msg.content;
      } else if (Array.isArray(msg.content)) {
        text = msg.content
          .filter((c) => c.type === "text")
          .map((c) => c.text)
          .join("\n");
      }

      if (text.trim()) {
        messages.push({
          role,
          text,
          timestamp: entry.timestamp,
          id: entry.id,
        });
      }
    }

    if (verbose && entry.type === "toolResult") {
      const resultText =
        typeof entry.result === "string"
          ? entry.result
          : JSON.stringify(entry.result);
      if (resultText) {
        messages.push({
          role: "tool",
          text: resultText.substring(0, 2000),
          timestamp: entry.timestamp,
          id: entry.id,
        });
      }
    }
  }

  return { meta: sessionMeta, messages };
}

/** Score a message against search terms. Returns 0 if no match. */
function scoreMessage(text, searchTerms) {
  const lower = text.toLowerCase();
  let score = 0;
  for (const term of searchTerms) {
    // Count occurrences
    let idx = 0;
    let count = 0;
    while ((idx = lower.indexOf(term, idx)) !== -1) {
      count++;
      idx += term.length;
    }
    if (count > 0) {
      // Longer terms are worth more (more specific)
      score += count * (1 + term.length / 10);
    }
  }
  return score;
}

/** Build context excerpts: the matching message plus surrounding messages */
function buildExcerpts(session, searchTerms) {
  const { meta, messages } = session;
  const excerpts = [];

  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    const score = scoreMessage(msg.text, searchTerms);
    if (score === 0) continue;

    // Grab window: 1 message before, the match, 2 messages after
    const windowStart = Math.max(0, i - 1);
    const windowEnd = Math.min(messages.length - 1, i + 2);
    const window = [];

    for (let j = windowStart; j <= windowEnd; j++) {
      const m = messages[j];
      // Truncate very long messages to keep output manageable
      const truncated =
        m.text.length > 1500
          ? m.text.substring(0, 1500) + `\n... [truncated, ${m.text.length} chars total]`
          : m.text;
      window.push({
        role: m.role,
        text: truncated,
        isMatch: j === i,
      });
    }

    excerpts.push({
      sessionDate: meta?.timestamp?.substring(0, 10) || "unknown",
      sessionId: meta?.id?.substring(0, 8) || "unknown",
      sessionCwd: meta?.cwd || "unknown",
      matchTimestamp: msg.timestamp,
      score,
      matchRole: msg.role,
      messages: window,
    });
  }

  return excerpts;
}

// ── Main ────────────────────────────────────────────────────────────────────
const sessionDirs = findSessionDirs();
const allExcerpts = [];

for (const dir of sessionDirs) {
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".jsonl"))
    .sort(); // chronological by filename

  for (const file of files) {
    const filepath = path.join(dir, file);
    try {
      const session = parseSession(filepath);
      const excerpts = buildExcerpts(session, terms);
      allExcerpts.push(...excerpts);
    } catch (err) {
      // Skip corrupt files
      if (verbose) {
        console.error(`Skipping ${file}: ${err.message}`);
      }
    }
  }
}

// Sort by score descending, take top N
allExcerpts.sort((a, b) => b.score - a.score);
const topExcerpts = allExcerpts.slice(0, limit);

if (topExcerpts.length === 0) {
  console.log(`No matches found for terms: ${terms.join(", ")}`);
  console.log(`Searched ${sessionDirs.length} session directory(ies)`);
  if (!searchAll) {
    console.log(`\nTip: Re-run with --all to search across all projects.`);
  }
  process.exit(0);
}

// ── Output ──────────────────────────────────────────────────────────────────
const scope = searchAll ? "ALL projects" : sessionDirs[0];
console.log(`=== Search results for: ${terms.join(", ")} ===`);
console.log(`Scope: ${scope}`);
console.log(`Found ${allExcerpts.length} matches, showing top ${topExcerpts.length}\n`);

for (let idx = 0; idx < topExcerpts.length; idx++) {
  const ex = topExcerpts[idx];
  console.log(`--- Match ${idx + 1}/${topExcerpts.length} (score: ${ex.score.toFixed(1)}) ---`);
  console.log(`Session: ${ex.sessionDate} [${ex.sessionId}]`);
  if (searchAll) {
    console.log(`Project: ${ex.sessionCwd}`);
  }
  console.log(`When: ${ex.matchTimestamp}`);
  console.log("");

  for (const m of ex.messages) {
    const marker = m.isMatch ? " <<<" : "";
    const roleLabel = m.role.toUpperCase().padEnd(9);
    const lines = m.text.split("\n");
    console.log(`  ${roleLabel} ${lines[0]}${marker}`);
    for (let li = 1; li < lines.length; li++) {
      console.log(`            ${lines[li]}`);
    }
    console.log("");
  }
}

console.log(`\n=== End of results (${topExcerpts.length}/${allExcerpts.length} shown) ===`);
