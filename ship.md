Ship the current session's work: commit remaining changes, push branches, create PRs, output links, and transition Jira.

## Input
$ARGUMENTS

Optional: path to a specific plan file. If not provided, use the current session's plan file under `~/.claude/plans/`.

## Steps

### Step 1 — Check task completion

Use `TaskList` to get all tasks for this session. If any tasks have status other than `completed`:

> **Blocked:** The following tasks are not yet complete:
> - Task name (status)
> - ...
>
> Complete these before shipping, or update their status if they are done.

STOP here. Do not proceed until all tasks are complete.

If the task list is empty (no tasks created), proceed — not all sessions use task tracking.

### Step 2 — Parse the plan file

Find and read the current session's plan file under `~/.claude/plans/`. Extract the `## Ship Metadata` section:

- **Branch** — the branch name (e.g., `__BRANCH_PREFIX__/__JIRA_KEY_LOWER__-1234-add-rate-limits`)
- **Repos** — comma-separated list of repo names (e.g., `repo-a, repo-b`)
- **Jira** — the __JIRA_KEY__ ticket key (e.g., `__JIRA_KEY__-1234`), or `none` for non-ticket work

If the plan file has no `## Ship Metadata` section, or Branch/Repos are missing, STOP:

> **Missing Ship Metadata.** This plan needs a `## Ship Metadata` section with Branch, Repos, and Jira fields. Add it to the plan file and re-run `/ship`.

### Step 3 — Commit uncommitted changes

For each repo in the Repos list, check the worktree at `__WORKSPACE_DIR__/worktrees/<branch>/<repo>/`:

```bash
git -C __WORKSPACE_DIR__/worktrees/<branch>/<repo> status --porcelain
```

If the worktree path does not exist, warn and skip that repo.

If there are uncommitted changes:
1. Show what will be committed: `git -C <worktree> diff --stat`
2. Stage changes: `git -C <worktree> add -A`
3. Commit with a meaningful message derived from the plan context:
   ```
   <type>: <concise description>

   Co-Authored-By: Claude <noreply@anthropic.com>
   ```

If there are no uncommitted changes, continue to the next step.

### Step 4 — Push branches and create PRs

For each repo, check if there are commits to push:

```bash
# Detect default branch
default_branch=$(git -C __WORKSPACE_DIR__/<repo> symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')

# Check for commits on the branch
git -C __WORKSPACE_DIR__/worktrees/<branch>/<repo> log origin/${default_branch}..<branch> --oneline
```

If no commits exist on the branch for a repo, note "no changes" and skip it.

For each repo with commits:

1. **Get the remote org/repo**:
   ```bash
   git -C __WORKSPACE_DIR__/<repo> remote get-url origin
   ```
   Extract `<org>/<repo>` from the URL.

2. **Push the branch**:
   ```bash
   git -C __WORKSPACE_DIR__/worktrees/<branch>/<repo> push -u origin <branch>
   ```

3. **Check if a PR already exists**:
   ```bash
   gh pr list --repo <org/repo> --head <branch> --state open --json number,url
   ```
   If a PR exists, note its URL and skip creation.

4. **Create the PR** (if none exists):
   Use `gh pr create` with:
   - `--repo <org/repo>`
   - `--head <branch>`
   - `--base <default-branch>`
   - `--title` — format as `<__JIRA_KEY__-XXXX>: <short description>` (omit ticket prefix if Jira is `none`)
   - `--body` — generate from plan context:
     - `## Summary` with 2-4 bullet points
     - `## Jira` linking to the ticket if applicable
     - `## Test Plan` derived from the plan's verification section

### Step 5 — Output PR links

Print a clear summary:

```
## Ship Summary

| Repo | PR | Status |
|------|----|--------|
| repo-a | org/repo#123 | Created |
| repo-b | org/repo#45 | Already existed |
| repo-c | — | No changes |
```

### Step 6 — Transition Jira ticket

If Jira is `none` or not specified, skip this step and note: "No Jira ticket — skipping transition."

If a Jira ticket is specified:

1. **Get available transitions**:
   Use the Atlassian MCP `getTransitionsForJiraIssue` tool to find the transition ID for "In Review" (or similar review status).

2. **Transition the ticket**:
   Use the Atlassian MCP `transitionJiraIssue` tool with the discovered transition ID.

3. **Add PR links as a comment**:
   Use the Atlassian MCP `addCommentToJiraIssue` tool to post all PR links on the ticket.

If any Jira step fails, warn but do not block — the PRs are already created.

## Error Handling

- **Plan file not found**: Stop and ask the user to provide the plan path via arguments.
- **Worktree missing for a repo**: Warn, skip that repo, continue with others.
- **No changes to push**: Note "no changes" in summary, skip PR creation for that repo.
- **PR already exists**: Report existing URL, do not create a duplicate.
- **Push fails**: Report the error, continue with other repos.
- **Jira transition fails**: Warn but do not block.
