#!/bin/sh
# AVYA pre-push gate — full flutter test suite.
#
# Audit 2026-05-20 / I10: pre-commit runs the FAST path (analyze +
# contract tests + 38 gate scripts). The slow full `flutter test` (~7
# min on this machine) runs here at push-time instead, so:
#
#   - Daily commits aren't blocked by the long suite.
#   - The full suite STILL runs before code leaves the local machine.
#   - CI runs it again on push regardless.
#
# Install: `sh scripts/setup-hooks.sh` (one-shot per clone).
#
# Bypass: `git push --no-verify` (use sparingly; CI catches anyway).

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Pre-push receives refs on stdin. Read them so we don't break the hook
# protocol; we don't actually need them for the test gate.
cat > /dev/null

echo "[pre-push] flutter test (full suite, ~7 min on this machine)..."
flutter test

echo "[pre-push] OK — full suite green."
exit 0
