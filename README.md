# Plan + Ship for Claude Code

Shareable version of Marlon's planning / shipping workflow for multi-repo work with git worktrees.

## What you get

- **`/plan`** — Not a file. Claude Code's built-in plan mode, shaped by `CLAUDE.md`. Plans auto-scaffold worktree setup, branch naming, phased implementation, and ship metadata.
- **`/ship`** — Slash command at `.claude/commands/ship.md`. Reads the plan's `## Ship Metadata`, commits, pushes, opens PRs across all listed repos, and transitions Jira.

## Install

```bash
chmod +x install.sh
./install.sh
```

You'll be asked for:
- **Workspace dir** — absolute path to the folder containing your repos (e.g. `/Users/alice/code`)
- **Branch prefix** — your username or initials, used for branch names like `alice/fmx-1234-add-rate-limits`
- **Jira project key** — e.g. `FMX`, or `none` if you don't use Jira

The script writes two files:
- `<workspace>/CLAUDE.md`
- `<workspace>/.claude/commands/ship.md`

Open Claude Code with `<workspace>` as its CWD. Type `/ship` to confirm it's loaded.

## After install — fill in the Repo Map

`CLAUDE.md` has a `## Repo Map` section with a single placeholder bullet. Replace it with one bullet per repo you work in. The planner uses these as hints to pick relevant repos without grepping everything.

Example:
```markdown
- **api-service** — Kotlin/Spring Boot REST API for customer accounts
- **worker-service** — Kafka consumer that enriches account events
- **shared-lib** — DTOs shared by api-service and worker-service
```

## Jira / Atlassian MCP

`ship.md` references the Atlassian MCP tools (`getTransitionsForJiraIssue`, `transitionJiraIssue`, `addCommentToJiraIssue`) abstractly. If you have the Atlassian MCP server configured, they'll resolve automatically. If not, Jira transitions will fail silently and ship will continue — PRs still get created.

If `Jira: none` in the plan's ship metadata, Jira is skipped entirely.

## How the flow works

1. Ask for a plan: `/plan add rate limits to api-service and worker-service for FMX-1234`
2. Claude fetches all repos, drafts a plan with worktrees, phases, and ship metadata. You review and accept.
3. Claude implements the changes in worktrees at `<workspace>/worktrees/<branch>/<repo>`.
4. You review the diff.
5. `/ship` — commits, pushes, opens PRs, moves the Jira ticket to In Review, posts PR links on the ticket.
6. `/cleanup-worktrees` (optional) — once PRs are merged, remove the worktrees.

## Customizing further

Edit `CLAUDE.md` freely — it's just instructions for Claude. Things people often tweak:
- The "Conventions" section (add team-specific rules)
- "Testing" section (add a link to your team's test doc, or repo-specific test commands)
- "Debugging & Investigation" (add pointers to your observability setup)

Edit `.claude/commands/ship.md` to customize commit message format, PR title format, or add extra steps (e.g., notify Slack).

## Files in this repo

| File | Purpose |
|---|---|
| `CLAUDE.md` | Templated workspace instructions |
| `ship.md` | Templated `/ship` slash command |
| `install.sh` | Renders the templates into your workspace |
| `README.md` | This file |

Placeholders in the templates: `__WORKSPACE_DIR__`, `__BRANCH_PREFIX__`, `__JIRA_KEY__`, `__JIRA_KEY_LOWER__`. The install script substitutes them.
