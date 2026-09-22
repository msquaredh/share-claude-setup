---
description: Fetch every repo under __WORKSPACE_DIR__ and fast-forward the ones sitting cleanly on their default branch; report everything else untouched
argument-hint: [repo ...]
---

Bring the local checkouts under `__WORKSPACE_DIR__/` up to date with origin.

Arguments: `$ARGUMENTS` — optional space-separated repo directory names. Default is every repo in the workspace.

## What "up to date" means here

- Every repo gets `git fetch --prune origin`. This only updates remote-tracking refs, so it is always safe.
- A repo is fast-forwarded (`git merge --ff-only origin/<default>`) only when it is checked out on its default branch, the working tree is clean, and it has no local commits ahead of origin.
- Anything else is left exactly as found and reported. Never `pull`, `checkout`, `stash`, `reset`, or touch anything under `worktrees/`.

## Steps

1. **Sync in parallel.** Run this as one command. It prints one tab-separated line per repo: `<repo>  <STATUS>  [detail]`. Add any non-project dirs listed under `### Excluded from workflows` in your CLAUDE.md to the `grep -v` pattern so they are left alone.
   ```bash
   DEV=__WORKSPACE_DIR__
   ls -1 "$DEV" \
     | grep -v -E '^(worktrees|\.claude|node_modules)$' \
     | while read d; do [ -d "$DEV/$d/.git" ] && echo "$d"; done \
     | xargs -P 8 -I{} bash -c '
   d=$1; g="git -C '"$DEV"'/$1"
   out() { printf "%s\t%s\t%s\n" "$d" "$1" "$2"; exit 0; }
   $g fetch --quiet --prune origin 2>/dev/null || out FETCH_FAILED
   def=$($g rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed "s#^origin/##")
   [ -z "$def" ] && def=$($g ls-remote --symref origin HEAD 2>/dev/null | sed -n "s#^ref: refs/heads/##p" | cut -f1)
   [ -z "$def" ] && out NO_DEFAULT_BRANCH
   cur=$($g rev-parse --abbrev-ref HEAD)
   [ "$cur" != "$def" ] && out SKIPPED_ON_BRANCH "$cur"
   [ -n "$($g status --porcelain)" ] && out SKIPPED_DIRTY
   ahead=$($g rev-list --count "origin/$def..HEAD"); behind=$($g rev-list --count "HEAD..origin/$def")
   [ "$ahead" -gt 0 ] && out SKIPPED_DIVERGED "ahead=$ahead behind=$behind"
   [ "$behind" -eq 0 ] && out UP_TO_DATE
   $g merge --ff-only --quiet "origin/$def" >/dev/null 2>&1 && out FAST_FORWARDED "+$behind" || out FF_FAILED
   ' _ {} | sort
   ```
   If `$ARGUMENTS` is non-empty, replace the three producer lines (`ls` / `grep` / `while`) with `printf '%s\n' $ARGUMENTS \` so only those repos are processed.

2. **Report.** Group by status, most actionable first. One line per repo for anything skipped or failed; counts only for the rest.
   - `FETCH_FAILED` — network or auth; name each repo
   - `FF_FAILED` / `NO_DEFAULT_BRANCH` — unexpected; include detail
   - `SKIPPED_DIVERGED` — local commits on the default branch; the user decides what to do
   - `SKIPPED_DIRTY` — uncommitted changes on the default branch
   - `SKIPPED_ON_BRANCH` — a feature branch is checked out; show which
   - `FAST_FORWARDED` — count, plus commits pulled in per repo
   - `UP_TO_DATE` — count

## Hard rules

- `--ff-only` is the only merge mode. Never force, rebase, or resolve anything.
- Skipped repos are a report, not a problem to fix. Do not stash, commit, or switch branches to unblock a fast-forward.
- Do not touch `worktrees/`; those are in-flight branches managed by `/plan-ticket` and `/ship`.
