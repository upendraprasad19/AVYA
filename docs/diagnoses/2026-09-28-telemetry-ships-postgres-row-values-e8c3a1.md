---
bug_id: e8c3a1
date: 2026-09-28
batch: day-swapper-sync-load (Hermes E-pass remediation, finding h6F2, lens L40)
status: fixed
blast_radius: platform
symptom: |
  Hermes seat h6 (L40, PII in telemetry) found that a failed
  `ai_coach_interactions` upsert could send the user's raw AI-coach chat text
  into the `client_errors` table. Postgres echoes the rejected row's VALUES
  into its error text (`details: Failing row contains (...)` on a not-null or
  check violation, `Key (cols)=(values)` on a unique or FK violation,
  `invalid input syntax for type X: "value"` on a type error), and
  `PostgrestException.toString()` carries that text. `_reportSyncFailure`
  posted `error.toString()` verbatim (only truncated at 2000 chars), and its
  own doc comment already said the message "can include the full echoed
  row". The same raw text also reached Crashlytics (a third party) through
  `ErrorTelemetry.recordNonFatal`'s Crashlytics leg, and the queued-retry,
  dead-letter and subscription-refresh posts. No incident is known; this is
  a latent leak found by review.
concept: telemetry-row-value-redaction
sot_registry_entry: error_telemetry_helper — the funnel every catch uses; this adds a redaction step to every sink it and SyncService's direct posts reach
writers:
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: "_syncCoachInteractions — orphan upsert payload carrying user_message / ai_response", line: 224 }
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: "_syncCoachInteractions catch — hands the PostgrestException to _reportSyncFailure", line: 246 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_reportSyncFailure — the log-client-error POST body's error_message", line: 2673 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_enqueueTelemetryFailure — the queued copy the next launch re-sends", line: 2594 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_sendDeadLetterTelemetry — op.lastErrorMessage", line: 839 }
  - { file: lib/core/services/error_telemetry.dart, method_or_widget: "recordNonFatal Crashlytics leg", line: 309 }
  - { file: lib/core/services/error_telemetry.dart, method_or_widget: "recordNonFatal log-client-error leg", line: 336 }
  - { file: lib/core/services/subscription_service.dart, method_or_widget: "_logRefreshFailure", line: 998 }
hive_key_prefix: "syncBox telemetry queue (the queued copy is now stored redacted)"
hive_key_formula: not_applicable — no key shape changed
sync_methods: [_syncCoachInteractions]
restore_methods: []
cloud_table: client_errors
cloud_columns: [error_message]
contract_test_path: "test/core/error_telemetry_redact_row_values_test.dart (6 unit) + test/sync/sync_error_row_values_redacted_test.dart (1 behavioural, real coach push against a stub PostgREST)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [upsert_coach_interaction]
cross_account_guard: not_applicable — no per-user data path changed; the fix only rewrites text on its way to a telemetry sink
forbidden_patterns_checked:
  - "redacting only in _reportSyncFailure — rejected: the same raw text reached Crashlytics through recordNonFatal (including from the ~70 caller-level H-42 telemetry-pair calls that pass the raw exception before calling _reportSyncFailure) and three other direct log-client-error posts. The redactor lives in ErrorTelemetry and every off-device sink calls it."
  - "dropping the error text entirely — rejected: the message and SQLSTATE code are the diagnostic. Only the echoed VALUES are removed; column names in `Key (cols)=` are kept."
  - "redacting AFTER the length cap — rejected: the cap can cut the structural suffix the patterns anchor on. Redaction runs first, and each pattern falls back to redacting to the end of the string when no suffix is found, so a truncated queued copy is still clean."
proposed_fix: |
  Added `ErrorTelemetry.redactRowValues(String)`, a pure function with three
  patterns (Failing row contains, Key (cols)=(values), invalid input
  syntax/value for type X: "value"). Each prefers the structural suffix
  Postgres/PostgREST puts after the value and otherwise redacts to the end
  of the string. Over-redaction is safe; under-redaction is the leak. Text
  with none of the shapes is returned unchanged. Applied at every sink that
  ships error text off the device: recordNonFatal's Crashlytics leg (hands
  Crashlytics a small `_RedactedError` wrapper, keeping the original type
  name, only when redaction changed the text) and its log-client-error leg,
  `_reportSyncFailure`, `_enqueueTelemetryFailure`,
  `_sendDeadLetterTelemetry`, and `SubscriptionService._logRefreshFailure`.
  `SyncStubServer` (test helper) gained an optional per-table `failBodies`
  map so a test can fail a write with a real-shaped Postgres body.
regression_test_planned: |
  test/core/error_telemetry_redact_row_values_test.dart: six unit tests.
  Four build the input from a real `PostgrestException(...).toString()` and
  cover Failing row (message, code and hint survive), a truncated Failing
  row with no closing paren, Key (cols)=(values) (column names survive), a
  Key value containing ")", invalid input syntax (the code survives), and
  byte-identical pass-through of text with no row values.
  test/sync/sync_error_row_values_redacted_test.dart: drives the real
  `pushCoachInteractionsForSyncDomain` against the stub server, failing the
  `ai_coach_interactions` write with a `Failing row contains (..., <chat
  text>, ...)` body, then reads the actual log-client-error request. It
  asserts the report still arrives, carries no chat text, shows
  `Failing row contains (<redacted>)`, and keeps SQLSTATE 23514.
  MUTATED AND RUN (rule 21):
  (1) `_reportSyncFailure`'s message reverted to `(error.toString())`,
  confirmed applied with `grep -c` (1). The behavioural test went red with
  `Expected: not contains 'my knee hurts since the divorce'` and the raw row
  shown as the actual value.
  (2) `redactRowValues` made a no-op (`=> raw`). Six tests went red: all five
  redacting unit tests plus the behavioural test. The pass-through test
  stayed green, which proves the file still compiled and the reds are
  assertion failures.
  Both mutations restored; the restore was confirmed by `grep -c` (0 mutant
  tokens left). 13/13 green across both new files plus sync_telemetry_test.
impact_analysis: |
  From the next build, no Postgres row values leave the device in
  telemetry. The error class, message, SQLSTATE code and column names are
  kept, so every existing client_errors triage query still works. Rows
  already in client_errors are unchanged. That table is service-role only;
  a live check for any existing echoed row text is part of this batch's
  Task 34 verification. Residue, stated and not fixed here:
  `debugPrint('[SyncService._...] $e')` still prints the raw text to the
  device's own log. That output is not shipped off the device, and since
  Android 4.1 other apps cannot read the system log. It is not a telemetry
  sink, so it is outside L40's scope.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "error_telemetry.dart redactRowValues + both recordNonFatal legs; sync_service.dart :839 / :2594 / :2673; subscription_service.dart :998. flutter analyze lib/ clean." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "the syncBox telemetry-retry queue now stores the redacted text (_enqueueTelemetryFailure)." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "no rows written or migrated; existing client_errors rows are not rewritten." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "the log-client-error body shape is unchanged (same keys); only the error_message value is redacted. Proven end to end by sync_error_row_values_redacted_test.dart reading the real request body." }
---

## Summary

A failed sync write can make Postgres echo the whole rejected row into its
error. That text was sent unchanged to `client_errors` and to Crashlytics. For
`ai_coach_interactions` the row includes the user's chat text. One pure
redactor, `ErrorTelemetry.redactRowValues`, now runs at every sink that sends
error text off the device. It keeps the message, the SQLSTATE code and the
column names, and replaces the echoed values with `<redacted>`. One
behavioural test drives the real coach push and reads the real request. It was
mutation-proven twice: removing the call site reddened it, and a no-op
redactor reddened six tests.
