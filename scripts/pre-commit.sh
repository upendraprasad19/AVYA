#!/bin/sh
# AVYA pre-commit gate — analyze + test only (APK Test #12.6+).
#
# Blocks the commit if `flutter analyze` or `flutter test` fail.
# Runs from any working tree under the repo root.
#
# The bug-fix discipline gate (rule 22 — closes-diagnose / regression-test-skipped)
# lives in a separate commit-msg hook (scripts/commit-msg.sh) because pre-commit
# runs BEFORE the commit message is finalized and cannot reliably read it from
# COMMIT_EDITMSG. Split established 2026-05-11 during audit batch (see
# docs/audit/2026-05-11/code-review-2026-05-11.md "the -m / -F / amend hook bug").
#
# Setup: run `scripts/setup-hooks.sh` once per clone (Git Bash on Windows,
# bash/zsh on macOS/Linux). The .git/hooks/ directory is not version-
# controlled, so every developer must install locally.
#
# Bypass: `git commit --no-verify` (use sparingly — CI will still run
# the same gate).

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

echo "[pre-commit] flutter analyze..."
flutter analyze --no-fatal-infos

echo "[pre-commit] flutter test..."
flutter test

echo "[pre-commit] OK"
exit 0
