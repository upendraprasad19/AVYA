---
reviewed_at: 2026-06-09T22:40:00+05:30
staged_against: 6890fb3..HEAD (branch apk34-obs-batch-2026-06-09)
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, logic_correctness]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — apk34-obs-batch-2026-06-09 (6890fb3..HEAD)

Fresh context-blind Sonnet pass over the 8 fixes + version chore + skill edit.
**0 P0, 0 P1, 4 P2.** Load-bearing logic verified clean: BUG-A fast-path +
genuine-expiry, BUG-B parenthesized-ternary collection-if (valid Dart), BUG-C
apikey(anon)-vs-Bearer(user) + 5 awaited ensureFreshToken in sync, BUG-E
`Uri.replace` URL versioning + verbatim forDisplay, BUG-F streak counts
`type='logged'` and no reader crashes on a missing `exercises` key, blast_radius
declarations correct, no new unguarded `unawaited(`.

## Finding 1 — P2 — function_exception_swallow
- **file:line:** lib/core/services/ai_service.dart (`_directHttpCall` + `_directMediaHttpCall` token fallback)
- **claim:** the hard `refreshSession()` fallback sits in a bare `catch (_) {}` — a network error during refresh is swallowed with no telemetry.
- **verification:** `grep -n "catch (_)" lib/core/services/ai_service.dart`
- **status:** accepted_as_is — the block ENDS by `throw AiServiceException(..., statusCode: 401)`, which IS the error sink: the caller (ai_coach_provider) handles the 401 / re-auth, and the failed EF call surfaces upstream. Adding ErrorTelemetry here would require a new import for marginal value over the throw. Documented; not a correctness gap.

## Finding 2 — P2 — token_logic
- **file:line:** lib/core/services/ai_service.dart (same blocks)
- **claim:** `ensureFreshToken()` already refreshes internally; the caller may call `refreshSession()` a second time when the refresh token is dead (redundant round-trip).
- **verification:** Read supabase_service.dart:170-206 + ai_service.dart:400-420
- **status:** accepted_as_is — harmless belt-and-braces (only fires when the first refresh returned null AND no cached token; fails fast). Mirrors callFunction's own hard-refresh fallback. Not worth a behavior change.

## Finding 3 — P2 — writer_reader_drift  [FIXED in this batch]
- **file:line:** lib/core/services/sync/sync_workout.dart (BUG-F synthesize) vs lib/core/services/workout_write_service.dart markCompleted no-schedule branch
- **claim:** BUG-F synthesized row wrote `completed_at` (ISO string) while production `markCompleted` synthesize writes `completed_at_ms` (int epoch) — divergent schemas for the same logical row; a future `getScheduleForDate` change could regress one.
- **verification:** `grep -n "completed_at" lib/core/services/sync/sync_workout.dart lib/core/services/workout_write_service.dart lib/core/services/workout_schedule_read_service.dart`
- **status:** accepted_FIXED — the BUG-F synthesized row now writes BOTH `completed_at` (ISO) and `completed_at_ms` (epoch) so the two synthesize paths produce an identical schema. (Same diagnose e9b4a2.)

## Finding 4 — P2 — logic_correctness (perf)
- **file:line:** lib/core/services/workout_schedule_read_service.dart `_scheduledWorkoutDays` / `isPhaseExpired`
- **claim:** when today is past the stored end date, `isPhaseExpired()` does an O(n) `workoutBox.keys` scan on every call (Train/Home rebuild) — potential jank on a mature account.
- **verification:** Read workout_schedule_read_service.dart:600-650
- **status:** accepted_as_is — fast-pathed: the scan runs ONLY when the cheap stored-window check already says expired (a transient state the user resolves by generating the next phase). Bounded (~336 schedule keys), in-memory Hive reads (sub-ms), same pattern as the existing streak walk. Memoizing would add a listenable + invalidation surface disproportionate to a P2. Revisit if expired-state jank is observed.

## Founder triage notes
0 P0/P1. Finding 3 fixed in-batch (1-line schema parity). Findings 1/2/4 accepted-as-is with rationale above. Verdict: accepted — clear to merge.
