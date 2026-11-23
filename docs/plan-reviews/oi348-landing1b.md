---
branch: oi348-landing1b
date: 2026-11-23
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record — OI-348 Landing 1b (B3/B7 past-phase history, B5 dictation)

Plan: `docs/plans/oi348-walk-fixes-landing1b.md`, v3 FINAL. Two independent units, one review seat per
unit per round (context-blind Sonnet reviewers that verified every claim against the code, the
speech_to_text 7.4.0 plugin source and the live schedule rows).

## Rounds
- **Round 1 (v1): `not_converged`.** B3 seat: 2 P1 (carry-forward lets a stray stamp swallow
  unstamped rows; consecutive short runs defeat the absorb rule) + 5 P2. B5 seat: 3 P1 (prefix
  re-emission wipes committed words; a rescored whole-utterance final duplicates; the word-overlap
  fallback fold duplicates on numerals and contractions) + 4 P2. All resolved in v2 (B3: runs over
  stamped rows only, noise dropped before merging, rows assigned by date; B5: fallback removed,
  commit only on the plugin's segment end, one mode decision, whole-utterance final rule).
- **Round 2 (v2, fresh seats, on the post-round-1 text): `converged` on both units** (0 P0/P1).
  B3: 6 P2 + 2 P3; B5: 4 P2 + 5 P3, all applied in v3 in place (noise tied to the rest-row mechanism,
  edge rule bounded by the previous segment's last stamped day, `phaseForDate` short-circuit kept
  first, per-row widget agreement test, raw `resultType` int, empty-partial guard, telemetry seam and
  reset, `S1b` / `T8b` / `T10` / `T11` / `S13` tests).

## Ground truth verified
Read: `workout_schedule_read_service.dart` (bucketing, display wrapper, `phaseForDate`, generators),
`week_selector.dart`, `phase_progress_reconciler.dart`, `pro_phase_advance.dart`,
`plan_integrity_reconciler.dart`, `workout_schedule_write_service.dart` (`holdWeek`),
`speech_input_controller.dart`, `speech_input_service.dart`, `error_telemetry.dart`, the fake engine,
the plugin's Android, Dart and web sources. Live, read-only (project `dedsavbjuwgarrhphgnl`):
`user_progress.plan_json.schedules` of the walk account (168 rows, stamps/weeks/status per date).

## Execution
Inline, one worktree (`oi348-landing1b`), decided at start (§4.12.7).

## B-pass
Pending (self-initiated before the merge, §4.3).
