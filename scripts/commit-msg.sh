#!/bin/sh
# AVYA bug-fix discipline gate (CLAUDE.md rule 22).
#
# Installed at .git/hooks/commit-msg — receives the path to the proposed
# commit message file as $1. This is the correct git lifecycle stage for
# message-content validation; doing the same check at pre-commit time
# fails for `-m` / `-F` / `--amend` commits because git doesn't update
# .git/COMMIT_EDITMSG until AFTER pre-commit runs.
#
# Split established 2026-05-11 during audit batch. Background: see
# docs/audit/2026-05-11/code-review-2026-05-11.md.
#
# If the commit subject matches ^(fix|bug|regression)(\([^)]*\))?:
# the body MUST contain either:
#   closes-diagnose: <6+-hex-char-id>   — referencing docs/diagnoses/*-<id>.md
#                                         that passes validate_diagnose_doc.dart
#   regression-test-skipped: <reason>   — waiver; appended to docs/skipped-discipline.md
#
# feat:/chore:/docs:/test:/refactor: commits are NOT subject to this gate.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

COMMIT_MSG_FILE="$1"
if [ -z "$COMMIT_MSG_FILE" ] || [ ! -f "$COMMIT_MSG_FILE" ]; then
  echo "[commit-msg] ERROR: no message file provided (got: '$COMMIT_MSG_FILE')" >&2
  exit 1
fi

COMMIT_SUBJECT=$(head -n1 "$COMMIT_MSG_FILE")
COMMIT_BODY=$(tail -n +2 "$COMMIT_MSG_FILE")

if ! echo "$COMMIT_SUBJECT" | grep -qE '^(fix|bug|regression)(\([^)]*\))?:'; then
  # Not a bug-fix commit; gate not applicable.
  exit 0
fi

echo "[commit-msg] bug-fix commit detected — checking discipline gate"

CLOSES_ID=$(echo "$COMMIT_BODY" | grep -oE 'closes-diagnose:[[:space:]]*[a-f0-9]{6,}' | sed 's/.*:[[:space:]]*//' | head -1)
SKIP_REASON=$(echo "$COMMIT_BODY" | grep -E '^regression-test-skipped:' | sed 's/^regression-test-skipped:[[:space:]]*//' | head -1)

if [ -n "$CLOSES_ID" ]; then
  DIAGNOSE_FILE=$(ls docs/diagnoses/*-${CLOSES_ID}.md 2>/dev/null | head -1)
  if [ -z "$DIAGNOSE_FILE" ]; then
    echo "[commit-msg] FAIL: closes-diagnose: $CLOSES_ID — no file matching docs/diagnoses/*-${CLOSES_ID}.md"
    exit 1
  fi
  if ! dart run scripts/validate_diagnose_doc.dart "$DIAGNOSE_FILE" >/dev/null 2>&1; then
    echo "[commit-msg] FAIL: $DIAGNOSE_FILE does not validate"
    dart run scripts/validate_diagnose_doc.dart "$DIAGNOSE_FILE"
    exit 1
  fi
  echo "[commit-msg] OK: $DIAGNOSE_FILE validates"
elif [ -n "$SKIP_REASON" ]; then
  echo "[commit-msg] WAIVER: $SKIP_REASON — logged to docs/skipped-discipline.md"
  SHA=$(git rev-parse HEAD 2>/dev/null || echo "<pending>")
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p docs
  echo "- $TIMESTAMP · $SHA · $SKIP_REASON" >> docs/skipped-discipline.md
else
  echo "[commit-msg] FAIL: bug-fix commit subject ('$COMMIT_SUBJECT')"
  echo "             Body must contain either:"
  echo "               closes-diagnose: <6+-hex-char-id>"
  echo "               regression-test-skipped: <reason>"
  echo "             See docs/discipline.md."
  exit 1
fi

exit 0
