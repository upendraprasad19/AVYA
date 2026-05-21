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

install_hook "$REPO_ROOT/scripts/pre-commit.sh" "$REPO_ROOT/.git/hooks/pre-commit"
install_hook "$REPO_ROOT/scripts/pre-push.sh" "$REPO_ROOT/.git/hooks/pre-push"
install_hook "$REPO_ROOT/scripts/commit-msg.sh" "$REPO_ROOT/.git/hooks/commit-msg"

echo "[setup-hooks] verify: ls -la $REPO_ROOT/.git/hooks/{pre-commit,pre-push,commit-msg}"
