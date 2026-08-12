#!/bin/sh
# Installs the AVYA git hooks into .git/hooks/.
#
# Run once per fresh clone. Re-running is idempotent (overwrites both hooks
# from scripts/pre-commit.sh and scripts/commit-msg.sh).
#
# FOUR hooks are installed (see the install_hook calls below — the count said
# "three" while installing four since prepare-commit-msg joined them):
#   pre-commit        — 73 of 86 discipline gates + Gate 40 + conditional index
#                       regens. NO flutter analyze / flutter test on the default
#                       path (cost split 2026-08-11; PRE_COMMIT_LEGACY=1 or
#                       PRE_COMMIT_FULL=1 bring them back for one run).
#   pre-push          — flutter analyze ALWAYS, then the full flutter test suite
#                       when the pushed range is >=account (audit 2026-05-20 /
#                       I10 split; analyze added 2026-08-11).
#   commit-msg        — bug-fix discipline gate (closes-diagnose /
#                       regression-test-skipped) + the closes-oi gate.
#   prepare-commit-msg— auto-prepends the `Blast-radius:` line.
#
# NOTE these are COPIES, not shims: install_hook() does a plain `cp`, so editing
# scripts/*.sh changes nothing until this script is re-run. And it installs into
# `git rev-parse --git-common-dir`/hooks, which is SHARED BY EVERY WORKTREE —
# re-running from an unmerged branch changes the hooks for every concurrent
# session at once (memory/feedback_worktree_per_session.md).
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
# The pre-push hook runs analyze and (at >=account) the full flutter test suite,
# so the idle window GREW on 2026-08-11 rather than shrank: analyze now runs on
# EVERY push, including the feature-tier ones that skip the suite and previously
# idled for only a moment. git opens the
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
