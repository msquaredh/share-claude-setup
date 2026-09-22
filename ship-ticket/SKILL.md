---
name: ship-ticket
description: Drive a Jira ticket end to end to a merged-ready PR with one human gate (plan approval): fetch ticket → worktree → plan → implement → test loop → adversarial self-review → PR → CI green. Use when the user says "ship __JIRA_KEY__-XXXX end to end" or invokes /ship-ticket.
---

## Input
$ARGUMENTS — a ticket key (e.g. `__JIRA_KEY__-1234`) or Jira URL. Required; if missing, ask.

## Ground rules (entire run)
- **Absolute paths for every command**: `git -C <abs-path>`, `mvn -f <abs-path>/pom.xml`, `<abs-worktree>/gradlew -p <abs-worktree>`. Never rely on shell cwd — a background run can report false-green after the shell loses its working directory. If any output looks suspicious (0 tests run, module names or paths that don't match the worktree, instant completion), assume cwd drift and re-run from scratch with absolute paths.
- **Build env**: follow the `## Shell & Build Conventions` section of the workspace CLAUDE.md (toolchain pins, package-registry tokens, PATH additions). Fix a failing credential at its source rather than working around it with shadow config dirs.
- **Conventions**: follow CLAUDE.md's Verification Before Claiming, Shell & Build, Schema & Data Model, and Code Changes sections throughout. Run any repo-specific formatter noted in CLAUDE.md before committing.
- This skill owns commit/push/PR (Phase 6) — the usual "review the diff, then /ship" pause is replaced by the Phase 5 adversarial review. The plan approval in Phase 2 is the ONLY human gate.

## Phase 1 — Ticket intake
1. Fetch the ticket via the Atlassian MCP (`getJiraIssue`), then all linked tickets, remote links, and comments (`getJiraIssueRemoteIssueLinks`, linked-issue fetches). Summarize: goal, acceptance criteria, constraints, and anything in comments that changes scope.
2. Rename the session: `mcp__ccd_session_mgmt__set_session_title` with `Ship __JIRA_KEY__-XXXX: <short description>`. If the tool is unavailable, skip silently.
3. If the Atlassian MCP is down, stop and tell the user — do not guess ticket scope from the key alone.

## Phase 2 — Plan (THE ONLY MANDATORY GATE)
Follow the `/plan-ticket` procedure (`.claude/commands/plan-ticket.md`) from Step 2 onward: enter plan mode, fetch ALL repos before exploration, parallel Explore agents on the relevant repos, branch name `__BRANCH_PREFIX__/<ticket-lowercase>-<short-description>` (same branch across all affected repos), phased plan with `## Ship Metadata`, clarifying questions, then ExitPlanMode.

**STOP here and wait for explicit plan approval. No worktrees, no edits, no commits until approved.**

## Phase 3 — Worktree + implement
1. Create worktrees per the plan: `__WORKSPACE_DIR__/worktrees/<branch>/<repo>/`, branched from `origin/<default-branch>` via fetch (check each repo's default — not every repo uses `main`).
2. Move the session into the primary worktree (`mcp__ccd_directory__change_directory`; Claude desktop app only, skip if unavailable) and `git add -N` new files so the diff panel tracks them.
3. Implement per plan. When a constructor or method signature changes, update every test that mocks or calls it in the same pass. Run `/simplify` on each changed repo before testing.

## Phase 4 — Test loop
1. Run the FULL suite per repo with absolute paths (`mvn -f <abs>/pom.xml verify` / `<abs>/gradlew -p <abs> build` / the repo's equivalent). Independent repos in parallel; with cross-repo dependencies, upstream first.
2. On failure: read the failure, fix, re-run. On suspicious output (see ground rules): discard the result and re-run from scratch.
3. Loop until genuinely green. In the report, paste the actual final test-summary line (tests run / failures / errors) per repo — never claim "tests pass" without it.

## Phase 5 — Adversarial self-review (before any commit)
Spawn a general-purpose subagent with the full diff (`git -C <worktree> diff origin/<default-branch>`) and the approved plan. Its ONLY job is to find problems — instruct it explicitly that it must not agree by default and every finding needs file:line evidence. It hunts for:
- **Scope creep** — any hunk not required by the ticket/plan
- **Misleading log/error wording** — messages that describe something other than what the code path actually does
- **Schema/migration hazards** — table/column names verified against the actual entities and migration files (not inferred from naming); every rule in CLAUDE.md's `## Schema & Data Model Conventions`
- **Lint escape hatches** — any `noqa`/suppression added; survey sibling repos for how they solved the same lint and demand that pattern instead
- **Sibling-repo convention deviations** — compare against how the org's other repos structure the same kind of change

Fix confirmed findings (re-run Phase 4 after fixes). Dismissed findings go in the final report's judgment calls.

## Phase 6 — Ship + CI loop
1. Follow the `/ship` procedure (`.claude/commands/ship.md`): commit (repo formatters first), push, create PRs (title `__JIRA_KEY__-XXXX: <desc>`; body = concise executive bullets, no blame/attribution for the bug being fixed), transition Jira to In Review, comment PR links on the ticket.
2. If the plan touches a shared library consumed by other repos in the plan: its PR must merge and publish before the downstream PRs can merge — note the required version bump in the consumers and flag this ordering in the report.
3. Poll CI: `gh pr checks <pr-url> --repo <org/repo> --watch` (or loop every few minutes). On failure:
   - Pull the failing job logs (`gh run view <id> --log-failed`).
   - Known env flakiness (keep the list in your workspace CLAUDE.md) → re-run the check once before touching code.
   - Real failure → fix in the worktree, re-run Phase 4 locally, commit, push, repeat.
   - After 3 distinct fix attempts on the same check, STOP and report state instead of thrashing.

## Phase 7 — Final report
- Ship summary table (repo | PR | CI status) plus **raw PR URLs** on their own lines for chat pasting. Jira keys and PRs as markdown links elsewhere.
- Diff summary per repo: `git -C <worktree> diff --stat origin/<default-branch>...HEAD`.
- Test evidence: the actual final suite summary line per repo.
- **Judgment calls** — every decision the user might disagree with: scope interpretations, naming choices, dismissed reviewer findings, flake-vs-real CI retry decisions, convention picks, anything the ticket left ambiguous that was resolved without asking.
- Remind: after merge, move the session out of the worktree, then `/cleanup-worktrees`.
