#!/bin/sh
# AVYA pre-commit gate — analyze + test only (APK Test #12.6+).
#
# Blocks the commit if `flutter analyze` or `flutter test` fail.
# Runs from any working tree under the repo root.
#
# The bug-fix discipline gate (rule 22 — closes-diagnose / regression-test-skipped)
# lives in a separate commit-msg hook (scripts/commit-msg.sh) because pre-commit
# runs BEFORE the commit message is finalized and cannot reliably read it from
# COMMIT_EDITMSG. Split established 2026-05-11 during audit batch (see
# docs/audit/2026-05-11/code-review-2026-05-11.md "the -m / -F / amend hook bug").
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

# Audit 2026-05-20 / I10: pre-commit splits into FAST (here) + FULL
# (scripts/pre-push.sh). The full `flutter test` suite (~7 min) is moved
# to pre-push so commits aren't blocked on the slow run. CI runs full
# suite on every push regardless.
#
# Fast path: contract tests + analyzer + all 38 gates (~3 min).
# Heavy: flutter test (full suite, ~7 min) → runs on pre-push instead.
#
# Set PRE_COMMIT_FULL=1 to force the full suite locally (e.g. before a
# merge to main).
if [ "${PRE_COMMIT_FULL:-0}" = "1" ]; then
  echo "[pre-commit] PRE_COMMIT_FULL=1 → flutter test (full suite)..."
  flutter test
else
  echo "[pre-commit] flutter test test/contracts/ (fast path)..."
  flutter test test/contracts/
  echo "[pre-commit] (full suite deferred to pre-push hook. Set PRE_COMMIT_FULL=1 to force here.)"
fi

# Regen bug index if any diagnose-doc was modified (per CLAUDE.md decluttering spec §8)
if git diff --cached --name-only | grep -q '^docs/diagnoses/'; then
  echo "[pre-commit] Diagnose-docs touched — regenerating INDEX.md..."
  if ! dart run scripts/build_bug_index.dart; then
    echo "[pre-commit] FAIL: build_bug_index.dart errored."
    exit 1
  fi
  git add docs/diagnoses/INDEX.md
fi

# Regen ADR index if any ADR file was modified (six industry-gap closure 2026-05-28).
if git diff --cached --name-only | grep -qE '^docs/adr/[0-9]{4}-.*\.md$'; then
  echo "[pre-commit] ADR docs touched — regenerating INDEX.md..."
  if ! dart run scripts/build_adr_index.dart; then
    echo "[pre-commit] FAIL: build_adr_index.dart errored."
    exit 1
  fi
  git add docs/adr/INDEX.md
fi

# Regen incident index if any incident file was modified.
if git diff --cached --name-only | grep -qE '^docs/incidents/[0-9]{4}-.*\.md$'; then
  echo "[pre-commit] Incident docs touched — regenerating INDEX.md..."
  if ! dart run scripts/build_incident_index.dart; then
    echo "[pre-commit] FAIL: build_incident_index.dart errored."
    exit 1
  fi
  git add docs/incidents/INDEX.md
fi

# Regen handbook index if any handbook file was modified.
if git diff --cached --name-only | grep -qE '^docs/handbook/.+\.md$'; then
  echo "[pre-commit] Handbook touched — regenerating INDEX.md..."
  if ! dart run scripts/build_handbook_index.dart; then
    echo "[pre-commit] FAIL: build_handbook_index.dart errored."
    exit 1
  fi
  git add docs/handbook/INDEX.md
fi

# Naming convention discipline is documented in root CLAUDE.md §3.7.
# Pre-commit enforcement (scripts/check_naming_conventions.dart) is
# out of scope for this batch — the protocol relies on agent discipline.

# Run every scripts/check_*.dart gate (tech-debt audit 2026-05-20 finding I2).
# Previously 25 of 27 gate scripts were dormant — written but never wired.
# Allow-list (build-only or advisory) lives in scripts/check_gate_scripts_wired.dart.
# Each script accepts a --warn-only flag during its 24h smoke window;
# remove the flag once the gate is proven stable.
echo "[pre-commit] Running tech-debt audit gates (bounded-parallel)..."
# Lean-workflow batch (2026-06-01): the ~28 check_*.dart gates ran sequentially.
# Run them with BOUNDED concurrency (PRE_COMMIT_GATE_JOBS, default 4) to shave
# wall-time without spawning 28 Dart VMs at once (same OOM ceiling discipline as
# Gradle -Xmx on this 16 GB box). MUST preserve the literal `scripts/check_*.dart`
# glob below AND the `case "$GATE_NAME" in ... esac` allowlist — Gate 33
# (scripts/check_gate_scripts_wired.dart) detects wiring via exactly those two
# textual markers; dropping either would make every gate read as "unwired".
MAX_GATE_JOBS="${PRE_COMMIT_GATE_JOBS:-4}"
GATE_FAILDIR="$(mktemp -d)"
GATE_JOBS=0
for GATE in scripts/check_*.dart; do
  GATE_NAME="$(basename "$GATE")"
  # Skip build-only / advisory gates per check_gate_scripts_wired.dart allowlist.
  case "$GATE_NAME" in
    check_apk_size_within_bounds.dart|\
    check_app_version_matches_pubspec.dart|\
    check_telemetry_pii_classification.dart|\
    check_unawaited_has_error_sink.dart|\
    check_razorpay_key_flavor.dart|\
    check_migrations_live.dart|\
    check_onconflict_live_arbiter.dart|\
    check_regression_catalog.dart|\
    check_snapshot_contract.dart|\
    check_test_runtime_budget.dart)
      # Razorpay gate: .env.prod is user-only / gitignored secret state.
      # Other gates: require live DB / merge context / build artifact —
      # run via /build-apk skill, NOT pre-commit. See
      # scripts/check_gate_scripts_wired.dart allowlist for rationale.
      continue
      ;;
  esac
  # Run each gate in the background; a failing gate drops a marker file.
  (
    if ! dart run "$GATE" >/dev/null 2>&1; then
      echo "$GATE_NAME" > "$GATE_FAILDIR/$GATE_NAME"
    fi
  ) &
  GATE_JOBS=$((GATE_JOBS + 1))
  if [ "$GATE_JOBS" -ge "$MAX_GATE_JOBS" ]; then
    wait || true   # drain the batch (marker files carry pass/fail, not $?)
    GATE_JOBS=0
  fi
done
wait || true
# Aggregate: one marker file per failed gate (same UX as the old sequential loop).
GATE_FAIL=0
for MARK in "$GATE_FAILDIR"/*; do
  [ -e "$MARK" ] || continue   # no failures -> unexpanded glob -> skip
  FAILED_NAME="$(basename "$MARK")"
  echo "[pre-commit] GATE FAIL: $FAILED_NAME — re-run for details: dart run scripts/$FAILED_NAME"
  GATE_FAIL=1
done
rm -rf "$GATE_FAILDIR"
if [ "$GATE_FAIL" -ne 0 ]; then
  echo "[pre-commit] One or more gates failed. Fix root cause; do NOT use --no-verify."
  exit 1
fi

# Regression catalog walk — only on merge commits (per spec §9.2)
if git rev-parse --verify MERGE_HEAD >/dev/null 2>&1; then
  echo "[pre-commit] Merge commit detected — walking regression catalog..."
  if ! dart run scripts/check_regression_catalog.dart; then
    echo "[pre-commit] FAIL: regression catalog detected a missing or failing test."
    exit 1
  fi
fi

echo "[pre-commit] All decluttering gates passed."

# Lean-workflow batch (2026-06-01): non-blocking blast-radius reminder.
# Git hooks cannot invoke Claude skills, so the code-review skill's documented
# "auto-trigger at >=account" is really a PRINTED nudge here -- run /code-review
# (B-pass) manually before pushing a >=account change. Same preamble-tolerant
# extraction as prepare-commit-msg.sh:41-43; reads the STAGED diff (default mode).
# (This `case` block carries no check_*.dart names, so Gate 33's allowlist
# detection is unaffected.)
REMINDER_TIER=$(dart run scripts/blast_radius_from_diff.dart 2>/dev/null \
  | grep -oE 'Blast-radius: (feature|account|platform|catastrophic)' \
  | tail -1 | awk '{print $2}' || true)
case "$REMINDER_TIER" in
  account|platform|catastrophic)
    echo "[pre-commit] NOTE: blast-radius=$REMINDER_TIER (>=account) -- run /code-review (B-pass) before pushing."
    ;;
esac

echo "[pre-commit] OK"
exit 0
