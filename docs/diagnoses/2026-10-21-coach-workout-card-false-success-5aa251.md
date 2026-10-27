---
bug_id: 5aa251
date: 2026-10-21
batch: train-coach-log-refresh (OI-370 B', saved signal; R1B-F3 of coach-log-truth)
status: fixed_in_code
tier: m_fix
blast_radius: account
symptom: >-
  The chat workout card (`WorkoutLogConfirmCard`, CONFIRM · LOG WORKOUT) cleared itself after every CONFIRM whether
  anything saved or not: `submitWorkoutDraft` ignored the `WriteResult` of each `logExercise` and of `markCompleted`,
  then cleared the draft. A failed exercise vanished with no word, a saved one gave no confirmation, and when the card
  was unmounted mid-submit (channel switch, OI-232) the clear ran on a dead `WidgetRef` and threw `StateError`. Found
  while planning coach-log-truth (review finding R1B-F3) and confirmed in code.
concept: coach_workout_card_saved_state — the card shows what the submit really did, from draft state the card watches.
sot_registry_entry: coach_workout_card_saved_state
writers:
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method_or_widget: "submitWorkoutDraft: per-exercise result → markSaved / keepFailed; the day mark gated on !wasCompletedBefore (status completed AND wlog_ present); the refresh on a save OR a new day mark; no WidgetRef passed to the write service; draft-id re-check before each write and before the mark", line: 334 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "WorkoutDraftNotifier.beginSubmit / markSaved / keepFailed / endSubmit / setDraft (held) / updateSet / discard", line: 1830 }
readers:
  - { file: lib/features/ai_coach/widgets/workout_log_confirm_card.dart, method_or_widget: "WorkoutLogConfirmCard.build via cardStateFor: saved row, partial / none-saved note, day line, Skipped line, held notice, discard confirm", line: 96 }
  - { file: lib/features/ai_coach/widgets/workout_draft_slot.dart, method_or_widget: "WorkoutDraftSlot keys the card by draft id", line: 18 }
hive_key_prefix: "exlog_, wlog_, schedule_"
hive_key_formula: "unchanged (WorkoutWriteService.logExercise / markCompleted); the date is the draft's first-attempt date"
sync_methods: [syncWorkoutData, pushSnapshot]
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/ai_coach/workout_log_confirm_card_saved_signal_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, fn: istDateStr, note: "a retry after IST midnight writes to the first attempt's day (firstAttemptAt), never the new day" }
provider_invalidations:
  - "workoutSurfaceProviders via invalidateWorkoutSurfaces when anything saved (see e2a418)"
telemetry_op_types:
  success: ["none new"]
  failure: ["none new: a failed logExercise is shown on the card (note) and is already reported by WorkoutWriteService"]
cross_account_guard: "the submit re-reads the current draft id through the captured container before each write and before the prior-status read / markCompleted; an auth change (WorkoutDraftNotifier.build reruns on authUserIdTokenProvider) makes it return at once. build() also drops a held card and cancels the hold timer, so neither crosses accounts. Known, stated: an auth flip inside logExercise's own lock await is not covered (plan R10-P3)."
forbidden_patterns_checked:
  - "a widget-local `_isSubmitting` / saved flag — REJECTED: lost on the card's rebuild and on unmount; state lives in the provider and is watched."
  - "markCompleted only when every exercise saved — REJECTED (R8B-P1-1): Train shows a day's logs only once it is done, so a partial save followed by DISCARD would hide saved sets for good."
  - "markCompleted on an already-completed day — REJECTED (R8A-P2-3): it replaces wlog_<date> wholesale and would drop the earlier workout's name, duration and rpe."
  - "a trimming input formatter — REJECTED (R6B-P2-2): it silently changes 1.2.5 to 1.2 and 8.5 to 85; bad input is rejected, deletions are always accepted."
  - "the edit sheet reading parentRef after a rebuild — REJECTED (R8A-P1-1, b7f3e2 class): the sheet captures the draft id and notifier at open."
proposed_fix: >-
  `submitWorkoutDraft` returns a `DraftSubmitOutcome`, attempts every exercise by index, skips (and names) exercises with
  no usable set, marks the day once anything from the card saved unless it was already done, and ends in `markSaved`
  (saved hold, then clear or show the held card) or `keepFailed` (only the failed exercises stay, with an in-card note
  naming what saved and what did not). Submitting, status, saved / skipped names, note, attempt count, first-attempt date,
  held-card flag and day-not-marked are immutable draft state; every write is id-guarded. Copy and TalkBack labels are
  founder-approved 2026-10-21.
regression_test_planned:
  - "test/ai_coach/workout_log_confirm_card_saved_signal_test.dart (43 cases, through the real WorkoutDraftSlot over a real Hive temp dir): saved; submitting + second submit refused; partial (note, pencil tap action, re-announce, fix and retry, day marked once); bodyweight bad weight; none saved; day not marked; already-done day not overwritten; skipped leftover; unusable sets skipped; cardio logged; skipped survives a retry; partial day-not-marked; held (a)-(e) + held during a partial + the held announcement once; cumulative saved names; discard after partial; auth flip mid-submit and after the writes; draft-id guard via auth; id guards direct; retry after IST midnight; stale edit sheet; timer cancel; TalkBack labels and live regions; input formatter (reject, never trim; backspace from a seeded negative; guard cases); cardStateFor and scroll truth tables; pins; large text at 320 dp incl. the densest state."
  - "test/contracts/conversational_log_handler_uses_write_service_test.dart: the three signature pins repointed to the new signature, not loosened."
mutation_proof: >-
  Scripted (scratchpad mut/run.py, exact-one-match replace, flutter test on the named file, restore in a finally,
  byte-compared after): every B' mutation listed in plan §3 (ignored logExercise result, keepFailed not trimming, no day
  mark on partial, !wasCompletedBefore removed, each id guard, both re-checks, cumulative names, updateSet resetting
  status, held notice, held applied at once, discard without confirm, formatter deletion clause and its length guard,
  trimming formatter, retry using the clock, Skipped line outside the live region, hasNote ignoring skipped,
  consumeHoldAnnouncement not called, unusable kept, enabled semantics, submitting not in draft state, second submit not
  refused, pencil without onTap, live region not keyed, weight field hidden, onDispose cancel removed, updateSet while
  saved, scroll rule, day line never passed, dayMarked ignoring a done day, names not de-duplicated, saved state removed,
  saved cleared at once, markSaved through ref). Per-mutation results in docs/audit/train-coach-log-refresh.closure.yaml. After the B-pass (fb5048e68fae): refresh only on a save, refresh always, the wlog_ check dropped, ref passed again, the held-card tap guard removed / on every card, "Discard the rest" under the finger, a saved card re-submitting, haptic removed / on every change, scroll arguments swapped: all red.
  Self-attested.
impact_analysis: >-
  Behaviour change, founder-approved 2026-10-21: the card now stays on screen after CONFIRM (1.5 s saved, 4 s with a
  day or Skipped line), keeps failed exercises with a note, asks before discarding after a partial save, and holds a new
  coach card while the current one is saving or failed. A partial save marks the day done (so the saved sets show on
  Train). A retry after midnight writes to the first attempt's day.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ clean; the 43-case slot test green" }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "exlog_/wlog_/schedule_ asserted in a real Hive temp dir per case (one wlog_ on a partial, unchanged on retry, untouched on a done day, none after an auth flip)" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no schema change" }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "the WriteService sync fan-out is unchanged" }
recurrence: "Same class as the AI breakdown card's 'didn't log' bug (ai_coach CLAUDE.md pitfall: every save action that mutates data MUST give the user a confirmation signal) and b7f3e2 (a WidgetRef used after its widget was disposed). Searched INDEX for WriteResult / ignored result / confirmation signal / disposed ref."
related_bugs:
  - b7f3e2
---

# The chat workout card cleared itself whether or not anything saved

## What was wrong

`submitWorkoutDraft` (origin/main `conversational_log_handler.dart:282-336`) awaited `logExercise` (`:303`) and
`markCompleted` (`:314`) without reading their `WriteResult`, then called
`ref.read(workoutDraftProvider.notifier).clearDraft()` (`:336`). The card had a widget-local `_isSubmitting` flag and no
saved state, so the user saw the card vanish in every case, and a card unmounted mid-submit threw on the dead ref.

## Fix

See `proposed_fix`. The card's states and copy are in plan §2 B' of `docs/plans/train-coach-log-refresh.md`.

## Not changed here

Two coach write paths for one request: OI-373. `logExercise` accepting a negative duration: OI-382. Coach-logged
workouts not counting toward `total_workouts_done`: OI-379.
