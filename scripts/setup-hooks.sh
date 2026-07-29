#!/bin/sh
# Installs the AVYA git hooks into .git/hooks/.
#
# Run once per fresh clone. Re-running is idempotent (overwrites both hooks
# from scripts/pre-commit.sh and scripts/commit-msg.sh).
#
# Three hooks are installed:
#   pre-commit  — flutter analyze + 38 gates + contract tests (FAST path)
#                 plus full flutter test if PRE_COMMIT_FULL=1
#   pre-push    — full flutter test (audit 2026-05-20 / I10 split)
#   commit-msg  — bug-fix discipline gate (closes-diagnose / regression-test-skipped)
#
# Why two hooks? pre-commit runs BEFORE the commit message is finalized, so it
# can't reliably read the proposed message. `git commit -m`/`-F`/`--amend` all
# fail to update .git/COMMIT_EDITMSG before pre-commit fires. The discipline
# gate must run at commit-msg time (which receives the message file path
# as $1). Split established 2026-05-11 — see audit doc.
#
# Windows: run from Git Bash (bundled with Git for Windows). cmd.exe and
# PowerShell will not execute the .sh file directly.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"

# Hooks live in the COMMON git dir, not "$REPO_ROOT/.git/hooks".
#
# In a linked worktree `.git` is a FILE containing `gitdir: …`, not a directory,
# so the old `$REPO_ROOT/.git/hooks/pre-commit` path failed outright:
#   cp: failed to access '<worktree>/.git/hooks/pre-commit': Not a directory
# CLAUDE.md §4.13 requires every session to work in its own worktree, so the
# installer was broken in exactly the place the workflow mandates. Git also
# shares one hooks dir across all worktrees, so installing to the common dir is
# both the working path AND the correct one.
HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$HOOKS_DIR"

install_hook() {
  local src="$1"
  local dst="$2"
  if [ ! -f "$src" ]; then
    echo "[setup-hooks] error: $src not found" >&2
    exit 1
  fi
  cp "$src" "$dst"
  chmod +x "$dst" || true
  echo "[setup-hooks] installed $dst"
}

install_hook "$REPO_ROOT/scripts/pre-commit.sh" "$HOOKS_DIR/pre-commit"
install_hook "$REPO_ROOT/scripts/pre-push.sh" "$HOOKS_DIR/pre-push"
install_hook "$REPO_ROOT/scripts/commit-msg.sh" "$HOOKS_DIR/commit-msg"
install_hook "$REPO_ROOT/scripts/prepare-commit-msg.sh" "$HOOKS_DIR/prepare-commit-msg"

# SSH keepalive for pushes (2026-05-30 cross-check fix).
# The pre-push hook runs the full flutter test suite (~8 min). git opens the
# SSH connection to fetch ref advertisements BEFORE running the hook, then the
# connection sits idle for the whole suite — GitHub's SSH server drops the idle
# git-receive-pack channel, so the object transfer AFTER the gate passes dies
# with SIGPIPE (exit 141). ServerAliveInterval sends null packets during the
# hook to keep the connection alive. Repo-local config (not ~/.ssh/config) so
# it ships with the clone via this setup step and touches nothing global.
git -C "$REPO_ROOT" config core.sshCommand \
  "ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=30 -o TCPKeepAlive=yes"
echo "[setup-hooks] configured core.sshCommand keepalive (survives long pre-push)"

echo "[setup-hooks] verify: ls -la $HOOKS_DIR/{pre-commit,pre-push,commit-msg,prepare-commit-msg}"
