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

# Base off the freshest main — whichever of `main` / `origin/main` is AHEAD.
#
# This used to prefer origin/main unconditionally whenever `git fetch` succeeded,
# calling it "the freshest main". That is only true when nothing is merged-but-
# unpushed — and §4.13's workflow is precisely *merge locally in the primary,
# then push*, so the stale window is STRUCTURAL, not a fluke.
#
# It bit for real on 2026-08-10: a worktree created after `gate-registry` merged
# to local main (f909cf35) but while the push was still in flight was based on
# be74bf63, WITHOUT the merged work, guaranteeing a conflict for a unit that
# touched the same files.
#
# Ordering matters: `git merge-base --is-ancestor A B` returns 0 when A == B, so
# identical refs satisfy BOTH tests. The equality case is handled FIRST and
# explicitly, so reordering the branches below cannot silently change behaviour.
#
# BOTH existence guards are required and the asymmetry was a real regression:
# the first version guarded only origin/main, so with a LOCAL main missing but
# origin/main present, `git rev-parse main` exits 128 and `set -e` aborts the
# whole script with a raw git error and no worktree created. The pre-diff code
# had no local-ref dependency at all and handled that case fine. Verified: a
# `set -e` script doing LOCAL_SHA="$(git rev-parse main)" in a repo without
# `main` exits 128 and never reaches the next line. (B-pass finding.)
BASE="main"
if ! git rev-parse --verify --quiet main >/dev/null; then
  # No local main. Fall back to origin/main if we can reach it, else let
  # `git worktree add` produce its own clear error rather than crashing here.
  if git fetch origin main --quiet 2>/dev/null &&
     git rev-parse --verify --quiet origin/main >/dev/null; then
    BASE="origin/main"
  fi
elif git fetch origin main --quiet 2>/dev/null &&
   git rev-parse --verify --quiet origin/main >/dev/null; then
  LOCAL_SHA="$(git rev-parse main)"
  REMOTE_SHA="$(git rev-parse origin/main)"
  if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
    BASE="main"                       # identical — either works
  elif git merge-base --is-ancestor main origin/main; then
    BASE="origin/main"                # local behind — remote is fresher
  elif git merge-base --is-ancestor origin/main main; then
    BASE="main"                       # merged-but-unpushed — LOCAL is fresher
  else
    # Genuinely diverged. WARN, do not exit: new-worktree.sh is the entry point
    # for ALL new work under §4.13 point 1, so hard-failing here is a ship-stop
    # for a hygiene problem — the error class §4.13 point 6 explicitly names.
    echo "⚠️  main and origin/main have DIVERGED (local $LOCAL_SHA / remote $REMOTE_SHA)." >&2
    echo "    Basing on local main. Reconcile them before merging this branch." >&2
    BASE="main"
  fi
fi
echo "→ basing '$SLUG' on $BASE ($(git rev-parse --short "$BASE"))"

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
