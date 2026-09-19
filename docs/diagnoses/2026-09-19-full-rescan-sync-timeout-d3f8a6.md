---
bug_id: d3f8a6
date: 2026-09-19
batch: oi204-delta-sync
status: fixed
blast_radius: platform
symptom: >
  OI-204 (docs/audit/open_issues.md:4432-4485, filed 2026-09-16). Live
  `client_errors` telemetry on the founder's account showed 34x
  `sync_exercise_logs` timeouts + 11x `sync_nutrition_logs` timeouts in one
  25h window (2026-09-14->16), still ongoing as of filing. `_syncExerciseLogs`
  (lib/core/services/sync/sync_workout.dart:185-418, the coalesced per-write
  fire-and-forget entry fired after every WorkoutWriteService.logExercise)
  iterates EVERY exlog_*-prefixed Hive row on EVERY call -- not just what
  changed since the last successful sync -- and awaits a network upsert per
  row, sequentially. As the founder's historical log count grew, each
  coalesced pass now routinely takes 14-40s even on success, tripping
  SyncService.restoreOpTimeout = Duration(seconds: 45) (sync_service.dart:2280,
  diagnose b7e4c1) -- a ceiling deliberately generous, meant to unstick a
  genuinely WEDGED call, not act as a normal-case latency budget. This doc
  covers the exercise-log half (Task 2); the nutrition-log half
  (_syncNutritionLogs) ships in the same batch as Task 3.
concept: exercise_log_sync_fingerprint_skip
sot_registry_entry: sync_exercise_log_payload_hash_index (NEW -- sole writer == sole reader == _syncExerciseLogs; the sync-owned fingerprint index that gates the idempotent workout_log_exercises + workout_log_sets re-upsert)
writers: >
  lib/core/services/sync/sync_workout.dart (_syncExerciseLogs -- the SOLE
  writer of the fingerprint index: loads it at method head [unless the
  disable_exlog_hash_skip kill-switch is set], stores index[key]=fp ONLY
  when the local exlogBundleSynced flag is still true at the end of the
  per-key try block -- that flag starts true and is set false inside the
  per-set upsert's catch block, so a partial failure never records a
  fingerprint for content that never fully reached cloud -- prunes to live
  exlog_ keys and persists after the loop);
  lib/core/services/sync_service.dart (the pure statics
  exlogPayloadFingerprint / exlogShouldSkipUpsert / exlogPrunedHashIndex +
  the shared private _fingerprintMatchesStored helper [also used by Task 3's
  nlogShouldSkipUpsert] + the _exlogHashIndexKey const + the
  disable_exlog_hash_skip kill-switch getter);
  lib/features/dev/simulation_service.dart (resetJourney adds the index key
  to the workoutBox prefix-clear list, mirroring the identical
  sync_sched_payload_hash_index special case for the identical reason --
  it is a single reserved key, not an exlog_-prefixed one).
readers: >
  lib/core/services/sync/sync_workout.dart (_syncExerciseLogs -- the SOLE
  reader: the skip decision reads index[key] for the current row). No other
  code reads or writes the index => writer/reader drift is structurally
  impossible. The per-user workoutBox file IS the namespace, so the index
  auto-clears on user-swap / sign-out / DPDP (no extra wiring beyond the
  explicit resetJourney clear, which covers the sim-harness path that never
  goes through a real account swap).
hive_key_prefix: sync_exlog_payload_hash_index
hive_key_formula: "reserved single key in user-scoped workoutBox -> Map{exlog_key: UUID-v5(canonical sorted-key JSON of {summary, sets})}"
sync_methods: ["SyncService._syncExerciseLogs", "SyncService.exlogPayloadFingerprint", "SyncService.exlogShouldSkipUpsert", "SyncService.exlogPrunedHashIndex", "SyncService._fingerprintMatchesStored"]
restore_methods: []
cloud_table: workout_log_exercises
cloud_columns: ["workout_log_id", "user_id", "exercise_id", "exercise_name", "logging_type", "set_number", "reps", "weight_kg", "duration_seconds", "distance_km", "is_pr", "has_warmup_sets", "completed_at"]
contract_test_path: test/contracts/sync_exercise_log_payload_hash_index_writer_to_reader_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["upsert_exercise_log", "upsert_workout_log_sets", "sync_exlog_fingerprint_failed", "sync_skipped_null_natural_key"]
cross_account_guard: true
forbidden_patterns_checked:
  - "An unconditional full-rescan re-upsert -- _syncExerciseLogs upserted EVERY exlog_ row on EVERY coalesced pass with zero change-detection, re-walking the founder's entire historical log and tripping the 45s restoreOpTimeout 34x/25h. FIXED -- a sync-owned fingerprint index (sync_exlog_payload_hash_index) lets an unchanged row skip its idempotent re-upsert."
  - "An edited row silently skipped because its Hive key/identity did not change. Verified directly (spec Sec5.3): WorkoutWriteService.editLog reuses the SAME Hive key in place (box.get(logKey) -> mutate -> box.put(logKey, ...)), so any content edit necessarily flips the fingerprint. Pinned by the 'edit-not-skipped proof' test: a changed per-set weight_kg flips exlogPayloadFingerprint AND exlogShouldSkipUpsert returns false for the resulting mismatched pair."
  - "A partial-failure key silently marked as fully synced -- if the summary upsert succeeds but the per-set upsert throws, a naive 'store the fingerprint at the end of the try block' would permanently skip the retry the per-set rows still need. FIXED -- exlogBundleSynced starts true, is set false ONLY in the per-set catch, and the store is gated on it; guarded statically by scripts/check_sync_hash_skip_atomicity.dart (Task 1, mutation-proven) and mechanically by the exact-call-site-count test (spec Sec8 item 4)."
  - "A fingerprint-computation exception silently causing a permanent no-op skip for a key (the feedback_bad_news_vs_no_news class). FIXED -- the fingerprint compute + skip-check runs inside its own try/catch that defaults to shouldSkip=false and fp=null on any exception, AND logs a distinguishable sync_exlog_fingerprint_failed telemetry event rather than failing silently (plan-review round 1, finding I13)."
proposed_fix: >
  Extends the proven H1b Part A fingerprint-skip pattern
  (_syncScheduledWorkouts, diagnose b4f7e2, 2026-06-27) to the exercise-log
  domain. A sync-owned fingerprint index (reserved key
  sync_exlog_payload_hash_index in the user-scoped workoutBox; sole
  writer+reader is _syncExerciseLogs so drift is structurally impossible)
  maps each exlog_* Hive key to a UUID-v5 fingerprint of the FULL push
  bundle -- the summary row payload plus its ordered per-set rows -- so a
  change to EITHER half (not just the summary) flips the fingerprint. In the
  loop: resolve the per-set rows BEFORE either network call (moved earlier
  than the pre-fix ordering, which built them after the summary upsert), so
  both halves of the bundle are fully known before the fingerprint is
  computed; if the row's fingerprint matches the last CONFIRMED push, skip
  both upserts as one unit. Store-on-full-success-only: the fingerprint is
  recorded only when the local exlogBundleSynced flag (true by default, set
  false inside the per-set catch) is still true at the end of the try block
  -- a throw anywhere leaves no entry, so the next pass retries. No
  status-based carve-out (unlike sched's status=='completed' exemption) --
  verified, not assumed: supabase/functions/ has zero writers to
  workout_log_exercises/workout_log_sets (9 files reference the tables, all
  read-only -- confirmed independently by grep for .update(/.upsert(/.insert(/
  .delete( chained after any .from("workout_log...") call, zero matches),
  and every edit path rewrites the same Hive key in place, so a content
  change is self-detecting. Prune the index to live exlog_ keys after the
  loop (covers deletes without per-call-site wiring). resetJourney clears
  the index key (a survivor would mis-skip the sim re-drive's push after a
  reset wipes cloud out-of-band). Kill-switch disable_exlog_hash_skip
  restores the verbatim pre-fix unconditional full sweep. The skip decision,
  fingerprint, and prune are pure statics on SyncService for behavioral
  coverage; the skip-decision logic itself is a shared private
  _fingerprintMatchesStored helper reused by Task 3's nlog counterpart
  (plan-review round 1, finding M11 -- the two were byte-identical and
  duplicating them was pure divergence risk with no offsetting benefit).
regression_test_planned: >
  test/contracts/sync_exercise_log_payload_hash_index_writer_to_reader_test.dart --
  12 behavioral assertions: exlogPayloadFingerprint is stable + sensitive to
  every field in EITHER half of the bundle (a changed summary field, a
  changed per-set field, AND an added/removed set -- a key-set change, not
  just a value change); exlogShouldSkipUpsert skips on a matching
  fingerprint, always pushes on a null stored fingerprint (never-pushed /
  store-on-success-only), always pushes when the kill-switch is set, and
  explicitly proves the edit-not-skipped case (a changed weight_kg flips the
  fingerprint AND flips the skip decision to false); exlogPrunedHashIndex
  drops entries for keys no longer present and handles the
  all-deleted/empty-liveKeys case; a real Hive Box round-trip proves the
  fingerprint survives put/get through the dynamic-typed Map Hive returns
  and still drives the skip decision correctly; a source-grep proves
  resetJourney's body contains the literal index key (mirroring the sched
  precedent this repo already has for exactly this hazard); a second
  source-grep proves the guarded store site (exlogHashIndex[key] = fp)
  appears EXACTLY ONCE in sync_workout.dart, the "exactly one store site"
  half of the atomicity property the static gate depends on. Plus:
  scripts/check_sync_hash_skip_atomicity.dart (Task 1, already-mutation-proven,
  see docs/audit/gate_test_ledger.yaml) runs clean against the restructured
  file. The mutation-proof for this batch: flipping
  _fingerprintMatchesStored's equality check (== -> !=) reddened EXACTLY 3
  of the 12 tests (traced by hand, not guessed, before running) --
  "matching fingerprint -> skip" (true flips to false), "a changed per-set
  field flips the fingerprint (this is the edit-not-skipped proof)" (its
  trailing exlogShouldSkipUpsert assertion flips false to true, since a
  non-matching pair now reads as "skip"), and the Hive round-trip test
  (its matching storedFingerprint/currentFingerprint pair asserts isTrue,
  and the mutation flips a match to read "don't skip"). The two "null stored
  fingerprint" and "kill-switch enabled" tests, AND the two source-grep tests
  Steps 7a/7b added (resetJourney clear; exact store call-site count), are
  correctly UNAFFECTED -- the `storedFingerprint != null` short-circuit means
  the first two never reach the mutated clause, and the latter two never
  call the mutated function at all. Restored the real implementation;
  confirmed all 12 green again. This was run TWICE for this batch: once
  against the 10-test file that existed after Step 5 (before Steps 7a/7b
  added their 2 source-grep tests), reddening the same 3 by the same trace;
  then re-run in full against the final 12-test file for this doc. Final,
  authoritative run output:
    00:00 +9 -3: Some tests failed.  (post-mutation: 9 passed, exactly the
      traced 3 reddened -- "matching fingerprint -> skip",
      "a changed per-set field flips the fingerprint...", "Hive round-trip...")
    00:00 +12: All tests passed!  (post-restore, full 12-test file)
  Also repointed (plan-review round 1, finding C3 -- the restructure moves
  the summary row from an inline map literal to a named summaryPayload
  variable, which strands the OLD "}, onConflict:" slice-end anchor two
  existing tests used): test/contracts/duration_seconds_aggregate_populated_test.dart's
  setUpAll and test/contracts/workout_log_exercises_cumulative_reps_test.dart's
  second test, both repointed onto the new "final summaryPayload = <String,
  dynamic>{" ... "};" anchor -- confirmed to FAIL with a clean, specific
  "summaryPayload map must exist" reason against the pre-restructure code
  (the anchor cannot exist before Step 7 lands, so a literal PASS there is
  impossible; the useful confirmation is that the failure is the expected,
  loud, single-reason one and not a compile error or an unrelated crash),
  then confirmed to PASS after the restructure landed. A THIRD file my own
  grep sweep found beyond the plan's named two --
  test/contracts/sync_natural_key_guard_test.dart -- anchored on the OLD
  "from('workout_log_exercises').upsert({" (trailing literal brace) for its
  own null-key-guard window; repointed (dropped the trailing brace) AND its
  windowChars widened for both its workout_log_exercises (800 -> 6000) and
  workout_log_sets (2600 -> 4200) groups, because the restructure moved the
  entire per-set-resolution block plus the new fingerprint-check block to
  sit between each guard and its (now later) upsert call -- measured via a
  scratch script walking the same comment-stripped concatenated source the
  test itself reads (5092 / 3192 chars respectively; the new windows leave
  ~900-1000 chars of margin). All 26 tests across the 5 affected files
  (the new file, sync_fanout_contract_test.dart, both repointed files, and
  sync_natural_key_guard_test.dart) green together post-restructure.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "_syncExerciseLogs restructured in sync_workout.dart (preamble loads the index, per-key fingerprint-check + skip, store-on-full-success-only, postamble prunes + persists) + 3 pure statics + shared _fingerprintMatchesStored + kill-switch getter in sync_service.dart + resetJourney clear in simulation_service.dart. flutter analyze lib/ clean (0 warnings, 0 errors; 9 pre-existing info-level lints in sync_workout.dart, none new -- confirmed by diffing against the unedited lines those infos cite, which are clamp/guard lines preserved verbatim from before this batch). 12/12 new behavioral tests + 26/26 across all 5 affected existing test files green." }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "the fingerprint index lives under reserved key sync_exlog_payload_hash_index in the user-scoped workoutBox. Sole writer+reader is _syncExerciseLogs. The per-user box file is the namespace => auto-clears on swap/sign-out/DPDP; resetJourney also wipes it explicitly (mirrors sync_sched_payload_hash_index's A-fix-3 -- pinned by a new source-grep test asserting the literal key string appears inside resetJourney's own function body, not merely anywhere in the file). The existing !key.startsWith('exlog_') guard on the row-sweep loop is unaffected by the reserved key sitting in the same box (same structural safety schedHashIndex already relies on)." }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "Independently grepped (not trusted from the spec's prose): supabase/functions/ has 9 files referencing workout_log_exercises/workout_log_sets, all read-only (grep for .update(/.upsert(/.insert(/.delete( chained within 3 lines after any .from('workout_log...') call across all 9 -- zero matches). Confirms no out-of-band cloud mutator exists for these tables today, which is why no status-carve-out (unlike sched's status=='completed') is needed. Migrations 057/064/083 (all pre-existing, already-applied) contain one-shot DELETE/UPDATE backfills on these tables -- named in class_constraints as a documented, non-blocking future-risk note (a hypothetical FUTURE one-shot repair migration landing after this index exists would need to clear the relevant index entries itself, same as resetJourney already does for a full account reset), not a currently-open defect. Final cloud state is unchanged by this fix: an unchanged row already holds the exact payload cloud has; a changed/never-pushed/failed-push row still upserts exactly as before." }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "The fingerprint-skip only suppresses a REDUNDANT idempotent re-upsert of a byte-identical bundle; every edited, newly-created, or previously-failed-to-push row still upserts on the very next coalesced pass (store-on-full-success-only + the edit-flips-the-fingerprint guarantee together mean no data-loss path exists). Worst-case miss (a fingerprint-computation exception, or the documented weeklyFullSync lost-update race) is a one-pass delay -- the next sync re-pushes -- never silent data loss, since Hive remains the source of truth throughout. Live before/after sync_exercise_logs timeout-rate telemetry on the founder's account is founder-gated (requires production traffic over multiple days to observe)." }
impact_analysis: >
  Platform blast radius (exercise-log sync fires on every workout log write
  and on every login full-sweep via weeklyFullSync). The fix removes the
  reason _syncExerciseLogs routinely trips the 45s restoreOpTimeout: an
  unchanged historical log entry no longer costs a network round-trip at
  all, so a coalesced pass's duration scales with what actually CHANGED
  since the last successful push, not with total history size. Every
  data-safety contract is preserved: a partial per-set failure never
  records a fingerprint (retries next pass), an edited row always
  re-detects (same-key-in-place editing makes content changes
  self-signalling), a computation failure fails open to "push normally"
  rather than a silent permanent skip, and the whole mechanism is
  kill-switched to the verbatim pre-fix behavior. This document covers Task
  2 (exercise logs) only; the nutrition-log half (_syncNutritionLogs, the
  worse-cost domain per spec Sec5.2 since its per-slot cost is 1 upsert + 1
  SELECT + N item upserts + 1 DELETE, all sequential) ships as Task 3 of the
  same batch, reusing the shared _fingerprintMatchesStored helper this task
  introduces. Sibling/precedent: b4f7e2 (H1b Part A -- the
  _syncScheduledWorkouts pattern this fix extends). related: b7e4c1 (the
  restoreOpTimeout ceiling this fix stops tripping, without touching the
  ceiling itself per the spec's explicit non-goal); d9b2c5 (the
  cross-device-completion contract that motivates sched's status carve-out,
  verified NOT to apply here since exercise logs have no out-of-band cloud
  mutator).
---

# Sync timeout: exercise-log full historical re-scan on every coalesced pass (d3f8a6)

## What happened
Live `client_errors` telemetry on the founder's account showed **34x
`sync_exercise_logs` timeouts** in a single 25h window (2026-09-14->16), still
ongoing at filing. `_syncExerciseLogs` re-walks and re-pushes **every**
historical `exlog_*` Hive row on **every** coalesced sync call, even when
nothing changed. As the founder's log history grew, a single pass routinely
took 14-40s, tripping `SyncService.restoreOpTimeout = 45s` -- a ceiling meant
to catch a genuinely wedged call, not bound normal-case latency.

## Root cause (the class)
**An unconditional full historical re-scan with zero change-detection** --
the same cost-tax class `_syncScheduledWorkouts` already had (diagnose
`b4f7e2`, H1b Part A, 2026-06-27) before that fix, now recurring in a second
domain. The upserts themselves are correct (idempotent, natural-key
`onConflict`); the waste is re-sending byte-identical rows the cloud already
holds, sequentially, on every write-triggered coalesced pass.

## Fix (extends the proven H1b Part A pattern to exercise logs)
A **sync-owned fingerprint index** (reserved key
`sync_exlog_payload_hash_index` in the user-scoped `workoutBox`; **sole
writer+reader is `_syncExerciseLogs`**, so drift is structurally impossible)
maps `exlog_key -> UUID-v5 fingerprint` of the exact push bundle -- the
summary row payload **plus** its ordered per-set rows, so an edit to either
half is detected. An unchanged row whose fingerprint matches the last
**confirmed** push skips both its `workout_log_exercises` and
`workout_log_sets` upserts as one unit.

- **Bundle-before-either-network-call:** the per-set rows are now resolved
  BEFORE the summary upsert (the pre-fix order built them after), so the
  fingerprint sees the complete bundle before any network call happens.
- **Store-on-full-success-only (the atomicity requirement):** a local
  `exlogBundleSynced` flag starts `true` and is set `false` inside the
  per-set upsert's catch block; the fingerprint is stored only if the flag
  is still `true` at the end of the try block. A partial failure therefore
  never marks a key as fully synced, so the retry the un-pushed sets still
  need is never silently lost. Guarded statically by
  `scripts/check_sync_hash_skip_atomicity.dart` (shipped one commit earlier
  per CLAUDE.md Sec4.11, Task 1 of this batch) and mechanically by an
  exact-call-site-count test.
- **No status-based carve-out** (unlike sched's `status=='completed'`
  exemption) -- verified, not assumed: `supabase/functions/` has zero
  writers to `workout_log_exercises`/`workout_log_sets` (independently
  grepped, 9 read-only referencing files), and every edit path rewrites the
  same Hive key in place, so a content change is self-detecting.
- **Fingerprint-failure safety net:** any exception computing or comparing
  the fingerprint defaults to "push normally, never store" -- never a
  silent skip -- and logs a distinguishable `sync_exlog_fingerprint_failed`
  telemetry event.
- **Prune:** the index is pruned to live `exlog_*` keys after the loop
  (covers deletes without per-call-site wiring).
- **`resetJourney` clears the index key** -- the identical special case
  `sync_sched_payload_hash_index` already needed, for the identical reason
  (it's a single reserved key, not an `exlog_`-prefixed one, so the sim
  harness's prefix-clear list would otherwise miss it and mis-skip the
  re-drive's push after a reset wipes cloud out-of-band).
- Kill-switch `disable_exlog_hash_skip` restores the verbatim pre-fix
  unconditional sweep.
- The skip decision itself is a **shared private helper**
  (`_fingerprintMatchesStored`) reused by Task 3's nutrition-log
  counterpart (`nlogShouldSkipUpsert`) -- the two decision bodies were
  byte-identical and had no domain-specific content worth duplicating.

## Why this cannot lose data
- A partial per-set failure records no fingerprint (store-on-full-success-only)
  -> the next pass retries the sets.
- Every edit rewrites the same Hive key in place -> the fingerprint
  necessarily flips -> the edit is never silently dropped. Pinned by the
  "edit-not-skipped proof" test.
- A fingerprint-computation exception fails OPEN to "push normally", never
  to a skip.
- First run starts with an empty index -> every row pushes once, healing
  any existing divergence before the index warms.

## Known limitations
**Fingerprint-determinism note (OI-204 B-pass, 2026-09-19, Finding 1 of the
lenses-1-5 reviewer), non-blocking:** `_resolveCompletedAt`'s last-resort
fallback (`sync_workout.dart:574`, `DateTime.now().toUtc().toIso8601String()`
-- already telemetry-flagged as `sync_completed_at_fallback` when hit) feeds
`summaryPayload['completed_at']`, which `exlogPayloadFingerprint` hashes. For
the rare exlog row that hits this fallback (all six earlier resolution tiers
-- `created_at`/`completed_at`/`logged_at`/`updated_at_ms`/`completed_at_ms`/
`dateKeyPrefix` -- exhausted), `completed_at` differs on every sync pass, so
the fingerprint never repeats and `exlogShouldSkipUpsert` can never return
`true` for that key. **Fails safe**: no data loss, no incorrect skip -- the
OI-204 optimization simply never engages for that one row, which falls back
to the exact pre-fix always-push behavior it already had. Not fixed
structurally (would need `_resolveCompletedAt` to signal fallback provenance
so the fingerprint could exclude a non-deterministic `completed_at`) --
proportionate given the existing telemetry already flags the anomaly, and a
row reaching this branch at all indicates a pre-existing upstream
data-quality gap (missing timestamps), not something this batch introduces.
Nutrition's equivalent parent `created_at` (`mergeNutritionLogsBySlot`) has
no such fallback -- it only ever takes the earliest already-stored
`log['created_at']` -- so this is exlog-specific.

**Gate-coverage note (plan-review round 1, finding I7), non-blocking:**
`check_schema_column_refs.dart` detects a write's column keys via
`RegExp("\.$method\(\s*\{")` -- i.e. only an inline `.upsert({` literal.
After this batch, `workout_log_exercises`'s columns live in the named
`summaryPayload` variable, so that gate silently stops validating them
against `backups/live_schema_columns.json` for this call site -- it does
not fail, it simply checks nothing there. `nutrition_logs` already has the
identical blind spot for the identical reason (`parentPayload` is already a
variable there), so this extends a pre-existing accepted pattern to a
second table rather than introducing a new one. Not fixed by reverting to
an inline literal -- noted here for anyone auditing gate coverage later.

## Verification
- `test/contracts/sync_exercise_log_payload_hash_index_writer_to_reader_test.dart`
  -- 12 behavioral assertions (fingerprint stability/sensitivity including
  the key-set-change case; skip/re-push semantics; prune; a real Hive
  round-trip; the resetJourney source-guard; the exact-store-call-site-count
  source-guard). Mutation-proof: flipping the shared equality check reddened
  exactly the 3 tests traced by hand in advance; restored, confirmed green.
- `scripts/check_sync_hash_skip_atomicity.dart` (Task 1) -- OK against the
  restructured file.
- All 26 tests across the 5 affected files (the new file,
  `sync_fanout_contract_test.dart`, the 2 plan-named repointed tests, and a
  3rd repointed test my own pre-restructure grep sweep found) green.
- `flutter analyze lib/` clean (0 warnings/errors; pre-existing infos only,
  confirmed none new).
- `dart run scripts/check_sot_registry_parity.dart` -- PASS after fixing 3
  stale `line_range` citations the ~120-line `sync_service.dart` insertion
  shifted (`compileDailySnapshot`, `applyRestoreCeiling`,
  `restoreFailureReason` -- none of which this batch's logic touches; pure
  line-shift drift).
- Live before/after `sync_exercise_logs` timeout-rate telemetry on the
  founder's account -- founder-gated (needs multi-day production traffic).

## Task 3 addendum — nutrition-log half (`_syncNutritionLogs`)

Ships in the same batch (branch `oi204-delta-sync`) as a second commit,
reusing this doc per the brief's explicit instruction — one root cause, one
doc, two fix commits both citing `closes-diagnose: d3f8a6`.

### Fix
Extends the SAME `sync_nutrition_log_payload_hash_index` fingerprint-skip
pattern to `_syncNutritionLogs`. Nutrition's bundle shape is a parent payload
(`nutrition_logs`) plus N item rows (`nutrition_log_items`), and its per-slot
push cost is the WORSE of the two OI-204 domains — 1 upsert + 1
id-resolution SELECT + N item upserts + 1 tail-vacuum DELETE, all
sequential. An unchanged slot (keyed by `'$date $mealType'`, matching the
existing same-slot merge, not a raw Hive key) now skips ALL of that as one
unit. `nlogShouldSkipUpsert` delegates to the SAME private
`_fingerprintMatchesStored` Task 2 introduced — not redefined.
Store-on-full-success-only via a local `nlogSlotSynced` flag, false'd in
BOTH the per-item upsert's catch AND the tail-vacuum's catch (2 swallowing
catches, vs exlog's 1 — `scripts/check_sync_hash_skip_atomicity.dart`'s
`nlogSpec.expectedSwallowCatches: 2` pins this count). `resetJourney`'s
nutritionBox prefix-clear list gained the reserved key
`sync_nlog_payload_hash_index`, mirroring the sched/exlog precedent.

### Mutation-proof (Step 5, rule 21)
Flipping the SHARED `_fingerprintMatchesStored`'s equality check
(`storedFingerprint == currentFingerprint` → `!=`) was traced BY HAND before
running: 3 of nlog's 10 base tests should redden ("matching fingerprint ->
skip", "an edited item quantity flips the fingerprint (edit-not-skipped
proof)", and the Hive round-trip test — "null stored fingerprint" and
"kill-switch enabled" short-circuit before the mutated clause and stay
green). Ran BOTH domains' suites together in one pass:

```
flutter test test/contracts/sync_nutrition_log_payload_hash_index_writer_to_reader_test.dart test/contracts/sync_exercise_log_payload_hash_index_writer_to_reader_test.dart
```

Post-mutation, actual output: `+16 -6` (16 passed, 6 failed out of 22 — 10
nlog + 12 exlog at that point). Exactly the traced 3 reddened in nlog's file
("nlogPayloadFingerprint an edited item quantity flips the fingerprint
(edit-not-skipped proof)", "nlogShouldSkipUpsert matching fingerprint ->
skip", "Hive round-trip fingerprint round-trips through dynamic-typed Hive
Map and drives the skip decision") plus the already-established 3 in
exlog's file ("a changed per-set field flips the fingerprint (this is the
edit-not-skipped proof)", "matching fingerprint -> skip", "Hive
round-trip..."). Restored (`grep -c` confirmed 0 occurrences of the mutated
token); re-ran: `+22`, all tests passed in both files.

### Step 7c — rewritten self-heal comment
`_syncNutritionLogs`'s item-loop `ownerChangedSince` guard carried a comment
(closure R2-N9) justifying an abandoned pass as safe because *"
`_syncNutritionLogs` has no fingerprint/skip-unchanged optimisation ... so it
re-walks EVERY nutrition Hive row on every pass."* This batch makes that
premise FALSE, so the comment is rewritten IN PLACE (not deleted) to
re-derive the argument under the new code: an abandoned pass persists
nothing to `nlogHashIndex` — the postamble's store sits after the
postamble's OWN `ownerChangedSince` guard (added this batch), which an
abandoned pass never reaches — so a retry is still safe, and a genuine
content change still flips the fingerprint on the next pass.

One residue is named, not silently assumed away (plan-review round 1,
finding M2, non-blocking, NOT structurally fixed this batch): content C1
fully pushed (fingerprint stored) → edited to C2 → a pass pushes PART of C2
then abandons via `ownerChangedSince` mid-item-loop (nothing persisted,
self-heals) → reverted back to C1 before the next pass → the next pass
fingerprint-matches C1 and SKIPS, while cloud may still hold a half-written
C2. Narrow: requires an edit-then-EXACT-revert landing inside an
account-switch race window.

### I9 — clear-on-revert for the merge-disable kill switch
While `disable_nutrition_slot_merge` is set, `_syncNutritionLogs` reverts to
the legacy per-key push (`_nutritionLogsRaw()`), a DIFFERENT concept than
the slot this index is keyed on. The postamble's `else` branch therefore
does not merely skip READING the index while inert — it DELETES
`sync_nlog_payload_hash_index` outright. Without this, a stale index
surviving a disable/re-enable cycle would fingerprint-match unchanged local
content and SKIP re-pushing exactly the slots the legacy path's "later raw
key silently overwrites an earlier same-slot one in cloud" behaviour may
have corrupted — turning the emergency revert into the thing that makes the
corruption permanent once slot-merge is re-enabled.

Test form used: SOURCE-GREP, not behavioral (brief Step 7's explicit
either/or choice). A behavioral drive of `_syncNutritionLogs`'s postamble
needs a live `_supabase.client` and `ownerChangedSince`/auth state; this
codebase has no DI seam for `SupabaseService` anywhere (`grep -rln
"MockSupabase|FakeSupabase|_supabase = Mock|SupabaseService(" test/` →
nothing), the SAME finding already established for the atomicity
sub-property. The "Hive round-trip" group in this test file opens a real
Hive box but never invokes `_syncNutritionLogs` itself, so it does not
supply the missing seam either. The source-grep test anchors on the LAST
occurrence of `if (!nlogHashSkipDisabled) {` in `sync_nutrition.dart` (the
string appears TWICE — once in the preamble's index-hydration, which has no
`else`, and once in the postamble, which does) and asserts the `else` body
contains the literal `_hive.nutritionBox.delete(SyncService._nlogHashIndexKey)`
call. This ambiguity was caught by the test itself failing on first run
(plain `indexOf` found the preamble's occurrence, not the postamble's) —
fixed to `lastIndexOf` before this addendum was written.

### Files
`lib/core/services/sync_service.dart` (nlog* pure statics +
`nlogHashSkipDisabledFor` + `_nlogHashIndexKey` + `_nlogHashSkipDisabled`
kill-switch getter, placed immediately after the exlog block);
`lib/core/services/sync/sync_nutrition.dart` (`_syncNutritionLogs`
restructured: preamble loads the index unless disabled, per-slot skip-check
inserted before the pre-existing `ownerChangedSince` guard, `nlogSlotSynced`
flag threaded through the item-loop and vacuum catches, store-on-success
block, postamble persists-or-clears); `lib/features/dev/simulation_service.dart`
(`resetJourney` nutritionBox clear list);
`test/contracts/sync_nutrition_log_payload_hash_index_writer_to_reader_test.dart`
(new, 14 tests); `docs/sot_registry.yaml` (new concept
`sync_nutrition_log_payload_hash_index`; plus 4 stale `line_range` citations
this task's 74-line `sync_service.dart` insertion shifted a second time —
`compileDailySnapshot`, `applyRestoreCeiling`, `restoreFailureReason` [all
three already fixed once by Task 2, shifted again by this task's own
insertion] and `checkAndSync` [not previously stale — newly caught this
time] — all repointed to their live line numbers, confirmed via
`dart run scripts/check_sot_registry_parity.dart`).

## See also
- `lib/core/services/sync/sync_workout.dart` (`_syncExerciseLogs`),
  `lib/core/services/sync/sync_nutrition.dart` (`_syncNutritionLogs`),
  `lib/core/services/sync_service.dart` (the pure statics + shared helper +
  kill-switches).
- `b4f7e2` (H1b Part A -- the `_syncScheduledWorkouts` pattern this fix
  extends).
- `b7e4c1` (the `restoreOpTimeout` ceiling this fix stops tripping, without
  adjusting the ceiling itself).
- `d9b2c5` (the cross-device-completion contract behind sched's status
  carve-out; verified not to apply to this domain).
- Task 3 of this batch (nutrition logs, `_syncNutritionLogs` -- reuses
  `_fingerprintMatchesStored`; see the addendum above).

## B-pass remediation — atomicity gate hardening (2026-09-19)

Ships in the same batch as a third commit, reusing this doc (same root cause tree: the
Task 1 gate this batch's §4.11 requirement produced), citing `closes-diagnose: d3f8a6`.
Whole-branch B-pass (`docs/reviews/oi204-delta-sync-bpass.md`), lenses-6-8 reviewer,
Finding 1 (P1).

### The defect
`checkDomainAtomicity` (`scripts/sync_hash_skip_atomicity_lib.dart`) checked for a store
statement's EXISTENCE via a whole-file regex match (`storeRe.hasMatch(stripped)`, whose
`\s*` spans newlines the way Dart's `\s` character class always does), then separately
located WHICH LINE(S) contain a store by re-running the same regex against each individual
line in isolation. A store statement wrapped across two lines -- a plausible `dart format`
output for a line past 80 columns, not a contrived shape -- matched the whole-file check but
matched NEITHER half when re-run per-line, so `storeLineIdxs` came back empty, the
backward-guard-scan loop never executed, and the function fell through to PASS regardless of
whether the store was actually guarded. An unconditional (unguarded) multi-line store --
exactly the atomicity violation this gate exists to catch -- was invisible to it.

### Fix
Compute `storeLineIdxs` from `storeRe.allMatches(stripped)` (the SAME whole-text match set
`hasStore` already uses) mapped to line indices via each match's start offset, instead of
re-running the regex per split line. Both checks now agree on what counts as a store
regardless of how many lines it spans.

### Mutation-proof (rule 21)
Two new fixtures added to `test/scripts/sync_hash_skip_atomicity_lib_test.dart`: an
unconditional store split across two lines (must FAIL) and a correctly-guarded store split
across two lines (must PASS -- the fix's own mirror case, confirming no new false-positive).
Reverted the fix, ran the split-store-unguarded test alone: reddened exactly as predicted
(`Expected: not null, Actual: <null>`) -- the pre-fix checker silently passed the exact
defect it exists to catch. Restored the fix, re-ran: 15/15 lib tests + 3/3 e2e tests green.
Re-ran `dart run scripts/check_sync_hash_skip_atomicity.dart` against the real
`sync_workout.dart`/`sync_nutrition.dart` -- still `OK` (current production code was never
affected; this closes a future-regression blind spot, not a live defect).
`docs/audit/gate_test_ledger.yaml`'s evidence extended with this mutation.
