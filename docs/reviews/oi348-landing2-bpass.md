---
reviewed_at: 2026-11-24T08:20:00+05:30
staged_against: 61c9433d
blast_radius: platform
reviewer: claude-sonnet-via-skill (3 context-blind seats: B8, B9, B10)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 8
verdict: accepted
verdict_note: all 8 triaged; 7 fixed in the fix-round commit, 1 stated as a residual (B9 F5); B8 F2's writers-vs-readers half is a false alarm (reason below)
---

# Code Review (B-pass) — OI-348 Landing 2 PR A (PR 332)

Reviewed head `61c9433d` (CI green on every job). Three fresh Sonnet seats, one per unit, each with the plan, the diagnose doc, the founder decisions and the rejected alternatives quoted, an exhaustive command list (read-only git, file reads, the named `flutter test` / `deno test` files, `dart analyze`, `deno check`; no scripts, no network, no SQL) and no mutations (shared tree). No P0 or P1.

## Finding 1 — P2 — function_exception_swallow (seat B9 F1)
- **file:line:** lib/features/profile/providers/body_measurements_provider.dart:130-141
- **claim:** `save()` now awaits `ProfileWriteService.patchProfileWith`, which rethrows; the old `MigratedKey.write` never threw. A failed unit write after the measurement was saved escaped the sheet's tap handler (no catch there), skipped `ref.invalidate(bodyMeasurementsProvider)`, and left the sheet open so a second tap saves the day again.
- **verification:** `sed -n 133,138p lib/features/profile/services/profile_write_service.dart` (the rethrow) at 61c9433d
- **suggested-fix:** catch around the unit patch with telemetry; mirror test with a throwing patch.
- **status:** accepted — fixed: caught as `measurement_unit_write_failed`; test `measurement_write_batch_behavioral_test.dart` MIRROR via the new one-shot seam `ProfileWriteService.debugFailNextPatchWith` (thrown inside the real try). Mutant MF1 (rethrow restored) red.

## Finding 2 — P3 — guard_without_its_mirror (seat B9 F2)
- **file:line:** user_repository.dart setUnitsMetric, units_pref_adopter.dart runIfNeeded, body_measurements_provider.dart save (the three `stillOwner` closures)
- **claim:** each `stillOwner` could become `() => true` with every B9 test green: no test swapped the owner while a write waited on the profile lock.
- **verification:** `grep -n "stillOwner\|owner" test/contracts/unit_preference_sync_writer_to_reader_test.dart` (renamed from unit_preference_writer_to_reader_test at 6d209cd5)
- **suggested-fix:** hold the lock, start the write, swap the owner, release, expect both profiles untouched.
- **status:** accepted — fixed: group "B-pass F2" in `unit_preference_sync_writer_to_reader_test.dart` for all three writers. Mutants MF2a/b/c red.

## Finding 3 — P3 — writer_reader_drift (seat B9 F3)
- **file:line:** lib/features/profile/screens/profile/screen.dart:131-150
- **claim:** a restore tick while a tap's write was still queued re-read the OLD stored value and flipped the switch back; nothing re-seeded it after the write landed.
- **verification:** read `invalidateOnBackgroundRestore` and `_onUnitsChanged` at 61c9433d
- **suggested-fix:** in-flight counter; skip the re-seed while set; re-seed when the write completes.
- **status:** accepted — fixed exactly so (`_unitsWritesInFlight`, `_reseedUnits`). Test `profile_units_row_test.dart` step 3. Mutant MF3 red.

## Finding 4 — P3 — writer_reader_drift (seat B9 F4)
- **file:line:** lib/core/services/units_pref_adopter.dart:88-93
- **claim:** the adopter's "no profile" check was `current.isEmpty`; the sign-up stub `{id, email, created_at}` (auth_session_bootstrapper.dart:1094-1104) is not empty, so the device unit would be copied into it and a near-empty `user_profile` row pushed.
- **verification:** `sed -n 1094,1104p lib/core/services/auth_session_bootstrapper.dart`
- **suggested-fix:** treat a profile without onboarding data as no profile.
- **status:** accepted — fixed: `UnitsPrefAdopter.profileHasRealData` (a goal or a height, the bootstrapper's own cloud test); a stub is `noProfile` (no write, no flag, retried). Tests: the stub case plus its MIRROR (a height alone copies) and the pure predicate. Mutant MF4 red (2).

## Finding 5 — P3 — blast_radius / shared device (seat B9 F5)
- **file:line:** lib/core/services/units_pref_adopter.dart `profileAlreadySet` branch
- **claim:** if the first account to settle on a device already has a cloud `units_system`, the device key is dropped; a second account that had set imperial on the old build reads metric.
- **verification:** read the branch
- **suggested-fix:** accept and document, or keep the key per account.
- **status:** accepted as a stated residual in diagnose e9a6c1 ("Residual, stated"): the old value was one per DEVICE (the bug itself), every account is a testing account (CLAUDE.md section 1), and a per-account offer cannot be reconstructed from what the old build stored.

## Finding 6 — P3 — writer_reader_drift, inserted-lines sub-check (seat B10 F1)
- **file:line:** docs/sot_registry.yaml, `_attemptSingleCallRestore` reader row (`line_range: 2318-2545`)
- **claim:** the range started in the previous function and ended mid-method; it was already off on main.
- **verification:** `grep -n "Future<RestoreResult?> _attemptSingleCallRestore" lib/core/services/sync_service.dart` (2387)
- **status:** accepted — fixed: 2361-2597 (doc comment to closing brace).

## Finding 7 — P3 — writer_reader_drift, inserted-lines sub-check (seat B8 F1)
- **file:line:** docs/sot_registry.yaml, home_screen.dart rows `_checkStreakFreezeUsed` (237-261), `invalidateOnRetry` (149-184), `MeasurementDueSlot` (492-500)
- **claim:** all three were already stale on main; the diff shifted them mechanically.
- **verification:** `grep -n "_checkStreakFreezeUsed() {\|const MeasurementDueSlot\|void invalidateOnRetry" lib/features/home/screens/home_screen.dart`
- **status:** accepted — fixed: 246-270, 155-191, 504-507.

## Finding 8 — P3 — writer_reader_drift (seat B8 F2)
- **file:line:** docs/sot_registry.yaml concepts `rank_floor_never_announced`, `rank_monotonic_current_code`
- **claim:** (a) the two floor predicates (`isFloorRank`, Dart and TS) had no rows; (b) evaluate-rank-promotions is listed as a writer though the diagnose doc lists it as a reader; (c) `rank_service.dart` ranges 138-210, 39-60, 138-145 were stale (already on main).
- **status:** (a) and (c) accepted — fixed: rows for `rank_ladder_data.dart:259-289` and `_shared/rank_engine.ts:112-119`; ranges now 72-220, 222-239, 140-149. (b) false_alarm: in this concept the cron is a WRITER of the thing the concept is about (the `promotion_ceremony` row it does or does not write); the diagnose doc's "reader" lists it as a reader of `rank_promotions`, a different object.

## Checked clean (summary of the seats' own reports)
- B10: read-by-read parity of all 29 READS against origin/main's index.ts (select, filter, order, limit, vUid); key order and set; no partial 200; runLimited (lazy, observed, settles before resolving); the page budget under concurrency; the timing line carries no user data; no test file in the deploy payload; the client prefetch never rejects unobserved, never turns a failure into an empty restore, the switch fails safe, the subscription refresh stays serial. Deno 122/122, Dart 22/22.
- B8: every announce path closed (stamp, Home, cron ceremony, Edge Function, trigger) with its SD1 mirror tested; auth literal and first in the new handler seam; `current_rank_code` still moves to SD2. Dart 9, Deno 21.
- B9: no remaining raw reader or writer of the legacy keys; restore merge per key; push sends valid values only; adopter gate and call sites; cross-account capture at all three writers. Dart 27 + 11 + 2.

## Founder triage notes
Triaged by the session (standing instruction: fix every surfaced bug in the batch; CLAUDE.md 4.2). No finding reverses a recorded founder decision.

## Tuning entry
- **2026-11-24** - blast-radius platform - 8 findings; 0 false_alarm in full (1 partial: B8 F2 b); tuning: none. Seats were told the tree is shared and must not be mutated; two seats then reported the author's concurrent registry edits as "not mine", which is correct behaviour; a future multi-seat run should give each seat its own worktree if mutation is wanted.
