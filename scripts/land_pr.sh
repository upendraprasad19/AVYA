#!/usr/bin/env sh
# scripts/land_pr.sh <pr> [--allow-workflow-change]
#
# Lands the PR of the CURRENT branch: syncs it with origin/main (scripts/sync_with_main.sh --commit), pushes it
# (scripts/safe_push.sh), waits for CI on the pushed head, checks that main and the PR head did not move (else another
# round, at most 3), replays CI's plan-review-record gate on the merge commit GitHub will create, then merges
# (scripts/safe_pr_merge.sh). Landing D of the merge-conflict-treadmill plan (docs/plans/merge-train.md, OI-309).
# The work is scripts/land_pr.dart; this wrapper only finds Dart, runs the CLI, forwards TERM/INT/HUP to it and owns the
# LAST stdout line (`result: ...`) for every exit the CLI cannot make. Invoking it is the instruction to push the branch's
# unpushed commits and to merge the PR; run it from the branch's own worktree. It never touches another branch.
#
# Exit codes (the CLI's): 0 merged, 1 needs-human, 2 refused (nothing changed yet), 3 ci-failed or ci-timeout,
# 4 error, 5 record-failed, 6 merge-refused, 7 merge-unverified. Any child status above 7 (a compile error 254, an async
# leak 255, a signal 128+n) is reported as `result: error`, exit 4. Only the PR number and `--allow-workflow-change`, in
# that order, are accepted: the CLI's test seams are never forwarded.
#
# It operates on the repository of the CALLER's working directory but finds its .dart next to its OWN path. Never pipe it
# (a pipe replaces its exit code with the last stage's). Unbounded phases, for a supervisor: the sync with --commit, the
# push and the merge wrapper; only the CI wait, each fetch and each gh call have a deadline. A signal sent to the wrapper
# alone reaches only the Dart CLI, not its children (the running child finishes first); signal the wrapper's process group.

set -u

refuse() {
  echo "land_pr: refused: $1"
  echo "result: refused"
  exit 2
}

usage="usage: sh scripts/land_pr.sh <pr> [--allow-workflow-change]"
if [ "$#" -ge 1 ] && [ "$1" = "--allow-workflow-change" ]; then
  refuse "the PR number comes first ($usage)"
fi
case "$#" in
  1) ;;
  2) [ "$2" = "--allow-workflow-change" ] || refuse "unknown argument \"$2\" ($usage)" ;;
  *) refuse "$usage" ;;
esac
case "$1" in
  ''|*[!0-9]*) refuse "\"$1\" is not a PR number ($usage)" ;;
esac

self=$(printf '%s' "$0" | tr '\\' '/')
case "$self" in
  */*) here=$(dirname "$self") ;;
  *) here=. ;;
esac
here=$(cd "$here" 2>/dev/null && pwd) || refuse "cannot locate the scripts directory next to $0"

[ -f "$here/land_pr.dart" ] || refuse "$here/land_pr.dart is missing"
[ -f "$here/_dart_bin.sh" ] || refuse "$here/_dart_bin.sh is missing"
# shellcheck disable=SC1091
. "$here/_dart_bin.sh"
DART_BIN="$(resolve_dart_bin)"
if [ "$DART_BIN" = "dart" ] && ! command -v dart >/dev/null 2>&1; then
  refuse "no dart on the PATH"
fi

# run_dart_cli (scripts/_dart_bin.sh) owns the signal forwarding, the wait for the real status and the race retry.
run_dart_cli "$DART_BIN" "$here/land_pr.dart" "$@"
rc=$?

if [ "$rc" -gt 7 ]; then
  echo "land_pr: the CLI ended with status $rc"
  echo "result: error"
  exit 4
fi
exit "$rc"
