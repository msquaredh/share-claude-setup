#!/usr/bin/env bash
# Render the templated CLAUDE.md and slash commands into your workspace.
#
# Usage:
#   ./install.sh                     # full install: CLAUDE.md + every skill
#   ./install.sh --only <skills>     # comma-separated subset, e.g. --only update-repo-map,cleanup-worktrees
#   ./install.sh --list              # show available skills
#   ./install.sh --repo-map-only     # alias for --only update-repo-map
#
# Skills install to <workspace>/.claude/commands/<skill>.md. The full install
# also writes <workspace>/CLAUDE.md; --only NEVER touches CLAUDE.md, so it is
# safe for a workspace that already has one.
#
# You are prompted only for the values the selected files actually use:
# workspace dir always; branch prefix, Jira key, and Datadog env tags only
# when a selected template contains those placeholders.
#
# Re-running overwrites whatever it installs.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKILLS=(plan-ticket ship update-repo-map cleanup-worktrees deploy-verify)

skill_desc() {
  # Description = frontmatter `description:` if the file starts with ---, else its first line
  local f="$1"
  if [[ "$(head -n 1 "$f")" == "---" ]]; then
    sed -n 's/^description: *//p' "$f" | head -n 1
  else
    head -n 1 "$f"
  fi
}

list_skills() {
  echo "Available skills:"
  for s in "${SKILLS[@]}"; do
    echo "  $s — $(skill_desc "$here/$s.md" | cut -c1-100)"
  done
}

is_skill() {
  local name="$1" s
  for s in "${SKILLS[@]}"; do
    [[ "$s" == "$name" ]] && return 0
  done
  return 1
}

MODE=full
ONLY=""
case "${1:-}" in
  "") MODE=full ;;
  --list) list_skills; exit 0 ;;
  --only) ONLY="${2:-}" ; MODE=only ;;
  --only=*) ONLY="${1#--only=}" ; MODE=only ;;
  --repo-map-only) ONLY="update-repo-map" ; MODE=only ;;
  *) echo "Unknown option: $1 (use --list, --only <skills>, or no args for full install)" >&2; exit 1 ;;
esac

selected=()
if [[ "$MODE" == "only" ]]; then
  if [[ -z "$ONLY" ]]; then
    echo "--only requires a comma-separated skill list, e.g. --only update-repo-map,cleanup-worktrees" >&2
    list_skills >&2
    exit 1
  fi
  IFS=',' read -ra requested <<< "$ONLY"
  for s in "${requested[@]}"; do
    s="$(echo "$s" | tr -d '[:space:]')"
    [[ -z "$s" ]] && continue
    if ! is_skill "$s"; then
      echo "Unknown skill: $s" >&2
      list_skills >&2
      exit 1
    fi
    selected+=("$s")
  done
  if [[ ${#selected[@]} -eq 0 ]]; then
    echo "No skills selected." >&2
    exit 1
  fi
else
  selected=("${SKILLS[@]}")
fi

# Templates being installed this run (used to decide which values to prompt for)
templates=()
for s in "${selected[@]}"; do
  templates+=("$here/$s.md")
done
if [[ "$MODE" == "full" ]]; then
  templates+=("$here/CLAUDE.md")
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

if grep -q '__BRANCH_PREFIX__' "${templates[@]}"; then
  read -rp "Branch prefix (your username, e.g. alice): " BRANCH_PREFIX
  if [[ -z "$BRANCH_PREFIX" ]]; then
    echo "Branch prefix is required for: ${selected[*]}" >&2
    exit 1
  fi
fi

if grep -q '__JIRA_KEY' "${templates[@]}"; then
  read -rp "Jira project key (e.g. ABC, or 'none' if no Jira): " JIRA_KEY
  if [[ -z "$JIRA_KEY" ]]; then
    echo "Jira project key is required for: ${selected[*]}" >&2
    exit 1
  fi
fi

JIRA_KEY_LOWER="$(echo "$JIRA_KEY" | tr '[:upper:]' '[:lower:]')"

ENV_TAG_DEV=""
ENV_TAG_TEST=""
ENV_TAG_PROD=""

if grep -q '__ENV_TAG_' "${templates[@]}"; then
  echo "Datadog env tags — the value your org puts in the 'env' tag per environment"
  echo "(press Enter to accept the default):"
  read -rp "  dev env tag [dev]: " ENV_TAG_DEV
  read -rp "  test env tag [test]: " ENV_TAG_TEST
  read -rp "  prod env tag [prod]: " ENV_TAG_PROD
  ENV_TAG_DEV="${ENV_TAG_DEV:-dev}"
  ENV_TAG_TEST="${ENV_TAG_TEST:-test}"
  ENV_TAG_PROD="${ENV_TAG_PROD:-prod}"
fi

render() {
  local src="$1"
  sed \
    -e "s|__WORKSPACE_DIR__|$WORKSPACE_DIR|g" \
    -e "s|__BRANCH_PREFIX__|$BRANCH_PREFIX|g" \
    -e "s|__JIRA_KEY_LOWER__|$JIRA_KEY_LOWER|g" \
    -e "s|__JIRA_KEY__|$JIRA_KEY|g" \
    -e "s|__ENV_TAG_DEV__|$ENV_TAG_DEV|g" \
    -e "s|__ENV_TAG_TEST__|$ENV_TAG_TEST|g" \
    -e "s|__ENV_TAG_PROD__|$ENV_TAG_PROD|g" \
    "$src"
}

mkdir -p "$WORKSPACE_DIR/.claude/commands"

installed=()
for s in "${selected[@]}"; do
  render "$here/$s.md" > "$WORKSPACE_DIR/.claude/commands/$s.md"
  installed+=("$WORKSPACE_DIR/.claude/commands/$s.md")
done

if [[ "$MODE" == "full" ]]; then
  render "$here/CLAUDE.md" > "$WORKSPACE_DIR/CLAUDE.md"
  installed+=("$WORKSPACE_DIR/CLAUDE.md")
fi

echo
echo "Installed:"
for f in "${installed[@]}"; do
  echo "  $f"
done
echo
echo "Open Claude Code with $WORKSPACE_DIR as CWD and type / to see the commands."
if [[ "$MODE" == "full" ]]; then
  echo "Edit $WORKSPACE_DIR/CLAUDE.md to fill in the Repo Map section with your repos,"
  echo "or run /update-repo-map to have Claude scan the workspace and populate it."
else
  echo "Your CLAUDE.md was not touched."
  if is_skill update-repo-map && [[ " ${selected[*]} " == *" update-repo-map "* ]]; then
    echo "If your CLAUDE.md has no '## Repo Map' section yet (or you have no CLAUDE.md),"
    echo "the first /update-repo-map run will propose one and create it after you confirm."
  fi
fi
