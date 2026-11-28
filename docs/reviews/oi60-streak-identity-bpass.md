---
reviewed_at: 2026-08-13T07:10:00+05:30
staged_against: f8480c6d41ad
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — f8480c6d41ad

Fresh context-blind Sonnet subagent over the staged diff. Batch: OI-60 pieces 1+2
(hold-week streak identity + the `custom_template` blackout). 4 findings — 2 P1, 2 P2 —
**all four fixed in this batch** per §4.2. Every finding was re-verified against the source by the
main thread before being acted on; two of the four were errors the main thread had introduced
itself.

## Finding 1 — P1 — guard_without_its_mirror

- **file:line:** lib/features/train/providers/train_provider.dart (hold arm of `resolveStreakWeekState`)
- **claim:** The hold arm trusted the caller-injected `holdOrdinal` to drive
  `holdWeekSessionProgress(...)`, whose date range comes from `_holdDatesByOrdinal()[ordinal]`,
  while `streakWeekId` and `weekStartDate` were computed fresh from `workoutDate`.
  `holdStatusProvider` derives `todayHoldOrdinal` from `nowWall()` at provider-**build** time and is
  a plain (non-autoDispose) `Provider` cached until `currentPlanProvider` invalidates — which
  `completeWorkout` does only at its very last statement. `DayRolloverObserver` fires only on
  `resumed`/`paused`, never mid-foreground. So a session left foregrounded across a Sunday→Monday
  midnight rollover carries an ordinal for the PREVIOUS hold week while `workoutDate` is already in
  the next one, writing a `streaks` row **keyed to one week and populated from another**.
- **verification:** `grep -n "holdOrdinalForDate(nowWall())" lib/features/train/providers/train_provider.dart`
  (provider builds the ordinal from the clock) + `sed -n '858,872p' lib/core/services/workout_schedule_read_service.dart`
  (`holdWeekSessionProgress` is independent of `workoutDate`) + the `ref.invalidate(currentPlanProvider)`
  position as the last statement of `completeWorkout`.
- **suggested-fix:** re-derive the ordinal from `workoutDate`; fall back to the clamped arm on mismatch.
- **status:** **fixed** — the injected ordinal is now the **flag gate only** (it is null whenever
  `enable_hold_weeks` is OFF, because `holdStatusProvider` returns `HoldStatusData.empty`), and
  `effectiveOrdinal = readSvc.holdOrdinalForDate(workoutDate)` drives the counts, so identity, row
  key and counts describe one week by construction. A null `effectiveOrdinal` (hold elapsed, or
  rolled out of it) falls through to the clamped arm.
  **Mutation-proven:** reverting to `holdWeekSessionProgress(holdOrdinal!)` reddens the new
  "STALE injected ordinal" case with `Expected: <0>` / `Actual: <3>` — hold 1's completed count
  leaking into a row keyed to hold 2's Monday. Note the naïve mutation (`holdOrdinal` without `!`)
  does not compile, since `int?` cannot pass where `int` is required — the type system already
  blocks that spelling, which is why the `!` form is the honest mutation.
  Two new behavioural cases: the stale-ordinal case above, and its mirror (a non-null injected
  ordinal with `workoutDate` outside any hold week → clamped arm).
  **This is the finding that justifies the B-pass.** Four plan-review rounds missed it; a plan
  review reads prose, and this class only shows against a diff.

## Finding 2 — P1 — review_record_integrity

- **file:line:** docs/plan-reviews/claude-open-issues-triage-976962.md
- **claim:** The frontmatter said `bpass: pending` while the body asserted
  `code_review_b_pass: accepted`, naming `docs/reviews/oi60-streak-identity-bpass.md`, which did not
  exist. The same staged document contradicted itself and cited a nonexistent artifact either way;
  §4.12.3 requires `bpass: accepted` for a ≥platform merge, and the keystone gate additionally
  requires the named file to EXIST and contain a line-anchored `verdict: accepted`.
- **verification:** `test -f docs/reviews/oi60-streak-identity-bpass.md` → missing.
- **status:** **fixed** — resolved by actually running the B-pass and writing this file, not by
  softening the claim. The main thread had already downgraded the frontmatter to `pending` when the
  first B-pass attempt died mid-run (so the tree never carried an unqualified false claim), but had
  missed the body line; the reviewer caught the residue. Both now consistent.

## Finding 3 — P2 — writer_reader_drift

- **file:line:** docs/sot_registry.yaml (`streaks` writers); lib/core/utils/phase_completion.dart
- **claim:** The registry's "corrected 2026-08-13" note claimed the stale citation was wrong
  "while the method starts at 1809". `completeWorkout` starts at **1514** pre-diff and **1599**
  post-diff — never 1809 in either version (1809 pre-diff lands inside the streak-row write block).
  Separately, `isTrainingDayType`'s claimed range `30-55` skipped line 29, its own docstring opener.
  Both are line-range errors inside the commit whose stated purpose includes fixing line-range drift.
- **verification:** `git show HEAD:lib/features/train/providers/train_provider.dart | grep -n "Future<void> completeWorkout"` → 1514;
  current tree → 1599; `grep -n "Whether a \`schedule_\*\` row's" lib/core/utils/phase_completion.dart` → 29.
- **status:** **fixed** — ranges corrected to `1599-2030` (post-diff `completeWorkout`),
  `491-598` (`resolveStreakWeekState`), `29-55` (`isTrainingDayType`), with the measurement command
  recorded in the entry so the next reader can re-derive rather than trust it. Genuinely embarrassing
  class: a correction to a line-range citation that was itself a wrong line-range citation.

## Finding 4 — P2 — guard_without_its_mirror

- **file:line:** lib/core/utils/phase_completion.dart vs lib/core/services/workout_schedule_read_service.dart
- **claim:** `isTrainingDayType` and `holdWeekSessionProgress`'s inline
  `type == 'rest' || type == 'off'` are the same rule kept as two independently-maintained copies.
  The doc comment asserted "the two must agree" but nothing enforced it, so a future edit to one
  silently diverges from the other — the exact drift class this batch exists to close.
- **verification:** no `isTrainingDayType(` reference anywhere in `workout_schedule_read_service.dart`.
- **status:** **fixed** — `holdWeekSessionProgress` now calls
  `isTrainingDayType((row['type'] ?? '').toString())`. The plan had said "leave it untouched unless
  provably character-equivalent, default don't"; the reviewer is right that a comment is not
  enforcement, and the predicates were already semantically identical, so collapsing to one copy is
  zero-behaviour-change and removes the drift surface. All 4 hold/streak test files stay green.

## Main-thread residue found while fixing (not a reviewer finding)

While repairing Finding 1's test coverage, the main thread found a **vacuous assertion in its own
new test**: the wiring case extracted the function body with `stripped.indexOf('\n}', fnStart)`,
which stops at `}) {` — the named-parameter list's closing brace, at column 0. The window was
therefore only the six-line signature, and both `isFalse` assertions in it were passing because an
empty window contains no violation. It surfaced only because a later `isTrue` assertion could not
pass against an empty window. Fixed by extracting from the end of the parameter list, plus two
guard-the-guard assertions (`body.length > 400` and a positive `holdWeekSessionProgress(` sanity
check) so a future truncation fails loudly instead of silently. Same family as
`feedback_green_check_input_set_width.md` — a green check is only as wide as its input set.

## Lenses that returned clean

- **function_exception_swallow** — `git diff --cached | grep -n "functions.invoke"` → no matches.
  The diff touches no `.functions.invoke(` call site.
- **blast_radius_mismatch** — cross-checked the measured `blast_radius_from_diff.dart -` output
  against `docs/blast_radius.yaml`: `train_provider.dart` = feature,
  `phase_completion.dart` = account (the `lib/core/utils` catch-all), the `ai-proxy` touch escalates
  account → platform. Consistent with the declared `blast_radius: platform`; no mismatch.
- **secrets_in_tree** — `git diff --cached | grep -nE "sk-[A-Za-z0-9]{10,}|rzp_live_|AKIA[0-9A-Z]{16}|-----BEGIN"`
  → no matches.
- **unawaited_no_error_sink** — `git diff --cached | grep -n "^\+.*unawaited("` → no matches. The two
  pre-existing `unawaited(syncProgressNow())` / `unawaited(evaluateAndPromote())` calls near the
  diff are untouched by it.

## Founder triage notes

All 4 findings accepted and fixed in-batch (§4.2 — no deferrals). Verdict `accepted`.
Post-fix state: `flutter analyze` clean on all 3 touched `lib/` files; 14/14 in the new behavioral
test and 51 green across the four hold/streak test files; six mutations run in total across the
batch, each reddening only its intended cases.
