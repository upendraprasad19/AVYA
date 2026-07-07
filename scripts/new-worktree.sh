#!/usr/bin/env sh
# scripts/new-worktree.sh <slug>
#
# Create an isolated git worktree for a session's work. Per CLAUDE.md §4.13,
# EVERY Claude session that will edit/stage/commit MUST work in its own worktree
# (its own git index) — never directly in the shared main folder, whose index is
# shared with other sessions and mixes their files (2 incidents 2026-07-07).
#
# Usage:   sh scripts/new-worktree.sh <slug>
# Example: sh scripts/new-worktree.sh unit-c-error-checks
#          → .claude/worktrees/unit-c-error-checks  (branch: unit-c-error-checks)

set -e

SLUG="$1"
if [ -z "$SLUG" ]; then
  echo "usage: sh scripts/new-worktree.sh <slug>   (e.g. unit-c-error-checks)" >&2
  exit 2
fi

# Resolve the PRIMARY worktree root (the shared main folder) — the FIRST entry of
# `git worktree list`, NOT the current worktree (so `.claude/worktrees/<slug>` is
# always created under the main folder even when this helper is run from another
# worktree). `sub()` handles spaces in the path (e.g. ".../Claude Code/Fitness App").
ROOT="$(git worktree list --porcelain | awk '/^worktree /{sub(/^worktree /,""); print; exit}')"
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)"
fi
cd "$ROOT"

WT=".claude/worktrees/$SLUG"
if [ -e "$WT" ]; then
  echo "❌ worktree path already exists: $WT" >&2
  echo "   pick a different <slug>, or: git worktree remove $WT" >&2
  exit 1
fi
if git show-ref --verify --quiet "refs/heads/$SLUG"; then
  echo "❌ branch '$SLUG' already exists — pick a different <slug>." >&2
  exit 1
fi

# Base off the freshest main (origin/main if reachable, else local main).
BASE="main"
if git fetch origin main --quiet 2>/dev/null; then
  BASE="origin/main"
fi

git worktree add "$WT" -b "$SLUG" "$BASE"

# .env is gitignored (build-time --dart-define-from-file) — copy it so
# flutter build/test work inside the worktree.
if [ -f .env ]; then
  cp .env "$WT/.env"
  echo "copied .env → $WT/.env"
fi

echo ""
echo "✅ worktree ready (isolated git index — safe from other sessions):"
echo "    cd \"$ROOT/$WT\""
echo "Edit + commit THERE. When done: push the branch, then merge to main +"
echo "push (the main folder is integration-only)."
