Sync the `## Repo Map` section in `__WORKSPACE_DIR__/CLAUDE.md` with what is actually present on disk.

## When to use

Run this whenever a new repo has been cloned into `__WORKSPACE_DIR__/` or an old one has been removed. The repo map informs how Claude reasons about which services to touch for a given task, so it should stay current.

## Instructions

1. **Sync checkouts first.** If `/pull-repos` is installed, invoke it (Skill tool, no arguments) so every repo is fetched and, where safe, fast-forwarded before anything is read. Keep its report: a repo it lists as skipped or failed has a working tree that may not match origin, so in step 5 read that repo's files with `git show origin/<default>:<path>` instead of from disk. If `/pull-repos` isn't installed, skip this step and say in the report that descriptions came from local checkouts as-is.

2. **List on-disk repos.** Get every top-level directory in `__WORKSPACE_DIR__/` and filter out non-repo entries:
   ```bash
   ls -1 __WORKSPACE_DIR__ \
     | grep -v -E '^(worktrees|\.claude|node_modules)$' \
     | while read d; do
         [ -d "__WORKSPACE_DIR__/$d/.git" ] && echo "$d"
       done
   ```
   Only directories containing `.git` count. Loose files (e.g. `CLAUDE.md`, ad-hoc notes) and known non-repo dirs are skipped.

3. **List mapped repos.** Read `__WORKSPACE_DIR__/CLAUDE.md` and extract every repo name from the `## Repo Map` section — the bolded token at the start of each bullet (e.g. `**api-service**`). Entries under an `### Excluded from workflows` subheading still count as mapped; they are listed there intentionally.

   **First run:** if `CLAUDE.md` doesn't exist or has no `## Repo Map` section, treat every on-disk repo as new and continue — step 6 covers proposing the section from scratch.

4. **Diff.**
   - **New on disk, not in map** → add.
   - **In map, not on disk** → flag for the user; do not silently remove. The user may have moved it intentionally.

5. **For each new repo, inspect — in parallel.** Run these reads concurrently per repo, then synthesize one line per repo. Do NOT read whole files; targeted reads only.
   - `README.md` — first ~40 lines for purpose
   - Build manifest to determine stack: `pom.xml` (Maven), `build.gradle.kts` / `build.gradle` (Gradle), `package.json` (Node/JS/TS), `Cargo.toml`, `requirements.txt`, etc.
   - `service.datadog.yaml` or similar service-metadata file if present — often has ownership and runbook hints
   - The entrypoint (e.g. `*Application.kt`, `main.go`, `index.ts`) to confirm framework if the manifest is ambiguous

6. **Classify into an existing category.** Read the headings inside `## Repo Map`. Use whatever categories the user has already set up (examples: `### Client App`, `### Backend Services`, `### Shared Libraries`, `### Data Processing Workers`, `### Infrastructure & Tooling`). If a repo doesn't cleanly fit any existing category, ask the user where it belongs rather than inventing a new one. If the map has no subheadings and is just a flat bullet list, append to that list.

   **First run (no `## Repo Map` yet):** group the inspected repos into a few sensible categories — or a flat list if there are only a handful — show the user the proposed section, and confirm the category names before writing. Non-project repos that happen to live in the workspace (dotfiles, editor config) go under `### Excluded from workflows` so future runs leave them alone.

7. **Write entries in the existing style.** Match whatever bullet format the user is already using. A common style is:
   ```
   - **<repo-name>** — <one-or-two-sentence description of purpose, stack, key consumers/dependencies>
   ```
   Guidelines for the description:
   - Lead with WHAT the service does in one phrase.
   - Mention the stack if non-obvious for that category (e.g. "Maven/Java" when most peers are Gradle/Kotlin).
   - Mention notable consumers or upstream dependencies if it clarifies the role.
   - If there's a relevant gotcha (fast-lane deploy, special build step, org-wide vs team-owned), tuck it at the end.

8. **Edit `__WORKSPACE_DIR__/CLAUDE.md`** using the `Edit` tool. Insert each new entry at the end of its category's bullet list. Do not reorder existing entries. On first run, append the new `## Repo Map` section to `CLAUDE.md` (creating the file if it doesn't exist).

9. **Report.** Print a short summary:
   - **Synced:** one line from `/pull-repos` (fast-forwarded N, skipped M, failed K), or "not installed"
   - **Added:** `<repo>` → `<category>`
   - **Stale (in map, not on disk):** `<repo>` — ask the user whether to remove
   - **No changes needed** — say so plainly

## Hard rules

- Never remove an existing map entry without explicit user confirmation.
- Never invent new categories; ask if a repo doesn't fit. (Exception: the first-run bootstrap, where you propose the initial set and the user confirms it.)
- The description comes from the repo's own README / build files — do not guess from the name alone. If the repo has neither README nor build manifest, ask the user what it is.
- Beyond the `/pull-repos` sync in step 1, this command is read-only against each repo — no checkouts, edits, or commits.
