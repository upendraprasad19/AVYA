---
bug_id: k7d3n5
date: 2026-09-22
batch: observation-batch-and-digest-redesign (post-push gate)
status: fixed
blast_radius: feature
symptom: |
  `sh scripts/safe_push.sh` FAILED with "Some tests failed." inside the
  pre-push hook's full CI-equivalent `flutter test test/ --exclude-tags
  golden` run, blocking the push of this batch's 2 already-landed commits
  (`0dcab614`, `96d7b91c`). The captured push log was truncated to a tail by
  the background-task output buffer, so the actual failure detail was not
  visible in it. Re-running the batch's own 10 new/modified test files in
  isolation reproduced exactly 1 of the (eventual) 4 full-suite failures:
  `test/contracts/alert_cron_failures_sync_test.dart: (setUpAll) [E]
  Expected: true / Actual: <false>`.
concept: alert_cron_failures_threshold_sync
sot_registry_entry: not_applicable
writers:
  - { file: alerts/_thresholds.yaml, method_or_widget: "cron_failures.defined_in_migration field", line: 77 }
readers:
  - { file: test/contracts/alert_cron_failures_sync_test.dart, method_or_widget: "setUpAll (migration file resolution)", line: 40 }
  - { file: test/contracts/alert_cron_failures_sync_test.dart, method_or_widget: "test 2 (stuck-branch time-bound assertion)", line: 64 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/alert_cron_failures_sync_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — source-grep test over static repo files (YAML + migration SQL text), no user data, no live DB read.
forbidden_patterns_checked:
  - "139_alert_cron_failures.sql; stuck-branch upper bound added by 140_hermes_pass_fixes_138_139.sql (compound prose string parsed as one non-existent file path)"
  - "(status = 'started' AND started_at < now() - interval '1 hour') asserted with no upper bound (the pre-migration-140 design this test used to pin)"
proposed_fix: |
  Two independent drifts, both introduced by the same B-pass Round 4b fix
  (Finding 4, "threshold staleness" — updating `alerts/_thresholds.yaml` to
  document migration 140's 6-hour bound) without re-running THIS test file
  afterward, which is exactly the "green check whose input set didn't
  include this" class the batch's own review process names elsewhere:

  1. `alerts/_thresholds.yaml`'s `defined_in_migration` field was rewritten
     to a compound, human-readable string naming BOTH 139 and 140
     ("139_alert_cron_failures.sql; stuck-branch upper bound added by
     140_hermes_pass_fixes_138_139.sql"). Every reader of this field
     (this test, and its sibling `alert_thresholds_sync_test.dart` for
     `client_errors_spike`) parses it via
     `RegExp(r'defined_in_migration:\s*"([^"]+)"').firstMatch(...)`, which
     captures the WHOLE quoted string as one group — so the compound string
     became a single, non-existent file path
     (`supabase/migrations/139_..sql; stuck-branch upper bound added by
     140_..sql`), and `File(...).existsSync()` returned false. Fixed by
     pointing the field at `140_hermes_pass_fixes_138_139.sql` alone,
     matching the sibling `client_errors_spike` entry's own established
     precedent (`087_alert_spike_reinclude_failure_events.sql` — the LATEST
     amending migration, not the original creating one, `086_...tune.sql`
     nor whatever created it before that). The human-readable history of
     both corrections already lives in the same block's `description` field
     and needs no duplicate home in the machine-parsed one.

  2. Even after fixing the path, `alert_cron_failures_sync_test.dart`'s own
     test 2 was asserting a design migration 140 deliberately overturned
     within this SAME batch: the stuck-job branch having "NO upper time
     bound" (correct for migration 139 as originally shipped, and this
     test's own reasoning text argued FOR that design) was replaced by the
     self-triggered Hermes pass with a `[1h, 6h)` bound (migration 140),
     because the unbounded version was found live-misfiring in production
     (two rows from a single crashed cron tick on 2026-09-19 were still
     'started' 2.5 days later and had already fired a real alert). This
     test — written earlier, during Part B's initial implementation — was
     never re-run against migration 140's superseding SQL by any of the 4
     review rounds, so nobody caught that its assertion now contradicts the
     shipped design. Fixed by rewriting the assertion to a
     whitespace-tolerant regex matching 140's actual `[1h, 6h)` clause, and
     rewriting the reasoning text to explain why the bound exists (a
     permanently-'started' row from a crashed isolate cannot be told apart
     from a genuinely still-running one, so "no bound" re-pages forever on a
     dead incident; 6h is chosen to sit inside the sibling
     `alert_cron_function_dead` alert's own 8-day horizon without masking a
     real still-running function).
regression_test_planned:
  - test/contracts/alert_cron_failures_sync_test.dart
impact_analysis: |
  Both changes are to a docs/config YAML value and a test's own assertions —
  no production code, migration, or Edge Function touched, and migrations
  139/140 (both already applied live and immutable) are untouched. Zero
  behavioral risk to the running app. The only risk was this contract
  silently testing stale, superseded behavior indefinitely — the exact class
  this test exists to catch for OTHER files, recurring here in itself.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter test test/contracts/alert_cron_failures_sync_test.dart: 7/7 passed after fix (was 1 setUpAll failure blocking all 7 downstream tests before)." }
mutation_proven:
  mutated: "Reverted alerts/_thresholds.yaml:77 to the compound-string form AND reverted the test's stuck-branch assertion + reasoning to the pre-fix single-line literal, confirmed applied by reading both files."
  result: "Re-ran flutter test test/contracts/alert_cron_failures_sync_test.dart: RED — setUpAll failed with Expected: true / Actual: <false> on migFile.existsSync(), exactly reproducing the original pre-push failure. Restored both fixes; re-ran: GREEN, 7/7 passed."
  confirmed_applied: "Read both files after the revert and after the restore to confirm exact content each time."
---

## Summary

The pre-push hook's full test suite failed on `alert_cron_failures_sync_test.dart`,
blocking the push of this batch's two already-landed commits. The background
push log was truncated before the actual failure detail, so the first step was
reproducing it directly: running the batch's own 10 new/modified test files in
isolation reproduced exactly 1 failure (of 4 total in the full suite) with full
detail.

## Root cause

Writer/reader drift, in two layers, both stemming from the same B-pass Round 4b
edit never being re-run against this specific test file:

1. **Field-format drift.** `alerts/_thresholds.yaml`'s `defined_in_migration`
   field (the writer) was changed from a bare filename to a compound
   two-migration prose string. Its reader
   (`test/contracts/alert_cron_failures_sync_test.dart:40-45`, and identically
   `alert_thresholds_sync_test.dart:53-59`) has always parsed this field as ONE
   bare filename via a greedy `[^"]+` regex group, so the compound string
   became one garbled, non-existent path.
2. **Stale design assertion.** Independent of the path bug, the test's own
   content assertion for the stuck-job branch (`test/contracts/
   alert_cron_failures_sync_test.dart:64-88`) still pinned the PRE-Hermes-pass
   design ("must have NO upper time bound") that migration 140 deliberately
   replaced with a bounded `[1h, 6h)` window, in the same batch, to fix a live
   misfire. The test was never re-run after that later design change.

## Fix

- `alerts/_thresholds.yaml:77` — `defined_in_migration` now names
  `140_hermes_pass_fixes_138_139.sql` alone (the current, live-defining
  migration), matching the sibling `client_errors_spike` entry's established
  "point at the latest amending migration" convention.
- `test/contracts/alert_cron_failures_sync_test.dart` — test 2's stuck-branch
  assertion rewritten as a whitespace-tolerant regex matching migration 140's
  actual `[1h, 6h)` bounded clause; its `reason:` text rewritten to explain the
  bound (crashed isolates leave permanently-`'started'` rows that an unbounded
  lookback cannot distinguish from genuinely-running ones).

## Verification

- `flutter test test/contracts/alert_cron_failures_sync_test.dart`: 7/7 green
  after the fix (was a `setUpAll` failure blocking all 7 before).
- Mutation proof: reverted both fixes together, re-ran — RED, reproducing the
  exact original failure (`Expected: true / Actual: <false>` on
  `migFile.existsSync()`); restored, re-ran — GREEN, 7/7.
- Full local suite re-run in progress separately to confirm the remaining 3 of
  the original 4 full-suite failures (this batch's own 10 touched test files,
  run in isolation, showed only this 1 — the other 3 are elsewhere in the
  ~6260-test suite and are being identified and fixed under the same
  no-deferrals discipline before re-attempting the push).

## Files changed

- Modified: `alerts/_thresholds.yaml`
- Modified: `test/contracts/alert_cron_failures_sync_test.dart`
- Created: this diagnose-doc.
