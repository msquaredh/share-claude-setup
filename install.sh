#!/usr/bin/env bash
# Render templated CLAUDE.md + ship.md into your workspace.
#
# Usage:
#   ./install.sh
#
# Prompts for workspace dir, branch prefix, and Jira key, then writes:
#   <workspace>/CLAUDE.md
#   <workspace>/.claude/commands/ship.md
#
# Re-running overwrites both files.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read -rp "Workspace dir (absolute path, e.g. /Users/alice/code): " WORKSPACE_DIR
read -rp "Branch prefix (your username, e.g. alice): " BRANCH_PREFIX
read -rp "Jira project key (e.g. FMX, or 'none' if no Jira): " JIRA_KEY

if [[ -z "$WORKSPACE_DIR" || -z "$BRANCH_PREFIX" || -z "$JIRA_KEY" ]]; then
  echo "All three fields are required." >&2
  exit 1
fi

if [[ ! -d "$WORKSPACE_DIR" ]]; then
  echo "Workspace dir does not exist: $WORKSPACE_DIR" >&2
  exit 1
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

render "$here/CLAUDE.md" > "$WORKSPACE_DIR/CLAUDE.md"
render "$here/ship.md" > "$WORKSPACE_DIR/.claude/commands/ship.md"

echo
echo "Installed:"
echo "  $WORKSPACE_DIR/CLAUDE.md"
echo "  $WORKSPACE_DIR/.claude/commands/ship.md"
echo
echo "Open Claude Code with $WORKSPACE_DIR as CWD. Type /ship to confirm it loaded."
echo "Edit $WORKSPACE_DIR/CLAUDE.md to fill in the Repo Map section with your repos."
