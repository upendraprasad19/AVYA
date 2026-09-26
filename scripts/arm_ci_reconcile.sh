#!/bin/sh
# Arms a CI-reconcile entry for a push that has just LANDED.
#
#   sh scripts/arm_ci_reconcile.sh [branch] [sha]
#
# Appends one JSON line to .claude/.ci_reconcile_pending.jsonl (gitignored).
# scripts/reconcile_ci.dart reads it at the next SessionStart, looks up what CI
# concluded for that SHA, and warns only if the answer is bad.
#
# CALLED FROM safe_push.sh's LANDED path, `|| true`-wrapped so it can never
# change a push's verdict. Also runnable by hand for a push made outside the
# wrapper.
#
# Deliberately dumb: append-only, no git mutation, no network, no dedup.
# Dedup happens on read (ci_reconcile_state_lib.dart), so a double-arm is
# harmless and this script has nothing that can fail interestingly.
#
# Exits 0 on every path a caller could reasonably hit. The one thing that
# matters is that it never, ever blocks the push it was called from.

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$REPO_ROOT" ] || exit 0

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"
SHA="${2:-$(git rev-parse HEAD 2>/dev/null)}"

# A detached HEAD reports the branch as "HEAD", which names no remote branch
# and would arm an entry that can never resolve. Nothing to record.
[ -n "$BRANCH" ] || exit 0
[ -n "$SHA" ] || exit 0
[ "$BRANCH" != "HEAD" ] || exit 0

STATE_DIR="$REPO_ROOT/.claude"
STATE_FILE="$STATE_DIR/.ci_reconcile_pending.jsonl"

# mkdir -p, because .claude/ is not guaranteed to exist — notably in the
# synthetic repos test/scripts/safe_push_test.dart builds, where the append
# would otherwise fail silently under the caller's `|| true`.
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# UTC ISO8601. `date -u +%FT%TZ` is POSIX-portable and matches what
# DateTime.tryParse accepts on the Dart side.
ARMED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || exit 0

printf '{"branch":"%s","sha":"%s","armed_at":"%s"}\n' \
  "$BRANCH" "$SHA" "$ARMED_AT" >> "$STATE_FILE" 2>/dev/null || exit 0

exit 0
