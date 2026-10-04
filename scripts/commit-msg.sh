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

# Resolve the Dart binary ONCE -- `flutter/bin/dart` is a wrapper that takes
# the SDK update lock and shells out to git on EVERY call (~4.0s vs ~0.3s for
# the SDK exe, measured). See scripts/_dart_bin.sh. Falls back to `dart`.
if [ -r "$REPO_ROOT/scripts/_dart_bin.sh" ] && sh -n "$REPO_ROOT/scripts/_dart_bin.sh" 2>/dev/null; then
  . "$REPO_ROOT/scripts/_dart_bin.sh" || true
  DART_BIN="$(resolve_dart_bin)" 2>/dev/null || DART_BIN="dart"
else
  # Guarded, and the guard is load-bearing: this file runs under `set -e`, so an
  # unguarded `.` of a missing file ABORTS the hook outright. `_dart_bin.sh`.s
  # own contract is "never wedge a hook", and sourcing it must honour that too.
  #
  # `[ -r ]` covers ABSENT. It does NOT cover CORRUPT: a truncated or
  # syntactically broken helper passes the readable test and then dies inside
  # `set -e`, wedging commit, push, merge AND commit-msg at once. Review round 1
  # (2026-08-17) reproduced it -- a stray paren in the helper made a merge exit 1
  # with `syntax error near unexpected token`.
  #
  # `. file || true` DOES NOT FIX THAT, and was tried first: POSIX requires a
  # non-interactive shell to ABORT on a syntax error in a dotted script, so the
  # `||` never runs. Verified -- it still exited 2. The working guard is a parse
  # check BEFORE sourcing (`sh -n`), which reads the file without executing it;
  # the `|| true` and the `|| DART_BIN="dart"` below then cover the remaining
  # runtime failures. Corrupt now falls back to a bare `dart` and the hook runs.
  # Caught by test/scripts/pre_push_analyze_always_e2e_test.dart, which builds a
  # temp repo holding only the hook script -- the same shape as a partial
  # checkout or a hook copied somewhere without its helper.
  DART_BIN="dart"
fi

COMMIT_MSG_FILE="$1"
if [ -z "$COMMIT_MSG_FILE" ] || [ ! -f "$COMMIT_MSG_FILE" ]; then
  echo "[commit-msg] ERROR: no message file provided (got: '$COMMIT_MSG_FILE')" >&2
  exit 1
fi

COMMIT_SUBJECT=$(head -n1 "$COMMIT_MSG_FILE")
COMMIT_BODY=$(tail -n +2 "$COMMIT_MSG_FILE")

# ── closes-oi gate ────────────────────────────────────────────────────────────
# Runs BEFORE the bug-fix subject test below, deliberately. That test exits 0 for
# any non-fix: subject, and OI closures overwhelmingly land in docs(...) commits
# — `f15cb1f3 docs(closure): close OI-47 and OI-51` is exactly the shape. Placed
# after the early exit, this gate would never fire on the commits it exists for.
#
# docs/audit/open_issues.md documents the `closes-oi: OI-NN` convention; it was
# followed in 5 citation lines across 3 of the last 400 commits and enforced by
# nothing. The gate itself decides by comparing the HEAD blob against the staged
# blob, never by parsing diff text (see its header for why).
if ! "$DART_BIN" run scripts/check_closes_oi_cited.dart "$COMMIT_MSG_FILE"; then
  exit 1
fi

if ! echo "$COMMIT_SUBJECT" | grep -qE '^(fix|bug|regression)(\([^)]*\))?:'; then
  # Not a strict bug-fix commit; mandatory gate not applicable.
  #
  # NARROW HEURISTIC (warn-only, P1.G discipline-overhaul 2026-06-18):
  # If the subject is feat:/refactor:/chore: but the body reads like a bug fix
  # (whole-word match for bug/regression/broke/broken, or the phrase "fixes a"),
  # suggest adding a closes-diagnose: ref.  This is advisory — never blocks —
  # to avoid training the --no-verify reflex (see feedback_mistake_no_verify_reflex.md).
  if echo "$COMMIT_SUBJECT" | grep -qE '^(feat|refactor|chore)(\([^)]*\))?:'; then
    if echo "$COMMIT_BODY" | grep -qiE '\bbug\b|\bregression\b|\bbroke\b|\bbroken\b|fixes a'; then
      echo "[commit-msg] HINT: commit subject is '$(echo "$COMMIT_SUBJECT" | cut -d: -f1):' but the body"
      echo "             mentions bug/regression/broke/broken. If this is a bug fix, consider:"
      echo "               closes-diagnose: <6+-hex-char-id>"
      echo "             (This is advisory — your commit is NOT blocked.)"
    fi
  fi
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
  if ! "$DART_BIN" run scripts/validate_diagnose_doc.dart "$DIAGNOSE_FILE" >/dev/null 2>&1; then
    echo "[commit-msg] FAIL: $DIAGNOSE_FILE does not validate"
    "$DART_BIN" run scripts/validate_diagnose_doc.dart "$DIAGNOSE_FILE"
    exit 1
  fi
  echo "[commit-msg] OK: $DIAGNOSE_FILE validates"
elif [ -n "$SKIP_REASON" ]; then
  echo "[commit-msg] WAIVER: $SKIP_REASON — logged to docs/skipped-discipline.md"
  # THE SHA HERE IS THE PARENT, NOT THE WAIVED COMMIT — and it is now labelled
  # as such. `commit-msg` runs BEFORE the commit object exists, so
  # `git rev-parse HEAD` can only ever return the commit this one is being
  # built ON TOP OF. Every entry in the ledger written before 2026-08-17
  # therefore cites the parent while reading like it cites the waived commit,
  # which sends an auditor to a commit whose message contains no waiver at all.
  #
  # Found while retiring this batch's worktree: the ledger said `7683f54f` for a
  # waiver that lives in `5a3ac089`, its child.
  #
  # Recording `after:<parent>` plus the BRANCH makes it resolvable without
  # guessing — `git log --first-parent <branch>` finds the commit whose parent
  # is that sha, deterministically. A post-commit hook could stamp the real sha
  # instead, but that is a sixth hook and a new install surface for a
  # one-line labelling problem.
  PARENT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "<unborn>")
  WAIVER_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<detached>")
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p docs
  echo "- $TIMESTAMP · after:$PARENT_SHA on $WAIVER_BRANCH · $SKIP_REASON" \
    >> docs/skipped-discipline.md
else
  echo "[commit-msg] FAIL: bug-fix commit subject ('$COMMIT_SUBJECT')"
  echo "             Body must contain either:"
  echo "               closes-diagnose: <6+-hex-char-id>"
  echo "               regression-test-skipped: <reason>"
  echo "             See docs/discipline.md."
  exit 1
fi

exit 0
