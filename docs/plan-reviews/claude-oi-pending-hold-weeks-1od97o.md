---
branch: claude/oi-pending-hold-weeks-1od97o
plan: docs/plan-reviews/claude-oi-pending-hold-weeks-1od97o.md
blast_radius: account
tier: ship_dark_build
review_rounds: 1
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/fob1-week-identity-bpass.md
---

# Plan Review — FOB-1 (week-identity coherence), OI-60 blocker 1 of 5

- **Batch:** `fob1-week-identity` — the first of OI-60's remaining flip-on blockers.
- **Branch:** `claude/oi-pending-hold-weeks-1od97o` (off `b7602ad`, == `main`).
- **Blast radius:** `account`, measured with `dart run scripts/blast_radius_from_diff.dart`
  against the staged diff, not estimated.
- **Kill-switch:** reuses `enable_hold_weeks` (default OFF). No new flag.

## Why `tier: ship_dark_build` / `review_rounds: 1`

§4.12.4 grants the lighter build-tier review to a change that is (a) gated behind a
kill-switch, (b) default OFF, and (c) has a passing behavioral test proving
byte-identical output when OFF. All three hold, and (c) is asserted rather than claimed:

> `flag OFF — the ship-dark byte-identical negative control` → *"weekIdentity equals the
> raw clamp EVEN WITH hold rows on disk"* — materializes real holds with the flag ON,
> turns it OFF, and asserts `weekIdentity().weekInPhase == getCurrentWeekNumber()`.

The **B-pass was still run and is still required** — §4.12.4 lightens only the second
independent round, never the self-driven adversarial pass, and §4.3 mandates it at
≥`account` regardless.

**This tier does NOT carry to the flip.** The commit that flips `enable_hold_weeks` needs
the full ×2 + `bpass: accepted` and must clear all three `enable_hold_weeks` rows in
`docs/ship_dark_pending_review.yaml` at once.

## Ground truth verified this session

Everything below was read in source, not carried from the FOB filing — which turned out
to be wrong in two places, both in the direction of *understating* the work:

1. `getCurrentWeekNumber()` ends in `.clamp(1, 4)` — `workout_schedule_read_service.dart:1096`.
2. `getProgramWeek(phase)` is `programWeekFor(phase, getCurrentWeekNumber())` — `:1087-1088`.
   So `phase_roadmap_screen.dart` inherits the clamp **indirectly**; a grep for the clamp
   would have missed it, and the FOB's own comment claimed the file had been moved off it.
   It had been moved off the *direct call* only.
3. `profile_content.dart:29` reads `stats.currentWeek` in a subtitle. The FOB named it only
   through its provider, so it was found by enumerating the clamp's consumers.
4. The three `enable_hold_weeks` ledger rows all still carry `flip_reviewed: false`.
5. `holdStatusProvider` held a **second** copy of the flag check.

## The one design decision, and the alternative rejected

**Decision:** `WeekIdentity` carries `weekInPhase` **XOR** `holdOrdinal`, and no projected
number at all.

**Rejected:** projecting `4 + ordinal` into a single `week` field. FOB-1's `do_not` bans it
outright, and the reason is concrete rather than stylistic: it manufactures the exact value
the UI already ruled dishonest, and `4 + ordinal` demotes a **phase-2** holder from program
week 8 to 5. Because the type has no field capable of holding a projection, one cannot be
reintroduced through it later — and the test asserts `weekInPhase` is **null** while
holding, rather than asserting it equals some other number, so the guard survives a refactor.

## Self-review findings, resolved in-batch

| # | Finding | Resolution |
|---|---|---|
| 1 | Two flag gates (provider + new seam) would drift | Gate moved into `activeHoldWeeks()` / `activeHoldOrdinalFor()`; provider delegates. Mutation-proven: removing it reddens 5 tests |
| 2 | Branching `WardBar(pct: currentWeek / 4.0)` would divide an H-number by 4 | Left unbranched — the clamped 4 is honest there; recorded as `verified_clean`, not overlooked |
| 3 | Un-clamping `SelectedWeekNotifier` would render "Week 5 hasn't started yet" over a week being trained | Left clamped — the exact trap OI-125 names |
| 4 | Changing Remotion's `weekNumber: number` type breaks existing renders | Added an **optional** `holdOrdinal` instead; omitting it renders byte-identically |
| 5 | Editing `ai_snapshot_builder` here ships a half-changed snapshot contract with no redeploy | Routed to FOB-3, which owns those same lines and carries the ai-proxy redeploy |

## B-pass findings — 2, both accepted and fixed in-batch

`docs/reviews/fob1-week-identity-bpass.md`, verdict `accepted`, 0 false alarms. The B-pass is
what the lighter ship-dark tier does **not** relax, and it earned that here — both findings were
real and neither was a judgement call.

| # | Sev | Lens | Finding | Fix |
|---|---|---|---|---|
| 1 | P1 | `guard_without_its_mirror` | `UserStatsNotifier.build()` read the identity via a plain singleton, so `userStatsProvider` had **no dependency-graph edge to the hold write**. Tabs live under `StatefulShellRoute.indexedStack` and are not rebuilt on switch, so Profile would keep showing `WEEK 4 OF 4` while Home/Train said `HOLDING · H1` — reintroducing the cross-tab contradiction this batch exists to close, on 2 of its 6 surfaces | `ref.watch(weekIdentityProvider)`, linking the graph once for every present and future call site rather than patching two call sites with an `invalidate` a third would forget |
| 2 | P2 | `test_can_actually_fail` | The surface coverage was presence-only. Reviewer **inverted a ternary and all 16 tests still passed** | Five label ternaries extracted to pure functions in `lib/core/utils/hold_week_labels.dart`; new 16-case table test asserts the exact string on both arms of each. The same inversion now reddens 4 |

The honest reading of finding 1: the seam, the provider, and four of six surfaces were all
correct. The defect was one level out — two surfaces reached a correct value through a notifier
with no edge to the write. That is `guard_without_its_mirror` at the call-site level, which is
exactly the failure the lens's 2026-08-17 tuning note describes: *follow the return value to its
call site.*

And finding 2 is the second consecutive batch where `test_can_actually_fail` beat a
mutation-proven change. This batch shipped two mutation proofs on the service seam and cited
both — while the label layer, which is what the user actually reads, had none. Mutation-proving
a seam does not mutation-prove its consumers.

## Verification

- `flutter analyze`: **0 errors, 0 warnings**; 258 infos, unchanged from the pre-batch baseline.
- `test/contracts/hold_week_identity_behavioral_test.dart`: 17/17 green.
- `test/contracts/hold_week_labels_test.dart`: 16/16 green.
- Mutation proof, three legs: hold arm neutered → **3** red; flag gate removed → **5** red across
  the identity file and `hold_display_read_path_test.dart`; `profileWeekSegment` inverted → **4**
  red, where the identical mutation reddened **0** before the label test existed.
- Full `flutter test` + the pre-commit gate loop: run before the commit landed.

## Scope boundary

This batch does **not** move OI-60 to closeable. Four flip-on blockers remain — FOB-3,
FOB-4, FOB-5, FOB-7(a)/(b) — and OI-127 is routed to whichever batch takes FOB-7(a)/(b) so
one batch holds the reconciler context. OI-125 (selectable past hold weeks) is a feature and
explicitly not a flip blocker.
