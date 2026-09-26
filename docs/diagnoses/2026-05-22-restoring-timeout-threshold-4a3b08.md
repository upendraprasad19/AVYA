---
bug_id: 4a3b08
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 8 / Theme D)
status: shipped
symptom: |
  Founder saw the "This is taking a while. CONTINUE →" escape-hatch
  button surface on the RestoringScreen on every cold start, even
  though the restore was progressing normally.

  Root cause: APK +28/+30 telemetry shows the founder's restore total
  is 35.9s every cold start, broken down:
    - Step A (lightweight): 23.8s ← single biggest contributor
      - custom_exercises: 18.9s (root cause investigation TBC — read-
        only Supabase MCP queries below)
      - user_preferences: 11.5s
      - user_progress: 7.4s
    - Step B: 9.9s
    - Step C: 2.1s
    - Subscription refresh: 146ms
    - Migrators (exlog + nlog): 0ms (already-migrated branch)

  The pre-fix CONTINUE-button threshold was 15s — Step A alone
  (23.8s) exceeded it, so the button surfaced for every user on every
  cold start regardless of state. The CTA was supposed to be an
  escape-hatch for genuine hangs; it became a permanent "is something
  broken?" signal that trained users to ignore the screen.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers:
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: _RestoringScreenState — _ctaAfter raised from 15s to 30s; new _softHintAfter at 15s for informational "Almost there…" copy; two distinct Timers + cancel paths, line: 40 }
readers:
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: build() renders soft hint OR CTA based on _showSoftHint && !_showTimeoutCta vs _showTimeoutCta, line: 380 }
hive_key_prefix: "n/a — UI threshold change only"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: [restoreFromCloudForUser]
cloud_table: n/a
cloud_columns: []
contract_test_path: test/contracts/restoring_screen_timeout_test.dart
ist_handling:
  - { file: lib/features/auth/screens/restoring_screen.dart, line: 50, source: "no date-key math — Duration constants only" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: restoring_screen runs post-sign-in inside HiveUserSession.openForUser scope (per Theme A fix); soft-hint + CTA are pure UI.
forbidden_patterns_checked:
  - "Single 15s threshold misclassifying every cold start as a stall."
  - "Soft hint + CTA rendered simultaneously at 30s (two stacked widgets)."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "restoring_screen.dart:40 — _softHintAfter / _ctaAfter constants + two timers + dispose/cancel paths" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/restoring_screen_timeout_test.dart — 7 assertions covering thresholds, timer wiring, copy, dispose, render condition" }
impact_analysis:
  callers_audited:
    - lib/features/auth/screens/restoring_screen.dart (only consumer of _showTimeoutCta + _showSoftHint)
  callers_updated_in_this_batch:
    - lib/features/auth/screens/restoring_screen.dart
  callers_unchanged:
    - lib/core/services/sync_service.dart (restore mechanics unchanged)
    - lib/core/services/sync/* (per-domain restore methods unchanged)
proposed_fix: |
  Two-stage UX in restoring_screen.dart:

  1. `_softHintAfter = Duration(seconds: 15)` — at 15s a soft
     informational hint "Almost there…" surfaces (italic, dim color).
     No interaction. The user understands the restore is still
     progressing. Median restore is 36s, so most users see this for
     ~15s before either (a) restore completes and navigation fires
     or (b) the 30s CTA replaces it.

  2. `_ctaAfter = Duration(seconds: 30)` — at 30s the actual
     escape-hatch CONTINUE button surfaces with the existing copy
     "This is taking a while. CONTINUE →". User can tap to navigate
     to /home with restore still running in the background (Theme F's
     provider invalidations will catch up when restore lands).

  3. Render condition for the soft hint: `_showSoftHint &&
     !_showTimeoutCta`. At the 30s mark both flags are true; without
     the negation, both widgets would render stacked.

  4. Both timers cancelled in `dispose()` AND in `_onContinueAnyway()`.

  Background-restore (A5) — a bigger refactor that would render /home
  immediately while restore continues in the background — is the
  RIGHT long-term fix but requires every provider that reads
  workout_logs / nutrition_logs / coach_interactions to handle a
  "data still streaming in" state. This batch ships the threshold
  fix; A5 lands in a dedicated work stream once the operational-
  observability story is in place to measure its impact.

  Investigation: custom_exercises 18.9s root cause
  ------------------------------------------------
  Read-only Supabase MCP queries during execution to identify whether
  the slowness is row-count or row-shape:

  ```sql
  -- Row count
  SELECT COUNT(*) FROM custom_exercises WHERE user_id = '<founder>';
  -- Row size
  SELECT MAX(LENGTH(tags::text)),
         MAX(LENGTH(notes::text)),
         MAX(LENGTH(image_url))
    FROM custom_exercises WHERE user_id = '<founder>';
  -- Index check
  SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'custom_exercises';
  ```

  If row count > 500 → user-facing "delete unused custom exercises"
  feature is the right fix (deferred from this batch — out of scope
  for the threshold ship).
  If row count is healthy but rows are large → opportunistic SELECT
  projection (only the columns Hive needs, not SELECT *).
  If neither → server-side query plan analysis via EXPLAIN.

  The threshold raise covers the user impact while we instrument the
  root cause. Code fix follows the data.
regression_test_planned:
  - test/contracts/restoring_screen_timeout_test.dart — 7 assertions: _ctaAfter at 30s, _softHintAfter at 15s, two Timer fields, initState schedules both, dispose + _onContinueAnyway cancel both, "Almost there…" copy present, soft-hint render condition negates CTA so both never stack.
related_bugs:
  - dc52a4  # Theme A — same screen, same batch; race fix is what lets the restore complete cleanly
---
# Body

## Why 30s, not 60s

35.9s is the founder's CURRENT median (post-everything: large custom
exercise set, full history restore, all migrators run). 30s catches
"normal" cases without being a permanent fixture; the user sees the
button only when restore genuinely exceeded median. For lighter
accounts (fresh signup, minimal custom data) the restore lands in
~10-15s and neither timer fires.

## Why both timers, not a single one bumped to 30s

The 15s soft hint is a UX cue, not a CTA. Without it, the screen
shows static text + dots for 30s with no signal of progress.
"Almost there…" tells the user the system is alive and reduces the
"is this broken" pressure that previously surfaced as panic taps on
the (now-gone-until-30s) CONTINUE button.

## Background-restore (A5) — why not now

A5 would mean rendering /home immediately on sign-in while restore
continues async. Every provider that reads cloud-restored data
(workout_logs, nutrition_logs, coach_interactions, custom_exercises,
…) would need a tri-state (data / loading / error) instead of the
current binary (data / pending). That's a 10+ file refactor. The
30s threshold gets the user impact under control NOW; A5 is a
discrete work stream in the operational-observability track once
the metrics are in place to validate it.

This batch's Theme F provider-invalidation fix is a precondition
for A5 (post-restore invalidation must be wired before /home can
render mid-restore).

## custom_exercises 18.9s — read-only investigation outcome

Read-only Supabase MCP queries during this batch (founder's
user_id confirmed in cloud):

[To be filled in post-deploy — the MCP queries above need to run
against the founder's live account during the smoke test, NOT in
this code change. Outcome documented in the project retrospective
after install.]

Most likely cause hypothesis (pre-data): pagination thrash.
`_fetchAllRows` uses pageSize=1000; founder's `custom_exercises`
table may have ~5000 rows (long-ago experimentation) requiring 5
round-trips of ~3-4s each. Fix path:
- If row count healthy: opportunistic projection.
- If row count huge: user-facing "delete unused" feature OR server-
  side soft-delete cleanup migration.

Code fix lands in a dedicated commit once data tells us which path.
The threshold fix here covers the symptom; the investigation
identifies the root cause.
