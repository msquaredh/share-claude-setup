# Plan + Ship for Claude Code

Shareable version of Marlon's planning / shipping workflow for multi-repo work with git worktrees.

## What you get

- **`/plan-ticket`** — Slash command at `.claude/commands/plan-ticket.md`. Takes a ticket key, Jira URL, or free-text description; fetches all repos, researches read-only in plan mode, and presents a phased plan (worktree setup → implement → simplify → test → ship → cleanup) with the `## Ship Metadata` block that `/ship` consumes. In the Claude desktop app it also moves the session into the worktree so the built-in diff panel tracks the change.
- **`/ship`** — Slash command at `.claude/commands/ship.md`. Reads the plan's `## Ship Metadata`, commits, pushes, opens PRs across all listed repos, and transitions Jira.
- **`/ship-ticket`** — Skill at `.claude/skills/ship-ticket/SKILL.md`. Drives a ticket end to end with one human gate (plan approval): ticket intake → `/plan-ticket` → worktrees → implement → full test loop → adversarial self-review by a subagent → `/ship` → CI watch-and-fix loop → report with judgment calls. Requires the Atlassian MCP server plus `plan-ticket` and `ship` installed.
- **`/update-repo-map`** — Slash command at `.claude/commands/update-repo-map.md`. Scans your workspace for new repos and edits `CLAUDE.md` to add them in the existing category style, classified from their README + build manifest. Flags stale entries without removing them. Calls `/pull-repos` first when it's installed so descriptions come from current code.
- **`/pull-repos`** — Slash command at `.claude/commands/pull-repos.md`. Fetches every repo in the workspace in parallel and fast-forwards only the ones sitting cleanly on their default branch; everything else (feature branch checked out, dirty tree, local commits) is reported and left alone. Never touches `worktrees/`.
- **`/cleanup-worktrees`** — Slash command at `.claude/commands/cleanup-worktrees.md`. Removes worktrees and local branches whose PRs have merged; reports what's still in flight.
- **`/deploy-verify`** — Slash command at `.claude/commands/deploy-verify.md`. Read-only rollout verification: confirms what version actually deployed, checks pod status, diffs warn+error logs by version, compares APM to the prior version's baseline, and classifies every anomaly before giving a verdict. Requires the Datadog MCP server.
- **`/rca`** — Skill at `.claude/skills/rca/SKILL.md`. Root-causes a production alert end to end from an incident ID, monitor name, error message, or Datadog URL: identify → error signals → quantify → blast radius → trace → code path → Jira, under hard verification rules (fresh checkouts, widen the window before any "no data" claim, read the code that emits every log line you cite). Output is TL;DR first with per-claim confidence and an explicit Unverified section. Requires the Datadog MCP server.
- **`CLAUDE.md`** — Workspace instructions that enforce the worktree invariants (branch naming, ship metadata, fetch-before-explore) on any planning request, hold your Repo Map, and carry the verification / build / schema / code-change conventions that `/ship-ticket` and `/rca` lean on.

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
- `<workspace>/.claude/commands/pull-repos.md`
- `<workspace>/.claude/commands/cleanup-worktrees.md`
- `<workspace>/.claude/commands/deploy-verify.md`
- `<workspace>/.claude/skills/ship-ticket/SKILL.md`
- `<workspace>/.claude/skills/rca/SKILL.md`

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

You're only prompted for the values the selected skills actually use (workspace dir always; branch prefix and Jira key only for skills that reference them, like `plan-ticket`, `ship`, and `ship-ticket`; Datadog env tags only for `deploy-verify` and `rca`).

Notes for standalone installs:
- `/update-repo-map` bootstraps itself: on first run it scans your workspace, proposes a categorized `## Repo Map` section, and adds it to your `CLAUDE.md` after you confirm (creating the file if you don't have one). It uses `/pull-repos` when present and skips the sync otherwise.
- `/plan-ticket` and `/ship` are a pair — plans emit the `## Ship Metadata` block that `/ship` parses. Installing one without the other works but you lose the handoff.
- `/ship-ticket` composes `/plan-ticket` and `/ship`, so install all three. It also references the `Verification Before Claiming`, `Shell & Build Conventions`, `Schema & Data Model Conventions`, and `Code Changes` sections of `CLAUDE.md` — if you keep your own CLAUDE.md, copy those sections over (the installer reminds you).
- `/deploy-verify` and `/rca` need the Datadog MCP server configured; without it they tell you which checks they can't run rather than fake a verdict.
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

`CLAUDE.md` also ships two `<Add your org's …>` placeholders under `Shell & Build Conventions` and `Schema & Data Model Conventions`. Fill them in (toolchain pins, token locations, DDL rules) or delete the lines.

## Jira / Atlassian MCP

`plan-ticket.md`, `ship.md`, `ship-ticket/SKILL.md`, and `rca/SKILL.md` reference the Atlassian MCP tools (`getJiraIssue`, `getTransitionsForJiraIssue`, `transitionJiraIssue`, `addCommentToJiraIssue`, `searchJiraIssuesUsingJql`) abstractly. If you have the Atlassian MCP server configured, they'll resolve automatically. If not, planning falls back to asking you to paste the ticket, ship's Jira transitions fail gracefully (PRs still get created), and `/rca` skips the Jira step. `/ship-ticket` is the exception: it refuses to guess ticket scope and stops if the MCP is down.

If `Jira: none` in the plan's ship metadata, Jira is skipped entirely.

## How the flow works

1. Ask for a plan: `/plan-ticket ABC-1234` (or `/plan-ticket add rate limits to api-service`)
2. Claude fetches all repos, researches in plan mode, and drafts a plan with worktrees, phases, and ship metadata. You review and accept.
3. Claude implements the changes in worktrees at `<workspace>/worktrees/<branch>/<repo>`. In the desktop app the session moves into the worktree so the diff panel follows along.
4. You review the diff.
5. `/ship` — commits, pushes, opens PRs, moves the Jira ticket to In Review, posts PR links on the ticket.
6. `/cleanup-worktrees` — once PRs are merged, remove the worktrees and local branches.

Or collapse steps 1–5 into one run: `/ship-ticket ABC-1234`. You approve the plan once; Claude implements, tests until green, has a subagent hunt for problems in the diff, ships, watches CI, and hands back a report with every judgment call it made.

Between tickets, `/pull-repos` keeps the local checkouts current without touching anything in flight.

## Customizing further

Edit `CLAUDE.md` freely — it's just instructions for Claude. Things people often tweak:
- The "Conventions" section (add team-specific rules)
- "Testing" section (add a link to your team's test doc, or repo-specific test commands)
- "Debugging & Investigation" (add pointers to your observability setup)
- "Shell & Build Conventions" (toolchain pins, known CI flakes that `/ship-ticket` should retry once before touching code)

Edit the files under `.claude/commands/` and `.claude/skills/` to customize commit message format, PR title format, or add extra steps (e.g., notify Slack).

## Files in this repo

| File | Purpose |
|---|---|
| `CLAUDE.md` | Templated workspace instructions |
| `plan-ticket.md` | Templated `/plan-ticket` slash command |
| `ship.md` | Templated `/ship` slash command |
| `ship-ticket/SKILL.md` | Templated `/ship-ticket` skill |
| `update-repo-map.md` | Templated `/update-repo-map` slash command |
| `pull-repos.md` | Templated `/pull-repos` slash command |
| `cleanup-worktrees.md` | Templated `/cleanup-worktrees` slash command |
| `deploy-verify.md` | Templated `/deploy-verify` slash command |
| `rca/SKILL.md` | Templated `/rca` skill |
| `install.sh` | Renders the templates into your workspace |
| `README.md` | This file |

Flat `<name>.md` files install to `.claude/commands/`; `<name>/SKILL.md` directories install to `.claude/skills/<name>/`, mirroring Claude Code's own layout.

Placeholders in the templates: `__WORKSPACE_DIR__`, `__BRANCH_PREFIX__`, `__JIRA_KEY__`, `__JIRA_KEY_LOWER__`, `__ENV_TAG_DEV__`, `__ENV_TAG_TEST__`, `__ENV_TAG_PROD__`. The install script substitutes them.
