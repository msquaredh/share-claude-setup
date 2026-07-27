# Development Workspace

## Planning Workflow — Worktree Isolation

Every development plan in this workspace MUST use git worktrees for branch isolation, whether the task touches one repo or many. The full procedure lives in the **`/plan-ticket`** command (`.claude/commands/plan-ticket.md`) — it auto-triggers on "plan this ticket", "plan __JIRA_KEY__-XXXX", or a pasted Jira URL. It researches read-only in plan mode, then presents a phased plan (Phase 1 worktree setup → 2 implement → 2.5 simplify → 3 test → 4 ship → 5 cleanup) with a `## Ship Metadata` block that `/ship` consumes, and always asks clarifying questions before finalizing.

Key invariants (see also [Conventions](#conventions)):
- **Discover + fetch first** — before any code exploration, fetch all relevant repos so analysis is based on current remote state. Non-coding tasks (pure research, docs, no repo changes) skip the worktree machinery entirely.
- **Branch naming** — `__BRANCH_PREFIX__/<ticket-lowercase>-<short-description>`, the SAME branch across all affected repos.
- **Ship Metadata** — every plan includes `## Ship Metadata` with `Branch`, `Repos` (comma-separated), and `Jira` (__JIRA_KEY__-XXXX or `none`).

## Repo Map

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
