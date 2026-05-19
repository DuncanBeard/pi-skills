---
name: rebase-to-dated-branch
description: Rebase current branch changes onto a fresh branch from main with today's date in the branch name. Use when asked to rebase, refresh, or update a dated feature branch.
---

# Rebase to Dated Branch

Rebase the changes from the current branch onto a new branch based off `main`. The new branch name should reflect that it's based off `main`, with today's date component.

## Procedure

1. Get the current branch name with `git branch --show-current`.
2. Parse the branch name to extract the **date portion** (expected format: `YYYY-MM-DD`) and the **prefix** (everything before the date). For example, `duncanbeard/airgap-release-2026-03-06` has prefix `duncanbeard/airgap-` and date `2026-03-06`.
3. Construct the new branch name by replacing the base branch identifier with "main" (e.g., `airgap-release` → `airgap-main`) and updating the date to today's date. For example: `duncanbeard/airgap-release-2026-03-06` → `duncanbeard/airgap-main-2026-04-10`.
4. List the commits unique to this branch: `git log origin/main..HEAD --oneline`. Show these to the user for confirmation before proceeding.
5. Fetch latest main: `git fetch origin main`.
6. Create the new branch from `origin/main` **without tracking**: `git checkout -b <new-branch-name> --no-track origin/main`. The `--no-track` flag is critical — without it the new branch tracks `origin/main` and a blind `git push` would push to main.
7. Cherry-pick the commits from the old branch in order (oldest first). Use `git cherry-pick <oldest>..<newest>` or pick individually.
8. If conflicts occur, **stop and report them** — do not force-resolve.
9. Push and set the upstream tracking branch so pushes go to the new branch name: `git push -u origin <new-branch-name>`.
10. Verify tracking is correct: `git branch -vv --list <new-branch-name>` — it must show `origin/<new-branch-name>`, **not** `origin/main`.
11. Show the final `git log --oneline -20` on the new branch to confirm.

## Post-Rebase Validation

After the cherry-pick is complete, diff the new branch against the old branch to verify nothing was lost:

1. Run `git diff <old-branch-name> <new-branch-name> -- . ':!*.lock'` to compare the two branches.
2. Analyze the diff and call out:
   - **Missing changes:** Files or hunks present on the old branch but absent on the new branch that are NOT explained by the updated main baseline.
   - **Unexpected additions:** New content on the new branch that doesn't come from either the cherry-picked commits or the updated main.
   - **Conflict artifacts:** Any leftover merge conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
   - **Binary file differences:** Flag any binary files that differ between the branches.
3. For each potential issue found, explain whether it is:
   - **Expected** (e.g., the old branch had a merge commit that pulled in main changes already present on the new branch's base), or
   - **Suspicious** (e.g., a change from one of the cherry-picked commits appears to be missing or altered).
4. Summarize with a clear **pass/fail verdict**: either "No changes lost — rebase looks clean" or a list of items that need manual review.

## Edge Cases

- If the current branch name has **no date component**, ask the user for the new branch name.
- If the new branch name **already exists** locally or on the remote, ask before overwriting.
- If the branch is **already up-to-date** with main (no unique commits), inform the user and stop.
