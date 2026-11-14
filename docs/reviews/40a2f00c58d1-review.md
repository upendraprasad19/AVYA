---
reviewed_at: 2026-10-23T12:00:00+05:30
staged_against: ff88cdbfee71 (reviewed); named by the hash after the F5 fix was staged
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
---

# Code Review — cardio-duration-distance (OI-389 Batch 1a)

One fresh read-only Sonnet seat with an exhaustive command list (read-only git, file reads, `flutter analyze lib/`, the batch's own test files). 0 P0, 0 P1, 1 P2, 4 P3.

## Finding 1 — P2 — writer_reader_drift
- **file:line:** lib/core/services/sync/sync_workout.dart (per-set push `clamp(0, 3600)`) vs `kMaxSetDurationSec = 21600`
- **claim:** a cardio set over 60 min is kept on this phone, but the cloud per-set row is clamped to 3600 s, so a second device restores 60 min.
- **verification:** `grep -n "clamp(0, 3600)" lib/core/services/sync/sync_workout.dart`
- **suggested-fix:** land OI-391 before the store launch.
- **status:** known_tracked — plan §0 and the diagnose-doc record it (founder D8); OI-391 (Batch 2) owns the cloud cap; closure ledger SPLIT-OI-391 `blocked_on_user`.

## Finding 2 — P3 — guard_without_its_mirror
- **file:line:** lib/core/services/workout_write_service.dart `_resolveLoggingType` (stored cardio/distance before the shape guess)
- **claim:** a custom name stored as cardio stays cardio when a later caller logs it as timed.
- **verification:** `grep -n "storedType ==" lib/core/services/workout_write_service.dart`
- **status:** false_alarm — by design (plan U3, round 6 B P2-2; mirrors the sticky exercise_id): the sticky type is what keeps a custom cardio row's km when the chat card re-logs it (T28b, M39b red). Custom-exercise precedence is Batch 1b's.

## Finding 3 — P3 — writer_reader_drift
- **file:line:** lib/core/services/workout_write_service.dart logExercise entry rebuild
- **claim:** a re-log on a restore-shaped / F5 row drops its top-level km.
- **verification:** `grep -n "totalKm" lib/core/services/workout_write_service.dart`
- **status:** known_tracked — OI-393 (d), recorded in the diagnose-doc as a known limit; the same reset is today's behaviour for every aggregate; 0 such rows live.

## Finding 4 — P3 — writer_reader_drift
- **file:line:** lib/core/services/sync/sync_workout.dart `isTimedOrCardio`
- **claim:** a distance row's summary `duration_seconds` is pushed as 0.
- **verification:** `grep -n "isTimedOrCardio" lib/core/services/sync/sync_workout.dart`
- **status:** false_alarm — unchanged push code, verified in plan §2 ("a distance row's duration travels per set only"); readers resolve per-set first and the per-set rows carry it.

## Finding 5 — P3 — guard_without_its_mirror
- **file:line:** lib/core/utils/cardio_format.dart `cardioDistanceDetail`
- **claim:** a per-set km of 0.0004 passes `km > 0` and prints "0 m".
- **verification:** `grep -n "round() > 0) formatDistance" lib/core/utils/cardio_format.dart`
- **status:** accepted, fixed — a km that rounds to 0 m is omitted (and the reps-rule count test uses the same rounding). T25 leg `600 s + 0.0004 km → "10 min"`; mutant (back to `km > 0`) reddens T25.

## Founder triage notes
Self-triaged per the account-tier advisory verdict; F1 and F3 are founder-ordered follow-ons (D10, 2026-10-22).
