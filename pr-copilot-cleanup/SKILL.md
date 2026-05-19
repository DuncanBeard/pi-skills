---
name: pr-copilot-cleanup
description: Clean up auto-generated AI content on an ADO pull request after a force-push. Strips the "AI description" block that GitOps PR Assistant appends to the PR description, and triages inline Copilot code-review comments -- applying useful suggestions or resolving them as "won't fix". Use after force-pushing a cleaned-up branch, or whenever Copilot auto-comments clutter a PR.
---

# PR Copilot Cleanup

Remove AI-generated noise from an Azure DevOps pull request: the auto-appended description block and inline Copilot code-review comments.

## Inputs

You need the following before starting:

- **PR ID** (e.g. `15398133`)
- **ADO org URL** (e.g. `https://msazure.visualstudio.com/DefaultCollection`)
- **Repository ID** -- get from the PR JSON `repository.id` field
- **Project ID** -- get from the PR JSON `repository.project.id` field

If the user gave you a PR URL, extract the PR ID from it. To get the repo and project IDs:

```bash
az repos pr show --id <PR_ID> --org <ORG_URL> 2>/dev/null \
  | python -c "
import json, sys
pr = json.load(sys.stdin)
print('repo_id=' + pr['repository']['id'])
print('project_id=' + pr['repository']['project']['id'])
"
```

## Step 1: Strip AI description block from PR description

Wait about 60 seconds after the most recent push, then re-fetch the PR description. The GitOps PR Assistant bot reacts to push events asynchronously and often appends an `#### AI description` block within a few minutes.

### Check for the AI block

```bash
az repos pr show --id <PR_ID> --org <ORG_URL> 2>/dev/null | python -c "
import json, sys
pr = json.load(sys.stdin)
desc = pr.get('description', '')
markers = ['----\n#### AI description', '#### AI description', '<!-- GitOpsUserAgent']
for m in markers:
    idx = desc.find(m)
    if idx >= 0:
        print('FOUND at char ' + str(idx))
        print('Preview: ' + desc[idx:idx+200])
        sys.exit(0)
print('CLEAN')
"
```

### If found, strip it and update

Truncate the description at the first marker and update the PR:

```bash
az repos pr show --id <PR_ID> --org <ORG_URL> 2>/dev/null | python -c "
import json, sys
pr = json.load(sys.stdin)
desc = pr.get('description', '')
markers = ['----\n#### AI description', '#### AI description', '<!-- GitOpsUserAgent']
for m in markers:
    idx = desc.find(m)
    if idx >= 0:
        desc = desc[:idx].rstrip()
        break
print(desc)
" > /tmp/pr-desc-clean.txt

az repos pr update --id <PR_ID> --org <ORG_URL> \
  --description "$(cat /tmp/pr-desc-clean.txt)" 2>/dev/null | python -c "
import json, sys
pr = json.load(sys.stdin)
print('Updated PR #' + str(pr['pullRequestId']) + ' -- AI description block stripped')
"
```

If the description is clean, report that and move on.

## Step 2: Triage inline Copilot code-review comments

Fetch all PR threads and filter to those from GitOps/Copilot that have file context (inline code comments).

### Fetch threads

```bash
TOKEN=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv 2>/dev/null)

curl -s -u ":$TOKEN" \
  "https://msazure.visualstudio.com/<PROJECT_ID>/_apis/git/repositories/<REPO_ID>/pullRequests/<PR_ID>/threads?api-version=7.0" \
  | python -c "
import json, sys, re, html
data = json.load(sys.stdin)
threads = data.get('value', [])
for i, t in enumerate(threads):
    comments = t.get('comments', [])
    if not comments:
        continue
    first = comments[0]
    author = first.get('author', {}).get('displayName', '?')
    ctype = first.get('commentType', '')
    status = t.get('status', 'unknown')
    tc = t.get('threadContext')
    has_file = tc and tc.get('filePath')
    is_bot = 'GitOps' in author or 'Copilot' in author

    # Only show bot inline comments that are not already resolved
    if not (is_bot and has_file and status in ('active', 'pending')):
        continue

    content = first.get('content', '')
    clean = re.sub(r'<[^>]+>', ' ', content)
    clean = html.unescape(clean)
    clean = re.sub(r'\s+', ' ', clean).strip()

    filepath = tc.get('filePath', '?')
    line = tc.get('rightFileStart', {}).get('line', '?') if tc.get('rightFileStart') else '?'

    print(f'THREAD_ID={t[\"id\"]} | STATUS={status}')
    print(f'File: {filepath}, line {line}')
    print(f'Comment: {clean[:1200]}')
    print()
"
```

### Present to user and decide

For each active bot comment thread, determine:
1. Is the file still in the current diff? If not, the comment is **stale** -- mark it won't fix.
2. Is the suggestion actually useful? Summarize it in plain English.

Use the `question` tool to present all bot comments in a table and ask the user which to **apply** vs **dismiss**. Group them if there are many.

### Apply a suggestion

If the user wants to apply a suggestion:
1. Read the file and make the edit using the `edit` tool
2. Stage, commit with a descriptive message, and push
3. Resolve the thread (see below)

### Resolve or reject threads via API

To **resolve** a thread (applied the suggestion):

```bash
TOKEN=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv 2>/dev/null)

curl -s -X PATCH -u ":$TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "fixed"}' \
  "https://msazure.visualstudio.com/<PROJECT_ID>/_apis/git/repositories/<REPO_ID>/pullRequests/<PR_ID>/threads/<THREAD_ID>?api-version=7.0"
```

To **reject** a thread (won't fix / not applicable):

```bash
curl -s -X PATCH -u ":$TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "wontFix"}' \
  "https://msazure.visualstudio.com/<PROJECT_ID>/_apis/git/repositories/<REPO_ID>/pullRequests/<PR_ID>/threads/<THREAD_ID>?api-version=7.0"
```

### Batch push and resolve

If multiple suggestions are applied:
1. Make all edits first
2. Stage and commit all changes in a single commit
3. Push once
4. Resolve all applied threads
5. Won't-fix all dismissed threads

## Notes

- The ADO REST API base URL is `https://msazure.visualstudio.com/<PROJECT_ID>/_apis/git/repositories/<REPO_ID>/...`
- The access token resource for ADO is `499b84ac-1321-427f-aa17-267ca6975798`
- Thread statuses: `active`, `fixed`, `wontFix`, `closed`, `byDesign`, `pending`
- Always use `2>/dev/null` on `az` commands to suppress the "does not support Azure DevOps Server" warning
- When stripping AI description, preserve any trailing newline the user's description had
