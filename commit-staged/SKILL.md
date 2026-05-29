---
name: commit-staged
description: Commit currently staged git changes with a descriptive, conventional commit message. Inspects the diff, summarizes intent, and writes a well-structured multi-line message. Use when asked to commit, save staged work, or create a commit.
---

# Commit Staged Changes

Create a high-quality commit message for the currently staged changes and commit them.

## Workflow

1. **Check for staged changes**
   ```bash
   git status
   git diff --cached --stat
   ```
   If nothing is staged, tell the user and stop.

2. **Inspect the full diff**
   ```bash
   git diff --cached
   ```

3. **Write the commit message** following these rules:

   ### Subject line (first line)
   - Imperative mood ("Add", "Fix", "Update", not "Added", "Fixes")
   - Max 72 characters
   - No trailing period
   - Summarize the *intent* of the change, not a file list

   ### Body (after blank line)
   - Wrap at 72 characters
   - Explain *why* the change was made and *what* it does at a high level
   - If multiple files/areas are touched, include a short bulleted summary
     using `- ` list items
   - Reference ticket/work-item IDs if they appear in branch name or diff

4. **Commit**
   ```bash
   git commit -m "<message>"
   ```

5. **Report** the short SHA, subject line, and file stats to the user.

## Notes
- Never amend or force-push unless explicitly asked.
- If the diff is very large (>500 lines), summarize by area rather than listing every change.
- If the branch name contains a ticket ID (e.g., `AB#12345`, `JIRA-999`), include it at the end of the subject or in the body.
