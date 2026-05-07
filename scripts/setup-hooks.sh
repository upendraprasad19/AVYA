#!/bin/sh
# Installs the AVYA pre-commit hook into .git/hooks/pre-commit.
#
# Run once per fresh clone. Re-running is idempotent (overwrites the hook
# from scripts/pre-commit.sh).
#
# Windows: run from Git Bash (bundled with Git for Windows). cmd.exe and
# PowerShell will not execute the .sh file directly.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
SRC="$REPO_ROOT/scripts/pre-commit.sh"
DST="$REPO_ROOT/.git/hooks/pre-commit"

if [ ! -f "$SRC" ]; then
  echo "[setup-hooks] error: $SRC not found" >&2
  exit 1
fi

cp "$SRC" "$DST"
chmod +x "$DST" || true

echo "[setup-hooks] installed $DST"
echo "[setup-hooks] verify: ls -la $DST"
