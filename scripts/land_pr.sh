#!/usr/bin/env sh
# scripts/land_pr.sh <pr> [--allow-workflow-change] [--ci-only]
#
# Lands the PR of the CURRENT branch: syncs it with origin/main (scripts/sync_with_main.sh --commit), pushes it
# (scripts/safe_push.sh), waits for CI on the pushed head, checks that main and the PR head did not move (else another
# round, at most 3), replays CI's plan-review-record gate on the merge commit GitHub will create, then merges
# (scripts/safe_pr_merge.sh). Landing D of the merge-conflict-treadmill plan (docs/plans/merge-train.md, OI-309).
# The work is scripts/land_pr.dart; this wrapper only finds Dart, runs the CLI, forwards TERM/INT/HUP to it and owns the
# LAST stdout line (`result: ...`) for every exit the CLI cannot make. Invoking it is the instruction to push the branch's
# unpushed commits and to merge the PR (with `--ci-only`: to push, never to merge); run it from the branch's own worktree.
# It never touches another branch.
#
# `--ci-only` (review CI, CLAUDE.md §4.12.8): the same preconditions, sync, push and CI wait, then `result: ci-green`,
# exit 0, and nothing after the CI wait (no main-moved round, no record replay, no merge). `ci-green` is a review gate,
# not merge-readiness (CI ran on the merge ref GitHub computed when the run started). Exit 0 is shared with `merged`:
# read the `result:` word, never only the status.
#
# Exit codes (the CLI's): 0 merged (or ci-green with --ci-only), 1 needs-human, 2 refused (nothing changed yet), 3 ci-failed or ci-timeout,
# 4 error, 5 record-failed, 6 merge-refused, 7 merge-unverified. Any child status above 7 (a compile error 254, an async
# leak 255, a signal 128+n) is reported as `result: error`, exit 4. Only the PR number FIRST, then `--allow-workflow-change`
# and/or `--ci-only` (any order, each at most once), are accepted: the CLI's test seams are never forwarded.
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

usage="usage: sh scripts/land_pr.sh <pr> [--allow-workflow-change] [--ci-only]"
if [ "$#" -ge 1 ]; then
  case "$1" in
    --allow-workflow-change|--ci-only) refuse "the PR number comes first ($usage)" ;;
  esac
fi
case "$#" in
  1|2|3) ;;
  *) refuse "$usage" ;;
esac
pr_arg=$1
shift
seen_wf=0
seen_ci=0
for a in "$@"; do
  case "$a" in
    --allow-workflow-change) [ "$seen_wf" = 0 ] || refuse "--allow-workflow-change given twice ($usage)"; seen_wf=1 ;;
    --ci-only) [ "$seen_ci" = 0 ] || refuse "--ci-only given twice ($usage)"; seen_ci=1 ;;
    *) refuse "unknown argument \"$a\" ($usage)" ;;
  esac
done
set -- "$pr_arg" "$@"
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
