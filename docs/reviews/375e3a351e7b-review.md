---
reviewed_at: 2026-08-30T09:35:36+05:30
staged_against: 375e3a351e7b
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 4
verdict: accepted
---

# Code Review — 375e3a351e7b

OI-150 — progress + profile write durability and restore authority. Dispatched as a
fresh, context-blind Sonnet subagent. Four findings, **zero false alarms**, all four
fixed in-batch. Two of the four were defects introduced by the batch's OWN earlier
fixes, which is the pattern this review history keeps recording.

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** `lib/shared/repositories/user_repository.dart:400-401` (seed), `:407-413` (cloud-null branch), `:506` (post-pass)
- **claim:** `disable_progress_restore_monotonic_merge` is documented as returning
  "verbatim pre-OI-83" behaviour. That promise was false in two of four paths: the
  OI-150 `phaseKeptLocal` seed ran unconditionally BEFORE `guardOff` was read, and
  the cloud-null branch ran before the `guardOff` check — so rolling the OLDER,
  WIDER switch left the NEWER coupling still overriding non-null cloud values.
  Pre-OI-83 had no companion coupling at all. The independence note reasoned about
  the flip in one direction only and never checked the reverse.
- **verification:** reviewer added two probe tests setting
  `kDisableProgressRestoreMonotonicMergeKey = true` and ran
  `flutter test test/contracts/progress_restore_monotonic_behavioral_test.dart`;
  both showed `phase_started_at` still refused and `refusedPhaseDeltaFields`
  still populated with the switch ON. Probes reverted and confirmed clean.
- **fix applied:** `guardOff` is now computed BEFORE the seed and both the seed and
  the cloud-null branch are gated on `!guardOff`. Pinned by two new tests
  ("OI-83 switch ON also disables the coupling on the KEY-ABSENT path" / "…on the
  CLOUD-NULL path"). Mutation-proven: reverting the seed to un-gated reddens 1.
- **status:** fixed

## Finding 2 — P1 — guard_without_its_mirror
- **file:line:** `lib/core/services/sync/sync_profile.dart:481-494`, `:498`, `:551-582`
- **claim:** The batch's own N10 fix ("a drain must not silently delete a marker for
  a push that never happened") was applied to both empty-Hive-map checks and to
  `_syncUserProgress`'s outer catch, but NOT to the three early `return`s inside
  `_retrySyncUserProgressOnceAfterConflict`. All three complete normally regardless
  of `fromQueue`, so a repeated version conflict during a drain returns void →
  executor returns `Result.ok` → `SyncQueue._runOne` removes the marker. The write
  was never delivered, yet the queue and `SyncBanner`'s pending count report it as
  synced. The `!fromQueue` guard protecting against retryCount-reset sits two lines
  above the very `return;` that lacked the throw.
- **verification:** reviewer traced the chain end-to-end by reading
  `sync_queue.dart:246-267` (`result.isOk` → `_remove(op.id)`) and
  `sync_service.dart:709-727`, and grepped the new test file for conflict coverage
  (`grep -n "conflict\|row_absent\|retryVersion" test/contracts/sync_queue_progress_marker_test.dart` → no hits).
- **fix applied:** all three drop paths now `throw` under `fromQueue`, mirroring the
  `if (fromQueue) rethrow;` one frame up, so the executor returns `Result.err` and
  the marker is retried/backed-off/dead-lettered honestly. Pinned by a new test
  asserting all three guards exist AND that the non-drain `return`s survive.
  Mutation-proven: reverting one throw reddens 1.
- **status:** fixed

## Finding 3 — P2 — asserted_fixture_value
- **file:line:** `docs/sot_registry.yaml` (`BiometricNotifier.logSleep`) vs `lib/features/profile/providers/profile_provider.dart:540`
- **claim:** A citation re-derived by this batch landed on 431-456 — the tail of the
  `BiometricData` constructor and the head of `build()` — while `logSleep` is at 540.
  The batch's own `ist_sites:` entry for the SAME method correctly says 540, so two
  citations for one function disagreed within one commit. `check_sot_registry_parity.dart`
  does not catch it: `_extractSymbol` takes the FIRST identifier of a dotted
  `Class.method` value, so it validated against `class BiometricNotifier` at :439 —
  which happens to fall inside the wrong range.
- **verification:** `grep -n "Future<void> logSleep\|class BiometricNotifier" lib/features/profile/providers/profile_provider.dart`
  → 439 / 540; `awk 'NR==431,NR==456'` dumped the cited range; `dart run scripts/check_sot_registry_parity.dart` → PASS despite the error.
- **fix applied:** repointed to 540-548, computed from the method's real span.
  ⚠ The gate's dotted-path extractor weakness is REAL and not fixed here — it makes
  every `Class.method` citation validate against the class. Filed rather than patched
  inside a platform-tier batch it does not belong to.
- **status:** fixed (citation); gate weakness recorded

## Finding 4 — P3 — asserted_fixture_value
- **file:line:** `lib/core/services/sync_service.dart:638-640`
- **claim:** The doc comment said `_syncReliabilityEnabled` has "exactly TWO gates".
  There are three — the third is the B3 version-conflict enqueue this same batch
  added, i.e. the newest and (per Finding 2) most consequential.
- **verification:** `grep -n "_syncReliabilityEnabled" lib/core/services/sync_service.dart lib/core/services/sync/sync_profile.dart` → 1 definition + 3 usages.
- **fix applied:** reworded to name all three sites.
- **status:** fixed

## Lenses that returned clean

- **missing_input** — enumerated every `profile['...']` read in `recomputeDerivedTargets`
  (`grep -no "profile\['[a-z_]*'\]" … | sort -u` → 11 unique keys) and diffed against
  `derivedTargetInputKeys`: exact 1:1, no gap. `WaterTargetService.computeFromProfile`
  reads only keys already covered.
- **writer_reader_drift** — enumerated every Hive writer of the four delta fields and
  the profile-derived set. The only split writers (`updateProgress`'s seed,
  `PhaseProgressReconciler`) are exactly the ones the per-key carve-out covers.
  Confirmed `toMap()` still emits both `carb_grams` and `carbs_grams`, and that
  `currentTargetMl()` never reads the stored `water_target_ml`.
- **asserted_fixture_value (beyond F3/F4)** — independently recomputed the calendar-age
  claim by brute-force sweep of every DOB 1980-2009 at 2026-08-30: **232 / 10,958 =
  2.117%**, exact match to the diff's prose. Traced `resolveActivityLevel('desk_job', 2)`
  → `'light'`. Spot-ran one `mutation_evidence` line and reproduced the stated result.
- **blast_radius_mismatch** — platform `requires:` all met; three new kill-switches,
  each reachable and default-correct.
- **function_exception_swallow / secrets_in_tree / unawaited_no_error_sink** — clean;
  commands recorded in the dispatch transcript.

## Founder triage notes
All four accepted and fixed in-batch per §4.2. Findings 1 and 2 were both introduced by
this batch's own earlier remediation — F1 by the N1 key-absent seed, F2 by an N10 fix
applied to two of three call frames. Both are now mutation-proven.
