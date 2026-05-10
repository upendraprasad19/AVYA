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

# ─────────────────────────────────────────────────────────────────────────────
# APK Test #13 — bug-fix commit gate.
#
# If the commit subject matches ^(fix|bug|regression)(\([^)]*\))?:
# the body MUST contain either:
#   closes-diagnose: <6+-hex-char-id>   — referencing docs/diagnoses/*-<id>.md
#                                         that passes validate_diagnose_doc.dart
#   regression-test-skipped: <reason>   — waiver; appended to docs/skipped-discipline.md
#
# feat:/chore:/docs:/test:/etc commits are NOT subject to this gate.
# ─────────────────────────────────────────────────────────────────────────────

COMMIT_MSG_FILE="${1:-.git/COMMIT_EDITMSG}"
if [ ! -f "$COMMIT_MSG_FILE" ]; then
  # No commit message file (amend or merge without message change) — skip gate.
  exit 0
fi

COMMIT_SUBJECT=$(head -n1 "$COMMIT_MSG_FILE")
COMMIT_BODY=$(tail -n +2 "$COMMIT_MSG_FILE")

if echo "$COMMIT_SUBJECT" | grep -qE '^(fix|bug|regression)(\([^)]*\))?:'; then
  echo "[pre-commit] bug-fix commit detected — checking discipline gate"

  CLOSES_ID=$(echo "$COMMIT_BODY" | grep -oE 'closes-diagnose:[[:space:]]*[a-f0-9]{6,}' | sed 's/.*:[[:space:]]*//' | head -1)
  SKIP_REASON=$(echo "$COMMIT_BODY" | grep -E '^regression-test-skipped:' | sed 's/^regression-test-skipped:[[:space:]]*//' | head -1)

  if [ -n "$CLOSES_ID" ]; then
    DIAGNOSE_FILE=$(ls docs/diagnoses/*-${CLOSES_ID}.md 2>/dev/null | head -1)
    if [ -z "$DIAGNOSE_FILE" ]; then
      echo "[pre-commit] FAIL: closes-diagnose: $CLOSES_ID — no file matching docs/diagnoses/*-${CLOSES_ID}.md"
      exit 1
    fi
    if ! dart run scripts/validate_diagnose_doc.dart "$DIAGNOSE_FILE" >/dev/null 2>&1; then
      echo "[pre-commit] FAIL: $DIAGNOSE_FILE does not validate"
      dart run scripts/validate_diagnose_doc.dart "$DIAGNOSE_FILE"
      exit 1
    fi
    echo "[pre-commit] OK: $DIAGNOSE_FILE validates"
  elif [ -n "$SKIP_REASON" ]; then
    echo "[pre-commit] WAIVER: $SKIP_REASON — logged to docs/skipped-discipline.md"
    SHA=$(git rev-parse HEAD 2>/dev/null || echo "<pending>")
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p docs
    echo "- $TIMESTAMP · $SHA · $SKIP_REASON" >> docs/skipped-discipline.md
  else
    echo "[pre-commit] FAIL: bug-fix commit subject ('$COMMIT_SUBJECT')"
    echo "             Body must contain either:"
    echo "               closes-diagnose: <6+-hex-char-id>"
    echo "               regression-test-skipped: <reason>"
    echo "             See docs/discipline.md."
    exit 1
  fi
fi

exit 0
