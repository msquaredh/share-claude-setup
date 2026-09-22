# Development Workspace

## Verification Before Claiming
- Before stating a root cause, `git fetch && git log origin/<default-branch> -1` and confirm the local checkout is current — reasoning from a stale repo produces wrong RCAs.
- Never assert 'no data' / 'no timeouts' / 'never fires' from a single query. Re-run with an explicitly widened time window and state the window in the claim.
- When a conclusion comes from logs or metrics, read the code path that emits that log line to confirm it actually fires on the branch in question before concluding anything from its absence.

## Investigation Output Style
- Lead with the answer in 3 lines or fewer, then evidence. No preamble, no restating the question.
- State confidence explicitly: CONFIRMED (code + data read), LIKELY (one source), HYPOTHESIS (not yet verified). Never present a hypothesis in declarative voice.

## Planning Workflow — Worktree Isolation

Every development plan in this workspace MUST use git worktrees for branch isolation, whether the task touches one repo or many. The full procedure lives in the **`/plan-ticket`** command (`.claude/commands/plan-ticket.md`) — it auto-triggers on "plan this ticket", "plan __JIRA_KEY__-XXXX", or a pasted Jira URL. It researches read-only in plan mode, then presents a phased plan (Phase 1 worktree setup → 2 implement → 2.5 simplify → 3 test → 4 ship → 5 cleanup) with a `## Ship Metadata` block that `/ship` consumes, and always asks clarifying questions before finalizing. For a fully autonomous run with a single approval gate, **`/ship-ticket`** chains plan → implement → test → adversarial review → PR → CI on top of the same procedure.

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

## Shell & Build Conventions
- Always use absolute paths in Bash commands, especially for background/long-running test runs — a lost working directory can produce a false-green test result.
- Do not silence lints with `noqa`/suppressions as a first resort. Grep sibling repos for how they solved the same lint and follow that pattern.
- <Add your org's toolchain pins here: JDK/Node version, where the package-registry token lives, PATH additions for gh/mvn/etc.>

## Schema & Data Model Conventions
- Verify every table and column name against the actual entity or migration file before writing scripts or SQL — do not infer from naming convention.
- <Add your org's DDL rules here: column types, index-creation pattern, join-table key convention.>

## Code Changes
- When applying a feature flag or gate, apply it to ALL relevant code paths and add tests symmetrically across each path.
- **Code comments**: only comment non-obvious motivations (underlying dependencies, edge cases); remove comments that restate the code. Aim for 1–2 lines.
- **No blame/attribution**: never name the PR, commit, release, or author that introduced the thing being fixed — not in code comments, commit messages, PR descriptions, or ticket comments. Describe the current behavior and the fix.

## Testing

After implementing changes that add new constructor parameters or method signatures, always check and update test files that mock or call those methods.

## Conventions

- **Jira project key**: __JIRA_KEY__
- **Branch naming**: `__BRANCH_PREFIX__/<ticket>-<short-description>`
- **Worktree path**: `__WORKSPACE_DIR__/worktrees/<branch-name>/<repo-name>/`
- **Branching**: Always from `origin/<default-branch>` via `fetch` (not `pull` — works even when other worktrees have the default branch checked out)
- **Shipping**: Use `/ship` to commit, push, create PRs, and transition Jira in one step
