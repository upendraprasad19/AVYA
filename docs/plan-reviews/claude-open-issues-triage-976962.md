---
branch: claude/open-issues-triage-976962
date: 2026-08-13
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi60-streak-identity-bpass.md
---

# Plan-review record — OI-60 pieces 1+2 (hold-week streak identity + the custom_template blackout)

## What shipped

Two defects in the same six lines of `ActiveWorkoutNotifier.completeWorkout`'s weekly-streak block,
plus two comment-only residuals:

- **FOB-2 (flag-gated, inert today).** `getCurrentWeekNumber()` clamps to `[1,4]` and a hold starts
  at `plan_start + 28`, so the dedup gate was `4 != 4` (the streak froze for the whole hold) and the
  `streaks` row key was always week 4's Monday (every hold completion overwrote that one row; cloud
  `streaks` is `UNIQUE(user_id, week_start)`).
- **The `custom_template` asymmetry (LIVE for all PRO users).** `planned` filtered
  `type == 'workout'` while `completedCount` filtered nothing. At 100% template conversion
  `planned == 0`, and both the increment and the row write are gated on `planned > 0` — a PRO user
  with a fully self-built week and perfect adherence got zero credit and no cloud row.
- **FOB-7(d)** — two stale line citations in `ai-proxy`'s size-envelope comment, de-numbered.
- **FOB-7(c)** — verified already-remediated; `verified_clean`, no code change.

Fix: extract `resolveStreakWeekState` (BOTH arms) + one shared `isTrainingDayType` predicate on both
sides of the ratio. Diagnose `a3f8d1`; closure `docs/audit/oi60-streak-identity.closure.yaml` (4/4
terminal). No migration, no EF deploy.

**Not §4.12.4 ship-dark tier.** The founder chose to fix the `custom_template` defect in this batch
rather than file it, which makes the flag-OFF path non-byte-identical — so `review_rounds: 1` was not
available and this took the full review.

## Review rounds — ground-truth verified against source, and each round's own corrections re-verified

This plan took **four** rounds because rounds 2 and 3 each found that the *previous* round's
correction had introduced the next defect. That is exactly the failure mode §4.12.1 predicts, and it
is why review #2 must run on the hardened plan rather than the original.

- **Round 1 — NOT CONVERGED (1 P0, 2 P1s).** Caught that the plan-review record path was wrong (the
  gate derives it from the branch, `/` → `-`, so a record at `open-issues-triage-976962.md` would
  never be found — a silent CI hard-fail), that `type: 'logged'` is a real schedule-row value
  (`workout_write_service.dart:454`, `sync_workout.dart:892`) so the proposed *inclusion* predicate
  would have silently dropped it, and that the numerator was left unfiltered so the asymmetry the
  plan claimed to close survived on the rest-day side. **All three re-verified by direct read before
  acting**, not taken from the review prose.
- **Round 2 — NOT CONVERGED (2 P1s, both introduced BY round 1's fixes).** Round 1's correction fed
  the *unclamped* index into `getWeek()` in the non-hold arm. `redoWeek4` extends only `plan_end`
  (`grep -n "_planStartKey" workout_schedule_write_service.dart` → nothing), so a rolled-week user
  sits at a true index ≥ 5 while the clamp reports 4 — that draft was a **live regression on the
  flag-OFF path**. Also refuted a false `plan_start` claim round 1 had introduced.
- **Round 3 — NOT CONVERGED (2 P1s).** Found that round 2's own P1-2 was itself a misdiagnosis:
  `train_provider.dart:567`'s `DateTime.now()` is inside `_autoGeneratePlan`, not the PRO advance,
  which passes `nextPhaseStartDate()` — so **round 1's original conclusion had been right all along**.
  I settled this myself by reading `nextPhaseStartDate` (`read_service:1446-1458`) rather than
  trusting either reviewer. Round 3 also found the extraction boundary made **five** verification
  rows unwritable (their asserted values are produced only inside `completeWorkout`, which the
  harness rule forbids driving) — a vacuous-test trap, the Gate-44 lesson.
- **§4.12.1 applied a second time, at round 3.** Rather than rewrite the churning paragraph a fourth
  time, the plan-start-moves-under-a-live-hold question was **deleted and filed as its own OI**. Round
  3's own assessment of its live risk was *nil*, it is not load-bearing for the fix, and three rounds
  had produced three different wrong answers. The extraction was simultaneously **widened to both
  arms** so every assertion became reachable.
- **Round 4 — CONVERGED.** No P0/P1. Five mechanical P2s (a code block and a test table left stale
  by the prose edits, an OI count, a `planStart`-must-match-Hive caveat), all applied. Round 4's
  verdict: *"The two edits did their job… Do not review this a fifth time; make the five edits and
  implement."*

## Ground-truth evidence

- **Every reviewer claim that changed the design was re-verified by direct file read** before acting:
  the `_planStartKey` absence in the write service, `type: 'logged'`'s two writers, the
  `_autoGeneratePlan` vs PRO-advance attribution, `nextPhaseStartDate`'s body, the strict `isBefore`
  hold-window filter, and the four `plan_start` write sites. Two reviewers contradicted each other on
  the advance path; the file settled it.
- **Mutation-proven, five mutations actually RUN** — each reddened only its intended cases:
  clamping the hold arm → 3 identity cases; `4 + ordinal` → the late-return case; narrowing `planned`
  to `type == 'workout'` → the blackout + `logged` cases; dropping the numerator's type filter → the
  completed-rest case; feeding the unclamped index to the non-hold arm → both flag-OFF cases
  (`Actual: 5` vs `Expected: 4`), including the redoWeek4 regression guard.
- 48/48 green across `hold_week_streak_identity_behavioral_test.dart` (new, 12 cases),
  `hold_display_read_path_test.dart`, `hold_week_mechanic_behavioral_test.dart`,
  `streaks_writer_to_reader_test.dart`. `flutter analyze` clean on both touched `lib/` files.
  Gate 40 PASS (25 closure files); diagnose-doc validator PASS.
- **This is the first test coverage the streak block has ever had** — a grep of `test/` for
  `last_streak_week|current_streak_weeks|workouts_planned` hits 12 files, none of which drove
  `completeWorkout`.

## Platform-tier artifacts

- `blast_radius: platform` — **measured, not asserted**: `scripts/blast_radius_from_diff.dart -`
  over the real file list returns `platform`. ⚠️ **Round 4 claimed "no glob matches
  `lib/features/train/**` or `lib/core/utils/**`, so the Dart changes alone would classify as
  `feature`" — that is WRONG on both halves, and I only caught it by running the tool instead of
  taking the claim.** Per-file, measured: `train_provider.dart` → `feature` (there IS an explicit
  glob, `docs/blast_radius.yaml:251`), but `phase_completion.dart` → **`account`** (the "anywhere
  else in `lib/`… `lib/core/utils`… is account" catch-all). So the Dart-only control returns
  `account`, not `feature`, and the `ai-proxy` comment edit
  (`docs/blast_radius.yaml:54`, `supabase/functions/ai-proxy/**` → platform) escalates
  `account → platform` rather than being the sole trigger of the review apparatus — §4.3's
  self-triggered B-pass would have applied to this batch either way. Recorded this way because a
  tier claim taken from review prose is exactly the "verified inputs ≠ verified conclusion" trap.
- `behavioral_test_path`: `test/contracts/hold_week_streak_identity_behavioral_test.dart`
- `code_review_b_pass`: accepted — `docs/reviews/oi60-streak-identity-bpass.md`, 4 findings
  (2 P1, 2 P2), **all four fixed in-batch** per §4.2. The B-pass found a real defect two P1-level
  plan-review rounds had missed (the injected hold ordinal can be stale relative to `workoutDate`
  across a midnight rollover, so the counts and the row key could describe different weeks) — a
  reminder that a plan review reads prose and only a diff review sees this class.
  It also caught that this record CONTRADICTED ITSELF: the frontmatter said `bpass: pending` while
  this line said `accepted`, naming a file that did not yet exist. Fixed by actually running the
  B-pass rather than by softening the claim.
- No migration, no Edge Function deploy → no live-prod-apply gate. The `ai-proxy` bundle is now
  comment-drifted from source; the next deploy's SHA delta is expected.
- OI-60 remains **OPEN** — `enable_hold_weeks` has not flipped, and the remaining FOB items stay hard
  flip-on preconditions. The flip itself requires its own full ×2 + `bpass: accepted` per §4.12.4.

## Prior round-1 review of the SUPERSEDED 6-item plan (history)

Before this narrow plan existed, a 6-item plan covering FOB-1,2,3,4,5,7 was reviewed and came back
NOT CONVERGED with structural redesigns in four items, which is what triggered the §4.12.1 split into
7 pieces. Its findings are retained at `docs/plan-reviews/open-issues-triage-976962-superseded.md`
(kept for the FOB-3/4/5 evidence that pieces 4-6 will need — notably: `AiSnapshotBuilder` has no
`Ref`; `AppEventsService` has no `event_name` column so a filter-by-event migration is unsatisfiable
as filed; `founder_metrics_engagement` cannot be `CREATE OR REPLACE` because adding a return column
changes its signature and a DROP drops its grants; and the reconciler's 1..4 scan **is** the
re-anchor trigger, so widening it buys zero healing).
