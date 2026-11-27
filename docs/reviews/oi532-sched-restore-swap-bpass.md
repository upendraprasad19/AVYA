---
reviewed_at: 2026-11-27T21:00:00+05:30
staged_against: f72863c4
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats: A lenses, B mutation)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 8
verdict: accepted
verdict_note: all findings fixed in the fold commit or recorded as accepted residue below; seat B survivors re-run on the fold tree
---

# Code Review — OI-532 (branch oi532-sched-restore-swap, reviewed f72863c4)

Two fresh Sonnet seats on the committed three-dot diff `origin/main...f72863c4` (main had not moved). Seat A ran the
eight lenses; seat B ran 44 new mutants in a scratch worktree (25 red, 19 survived).

## Finding A1 — P2 — guard_without_its_mirror
- **file:line:** lib/core/services/sync/sync_workout.dart (Case 2 `keepMarkedUnconfirmed`)
- **claim:** a marked row whose template link never resolves stays unconfirmed forever: re-sent every pass, and the
  restore is kept off its date permanently (before the change it confirmed once).
- **status:** fixed. `SchedUnpushedSwaps.maxMarkAge` (14 days): an expired mark reads as gone and is pruned. T10b;
  mutants p, r red.

## Finding A2 — P3 — guard_without_its_mirror (concurrency)
- **file:line:** lib/core/services/workout_write_service.dart `swapScheduledDays`
- **claim:** the pre-row mark is a new await between the read of the two rows and their writes; a restore (no date
  lock) landing a cloud completion in that gap would be overwritten from the stale read.
- **status:** fixed. Both rows re-read after the mark; any change refuses the swap (`day_swap_row_changed_mid_swap`).
  T14 / T14b; mutants q2, qA red (the first form of q was malformed: `false && !A || !B` still checked B).

## Finding A3 — P3 — guard_without_its_mirror
- **claim:** a cloud `completed` on a locally swapped date takes the cloud's content for that date.
- **status:** accepted (spec I6: the completion is what was done on that date; the partner day keeps its content until
  the push lands). Recorded in diagnose f5a2c8.

## Finding A4 — P3 — unawaited_no_error_sink
- **claim:** (a) a rolled-back swap keeps its pre-marks; (b) a throwing `markAll` leaves that swap unprotected.
- **status:** accepted. (a) clears on the next push (equal fingerprint, skip branch) and is bounded by A1's expiry;
  (b) fails open to the pre-fix behaviour with `workout_write_service_swap_mark` telemetry.

## Finding A5 — P3 — writer_reader_drift (inserted-lines sub-check)
- **claim:** stale cites: `notification_cron_eligibility_and_pro_gate` 132-134 / 179-180; `exercise_logs_read_path`
  moveExerciseLogs range; diagnose cite `sync_service.dart:1962`; OI-532 board lines.
- **status:** the first is a FALSE ALARM (those ranges cite `supabase/functions/*/index.ts`, not sync_service.dart; no
  shift). The rest fixed: moveExerciseLogs repointed to its doc comment + body (1047-1279; it was already mis-cited on
  main), every cite of the diffed files remapped through the diff hunks again after the fold edits, the diagnose cite
  now `:1943` / `:1965`, the closed OI-532 entry marked as pre-fix lines.

## Finding A6 — P3 — asserted_fixture_value (test teeth)
- **claim:** push-side kill switch, account switch, rescue path untested; T8 relies on pre-existing L3.
- **status:** fixed (T6b, U5, U8, T19). The rescue path goes through `swapScheduledDays` (covered by the contract
  test); T8 is kept as the launch-order proof.

## Finding B1 — P2 — mutation survivors (seat B, 14 real gaps)
- **status:** fixed with T15 (M13), T16 (M26), T17 (M27+M28 together), T18 (M35), T19 (M37), T20 (M40, M41), U5 (M1,
  M2), U6 (M7, M15), U7 (M14), U8 (M3), T6b (M22). Re-run on the fold tree: all red.
- **Equivalent / accepted:** M16, M18, M19, M24 (seat B's reasoning); M20 (`!index.aborted` on the clear:
  `pushIfChanged` returns false once aborted); M27 or M28 ALONE (each of the pair covers T17's owner change; removing
  both reddens T17); M42 (the flag getter fails open on a closed box, the pattern of every sibling getter); M44 (a
  `beginSwap` fault cannot be injected without a throwing box).

## Finding B2 — P3 — seat B false lead
- **claim:** T18's first form asserted a cleanup on September dates.
- **status:** fixed. `TemplateService.cleanSyncTemplateSchedule` sweeps from the REAL `DateTime.now()`, so T18 now
  observes the cleanup on a real future date.

## Founder triage notes
Self-triaged by the session (no decision for the founder in any finding).

## Tuning entry
- **2026-11-27** - blast-radius platform - 8 findings; 1 false_alarm (A5's EF ranges, misattributed to the wrong file:
  a registry block lists several `file:` entries); tuning: a mutant whose REPLACEMENT contains its original text
  reads as NOT-APPLIED in an exact-once driver, and `false && !A || !B` is not a full neuter of a two-clause guard;
  check operator precedence before calling a survivor a gap.
