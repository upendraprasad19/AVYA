---
bug_id: d8e2f4
date: 2026-09-16
batch: apk43-obs-fixes (Obs 1 of 3)
status: fixed
blast_radius: account
symptom: |
  Founder reported (APK 1.0.0+43, one screenshot) being able to save
  breakfast, lunch, and dinner via the AI food-logging tab, but repeatedly
  seeing a red "Could not save — try again." snackbar when saving a snack.
concept: error_telemetry_helper
sot_registry_entry: |
  error_telemetry_helper
  (docs/sot_registry.yaml:4694) — adds a new reader entry for
  lib/features/nutrition/providers/nutrition_provider.dart
  AiBreakdownNotifier.saveMeal catch block, line_range 980-993,
  op_type 'ai_breakdown_notifier_save_meal'. Not a new concept.
writers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "AiBreakdownNotifier.saveMeal catch block — now calls ErrorTelemetry.recordNonFatal(reason: 'ai_breakdown_notifier_save_meal')", line: 990 }
readers:
  - { file: lib/core/services/error_telemetry.dart, method_or_widget: "recordNonFatal — posts to Crashlytics (fatal:false) + log-client-error Edge Function", line: 221 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: client_errors
cloud_columns: [error_code, error_message, op_type]
contract_test_path: test/contracts/ai_breakdown_notifier_save_meal_telemetry_test.dart
ist_handling:
  - "Not applicable — no date keys or counter resets involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [ai_breakdown_notifier_save_meal]
cross_account_guard: "Not applicable — the catch block reports on the currently-authenticated user's own save attempt; no cross-account read or write is introduced."
forbidden_patterns_checked:
  - { pattern: "catch (e, st) { debugPrint(...); return WriteResult.fail(...); } with no ErrorTelemetry call, inside AiBreakdownNotifier.saveMeal", absent: true }
proposed_fix: |
  Add ErrorTelemetry.recordNonFatal(e, st, reason:
  'ai_breakdown_notifier_save_meal') to the previously-silent catch block
  in AiBreakdownNotifier.saveMeal, matching the pattern already used by
  every OTHER catch block in this file and in NutritionWriteService. This
  is an OBSERVABILITY fix, not a root-cause fix for the founder's original
  trigger — see Impact analysis below for why the original exception's
  identity could not be conclusively determined in this batch, and what a
  recurrence will now surface.
regression_test_planned:
  - test/contracts/ai_breakdown_notifier_save_meal_telemetry_test.dart (new file)
impact_analysis: |
  INVESTIGATION FINDING, stated plainly: the exact original exception that
  produced the founder's repeated snack-save failure could NOT be
  conclusively identified in this batch, and this fix does not claim to be
  a root-cause fix for it. What was established:

  1. Cloud verification (SQL query against nutrition_logs for the founder's
     test account, date = the failure date) confirmed only breakfast/lunch/
     dinner rows exist — no snack row — ruling in favor of "the write never
     completed" over "it succeeded but a stale UI state showed failure".
  2. mealType validation was investigated and RULED OUT as the cause:
     lib/features/nutrition/services/meal_slot_inference.dart's
     inferMealSlot() and the canonical mealSlotKeys constant both use
     'snacks' (plural), matching NutritionWriteService's
     _allowedMealTypes set exactly — there is no singular/plural mismatch
     at the mealType-validation layer that prior sessions or this one could
     find.
  3. Every throw site INSIDE NutritionWriteService.logMeal was traced and
     found to be already wrapped by its OWN internal try/catch (Hive put at
     nutrition_write_service.dart:113-121, provider invalidation at
     :762-781, cloud sync fan-out at :138-146) — each of those failure
     modes already reports via ErrorTelemetry with its own distinct reason
     (e.g. nutrition_write_service_log_meal_hive_put) and returns a
     WriteResult.fail(...) rather than throwing. None of those reasons
     showed up in a client_errors query for the founder's account in the
     failure window, which is evidence AGAINST the failure originating
     inside logMeal's Hive-put layer specifically (though absence of a row
     is not proof, since this exact silent-catch gap could equally explain
     an absence if the true failure site were the outer catch itself —
     which is precisely the gap this fix closes for any recurrence).
  4. Because AiBreakdownNotifier.saveMeal's own try/catch (the one this fix
     instruments) had ONLY a debugPrint and no cloud telemetry, IF the
     original exception's throw site was somewhere not wrapped by
     logMeal's own internal catches (e.g. computeLogKey, _clampMealPayload,
     or a future code path), there would be NO record of it anywhere in
     client_errors — a genuine observability blind spot, independent of
     whatever the root cause turns out to be.

  This fix closes that blind spot. It does NOT change any validation,
  retry, or write logic — WriteResult.fail() paths that don't throw
  (mealType rejection, Hive put failure) are unaffected and already had
  telemetry via their own existing ErrorTelemetry calls. A recurrence will
  now surface in client_errors under op_type
  'ai_breakdown_notifier_save_meal' with the real exception's class and
  message, which is what would be needed to close this out with an actual
  root-cause fix.

  Blast radius (scripts/blast_radius_from_diff.dart) is `account`, not
  `feature`, because error_telemetry.dart is a shared core service used
  35+ call sites app-wide — the new debugOnRecordNonFatalForTests test
  seam added to it is additive and null by default (zero behavior change
  in production), but the file itself sits above the feature tier.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "nutrition_provider.dart catch block + error_telemetry.dart test seam added; flutter analyze lib/ exits 0 with only pre-existing info-level issues, none in touched files." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive key or schema change — this fix adds telemetry reporting only, no persisted state changes shape." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Queried nutrition_logs for the founder's account on the failure date via mcp Supabase execute_sql — confirmed no snack row exists (breakfast/lunch/dinner rows present), ruling out a silent-success/stale-UI explanation." }
---

## Summary

First of three findings from the APK 1.0.0+43 observation batch. Adds
telemetry to a previously-silent catch block so a recurrence of the
founder-reported repeated "Could not save — try again." on snack saves is
diagnosable via `client_errors`, given the original exception's identity
could not be conclusively established in this batch.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "nutrition", "save meal",
"logMeal", "snack" — no prior diagnose-doc covers a silent catch in
`AiBreakdownNotifier.saveMeal` or a snack-specific save failure. Checked
`feedback_source_grep_false_confidence.md` and
`feedback_writer_reader_field_drift_recurring.md` for the recurrence
class — this is not a writer/reader field-name drift (mealType validation
was traced and confirmed correct end-to-end), it is a plain missing-
telemetry gap. Not a recurrence of a previously-diagnosed bug.

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer (pre-fix):** `AiBreakdownNotifier.saveMeal`'s catch block
(`lib/features/nutrition/providers/nutrition_provider.dart`, then around
line 963) caught any exception from `NutritionWriteService.instance.logMeal`
and only ran `debugPrint('[AiBreakdownNotifier.saveMeal] error: $e\n$st')`
— a debug-only log invisible in a release build, with no `ErrorTelemetry`
call.

**Reader:** none existed — this is exactly the gap. Every OTHER catch block
in `nutrition_provider.dart` and `NutritionWriteService` reports via
`ErrorTelemetry.recordNonFatal` or `.logEvent`; this one was the sole
exception.

As detailed in `impact_analysis` above, the investigation could not
conclusively identify WHAT throws inside this specific try block in
production — every throw site inside `NutritionWriteService.logMeal` is
already independently guarded and already reports its own telemetry. The
gap this fix closes is structural (a defense-in-depth catch with no
observability), not a specific field-name or validation drift.

## Fix

Added `unawaited(ErrorTelemetry.recordNonFatal(e, st, reason:
'ai_breakdown_notifier_save_meal'))` to the catch block, alongside the
existing `debugPrint`. No other logic changed — the catch still returns
`WriteResult.fail(e.toString())` exactly as before, so the UI-facing
"Could not save — try again." behavior is unchanged; only the
observability improved.

Two small test-only seams were added to make the fix's effect assertable
end-to-end through the REAL method body (a hard requirement per CLAUDE.md
rule 21 — a source-grep alone would not prove the wiring works):

1. `ErrorTelemetry.debugOnRecordNonFatalForTests`
   (`error_telemetry.dart:72-80`) — mirrors the existing
   `debugOnLogEventForTests` seam exactly. When non-null, `recordNonFatal`
   invokes the hook instead of making Crashlytics/network calls. Null in
   production; zero behavior change.
2. `AiBreakdownNotifier.throwBeforeLogMealForTest`
   (`nutrition_provider.dart:920-931`) — when non-null, `saveMeal` throws
   the given object immediately before calling
   `NutritionWriteService.instance.logMeal`. Necessary because
   `NutritionWriteService` is a hard singleton with no DI seam, and (per
   the investigation above) nothing in normal operation is known to
   organically escape to `saveMeal`'s own catch block — every internal
   throw site in `logMeal` already has its own catch. This mirrors the
   existing `serviceFailCounts` / `resetCircuitBreakerForTests` test seams
   already present in the same class. Null in production; zero behavior
   change.

## Verification

`test/contracts/ai_breakdown_notifier_save_meal_telemetry_test.dart` (3
tests, the 3rd added post-B-pass): (1) seeds real `AiBreakdownData` state on
a real `ProviderContainer`-backed `AiBreakdownNotifier`, injects a fault via
`throwBeforeLogMealForTest`, captures the `ErrorTelemetry.recordNonFatal`
call via `debugOnRecordNonFatalForTests`, and asserts the result is a
failed `WriteResult` AND the captured `reason` is exactly
`'ai_breakdown_notifier_save_meal'` AND the captured error object is the
exact injected object (`same()`); (2) early-return control — no state set,
`saveMeal` short-circuits to `WriteResult.noState()` before the try block,
asserts the telemetry hook never fires; (3) **real negative control**
(`docs/reviews/6f1e4db85459-review.md` finding 2, P3) — drives a REAL
successful save through the REAL `NutritionWriteService.instance.logMeal`
against a real Hive box (via `test/nutrition_write_service/helpers/
nws_test_setup.dart`, the same helper the `NutritionWriteService` unit
suite uses), with `throwBeforeLogMealForTest` left null, and asserts BOTH
that an `nlog_*` row actually landed in Hive AND that the telemetry hook
never fired. Test (2) alone would pass identically even with the whole fix
reverted (it never reaches the try block), so it proved nothing about the
catch block's actual silence on success; test (3) is the one that would
break if `recordNonFatal` were miscalled outside the catch. All 3 passed.

**Mutated and run** (rule 21), twice: (a) removed the `unawaited(ErrorTelemetry.
recordNonFatal(...))` call from the catch block, restoring the pre-fix
debugPrint-only behavior. Re-ran — reddened exactly 1 of what was then 2
tests, with a clean assertion failure (`Expected:
'ai_breakdown_notifier_save_meal' / Actual: <null>`), confirming a real
functional gap detected (not a compile error — the file still compiled and
ran; the early-return-control test stayed green as expected since it
asserts the ABSENCE of a call either way). Restored; re-ran green. (b)
After test (3) was added, moved the `recordNonFatal` call to fire
UNCONDITIONALLY right after entering the try block (the exact "misplaced
call" defect shape test (3) exists to catch) — reddened exactly test (3)
(`Expected: false / Actual: <true>`), the other 2 stayed green. Restored;
re-ran green (3/3). `git diff --stat` (vs `HEAD`, since each mutation round
staged nothing) confirmed only the intended 27 lines remained in
`nutrition_provider.dart` and 14 in `error_telemetry.dart`.

`flutter analyze lib/` exits 0 (only pre-existing info-level issues, none
in touched files). Combined run of this file together with the pre-
existing `test/features/nutrition/ai_breakdown_save_confirmation_test.dart`
(which exercises the UI/snackbar layer via fake notifier overrides and so
cannot see this catch block at all — confirmed complementary, not
redundant), `error_telemetry_helper_behavioral_test.dart`, and
`error_telemetry_helper_writer_to_reader_test.dart` — all green together,
no interference from the new `debugOnRecordNonFatalForTests` seam
defaulting to null.

## Related

Sibling finding in the same observation batch: Obs 2 (diagnose `a1c6b9`,
AI coach history-poisoning) and Obs 3 (OI-204, sync/restore timeout storm
— documented, explicitly not fixed in this batch per founder direction).
Not a recurrence of any prior diagnose-doc (see Bug-history lookup above).

**Open residual:** the original exception's identity remains unknown. If
this recurs, `client_errors` will now carry a row with `op_type =
'ai_breakdown_notifier_save_meal'` and the real `error_code`/
`error_message`, which is the evidence needed to file a proper root-cause
fix.
