---
review: workout-adherence-d1 B-pass (⑧ 8-A/D1 — phase-completion-rate extraction)
branch: workout-adherence-d1
date: 2026-07-17
reviewer: context-blind adversarial subagent (B-pass, §4.3, account)
blast_radius: account
verdict: accepted
---

# B-pass — Batch 8 UNIT 1 (D1: adherence-signal extraction)

Context-blind adversarial review of the implemented diff (4 changed + 3 new files) + a live run
(`flutter analyze` clean; the behavioral suite green; the reader-manifest gate green). Branch HEAD ==
main `650ac0d4`; diff scope exactly the intended files.

## Verdict: ACCEPTED — no P0/P1. One P2, fixed IN-BATCH.

Per-claim verification (all confirmed to source):
1. **Byte-identical card refactor** — the list-comprehension adapter feeds `phaseCompletionRate` the same
   iteration in the same order; the helper reproduces the old loop exactly (rest-skip, done-count,
   `total==0→0.0`, int/int→double). `canGraduate` (`>= phaseUnlockCompletionRate`) + the displayed %
   read the unchanged return value. No edge diverges. ✓
2. **isRest/isDone + demotion** — the read-service rule is character-identical to `train_provider.dart:
   601-603/637-638`; reads via `getWeek`→`getScheduleForDate`, inheriting the completed→planned
   cross-date demotion (`:460-472`), not a raw box walk. ✓
3. **Inertness** — `currentPhaseCompletionRate()` has NO production caller (grep) → D1 changes nothing at
   runtime beyond the byte-identical card move. ✓
4. **Tests** — 9 green; each axis genuinely pins (demotion, custom_template, paused, dynamic span, the
   phase-1 cap). No trivially-passing assertion. ✓
5. **Gates/analyze** — `flutter analyze` clean; `check_reader_manifest_complete` green (the read goes
   through the already-manifested `getWeek`/`getScheduleForDate`, not a new raw-prefix scan); no
   hive-map-drift risk (null-safe `type`/`status` reads). ✓
6. **SoT + record** — structurally well-formed. ✓

## P2 (fixed in-batch — §4.2)

**`currentPhaseCompletionRate()` totalWeeks did NOT mirror the card for a phase-1 mid-phase regen.** The
initial implementation used a bare scan (weeks 5-12) regardless of phase, and asserted (in the comment,
the SoT note, and this record) that it was "equivalent for all real data because a phase-1 plan has no
weeks 5-12 rows." **That is false:** a mid-phase Edit-Profile regen calls `generateAndScheduleFromDate`,
which does NOT move `plan_start_date` when `!isFirstGeneration` (`workout_schedule_read_service.dart:270-
275`) but materializes 4 weeks from today's Monday (`:267`) — leaving a `current_phase==1` plan with
week-5/6 rows (relative to the unchanged `plan_start`). The card caps phase-1 at 4 weeks
(`train_provider.dart:583`); a bare scan would count weeks 5-6 and under-report — the exact writer/reader
drift the extraction exists to kill.

**Fix (root, in-batch):** made the method phase-aware — `phase = UserRepository.getProgress()
.current_phase ?? 1`, then `phase<=1 ? 4 : scan(weeks 5-12)`, mirroring `train_provider.dart:582-592`
exactly. Added a behavioral pin (`phase 1 with week-5/6 rows → totalWeeks capped at 4 → 2/4 not 2/6`) +
seeded `current_phase=2` for the phase≥2 dynamic-span case. Corrected the three false "no weeks 5-12
rows / equivalent for all real data" statements in the comment, SoT, and this plan-review record.

## Verification after the P2 fix
`flutter analyze` clean; `phase_adherence_rate_test.dart` = **9 GREEN** (adds the phase-1-cap pin).
Byte-identical to the card (now including the totalWeeks span), inert, account-tier, no flag, no migration.
No open issues.
