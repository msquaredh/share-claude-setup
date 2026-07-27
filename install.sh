#!/usr/bin/env bash
# Render templated CLAUDE.md, ship.md, and update-repo-map.md into your workspace.
#
# Usage:
#   ./install.sh                  # full install: CLAUDE.md + /ship + /update-repo-map
#   ./install.sh --repo-map-only  # just /update-repo-map; never touches CLAUDE.md
#
# Full install prompts for workspace dir, branch prefix, and Jira key, then writes:
#   <workspace>/CLAUDE.md
#   <workspace>/.claude/commands/ship.md
#   <workspace>/.claude/commands/update-repo-map.md
#
# Re-running the full install overwrites all three files. --repo-map-only writes
# only the update-repo-map command file and leaves everything else alone.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_MAP_ONLY=false
if [[ "${1:-}" == "--repo-map-only" ]]; then
  REPO_MAP_ONLY=true
elif [[ -n "${1:-}" ]]; then
  echo "Unknown option: $1 (only --repo-map-only is supported)" >&2
  exit 1
fi

read -rp "Workspace dir (absolute path, e.g. /Users/alice/code): " WORKSPACE_DIR

if [[ -z "$WORKSPACE_DIR" ]]; then
  echo "Workspace dir is required." >&2
  exit 1
fi

if [[ ! -d "$WORKSPACE_DIR" ]]; then
  echo "Workspace dir does not exist: $WORKSPACE_DIR" >&2
  exit 1
fi

BRANCH_PREFIX=""
JIRA_KEY=""
if ! $REPO_MAP_ONLY; then
  read -rp "Branch prefix (your username, e.g. alice): " BRANCH_PREFIX
  read -rp "Jira project key (e.g. ABC, or 'none' if no Jira): " JIRA_KEY

  if [[ -z "$BRANCH_PREFIX" || -z "$JIRA_KEY" ]]; then
    echo "All three fields are required." >&2
    exit 1
  fi
fi

JIRA_KEY_LOWER="$(echo "$JIRA_KEY" | tr '[:upper:]' '[:lower:]')"

render() {
  local src="$1"
  sed \
    -e "s|__WORKSPACE_DIR__|$WORKSPACE_DIR|g" \
    -e "s|__BRANCH_PREFIX__|$BRANCH_PREFIX|g" \
    -e "s|__JIRA_KEY_LOWER__|$JIRA_KEY_LOWER|g" \
    -e "s|__JIRA_KEY__|$JIRA_KEY|g" \
    "$src"
}

mkdir -p "$WORKSPACE_DIR/.claude/commands"

render "$here/update-repo-map.md" > "$WORKSPACE_DIR/.claude/commands/update-repo-map.md"

if $REPO_MAP_ONLY; then
  echo
  echo "Installed:"
  echo "  $WORKSPACE_DIR/.claude/commands/update-repo-map.md"
  echo
  echo "Open Claude Code with $WORKSPACE_DIR as CWD and run /update-repo-map."
  echo "If your CLAUDE.md has no '## Repo Map' section yet (or you have no CLAUDE.md),"
  echo "the first run will propose one and create it after you confirm."
  exit 0
fi

render "$here/CLAUDE.md" > "$WORKSPACE_DIR/CLAUDE.md"
render "$here/ship.md" > "$WORKSPACE_DIR/.claude/commands/ship.md"

echo
echo "Installed:"
echo "  $WORKSPACE_DIR/CLAUDE.md"
echo "  $WORKSPACE_DIR/.claude/commands/ship.md"
echo "  $WORKSPACE_DIR/.claude/commands/update-repo-map.md"
echo
echo "Open Claude Code with $WORKSPACE_DIR as CWD. Type /ship to confirm it loaded."
echo "Edit $WORKSPACE_DIR/CLAUDE.md to fill in the Repo Map section with your repos,"
echo "or run /update-repo-map to have Claude scan the workspace and populate it."
