# Development Workspace

## Planning Workflow — Worktree Isolation

Every development plan in this workspace MUST use git worktrees for branch isolation, whether the task touches one repo or many. When creating a plan (via `/plan` or any planning request):

### 1. Discover repos and fetch latest (DO THIS FIRST, before any code exploration)
Scan `__WORKSPACE_DIR__/` for directories containing `.git`, **excluding** `iterm2` and `worktrees`. For each repo:
```bash
# Fetch latest from origin so all analysis is based on current remote state
git -C __WORKSPACE_DIR__/<repo> fetch origin

# Detect default branch
DEFAULT_BRANCH=$(git -C __WORKSPACE_DIR__/<repo> symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

# Fast-forward local default branch to match origin so code exploration sees latest state
CURRENT_BRANCH=$(git -C __WORKSPACE_DIR__/<repo> rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ]; then
  # Default branch is checked out — pull updates both the ref and working tree
  git -C __WORKSPACE_DIR__/<repo> pull --ff-only origin "$DEFAULT_BRANCH"
else
  # Different branch checked out — just update the ref (working tree doesn't need it)
  git -C __WORKSPACE_DIR__/<repo> branch -f "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" 2>/dev/null || true
fi
```
This MUST happen before reading any code or exploring the codebase. Do not start analyzing or planning until all relevant repos are fetched and local default branches are up to date.

### 2. Determine branch name
- If a Jira ticket is referenced (e.g., __JIRA_KEY__-1234), fetch details via the Atlassian MCP tool
- Convention: `__BRANCH_PREFIX__/<ticket-lowercase>-<short-description>` (e.g., `__BRANCH_PREFIX__/__JIRA_KEY_LOWER__-1234-add-rate-limits`)
- Without a ticket: `__BRANCH_PREFIX__/<short-description>`
- Use the SAME branch name across ALL affected repos

### 3. Structure every plan as:

**Phase 1 — Setup (worktree creation)**
For each affected repo:
```bash
# Verify clean working tree
git -C __WORKSPACE_DIR__/<repo> status --porcelain

# Create worktree from latest remote default branch (already fetched in step 1)
git -C __WORKSPACE_DIR__/<repo> worktree add \
  __WORKSPACE_DIR__/worktrees/<branch-name>/<repo> \
  -b <branch-name> origin/<default-branch>
```

**Phase 2 — Implement**
Ordered list of changes across repos, with dependencies noted. When multiple repos have independent changes (no cross-repo dependencies), execute them in parallel using separate agents — each working in its own worktree. When there ARE dependencies (e.g., repo B consumes a new field from repo A), sequence them: implement the upstream repo first, then the downstream.

**Phase 2.5 — Simplify**
After implementation is complete and before running tests, run `/simplify` on each repo that was changed. When multiple repos were changed independently, run `/simplify` in parallel. This catches code reuse opportunities, behavioral inconsistencies, and efficiency issues before they ship.

**Phase 3 — Test**
Run tests for each repo. When repos are independent, run tests in parallel. When there are dependencies, test upstream repos first.

**Phase 4 — Ship**
User manually reviews changes, then runs `/ship` when ready.

**Phase 5 — Cleanup**
Worktree removal and branch deletion (or use `/cleanup-worktrees`):
```bash
git -C __WORKSPACE_DIR__/<repo> worktree remove \
  __WORKSPACE_DIR__/worktrees/<branch-name>/<repo>
git -C __WORKSPACE_DIR__/<repo> branch -d <branch-name>
```

### 4. Include Ship Metadata in every plan

Every plan file MUST include a `## Ship Metadata` section (parsed by `/ship` to automate PR creation and Jira transitions):

```
## Ship Metadata
- **Branch:** __BRANCH_PREFIX__/<ticket>-<description>
- **Repos:** <comma-separated repo names>
- **Jira:** <__JIRA_KEY__-XXXX or "none">
```

### 5. Always ask clarifying questions before finalizing the plan

## Repo Map

<!--
  Replace this section with your own repo descriptions. The planner uses these
  hints to pick the right repos quickly instead of grepping everything.
  One bullet per repo with a short description of its role.
-->

- **<repo-name>** — <one-line description of what this service/repo does>

### Excluded from workflows
- **worktrees/** — Temporary worktrees for in-flight work

## Multi-Repo Exploration

- **Identify relevant repos first** — determine which repos to explore from the Jira ticket, plan context, or by asking. Do not grep across all repos blindly.
- **Use parallel subagents** — when exploring multiple repos, spawn separate Explore agents for each repo to investigate simultaneously rather than searching sequentially.

## Debugging & Investigation

When diagnosing production/dev issues (pods down, API errors), check the simplest explanations first (pod not running, service down) before diving into log-level analysis of specific log lines.

## Testing

After implementing changes that add new constructor parameters or method signatures, always check and update test files that mock or call those methods.

## Conventions

- **Jira project key**: __JIRA_KEY__
- **Branch naming**: `__BRANCH_PREFIX__/<ticket>-<short-description>`
- **Worktree path**: `__WORKSPACE_DIR__/worktrees/<branch-name>/<repo-name>/`
- **Branching**: Always from `origin/<default-branch>` via `fetch` (not `pull` — works even when other worktrees have the default branch checked out)
- **Shipping**: Use `/ship` to commit, push, create PRs, and transition Jira in one step
