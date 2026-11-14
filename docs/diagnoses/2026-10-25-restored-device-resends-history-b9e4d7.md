---
bug_id: b9e4d7
date: 2026-10-25
batch: sync-storm-first-sweep
status: fixed
blast_radius: platform
symptom: >-
  A fresh browser profile that signs in to an account with history shows about
  30 s of "Pulling your dispatch", then the banner "Sync paused - your data is
  safe". The gateway log of that launch (founder, 2026-10-25 09:02 IST, web
  1.0.0+48, private window) holds 2,228 requests, of which `workout_log_exercises`
  took 633 upserts for 207 live exercise bundles (3.06x per bundle),
  `scheduled_workouts` 280 for 140 rows, and 51 answered HTTP 503. The device had
  just DOWNLOADED all of it. Three causes, each measured or read from code: the
  one-time ExlogKeyMigrator rewrote every canonical restored row with
  `updated_at_ms = now`, which changes the pushed `completed_at` and so every
  fingerprint the restore had recorded (the exercises then pushed again); the skip
  index persisted its confirmations only in `commit`, at the END of a pass, so a
  retry, a reload or an abort redid the pass; and a fresh device (`last_full_sync`
  null) ran the daily sweep at once, at the same time as the migrator-triggered
  workout push. The phone cold start is a separate, unmeasured symptom (OI board).
concept: restored_device_resends_history
sot_registry_entry: sync_exercise_log_payload_hash_index
writers:
  - { file: lib/core/services/exlog_key_migrator.dart, method: ExlogKeyMigrator.runIfNeeded (the put of the rewritten row, now skipped for a lone canonical row whose rewrite is byte-equal), line: 172 }
  - { file: lib/core/services/sync/sync_skip_index.dart, method: SyncSkipIndex._flush (incremental write of the pending confirmations and drops), line: 329 }
  - { file: lib/core/services/sync/sync_skip_index.dart, method: SyncSkipIndex._countFlushEvent (every kSkipIndexFlushEvery durable events: a confirmed push, or the drop of a stored fingerprint), line: 316 }
  - { file: lib/core/services/sync_service.dart, method: _markFreshDeviceIfEmpty (the durable fresh_device_<userId> marker), line: 1581 }
  - { file: lib/core/services/sync_service.dart, method: _postponeFirstSweep (stamps last_full_sync with the marker time, consumes the marker), line: 1614 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: _syncExerciseLogs (skip decision against the stored fingerprint; sends completed_at = latestWriteIso = max(resolved, updated_at_ms)), line: 557 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: checkAndSync (shouldRunFullSweep reads last_full_sync), line: 1080 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _markFreshDeviceIfEmpty (reads last_full_sync - null means never swept - and the marker key for first-wins), line: 1593 }
hive_key_prefix: "fresh_device_ (syncBox); sync_exlog_payload_hash_index (workoutBox); exlog_ (workoutBox)"
hive_key_formula: "fresh_device_<userId> -> UTC ISO-8601 instant of the first launch that found the device empty (first-wins, deleted by its sole consumer); sync_exlog_payload_hash_index -> {exlog_key: fingerprint}; exlog_<istdate>_<hash> rows as before"
sync_methods:
  - _syncExerciseLogs
  - _markFreshDeviceIfEmpty
  - _postponeFirstSweep
restore_methods:
  - _restoreExerciseLogs
cloud_table: workout_log_exercises
cloud_columns: [completed_at, set_number, weight_kg, reps, duration_seconds]
contract_test_path: test/contracts/exlog_migrator_keeps_restored_fingerprints_test.dart
ist_handling: []  # W3 stores UTC instants, no IST date key is written or read
provider_invalidations: []
telemetry_op_types:
  success: [first_sweep_postponed]
  failure: [sync_exlog_migrator_compare, sync_skip_flush_exlog, sync_fresh_device_mark, sync_first_sweep_postpone]
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: "\\?\\? DateTime\\.now\\(\\)", absent: true }
  - { pattern: "Hive\\.box\\(", absent: true }
  - { pattern: "skipServerPost", absent: true }
proposed_fix: >-
  W1 - ExlogKeyMigrator builds the row it would write WITHOUT the new write stamp
  and compares it with the stored row (SyncFingerprint.canonicalJson); a lone
  canonical-keyed row that is byte-equal is not put, and PendingExlogDeletes.cancelFor
  still runs. A comparison that throws (NaN/Infinity) falls back to the old rewrite
  and reports once (sync_exlog_migrator_compare). Kill switch
  disable_exlog_migrator_skip_unchanged (it only matters before a device's first
  migrator run: the one-time flag exlog_key_migration_v8 is already set after).
  W2 - SyncSkipIndex writes the pending confirmations and removals into a FRESH
  re-read of the box every 25 durable events (kSkipIndexFlushEvery; an event is a
  confirmed push, or the drop of a fingerprint that WAS stored), no await between
  the read and the put, never a prune; a failed put keeps the pending sets and
  reports once per instance (sync_skip_flush_<domain>). Kill switch
  disable_skip_index_incremental_flush.
  W3 - a durable per-user marker syncBox[fresh_device_<userId>] is written
  first-wins before any restore op writes history (top of checkAndSync and the
  restore core after openForUser); at the sweep decision a marker younger than 1 h
  with no owed failure stamps last_full_sync with the MARKER time and skips the
  sweep once (a postponement, not a drop). Kill switch disable_first_sweep_postpone.
  All three switches are live by default (opt-out). That is a deliberate reading
  of CLAUDE.md 4.6.1 for a tester-only app (section 1: every account is a testing
  account); it therefore does not qualify for ship_dark_build and gets the full
  x2 plan review, and deleting the switches and their old paths (4.6.4) is an OI.
regression_test_planned:
  - test/contracts/exlog_migrator_keeps_restored_fingerprints_test.dart
  - test/sync/sync_skip_index_incremental_flush_test.dart
  - test/sync/first_sweep_decision_test.dart
  - test/contracts/first_launch_sweep_decision_writer_to_reader_test.dart
related_bugs:
  - f3d2a7  # the restore did not record push fingerprints at all (L1a-3); this is the same family through a different writer
  - f1c6b4  # per-launch restore writers rewrote unchanged rows; same "compare before you write" cure
  - a8c4e5  # overlapping passes lost each other's confirmations; the flush re-reads for the same reason
  - e5b2a9  # outage resilience: the failed sweep is owed; an owed sweep is never postponed
  - d3f8a6  # OI-204: the skip index this builds on
recurrence: |
  Recurrence of the "a restored device pushes its history back" family: f3d2a7
  (2026-10-09) fixed the restore not recording fingerprints, and its test proved
  restore -> push == 0 upserts. That test never ran the exercise-log MIGRATOR
  between the restore and the push, and the migrator (a one-time boot rewrite,
  exlog_key_migration_v8) re-stamps every canonical row. Same symptom, a second
  writer of the row the fingerprint covers. The cure is the f1c6b4 one (compare
  against the stored value before writing) applied to the migrator. The other two
  causes (progress saved only at the end of a pass; the first sweep running
  alongside the restore-triggered push) are new mechanisms of the same family;
  bug-classes 2.123 and 2.124.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "exlog_key_migrator.dart W1; sync_skip_index.dart W2 (_flush, flushEvery, flushEnabledResolver); first_sweep_decision.dart (new, pure) + sync_service.dart W3 (_markFreshDeviceIfEmpty, _postponeFirstSweep, _hasLocalWorkoutHistory, _setTimestamp(at:)); sync_flags.dart three getters. Tests: the four new files, 78 tests." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "New syncBox key fresh_device_<userId> (naming_conventions 3.3); the skip index in workoutBox is now written mid-pass; exlog_ rows of a lone canonical row are no longer rewritten. Real Hive temp-dir boxes in all four test files." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No column or table changes." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud data changes; the fix only stops a re-upload." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: verified, evidence: "Supabase gateway logs of the 2026-10-25 09:02 IST launch were read (read-only): 2,228 requests, 633 workout_log_exercises upserts for 207 bundles, 51 HTTP 503. No write was made to the project." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Real restore writer -> real migrator -> real exercise push against SyncStubServer: 0 upserts after the fix, 2 before (Expected 0, Actual 2 on origin/main code); plus a real timed row (4b) 0 upserts, red on main. The founder-run device check (plan section 9) is the live proof and is owed." }
impact_analysis: >-
  Every account that signs in on a device with no local history (a new browser
  profile, a reinstall, a cleared site) and every device that still carries the
  v8 exercise-log migration flag unset. W1 changes what the migrator writes for a
  lone canonical row: nothing, when its rewrite would be byte-equal; all other
  shapes are rewritten as before. W2 adds a Hive write per 25 durable events in
  every SyncSkipIndex domain (about n^2/50 entry copies per pass: exactly 1,375
  at 262 rows, about 0.5M at 5,000) and changes nothing about which rows push.
  W3 delays everything ONLY the daily sweep pushes (Health Connect imports,
  plan_json, profile/progress/preferences/coach pushes) until the first launch at
  least 24 h after the first one (unbounded for an inactive user). Pre-launch
  every account is a testing account (CLAUDE.md section 1).
---

# A restored device uploads its own history back

Plan: `docs/plans/2026-10-25-sync-storm-first-sweep.md` (v4.1, converged after four context-blind review rounds; the B-pass below ran on the built code). Founder scope call (2026-10-25, "Smallest piece first (Recommended)"): this batch is the migrator fix, saving progress every ~25 rows, and skipping the first full sweep on a fresh device. The "one pass at a time" guard, fingerprints for the other 15 domains on restore, request batching and telemetry batching are tracked separately on the OI board; the phone cold start is unmeasured and also tracked there.

## Writers and readers (named before the fix, CLAUDE.md 4.1)

- Row writer: `ExlogKeyMigrator.runIfNeeded` (`exlog_key_migrator.dart`) puts `{...base, sets, aggregates, updated_at_ms: now}` for EVERY group, one per `exlog_` row, once per device (flag `exlog_key_migration_v8`).
- Fingerprint writer: `_restoreExerciseLogs` (`sync_workout.dart`, L1a-3) records `SyncSkipIndex.recordConfirmedAll` with the fingerprint of the bundle the push would build.
- Reader: `_syncExerciseLogs` (`sync_workout.dart:557`) compares the fingerprint of the row it would send; `completed_at = latestWriteIso(...) = max(resolved, updated_at_ms)` is part of that fingerprint. A migrator `updated_at_ms = now` therefore changes `completed_at` for every restored row.
- Persistence: `SyncSkipIndex.commit` (end of pass) was the only writer of the confirmations a pass made, and of the drops of stale fingerprints.
- Sweep gate: `checkAndSync` runs `weeklyFullSync` when `shouldRunFullSweep` says so; `last_full_sync` is null on a device that never swept.

## Measured

- Gateway log, 2026-10-25 09:02 IST (read-only, section 2.1 of the plan): 2,228 requests, `workout_log_exercises` 633 upserts for 207 live bundles (262 rows), `scheduled_workouts` 280 for 140 rows, 51 HTTP 503 (28 of 29 in one half-minute). The three failures that armed the banner were `restore_sync_exercises`, `restore_sync_nutrition` and `restore_sync_exercise_logs` = `TimeoutException after 0:00:45`. Two of them are `weeklyFullSync` push steps (`sync_exercises`, `sync_nutrition`); `restore_sync_exercise_logs` is the `syncWorkoutDataNow` fan-out step the migrator-triggered `syncWorkoutData()` runs. So both pushers timed out, which is evidence for the "two pushers at once" cause. None is a restore read.
- RED on `origin/main` code: restore two exercises, run the real migrator, push: `[sync-skip] exlog: pushed 2, skipped 0`, `Expected: <0> Actual: <2>`. This proves the mechanism on the stub chain; it does not prove the migrator was the dominant cause of the incident (633 for 207 is the incident volume that the migrator, the sweep and the retry together can explain).
- The migrator contract test (15 tests) against `origin/main`'s migrator file (replaced for one run, restored by sha): 6 red (1, 2, 3, 4b, 8, 9), 9 green (4, 4c, 5, 5b, 5c, 6, 7, 8b, 10). The green ones are regression pins that exist to kill mutants.
- NOT established: why single-row reads took 8 to 33 s upstream on the phone, and the cause of the 28-of-29 HTTP 503 burst (compute tier, or dashboard CPU/IO 09:15 to 09:25 IST). Both are carried on the OI board. The two extra table reads at 09:02:14-17 have a code explanation (two concurrent full restores on a fresh device by design) that is not correlated with those timestamps.

## Shapes the migrator test pins (and one wrong explanation the B-pass caught)

- Test 4's fixture row has `logging_type: weight_reps` (the `_summary` default). The push therefore sends `duration_seconds` 0 while the cloud row says 600, `restoredBundleEqualsCloud` fails at its duration check, and no fingerprint is recorded. An earlier version of the test, the plan and this doc called the cause "the push does not reproduce its metric-less set" and labelled it MEASURED; that was wrong (the push count, one, was right). Test 4 now says what it shows.
- Test 4b is a real timed row (`logging_type: timed`, zero metrics, a per-set duration): the restore records its fingerprint, the migrator finds nothing to change, the push sends 0 upserts. It is red on main.
- Test 4c is a timed row whose cloud weight/reps are NULL: recorded, but the migrator adds `weight_kg 0.0`, `reps_completed 0` and `volume_kg 0.0`, so the pushed body changes (NULL becomes 0.0) and it pushes once with or without the stamp. That is residual shape 1 of the plan, now pinned instead of asserted from a wrong reason.

## Mutation proof (CLAUDE.md 4.4 rule 21)

84 mutants, each applied once to the FINAL tree of the four test files and the four mutated source files (sha256 prefixes at run start: `exlog_key_migrator.dart` f901036a9af1, `first_sweep_decision.dart` 4a334f1f3b79, `sync_skip_index.dart` 4f35b5d6d4c2, `sync_service.dart` c1944f4cec4d, `exlog_migrator_keeps_restored_fingerprints_test.dart` fadc0235ef95, `first_launch_sweep_decision_writer_to_reader_test.dart` a3a8a113d1e3, `first_sweep_decision_test.dart` 7eda66db3aef, `sync_skip_index_incremental_flush_test.dart` 177286a00547). The runner computed every new content and asserted every anchor count before opening any file for writing, restored the original in `finally`, and verified it by sha256 after each mutant and at the end (`ALL RESTORED`; re-hashed after the run, all eight files equal the start fingerprint; afterwards only the header comment of the Gate 9 contract file changed, comment-only, and that file re-ran 3/3). Every mutant was confirmed APPLIED by comparing the file after the write with the computed content (for the pure deletions W1d, W1e, M16, N1, M23, M28, M29, M60 there is no new text to count, so the comparison with the computed content, which differs from the original, is the evidence). None is a compile error: each run printed both a pass and a fail count. Red = failing tests over the file run (W1 15, W2 31, W3 29, the Gate 9 contract file 3). The runner records the failing test names per mutant (for example M16 fails six named tests in the removals group, so it reddens for the intended reason).

| # | Mutation | Red / tests |
|---|---|---|
| M1 | drop group.length == 1 | 0 / 15, EQUIVALENT (argued) |
| M2 | drop group.first.key == newKey | 1 / 15 |
| M3 | candidate carries a bumped updated_at_ms | 6 / 15 |
| M4 | compare ignores sets/set_number | 1 / 15 |
| M5 | skip cancelFor on the unchanged path | 1 / 15 |
| M6 | migrator kill switch ignored | 1 / 15 |
| M7 | try/catch dropped around the compare | 1 / 15 |
| M8 | bump updated_at_ms on the unchanged path | 6 / 15 |
| W1a | compare-failure report once -> per row | 1 / 15 |
| W1b | a throw turns the skip off for the rest of the run | 1 / 15 |
| W1c | compare-failure report skips the server post | 1 / 15 |
| W1d | unchanged counter deleted | 1 / 15 |
| W1e | rewritten counter deleted | 1 / 15 |
| W1f | unchanged path puts the base row back | 0 / 15, EQUIVALENT (argued) |
| M9 | flush at > flushEvery instead of >= | 25 / 31 |
| M10 | counter never reset | 4 / 31 |
| M11 | flush before the confirmation joins pending | 19 / 31 |
| M12 | flush merges _stored + _confirmed instead of a fresh read + pending | 5 / 31 |
| M13 | pending not cleared after a successful flush | 3 / 31 |
| M14 | pending cleared on failure | 1 / 31 |
| M15 | flush error rethrown | 2 / 31 |
| M16 | removals not applied by the flush | 6 / 31 |
| M17 | owner check dropped in _flush (production-equivalent: argued) | 1 / 31 |
| M18 | counter advances on skipped rows | 1 / 31 |
| M19 | counter advances on fp == null | 1 / 31 |
| M20 | flush kill switch ignored | 3 / 31 |
| M21 | disabled guard dropped from _flushOn | 0 / 31, EQUIVALENT (argued) |
| M22 | telemetry per failure instead of once | 1 / 31 |
| M48 | flush mutates the object read from the box in place | 1 / 31 |
| M49 | pending not cleared when next == read | 1 / 31 |
| M50 | _forget skips _pendingConfirm.remove | 1 / 31 |
| M51 | a confirm skips _pendingForget.remove | 0 / 31, EQUIVALENT as a pair with M54 (argued) |
| M53 | M51 + the flush applies confirms before forgets (both defences removed) | 1 / 31 |
| M54 | the flush applies confirms before forgets alone | 0 / 31, EQUIVALENT as a pair with M51 (argued) |
| S1 | constructor default flushEvery = 1 | 1 / 31 |
| S1b | constructor default flushEvery = 5 | 1 / 31 |
| S2 | flush drops value-only updates (no per-entry compare) | 1 / 31 |
| S3 | flush skips confirmations for keys already in the box | 1 / 31 |
| S4 | pending forgets not cleared after a successful flush | 1 / 31 |
| S11 | _flushOn read live instead of at construction | 1 / 31 |
| N1 | a failed push of a stored row does not count | 6 / 31 |
| N1b | an unconfirmed push of a stored row does not count | 1 / 31 |
| N2 | a drop counts even when no fingerprint was stored | 2 / 31 |
| N3 | _forget never reports a stored drop | 7 / 31 |
| M23 | decideSweep: due check dropped | 1 / 29 |
| M24 | decideSweep: first && -> \|\| | 8 / 29 |
| M25 | decideSweep: second && -> \|\| | 7 / 29 |
| M26 | decideSweep: not-due returns run | 1 / 29 |
| M27 | decideSweep: !owed dropped | 2 / 29 |
| M28 | marker not consumed | 5 / 29 |
| M29 | future marker honoured | 2 / 29 |
| M30 | window < -> <= | 1 / 29 |
| M31 | ownerChangedSince dropped in the stamp | 1 / 29 |
| M32 | stamp uses now instead of the marker time | 1 / 29 |
| M33 | shouldMarkFreshDevice: first-wins dropped | 3 / 29 |
| M34 | shouldMarkFreshDevice: hasLocalHistory flipped | 5 / 29 |
| M35 | shouldMarkFreshDevice: lastFullSync flipped | 4 / 29 |
| M36 | shouldMarkFreshDevice: enabled flipped | 3 / 29 |
| M37 | marker key without the user id | 1 / 29 |
| M38 | currentOwnerFullId == userId guard dropped in the marker writer | 1 / 29 |
| M39 | kill switch ignored in the marker writer | 1 / 29 |
| M40 | kill switch ignored in the decision | 1 / 29 |
| M41 | postpone catch rethrows | 1 / 29 |
| M42 | await between marker read and put | 1 / 29 |
| M43 | marker call removed from checkAndSync | 1 / 29 |
| M44 | marker call moved after _restoreIfNeeded in checkAndSync | 1 / 29 |
| M45 | marker call removed from the restore core | 1 / 29 |
| M46 | weeklyFullSync left unwrapped | 1 / 29 |
| M47 | _restoreIfNeeded keeps its own copy of the key loop | 1 / 29 |
| M52 | restore-core marker call moved after ensureFreshToken | 1 / 29 |
| MA | checkAndSync marker call made conditional | 1 / 29 |
| MB | sweep also runs in an else branch | 1 / 29 |
| MC | restore-core marker call made conditional | 1 / 29 |
| MD | exlog_ rows no longer count as history | 1 / 29 |
| ME | postpone event emitted before the decision | 8 / 29 |
| MF | marker parsed with DateTime.parse (throws on garbage) | 1 / 29 |
| MG | marker written in local time (no toUtc) | 1 / 29 |
| M55 | contract: reader key differs from the writer key | 2 / 3 |
| M56 | contract: writer key differs from the reader key | 1 / 3 |
| M57 | contract: marker key without the user id | 2 / 3 |
| M58 | contract: stamp uses now | 2 / 3 |
| M59 | contract: writer spells the key as a literal | 1 / 3 |
| M60 | contract: marker not consumed | 1 / 3 |
| MG2 | contract: marker written in local time | 1 / 3 |

What the runs found, so the table is not read as a clean sweep:

- **Survivor measured before the final run, fixed with a test:** M4 (test 5b's restored summary-only row also lacks `volume_kg`, so it differed for a second reason and hid a comparison that ignored `sets`; test 5c isolates `sets`). **Gaps the B-pass reviewers named by reading the tests, closed with new tests and then mutated (the old tests were NOT re-run against these mutants, so they are not measured survivors):** S1 (nothing built the index with the constructor default), S2/S3 (no flush whose only effect was a new fingerprint on a key already in the box), S4 (a stale pending drop re-applied after a successful flush), S11 (the switch decided at construction was not pinned), MA/MB/MC (the wiring pins accepted a conditional marker call or an else branch that re-runs the sweep), MD (no exlog-only history case), ME (the postpone event was not asserted absent on the other paths), MF/MG (a malformed marker and the UTC text), W1a-W1e (report once, a throw switching the skip off for the rest of the run, the default server post, the counters in the log line).
- **M18, M19 and M38:** their tests were tightened by reading the code before the first run (skipped or fingerprint-less rows first, then confirmations; a test where the live account differs from the open Hive session). The old versions were not run against the mutants.
- **Equivalents, measured at 0 red, equivalence argued:** M1 (with `group.length > 1`, `base` is the last entry and `mergedSets` holds every entry's sets or a synthesized set, so the candidate has strictly more sets than `base`, or `sets` where `base` has none; the canonical JSON is never equal). W1f (the unchanged path putting `base` back writes the same bytes; no observer of a Hive write exists in `lib/core/services`). M21 (every read of `_flushOn` that can flush sits inside `if (fp != null)`, and `fp` is computed only when the index is not `disabled`). M51 and M54 as a pair (the confirm path removes the key from the pending drops AND `_flush` applies drops before confirmations, so either defence alone is enough; M53 removes both and the "fail k then confirm k in one window" test reddens). M17 is red only because test 17 counts owner checks with a closure; in production `ownerChangedSince(userId)` is stateless and no await separates the post-push check from the flush's, so the second check is defence in depth, not a separate protection.
- Self-attested residue: M1, W1f, M21, M51, M54 are argued, not measured. The wiring pins on `checkAndSync` and the restore core are source-grep (presence only: `checkAndSync` cannot run under `SyncHarness`); indirection beyond the pinned shapes is not covered, and the device check owes the runtime proof.

## What the B-pass found (2026-10-25, four fresh read-only Sonnet reviewers: W1, W2, W3, docs/governance)

No P0 and no P1 in the code. Every finding was checked against the code by me before acting; the review file is `docs/reviews/sync-storm-first-sweep-bpass.md`. The P1 of the docs reviewer was a wrong disclosure: this doc, `sync.md` and the registry said sweep-only pushes wait "up to 24 h", but the stamp is the marker time and the interval is one day, so they wait until the first launch at least 24 h after the first one (unbounded for an inactive user). Fixed in all three. One design change came out of W2 Finding 4: confirmations were durable mid-pass but drops of stale fingerprints were not, so a pass killed after a failed push of an edited row kept the old fingerprint and a later revert of the content would have been skipped against a cloud row that held the edited summary. This also exists on main (a killed pass loses its drops there too), so it is not a regression, but the registry claimed the drop was durable; the drop of a STORED fingerprint now counts as a flush event. Tests: dropping stored fingerprints, unconfirmed, never-stored, shared window, edit-then-revert after a killed pass; mutants N1, N1b, N2, N3.

## Final verification (2026-10-25, on the final tree)

- `flutter analyze --no-fatal-infos` over the whole project: 0 warnings, 0 errors (infos only; the new flush test has two `unnecessary_underscores` infos on its `reportFailure: (_, __, ___) {}` stubs, the idiom its sibling `sync_skip_index_overlap_commit_test.dart` already uses).
- The four new files plus the public-API snapshot test: 79 passed.
- Full suite, `TZ=Asia/Kolkata flutter test --exclude-tags golden`: 11,312 passed, 11 skipped, 0 failed, exit 0 (the golden-tagged tests are excluded on the UTC VPS and run on CI).
- The pre-commit gate loop is run on the staged state immediately before the commit; its result is on the commit, not asserted here.

## Open questions and limits

- Extra table reads at launch (two concurrent restores) and the backend stall are not established; OI board.
- **Timezone.** CI pins IST and the VPS is UTC, so every run here used `TZ=Asia/Kolkata`. The marker is a UTC instant and the window compares instants, so it is zone-independent; the writer's `.toUtc()` is pinned by a test that the text ends with `Z` (mutant MG). `_setTimestamp(at: marker)` writes the marker's ISO text (with a trailing `Z`) where the usual stamp is local without one, and `_getTimestamp` reads both with `DateTime.tryParse`, so the instant is identical. A device in another zone was not run.
- **Summary-only rows.** A canonical-keyed restored row with no per-set rows is still rewritten (the migrator synthesizes a set) and pushed once; the push sends `set_number = 1` for it whatever the cloud holds. Not changed here (OI board).
- **`last_full_sync` value semantics (CLAUDE.md 4.1.5 point 3).** It gains the meaning "stamped by a postponement": after a postponement it is non-null although no sweep ran, and non-null no longer implies "swept". Readers, from `git grep -n "last_full_sync|_lastFullSyncKey|lastFullSync" -- lib test supabase scripts integration_test`: `shouldRunFullSweep` / `checkAndSync` (`sync_service.dart:1079`), `_markFreshDeviceIfEmpty` (`:1593`, relies on null meaning never swept and on a postponement making it non-null so it does not mark again), `sync_retry_controller.dart:130-135`, the tests `sync_retry_controller_test.dart`, `test/supabase/sync_service_test.dart:337-363` (a stale 7-day assertion), `first_sweep_decision_test.dart` and `first_launch_sweep_decision_writer_to_reader_test.dart`; `supabase/functions` has none.
- **Kill switch scope.** `disable_exlog_migrator_skip_unchanged` only matters before a device's first migrator run; afterwards `exlog_key_migration_v8` is set and the migrator never runs again, so reverting after rollout means clearing that flag (which re-runs the whole migrator).
- **Flush edge cases.** `readIndex` swallows a read error and returns `{}`; a flush after such a read would write only the pending entries over the whole index. The same exposure exists in `commit`, costs extra pushes and never a false skip (the file's own rule), and is unreachable for a closed box (the put throws too). A flush never prunes: after a killed pass, entries for rows deleted since stay until the next completed `commit`.
- **Cost.** The arithmetic is exact (25 x (1 + ... + 10) = 1,375 entry copies at 262 rows). The disk claim in the plan is native-only; from memory of hive 2.2.3 (not verified here) the web backend overwrites the key and does not append, and the native backend appends with compaction triggered by entry counts, so a native box can carry dead index frames for a while. Each flush on the `customItem` domain rewrites `customBox`, which two screens listen to; that happens only with at least 25 custom items.
- Runtime verification on a device is owed by the founder (plan section 9: a normal window with site data cleared, the server quiet, path A and path B, day +1, reload mid-restore, offline first launch). The request count will be reported against the 2,228 baseline; the "about 300" figure was an estimate.
