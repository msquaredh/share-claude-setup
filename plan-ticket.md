Plan a development ticket using the git-worktree isolation workflow. Use this when the user says "plan this ticket", "plan __JIRA_KEY__-XXXX", "let's plan", pastes a Jira/ticket URL to plan, or invokes /plan-ticket — i.e. any request to plan a coding change across one or more workspace repos. Researches read-only in plan mode, then presents a phased plan (worktree setup → implement → simplify → test → ship → cleanup) with Ship Metadata that /ship consumes. For non-coding investigations (pure research, docs, debugging with no repo changes), skip the worktree machinery.

## Input
$ARGUMENTS

Optional: a ticket key (e.g. `__JIRA_KEY__-1234`), a Jira URL, or a free-text description of the work. If empty, ask what to plan.

## Steps

### Step 1 — Resolve the task

- If the input references a ticket key or Jira URL, fetch the ticket via the Atlassian MCP tool (if configured) and summarize the goal, acceptance criteria, and any linked context. If no Atlassian MCP is available, ask the user to paste the ticket description.
- Otherwise treat the input as a free-text description.
- **Rename the session** so it's recognizable later: call `mcp__ccd_session_mgmt__set_session_title` with `Plan __JIRA_KEY__-XXXX: <short what-it's-about>` derived from the ticket summary (e.g. `Plan __JIRA_KEY__-1234: add rate limits to api-service`), not the bare ticket key. For free-text input, use `Plan: <short description>`. If the tool is unavailable, skip silently.
- Decide whether this is a **coding change** (touches repo source) or a **non-coding task** (pure investigation, docs, observability/ticket work with no repo changes). For non-coding tasks, SKIP the worktree machinery (Steps 3–5 and Phases 1/5) — just research and present a plain plan, no Ship Metadata. Do not run `git fetch`/worktree setup for non-coding work.

### Step 2 — Enter plan mode

Call EnterPlanMode. Everything below is read-only research — **no code changes and no worktrees are created until the plan is approved**. (This is the step that makes "plan this ticket" actually engage plan mode instead of starting work inline.)

### Step 3 — Discover repos and fetch latest (before any code exploration)

Scan `__WORKSPACE_DIR__/` for directories containing `.git`, **excluding** `worktrees` and anything listed under `### Excluded from workflows` in the Repo Map. For each repo, fetch so analysis is based on current remote state. The `git fetch` is the critical freshness step (it updates `origin/<default>` refs that exploration reads); the local-branch fast-forward is best-effort and may be skipped if plan mode blocks the working-tree update:

```bash
# Fetch latest from origin so all analysis is based on current remote state
git -C __WORKSPACE_DIR__/<repo> fetch origin

# Detect default branch
DEFAULT_BRANCH=$(git -C __WORKSPACE_DIR__/<repo> symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

# Fast-forward local default branch to match origin so code exploration sees latest state (best-effort)
CURRENT_BRANCH=$(git -C __WORKSPACE_DIR__/<repo> rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ]; then
  git -C __WORKSPACE_DIR__/<repo> pull --ff-only origin "$DEFAULT_BRANCH" || true
else
  git -C __WORKSPACE_DIR__/<repo> branch -f "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" 2>/dev/null || true
fi
```

Do not start analyzing or planning until all relevant repos are fetched.

### Step 4 — Identify relevant repos and explore

- Determine which repos the work touches from the ticket, context, or the Repo Map in CLAUDE.md. Do not grep across all repos blindly — if it's ambiguous which repos are involved, ask.
- Explore the relevant repos with **parallel Explore agents** (one per repo) rather than searching sequentially.
- Verify architectural claims against actual source code, not README files or service names.

### Step 5 — Determine branch name

- With a ticket: `__BRANCH_PREFIX__/<ticket-lowercase>-<short-description>` (e.g. `__BRANCH_PREFIX__/__JIRA_KEY_LOWER__-1234-add-rate-limits`).
- Without a ticket: `__BRANCH_PREFIX__/<short-description>`.
- Use the SAME branch name across ALL affected repos.

### Step 6 — Draft the phased plan

Structure the plan as:

**Phase 1 — Setup (worktree creation)** — for each affected repo:
```bash
# Verify clean working tree
git -C __WORKSPACE_DIR__/<repo> status --porcelain

# Create worktree from latest remote default branch (already fetched in Step 3)
git -C __WORKSPACE_DIR__/<repo> worktree add \
  __WORKSPACE_DIR__/worktrees/<branch-name>/<repo> \
  -b <branch-name> origin/<default-branch>
```

**Phase 2 — Implement** — ordered list of changes across repos, with dependencies noted. Independent changes (no cross-repo dependency) run in parallel via separate agents, each in its own worktree. When repo B consumes a new field from repo A, sequence them: upstream first, then downstream.

**Phase 2.5 — Simplify** — after implementation, before tests, run `/simplify` on each changed repo (in parallel when repos are independent). Catches reuse opportunities, behavioral inconsistencies, and efficiency issues before they ship.

**Phase 3 — Test** — run tests per repo. Independent repos in parallel; with dependencies, test upstream first.

**Phase 4 — Ship** — user reviews changes, then runs `/ship`.

**Phase 5 — Cleanup** — worktree removal and branch deletion (or `/cleanup-worktrees`):
```bash
git -C __WORKSPACE_DIR__/<repo> worktree remove \
  __WORKSPACE_DIR__/worktrees/<branch-name>/<repo>
git -C __WORKSPACE_DIR__/<repo> branch -d <branch-name>
```

Every plan MUST include a `## Ship Metadata` section (parsed by `/ship`):
```
## Ship Metadata
- **Branch:** __BRANCH_PREFIX__/<ticket>-<description>
- **Repos:** <comma-separated repo names>
- **Jira:** <__JIRA_KEY__-XXXX or "none">
```

### Step 7 — Ask clarifying questions

Always ask clarifying questions before finalizing the plan.

### Step 8 — Present for approval

Present the full plan via ExitPlanMode. This both requests approval and auto-saves the plan to `~/.claude/plans/`, which is exactly where `/ship` reads it. Worktree creation (Phase 1) and all edits happen only after the user approves and exits plan mode.
