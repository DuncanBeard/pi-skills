---
name: check-history
description: Re-check the last response by searching past pi chat sessions for prior knowledge. Use when the user says things like "we talked about this before", "you already know this", "check your history", "try again", "you're wrong, we fixed this", or otherwise implies a past conversation has relevant context you're missing.
---

# Check History

Re-evaluate the last response using evidence from past conversations. The user
believes you made a mistake that prior sessions would correct.

## Workflow

### Step 1 — Identify what to search for

Look at the **last assistant response** and the **user's complaint/trigger**.
Extract 3-6 concrete search terms: key identifiers, error messages, file paths,
config names, function names, or technical terms that would appear in a prior
conversation about the same topic. Prefer specific tokens (e.g.
`monitoringGcsAuthId`, `fairfax`, `EtwSession`) over generic ones (`error`,
`config`, `fix`).

### Step 2 — Search local sessions (same project)

Run the search script against sessions from the current working directory:

```bash
node "<skill_dir>/search-sessions.js" --cwd "<current_working_directory>" --terms "term1,term2,term3"
```

`<skill_dir>` is the directory containing this SKILL.md file.

Review the results. The script outputs timestamped conversation excerpts where
those terms appeared, with surrounding context.

### Step 3 — Analyze and re-respond

Compare what you said in the last response against what the past sessions show.
Look for:

- **Corrections you made before** — did you fix this same mistake in a prior chat?
- **Decisions that were made** — did the user and a prior assistant agree on an
  approach you're now contradicting?
- **Facts you're getting wrong** — config values, file paths, parameter names
  that the history shows differently than what you just said.

Then produce a corrected response, explicitly noting:
1. What was wrong in your last response
2. What the prior conversation established
3. The corrected answer

### Step 4 — If the user asks again or says "check wider"

If the local search didn't find anything useful, or the user triggers this skill
a second time, expand to **all session directories**:

```bash
node "<skill_dir>/search-sessions.js" --all --terms "term1,term2,term3"
```

This searches across every project the user has used pi in.

## Notes

- The search script returns the 20 most relevant conversation excerpts by default.
  Use `--limit 50` if you need more.
- Each excerpt includes the session date and surrounding messages for context.
- The `--verbose` flag includes tool results and thinking blocks.
- If search results are very large, focus on the **most recent** matching sessions
  first — they're most likely to reflect current decisions.
- Be humble. The user is telling you they have prior context you're missing.
  Trust the history over your current assumptions.
