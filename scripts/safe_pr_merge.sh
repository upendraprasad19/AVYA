#!/usr/bin/env sh
# scripts/safe_pr_merge.sh <pr-number> [--allow-workflow-change]
#
# The sanctioned way to merge a pull request: merges ONLY when every required CI
# job is green on the PR's head commit, and refuses (exit 1) otherwise. See
# scripts/safe_pr_merge.dart for the rules and scripts/safe_pr_merge_lib.dart for
# the exact job names it requires.
#
# WHY: `main` has no required status checks, and pre-push no longer runs the
# local full suite for a BRANCH push (OI-275, docs/plans/2026-10-10-release-
# cycle-speedup.md) -- CI on the PR is the full-suite gate, and this wrapper is
# the control that makes "merge" depend on it.
#
# Only the PR number and, optionally, the literal `--allow-workflow-change` are
# forwarded, deliberately: the Dart program has a test-only `--gh` override that
# this entry point must never expose. `--allow-workflow-change` is the explicit
# "I read the .github/ diff" acknowledgement for a PR that edits CI configuration.
#
# A settings allow-rule should name THIS script, never raw `gh pr merge`:
#   Bash(sh scripts/safe_pr_merge.sh:*)
set -e

ALLOW=""
if [ "$#" -eq 2 ] && [ "$2" = "--allow-workflow-change" ]; then
  ALLOW="--allow-workflow-change"
elif [ "$#" -ne 1 ]; then
  echo "usage: sh scripts/safe_pr_merge.sh <pr-number> [--allow-workflow-change]" >&2
  exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ -r "$REPO_ROOT/scripts/_dart_bin.sh" ] && sh -n "$REPO_ROOT/scripts/_dart_bin.sh" 2>/dev/null; then
  . "$REPO_ROOT/scripts/_dart_bin.sh" || true
  DART_BIN="$(resolve_dart_bin)" 2>/dev/null || DART_BIN="dart"
else
  DART_BIN="dart"
fi

# `dart <file>` (not `dart run`): `dart run` prepends "Running build hooks..." to
# stdout, which would pollute the output of a wrapper people read.
if [ -n "$ALLOW" ]; then
  exec "$DART_BIN" scripts/safe_pr_merge.dart "$1" "$ALLOW"
fi
exec "$DART_BIN" scripts/safe_pr_merge.dart "$1"
