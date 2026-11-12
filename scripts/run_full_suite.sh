#!/usr/bin/env sh
# scripts/run_full_suite.sh -- the LOCAL full test suite, one at a time on this machine.
#
#   sh scripts/run_full_suite.sh        (no arguments; run it in the BACKGROUND: 77-116 min on the VPS)
#
# Runs exactly CI's invocation (`.github/workflows/test.yml`: TZ Asia/Kolkata, `flutter test test/ --exclude-tags
# golden`) under the machine-wide lock of scripts/_suite_lock.sh: a second local full suite WAITS for the first
# instead of competing for the 4 cores. Exits with the suite's status.
#
# Review rounds take the full suite from CI, not from here (CLAUDE.md §4.12.8: `sh scripts/land_pr.sh <pr>
# --ci-only`). Use this only when a LOCAL full run is needed (e.g. a catastrophic batch, whose commit is gated on a
# review of the staged diff, so CI cannot run first). Plan: docs/plans/review-ci-suite-lock.md.
#
# The suite runs with AVYA_SUITE_LOCK_HELD=1 (a hook run inside it must not wait on this lock) and with fd 9
# closed (`9>&-`: no test child can hold the lock). Tests: test/scripts/suite_lock_e2e_test.dart.

set -u

if [ "$#" -ne 0 ]; then
  echo "usage: sh scripts/run_full_suite.sh   (no arguments: it runs CI's full-suite invocation)" >&2
  exit 2
fi

rfs_self=$(printf '%s' "$0" | tr '\\' '/')
case "$rfs_self" in
  */*) rfs_here=$(dirname "$rfs_self") ;;
  *) rfs_here=. ;;
esac
rfs_here=$(cd "$rfs_here" 2>/dev/null && pwd) || {
  echo "run_full_suite: cannot locate the scripts directory next to $0" >&2
  exit 2
}
rfs_top=$(git -C "$rfs_here" rev-parse --show-toplevel 2>/dev/null) || {
  echo "run_full_suite: $rfs_here is not inside a git work tree" >&2
  exit 2
}
cd "$rfs_top" || exit 2

. "$rfs_here/_suite_lock.sh"
suite_lock_acquire || exit 1

rfs_start=$(date +%s)
echo "[run_full_suite] $(date '+%Y-%m-%d %H:%M:%S %z') full suite started in $rfs_top"
AVYA_SUITE_LOCK_HELD=1 TZ=Asia/Kolkata flutter test test/ --exclude-tags golden 9>&-
rfs_rc=$?
echo "[run_full_suite] $(date '+%Y-%m-%d %H:%M:%S %z') full suite ended: exit $rfs_rc after $(( $(date +%s) - rfs_start ))s"
exit "$rfs_rc"
