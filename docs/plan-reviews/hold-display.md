---
branch: hold-display
blast_radius: account
tier: ship_dark_build
review_rounds: 1
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/hold-display-bpass.md
---

# Plan review — hold-display (free-tier "Hold the Line" DISPLAY, Slices 2-6)

## What shipped

Slice 1 (branch `hold-mechanic`, merge `7ca850d9`) taught the write path to materialize hold weeks
— row-stamped `is_hold` + `hold_ordinal`, Monday-backdated, `plan_end` extended. It was invisible.
This batch makes it visible, built to the founder-locked mockup
`docs/design/holdweek_train_mockup.html`:

- **Read path** (additive, `WorkoutScheduleReadService`): `holdWeeks()`, `holdOrdinalForDate()`,
  `holdWeekSessionProgress()`, plus the pure `isDeloadHold(n) = n % 4 == 0` — the display half of a
  cadence the writer computes but never persists.
- **`holdStatusProvider`** (`train_provider.dart`): the SINGLE branch point every hold surface
  reads, returning `HoldStatusData.empty` whenever `enable_hold_weeks` is OFF.
- **UI**: `HoldChipGroup` (H-n chips, ✓, dashed upcoming-deload preview, read-only week sheet) in
  its own file; `HOLDING · Hn` pill + honest SESSIONS tally in the plan header; a date-sourced
  today card; `HoldRoadmapStrip`; and the hold promoted to an accented pill on the day-29 wall.
- **De-duplication**: the `enable_hold_weeks` branch previously existed in two independently-edited
  call sites; it now lives once, in `runFreeTierRepeatWrite`.

No migration, no Edge Function deploy, no schema change.

## The root cause this batch had to solve (ground truth, verified against source)

The mockup's centrepiece — a today card reading "TODAY · HOLD WEEK" with a working START button —
was **not reachable by pure addition**, and the original plan claimed it was. Verified:

`holdWeek()` stamps hold rows `week = 4 + ordinal` (`workout_schedule_write_service.dart`, pinned by
`hold_week_mechanic_behavioral_test.dart`), but `CurrentPlanData.weeks` only ever holds 4 entries for
phase 1 (`train_provider.dart` hardcodes `totalWeeks = 4` for `phase <= 1`). So `getWeek(5)` returns
`[]`, and the today card — which sources `plan.getWeek(plan.currentWeek).todayWorkout` — can never
find a hold day. This is the repo's recurring **writer/reader drift** class: writer stamps week 5,
reader indexes `getWeek(4)`.

The fix is a hold-specific read path keyed on `hold_ordinal`/date, with exactly one guarded branch in
shared rendering (the today card). The alternative — un-clamping `getCurrentWeekNumber()` — is the
16-P0 project in `docs/plan-reviews/free-tier-hold-findings.md` and is deliberately **out of scope by
construction**: this batch modifies no clamped reader, so P0-1/2/6/7/8/9/12/13 are not reachable from
this diff. That is a scope boundary, not a deferral — see `docs/audit/hold-display.closure.yaml`.

## Review rounds

**Ship-dark build tier (§4.12.4) — 1 independent round.** `enable_hold_weeks` stays **default OFF**;
every new surface reads the single `holdStatusProvider` branch point, which returns the `const`
empty singleton when the flag is off. The `ship-dark` group in
`test/contracts/hold_display_read_path_test.dart` is the byte-identical evidence: with the flag OFF
the legacy `redoWeek4` path stamps `is_hold` on no row, so every hold reader returns empty — and,
after the B-pass, a `ProviderContainer` test proves the provider ALSO returns empty in the rollback
case (flag ON → holds materialized → flag OFF), which is the only case where stale data could leak.

Blast-radius **verified by running the tool** (`scripts/blast_radius_from_diff.dart` → `account`),
not asserted — the findings doc records that tier being wrongly asserted twice before. `account` is
below the threshold at which the gate itself demands `bpass: accepted`; the B-pass was run anyway
because §4.3 requires it self-initiated for any ≥account code change.

**B-pass** (`docs/reviews/hold-display-bpass.md`, verdict: accepted). Fresh context-blind Sonnet over
the staged diff. **4 findings, all real, all fixed in-batch** — every one re-verified against source
by the author before acceptance rather than taken on the subagent's word:

- **P1 — hold chips lingered and were RELABELLED after a PRO phase advance.** The hold scan was
  unbounded, so a user who held on Phase 1 and then converted to PRO kept seeing their Phase-1 holds
  under a "PHASE II · HOLDING" header, double-rendered alongside `pastPhaseBlocks()`. Fixed by
  scoping the whole hold read surface to `date >= plan_start`. **The batch's own tests all passed
  before this** — none of them modelled a phase advance, and the failure only appears on the
  conversion path.
- **P2 ×3** — the provider's flag-OFF early return was untested and cited a test file that did not
  exist (the unverified-claim class); the closure ledger overclaimed hold-UI coverage; one SoT
  `line_range` was wrong (56-115 → 56-99). All fixed, including writing the missing tests.

**Convergence:** the round produced no P0, and its one P1 was a contained scoping bug fixed at the
root with a regression test that fails without the fix. Per §4.12.4 the FULL ×2 review is required
again — no exceptions — on the commit that flips `enable_hold_weeks` on, which is where real user
risk starts. Both `enable_hold_weeks` rows in `docs/ship_dark_pending_review.yaml` must clear in that
one commit.

## Ground-truth verification

- `holdWeek()`'s stamped fields, types and `n % 4 == 0` cadence read from source, and re-proven by
  driving the REAL writer in the new tests (not a hand-built fixture).
- `week=4+ordinal` vs `totalWeeks=4` clamp confirmed in both files; `getWeek(5) == []` is why the
  date-sourced branch exists.
- `phaseNameFor` is `@visibleForTesting` — the roadmap strip uses the public instance method instead.
- The pinned neighbours (`phase_relative_week_label`, `week_selector_past_phases`,
  `week_completion_check`, `phase_unlock_card_thursday_gate`, `hold_week_mechanic_behavioral`) were
  run and are green. `week_selector_past_phases_test` initially failed on its source-order proxy
  after a hoisted local variable; the CODE was adapted to preserve the guarantee rather than the test
  weakened.
- `flutter analyze` on the full `lib/` reports 45 issues — **identical to the pre-change baseline**
  (measured by stashing this work), all pre-existing `share_plus` deprecations. Zero new.
