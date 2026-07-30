# Plan + Ship for Claude Code

Shareable version of Marlon's planning / shipping workflow for multi-repo work with git worktrees.

## What you get

- **`/plan-ticket`** — Slash command at `.claude/commands/plan-ticket.md`. Takes a ticket key, Jira URL, or free-text description; fetches all repos, researches read-only in plan mode, and presents a phased plan (worktree setup → implement → simplify → test → ship → cleanup) with the `## Ship Metadata` block that `/ship` consumes.
- **`/ship`** — Slash command at `.claude/commands/ship.md`. Reads the plan's `## Ship Metadata`, commits, pushes, opens PRs across all listed repos, and transitions Jira.
- **`/update-repo-map`** — Slash command at `.claude/commands/update-repo-map.md`. Scans your workspace for new repos and edits `CLAUDE.md` to add them in the existing category style, classified from their README + build manifest. Flags stale entries without removing them.
- **`/cleanup-worktrees`** — Slash command at `.claude/commands/cleanup-worktrees.md`. Removes worktrees and local branches whose PRs have merged; reports what's still in flight.
- **`/deploy-verify`** — Slash command at `.claude/commands/deploy-verify.md`. Read-only rollout verification: confirms what version actually deployed, checks pod status, diffs warn+error logs by version, compares APM to the prior version's baseline, and classifies every anomaly before giving a verdict. Requires the Datadog MCP server.
- **`CLAUDE.md`** — Workspace instructions that enforce the worktree invariants (branch naming, ship metadata, fetch-before-explore) on any planning request, and hold your Repo Map.

## Install

```bash
chmod +x install.sh
./install.sh
```

The full install writes:
- `<workspace>/CLAUDE.md`
- `<workspace>/.claude/commands/plan-ticket.md`
- `<workspace>/.claude/commands/ship.md`
- `<workspace>/.claude/commands/update-repo-map.md`
- `<workspace>/.claude/commands/cleanup-worktrees.md`
- `<workspace>/.claude/commands/deploy-verify.md`

You'll be prompted for:
- **Workspace dir** — absolute path to the folder containing your repos (e.g. `/Users/alice/code`)
- **Branch prefix** — your username or initials, used for branch names like `alice/abc-1234-add-rate-limits`
- **Jira project key** — e.g. `ABC`, or `none` if you don't use Jira
- **Datadog env tags** — what your org puts in the `env` tag for dev/test/prod (Enter accepts `dev`/`test`/`prod`)

Open Claude Code with `<workspace>` as its CWD. Type `/` to confirm the commands loaded.

> **Heads up:** the full install overwrites `<workspace>/CLAUDE.md`. If you already have a CLAUDE.md you want to keep, use `--only` below.

## Installing individual skills

Any skill can be installed on its own — your existing `CLAUDE.md` is never touched:

```bash
./install.sh --list                                  # see what's available
./install.sh --only update-repo-map                  # one skill
./install.sh --only plan-ticket,ship,cleanup-worktrees  # or several
```

You're only prompted for the values the selected skills actually use (workspace dir always; branch prefix and Jira key only for skills that reference them, like `plan-ticket` and `ship`).

Notes for standalone installs:
- `/update-repo-map` bootstraps itself: on first run it scans your workspace, proposes a categorized `## Repo Map` section, and adds it to your `CLAUDE.md` after you confirm (creating the file if you don't have one).
- `/plan-ticket` and `/ship` are a pair — plans emit the `## Ship Metadata` block that `/ship` parses. Installing one without the other works but you lose the handoff.
- `/deploy-verify` needs the Datadog MCP server configured; without it the command will tell you which checks it can't run rather than fake a verdict.
- `--repo-map-only` still works as an alias for `--only update-repo-map`.

## After install — fill in the Repo Map

`CLAUDE.md` has a `## Repo Map` section with a single placeholder bullet. Replace it with one bullet per repo you work in. The planner uses these as hints to pick relevant repos without grepping everything.

Example:
```markdown
- **api-service** — Kotlin/Spring Boot REST API for customer accounts
- **worker-service** — Kafka consumer that enriches account events
- **shared-lib** — DTOs shared by api-service and worker-service
```

Or skip the manual fill-in and run `/update-repo-map` — Claude will scan your workspace, classify each repo from its README + build manifest, and write the entries for you. Re-run it any time you clone a new repo.

## Jira / Atlassian MCP

`plan-ticket.md` and `ship.md` reference the Atlassian MCP tools (`getJiraIssue`, `getTransitionsForJiraIssue`, `transitionJiraIssue`, `addCommentToJiraIssue`) abstractly. If you have the Atlassian MCP server configured, they'll resolve automatically. If not, planning falls back to asking you to paste the ticket, and ship's Jira transitions fail gracefully — PRs still get created.

If `Jira: none` in the plan's ship metadata, Jira is skipped entirely.

## How the flow works

1. Ask for a plan: `/plan-ticket ABC-1234` (or `/plan-ticket add rate limits to api-service`)
2. Claude fetches all repos, researches in plan mode, and drafts a plan with worktrees, phases, and ship metadata. You review and accept.
3. Claude implements the changes in worktrees at `<workspace>/worktrees/<branch>/<repo>`.
4. You review the diff.
5. `/ship` — commits, pushes, opens PRs, moves the Jira ticket to In Review, posts PR links on the ticket.
6. `/cleanup-worktrees` — once PRs are merged, remove the worktrees and local branches.

## Customizing further

Edit `CLAUDE.md` freely — it's just instructions for Claude. Things people often tweak:
- The "Conventions" section (add team-specific rules)
- "Testing" section (add a link to your team's test doc, or repo-specific test commands)
- "Debugging & Investigation" (add pointers to your observability setup)

Edit the files under `.claude/commands/` to customize commit message format, PR title format, or add extra steps (e.g., notify Slack).

## Files in this repo

| File | Purpose |
|---|---|
| `CLAUDE.md` | Templated workspace instructions |
| `plan-ticket.md` | Templated `/plan-ticket` slash command |
| `ship.md` | Templated `/ship` slash command |
| `update-repo-map.md` | Templated `/update-repo-map` slash command |
| `cleanup-worktrees.md` | Templated `/cleanup-worktrees` slash command |
| `deploy-verify.md` | Templated `/deploy-verify` slash command |
| `install.sh` | Renders the templates into your workspace |
| `README.md` | This file |

Placeholders in the templates: `__WORKSPACE_DIR__`, `__BRANCH_PREFIX__`, `__JIRA_KEY__`, `__JIRA_KEY_LOWER__`, `__ENV_TAG_DEV__`, `__ENV_TAG_TEST__`, `__ENV_TAG_PROD__`. The install script substitutes them.
