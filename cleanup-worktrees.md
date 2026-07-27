Clean up git worktrees for branches that have been merged.

## Instructions

1. **List all worktree branches**: Scan `__WORKSPACE_DIR__/worktrees/` for directories. Each top-level directory name is a branch name, and each subdirectory is a repo worktree.

2. **Check merge status**: For each branch, check if the PR was merged. For each repo worktree under that branch:
   ```bash
   # Get the GitHub org/repo from the remote URL
   remote_url=$(git -C __WORKSPACE_DIR__/<repo> remote get-url origin)
   # Check if a PR for this branch was merged
   gh pr list --repo <org/repo> --head <branch-name> --state merged --json number,title
   ```
   A branch is considered merged if ALL its repos have merged PRs (or if a repo had no PR created, meaning no changes were pushed).

3. **Clean up merged branches**: For each merged branch:
   ```bash
   # Remove each repo worktree
   git -C __WORKSPACE_DIR__/<repo> worktree remove \
     __WORKSPACE_DIR__/worktrees/<branch-name>/<repo>

   # Delete the local branch
   git -C __WORKSPACE_DIR__/<repo> branch -d <branch-name>
   ```
   Then remove the empty branch directory:
   ```bash
   rm -rf __WORKSPACE_DIR__/worktrees/<branch-name>
   ```

4. **Report unmerged branches**: For branches that are NOT fully merged, list them with their PR status (open, draft, no PR) so the user knows what's still in flight.

5. **Summary**: Print a summary showing:
   - How many branches were cleaned up
   - How many are still active
   - Any errors encountered (e.g., uncommitted changes in a worktree)

## Important
- If a worktree has uncommitted changes, warn the user and skip it — do NOT force remove
- Use `git worktree remove` (not `rm -rf`) to properly unregister the worktree
- If `branch -d` fails (branch not fully merged), warn the user rather than using `-D`
