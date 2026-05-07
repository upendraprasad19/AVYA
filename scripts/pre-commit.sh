#!/bin/sh
# AVYA pre-commit gate (APK Test #12.6+).
#
# Blocks the commit if `flutter analyze` or `flutter test` fail.
# Runs from any working tree under the repo root.
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
