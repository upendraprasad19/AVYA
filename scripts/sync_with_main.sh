#!/usr/bin/env sh
# scripts/sync_with_main.sh [--commit]
#
# Syncs the CURRENT branch with origin/main and resolves, by record, the conflicts that are two independent
# appends to a ledger (landing C2 of the merge-conflict-treadmill plan, docs/plans/sync-resolver.md, OI-309).
# The work is scripts/sync_with_main.dart; this wrapper only finds Dart, runs the CLI and owns the LAST
# stdout line (`result: ...`) for every exit the CLI cannot make itself.
#
#   sh scripts/sync_with_main.sh            merge origin/main without committing, resolve + stage what it can
#   sh scripts/sync_with_main.sh --commit   the same, then conclude the merge (a conflicted merge runs the full
#                                           pre-commit loop through scripts/safe_commit.sh and takes minutes:
#                                           run it in the background)
#
# Exit codes (the CLI's): 0 done, 1 the merge is pending and paths remain, 2 refused (nothing changed),
# 3 `--commit` failed, 4 internal error. Any child status above 4 (a compile error 254, an async leak 255, a
# signal 128+n) is reported as `result: error`, exit 4.
#
# It operates on the repository of the CALLER's working directory but finds its .dart next to its OWN path, so
# `sh <primary>/scripts/sync_with_main.sh` works in any worktree, including one cut before this script existed.
# Never pipe it (a pipe replaces its exit code with the last stage's; check_safe_wrapper_not_piped.dart only
# knows safe_commit.sh and safe_push.sh). Unbounded phases, for a supervisor: `git merge` and its hooks, the
# gate-index builder and `--commit`; only the fetch has a deadline. Signal the wrapper's process group: a signal sent to
# the wrapper alone reaches only the Dart CLI, not its children (after one, `git merge` or the commit of `--commit` may
# still finish although the wrapper has printed `result: error`).

set -u

refuse() {
  echo "sync_with_main: refused: $1"
  echo "result: refused"
  exit 2
}

case "$#" in
  0) ;;
  1) [ "$1" = "--commit" ] || refuse "unknown argument \"$1\" (usage: sh scripts/sync_with_main.sh [--commit])" ;;
  *) refuse "too many arguments (usage: sh scripts/sync_with_main.sh [--commit])" ;;
esac

self=$(printf '%s' "$0" | tr '\\' '/')
case "$self" in
  */*) here=$(dirname "$self") ;;
  *) here=. ;;
esac
here=$(cd "$here" 2>/dev/null && pwd) || refuse "cannot locate the scripts directory next to $0"

[ -f "$here/sync_with_main.dart" ] || refuse "$here/sync_with_main.dart is missing"
[ -f "$here/_dart_bin.sh" ] || refuse "$here/_dart_bin.sh is missing"
# shellcheck disable=SC1091
. "$here/_dart_bin.sh"
DART_BIN="$(resolve_dart_bin)"
if [ "$DART_BIN" = "dart" ] && ! command -v dart >/dev/null 2>&1; then
  refuse "no dart on the PATH"
fi

# run_dart_cli (scripts/_dart_bin.sh) owns the signal forwarding, the wait for the real status and the race retry.
run_dart_cli "$DART_BIN" "$here/sync_with_main.dart" "$@"
rc=$?

if [ "$rc" -gt 4 ]; then
  echo "sync_with_main: the CLI ended with status $rc"
  echo "result: error"
  exit 4
fi
exit "$rc"
