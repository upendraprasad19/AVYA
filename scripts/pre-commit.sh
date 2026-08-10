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

# Git exports GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE into every hook, and they
# override even `git -C <path>` — the documented env-leak class
# (feedback_mistake_git_hook_env_leak; see the header of
# scripts/plan_review_record_lib.dart for the same trap in test code).
#
# It bites here because `flutter` derives its own version by running
# `git -C "$FLUTTER_ROOT" describe`. With GIT_DIR leaked, that reads THIS repo
# instead of the SDK, so flutter reports `0.0.0-unknown` / `channel
# [user-branch]`, decides the SDK is unavailable, and fails dependency
# resolution with "depends on integration_test from sdk which doesn't exist" —
# a message that points at pubspec.yaml and not at the actual cause.
#
# Scoped to flutter deliberately: the git-dependent gates below (staged-diff
# blast radius, worktree guard, closure/index regen) still need the real git
# env, so this must NOT be a blanket `unset` at the top of the script.
flutter() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE flutter "$@"
}

echo "[pre-commit] flutter analyze..."
flutter analyze --no-fatal-infos

# Audit 2026-05-20 / I10: pre-commit splits into FAST (here) + FULL
# (scripts/pre-push.sh). The full `flutter test` suite (~7 min) is moved
# to pre-push so commits aren't blocked on the slow run. CI runs full
# suite on every push regardless.
#
# Fast path: contract tests + analyzer + the gate loop (~3 min). 86 gate files
# exist; the loop runs 71 (15 are case-skipped below). 2 of those 15
# (check_no_deferral_euphemism, check_skipped_discipline_budget) are invoked
# EXPLICITLY above, so real pre-commit coverage is 73 of 86 — quoting only "71"
# understates it the same way the old "38" overstated it.
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

# Regen the open-issues index whenever the board moves.
#
# THIS IS THE MECHANISM THE BOARD LACKED. open_issues.md went unread for 70 days
# while dozens of batches shipped; its own reconciliation section names the cause
# ("no gate, no hook, no CI job referenced it — everything with a gate holds,
# everything on intention decays") and then credits a fix,
# scripts/check_open_issues_reconciled.dart, that `git log --all` shows was never
# written. This regen is the real one.
if git diff --cached --name-only | grep -q '^docs/audit/open_issues\.md$'; then
  echo "[pre-commit] Open-issues board touched — regenerating OPEN_INDEX.md..."
  if ! dart run scripts/build_oi_index.dart; then
    echo "[pre-commit] FAIL: build_oi_index.dart errored."
    exit 1
  fi
  git add docs/audit/OPEN_INDEX.md
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

# Regen the gate index when any BAKED input changes.
#
# The trigger below is exhaustive over the baked inputs, and the qualifier
# matters: an earlier draft claimed "exactly covers" while omitting three
# sources. Note it is `scripts/*.dart`, NOT `scripts/check_*.dart` —
# validate_audit_closure.dart (Gate 40) and gate_index_lib.dart (which holds
# _extraGateScripts and the historical-aliases table) both feed BAKED columns
# and neither matches check_*. And BOTH closure-ledger filename conventions are
# listed: *_closures.yaml matches 6 files, *.closure.yaml matches 18 more.
#
# The 5 pre-existing collisions (Gates 7, 18, 19, 23, 44) were resolved in the
# commit that follows the one introducing this block, so --warn-only is gone and
# a duplicate number now BLOCKS. It existed for exactly one commit: without it,
# the introducing commit would have been blocked by its own hook and the
# collision baseline it produces could never have been written.
if git diff --cached --name-only | grep -qE '^(scripts/.+\.dart|\.claude/commands/build-apk\.md|docs/audit/([^/]+_closures\.yaml|[^/]+\.closure\.yaml|closed_issues\.md|gate_test_ledger\.yaml))$'; then
  echo "[pre-commit] Gate-index input touched — regenerating GATE_INDEX.md..."
  if ! dart run scripts/build_gate_index.dart; then
    echo "[pre-commit] FAIL: build_gate_index.dart errored."
    exit 1
  fi
  git add docs/audit/GATE_INDEX.md
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

# Naming convention discipline is documented in root CLAUDE.md §4.7.
# Pre-commit enforcement via scripts/check_naming_conventions.dart is
# wired automatically by the `for GATE in scripts/check_*.dart` loop below
# (tech-debt audit 2026-05-20 wiring — Gate 33 confirms every check_*.dart
# is covered). No manual invocation needed here.

# Gate 40: validate all docs/audit/ closure ledgers (P1.E, discipline-overhaul
# 2026-06-18). Enforces closed==N structural invariant: every item in a
# multi-item batch/audit must carry a terminal_state; non-terminal items fail.
# NOT in the check_*.dart loop (Gate 33 globs only check_*.dart names).
echo "[pre-commit] Gate 40: validate_audit_closure..."
if ! dart run scripts/validate_audit_closure.dart; then
  echo "[pre-commit] FAIL: audit closure ledger has invalid or non-terminal entries. Fix root cause; do NOT use --no-verify."
  exit 1
fi

# Run every scripts/check_*.dart gate (tech-debt audit 2026-05-20 finding I2).
# Previously 25 of 27 gate scripts were dormant — written but never wired.
# Allow-list (build-only or advisory) lives in scripts/check_gate_scripts_wired.dart.
# Each script accepts a --warn-only flag during its 24h smoke window;
# remove the flag once the gate is proven stable.
# P1.G (2026-06-18): the waiver-budget gate ran --warn-only during its §4.11
# baseline window, pending the 2 open waivers from 2026-05-11. BOTH are now
# marked "**resolved** 2026-06-19" in docs/skipped-discipline.md:5-6, so the
# script's own stated removal condition was met — and it exits 0 without the flag
# (verified by running it). The flag is gone; this is now a hard gate.
# Note it is ALSO in the case-skip list below, so it does not double-run.
echo "[pre-commit] Gate-SDB: check_skipped_discipline_budget..."
if ! dart run scripts/check_skipped_discipline_budget.dart; then
  echo "[pre-commit] FAIL: open skipped-discipline waivers older than 14 days (§4.11). Fix root cause; do NOT use --no-verify."
  exit 1
fi

# Gate-DEU (discipline audit 2026-06-27): flag deferral-EUPHEMISM phrases in the
# staged Markdown additions (CLAUDE.md §4.2 bans the semantic, not just "defer").
# HARD-FAIL since 2026-06-28 (baseline soak cleared — zero false positives). Kept
# as an explicit pre-commit-only invocation (scans the staged index; CI has no
# staged diff) + allow-listed from the check_*.dart loop to avoid a double-run.
echo "[pre-commit] Gate-DEU: check_no_deferral_euphemism..."
if ! dart run scripts/check_no_deferral_euphemism.dart; then
  echo "[pre-commit] FAIL: deferral euphemism in staged docs (§4.2). Fix root cause; do NOT use --no-verify."
  exit 1
fi

echo "[pre-commit] Running tech-debt audit gates (bounded-parallel)..."
# Lean-workflow batch (2026-06-01): the check_*.dart gates ran sequentially.
# 86 gate files exist; this loop runs 71 (15 case-skipped below).
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
    check_apk_release_signed.dart|\
    check_plan_review_record_exists.dart|\
    check_telemetry_pii_classification.dart|\
    check_unawaited_has_error_sink.dart|\
    check_razorpay_key_flavor.dart|\
    check_migrations_live.dart|\
    check_onconflict_live_arbiter.dart|\
    check_two_user_cross_account.dart|\
    check_regression_catalog.dart|\
    check_snapshot_contract.dart|\
    check_test_runtime_budget.dart|\
    check_no_deferral_euphemism.dart|\
    check_closes_oi_cited.dart|\
    check_skipped_discipline_budget.dart)
      # Razorpay gate: .env.prod is user-only / gitignored secret state.
      # Other gates: require live DB / merge context / build artifact —
      # run via /build-apk skill, NOT pre-commit. See
      # scripts/check_gate_scripts_wired.dart allowlist for rationale.
      # check_skipped_discipline_budget.dart: ships --warn-only (§4.11
      # gates-before-refactor baseline window — 2 pre-existing open waivers
      # from 2026-05-11 are >14d old; remove --warn-only once waivers are
      # resolved or a behavioral test ships). Invoked explicitly below.
      # check_closes_oi_cited.dart: a commit-msg gate — it takes the proposed
      # message file as its argument, and that file does not exist yet at
      # pre-commit time (the same reason scripts/commit-msg.sh exists at all).
      # This loop invokes every gate with NO arguments, so running it here would
      # only ever produce its usage error. Wired in scripts/commit-msg.sh.
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
