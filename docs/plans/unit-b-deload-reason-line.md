# Unit B — deload reason line: fix the stale-reason defect, then flip

**Branch:** `unitb-deload-reason` · **Blast-radius:** platform (verified via
`blast_radius_from_diff.dart -`) · **OI-53 flag 4 of 12.**

Split out of the phase-arc flip on 2026-09-05 by founder decision, because the
line carries an unfixed defect. This unit fixes it, then flips
`enable_deload_reason_line` → `disable_deload_reason_line`.

## 1. Bug-history lookup (§4.1.5)

`docs/diagnoses/INDEX.md` contains **zero** entries matching `deload`
(`grep -inE "deload" docs/diagnoses/INDEX.md` → 0 lines). The nearest neighbours
are week-4 *identity* bugs (`f4c8e1` hold-week clamp, `d7f3a9` `redoWeek4`,
`a7d3f1` restore week/phase drift), none of which touch the reason string.
**Not a recurrence** — recorded explicitly so a future audit can verify.

It IS an instance of the repo's default suspect class, writer/reader drift
(`feedback_writer_reader_field_drift_recurring.md`, ≥15×): two facts about one
decision are stored in two places and only one of them is maintained.

## 2. The defect — writer and reader by file:line

**Reason WRITER** — `lib/core/services/deload_evaluator.dart:159-162`
`box.put('deload_reason_phase_$phase', deloadDecisionReason(...))`.
Reached only under Guard 1 (`triggeredDeloadEnabled && readinessEnabled`,
`:55-56`) — **both LIVE since 2026-09-01**, so these keys exist in real users'
Hive today. Gated additionally by the idempotency flag at `:78-79`
(`deload_evaluated_for_phase_<P>`).

**Reason READER** — `lib/core/services/workout_schedule_read_service.dart:1109-1120`
(`currentDeloadReason()`), via `deloadReasonProvider`
(`train_provider.dart:944-947`) → `phase_arc_strip.dart:67-69`.

**No deleter exists** — `grep -rn "deload_reason_phase" lib/` returns 4 hits, all
declaration/comment/write/read; none delete.

**Character WRITERS that invalidate a stored reason** (each re-stamps week 4 back
to `deload` while the reason still says `working`):

| # | Path | Re-stamps blob | Re-stamps rows | Stays in phase P |
|---|---|---|---|---|
| 1 | `workout_schedule_read_service.dart:388` (`generateAndScheduleFromDate`), live caller `edit_profile_screen.dart:2029` | yes (`plan.toMap()`) | yes (`:288/:309/:487/:508`) | yes — `phase: currentPhase` (`edit_profile_screen.dart:2022`) |
| 2 | `regenerate_plan_planner.dart:294` (AI-coach regen) | — | yes | yes — `resolvedPhase` (`:168-177`) |

Path 2 was **not** named in the phase-arc flip's split note; found by this
investigation. Both are reachable by an ordinary user mid-phase.

**Failure chain.** Eval lifts week 4 of phase P → rows+blob become `working`,
`deload_reason_phase_P` = *"Working week — you've recovered…"*, flag set. User
edits their profile and taps Reschedule (or asks the coach to regenerate) →
week 4 is re-stamped `deload`. Next eval → `:79` returns early on the flag, so
nothing rewrites the reason. **The strip renders a `DELOAD` node above "Working
week — you've recovered", for the rest of phase P.**

## 3. The source-of-truth subtlety that shapes the fix

The strip renders the **blob**: `phaseArcProvider` → `currentWaveCharacters()`
(`read_service:1224-1232`, `current_plan.week_plans[i].week_character`).
`currentDeloadReason()` derives its phase from the **scheduled rows**
(`getWeek(4)`). A validation written against rows could therefore contradict the
node it sits under. **Validation must read the blob** — the same source the strip
renders — mirroring how `deloadPhaseFromWeek4` is already shared by writer and
reader so the key can never drift.

## 4. The fix

**Writer** (`deload_evaluator.dart:159-162`) — store the decision's OUTCOME
alongside its prose:

```dart
await box.put('${…deloadReasonKeyPrefix}$phase', {
  'text': deloadDecisionReason(…),
  'week_character': liftedAny ? 'working' : 'deload',
});
```

`liftedAny` is already the exact predicate the copy branches on
(`deload_reason.dart:27-31`: a `shouldLift` that lifted nothing must read as a
kept recovery week). Storing it makes explicit what the copy already assumes.

**Reader** (`currentDeloadReason()`) — self-validating: return the text only when
the stored `week_character` equals the blob's week-4 character. Mismatch,
malformed, short blob, or a **legacy bare String** → `null`.

**Why the reader and not a deleter.** A deleter must be added to every
plan-mutating path — two today, and silently owed by any third added later. The
reader is one seam that covers all of them, including cross-device sync and
restore. This is the "fix the class, not the instance" rule from
`feedback_mistake_guard_without_its_mirror.md`.

**Mirror case (lens 6).** The inverse — stored `deload`, blob `working` — is
reachable via a cross-device sync landing a lifted blob over a local keep. The
check is therefore **equality**, not "is it working".

**Legacy bare Strings** (written since 2026-09-01) cannot be validated and
resolve to `null`. Nothing is lost: the display flag is OFF today, so no user
currently sees a line, and the value self-heals at the next phase advance.

**Explicitly NOT doing** — clearing `deload_evaluated_for_phase_<P>` on regen so
the eval re-runs and writes a correct line. That mutates a LIVE feature
(`triggered_deload`, live 2026-09-01): a re-eval could lift the freshly
regenerated week 4. Round 2 of the phase-arc review rejected exactly this class
of change. No line is the honest, inert outcome, and it degrades to precisely
what ships today.

**Also NOT re-proposing** — `_liftWeekFour` returning blob-write state. Round 2
proved it targets an unreachable contradiction while creating a reachable one.

## 5. The flip

`enable_deload_reason_line` → `disable_deload_reason_line`, catch-block default
`false` → `true`. Dev-panel toggle updated to the delete-key-restores-default
shape. §4.12.4's lighter `ship_dark_build` tier does **not** apply to a flip:
full ×2 + `bpass: accepted`.

## 6. Tasks

1. Diagnose-doc for the stale-reason defect.
2. Writer: store `{text, week_character}`.
3. Reader: validate against the blob; null on mismatch/legacy/short.
4. Behavioral regression test — must fail without the fix (mutation-proven, and
   the mutation must leave the code compiling per rule 21).
5. Flip the flag + dev panel + the `enable_…` set in
   `phase_arc_reader_behavioral_test.dart:209`.
6. Docs: flags comment, `sot_registry.yaml`, `lib/features/train/CLAUDE.md`,
   `ship_dark_pending_review.yaml`, OI-53 count, closure YAML.
7. Owed from the prior turn: `docs/superpowers/skills-log.md` compaction line.
