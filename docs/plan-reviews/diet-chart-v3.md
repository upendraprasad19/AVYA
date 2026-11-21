---
branch: diet-chart-v3
date: 2026-11-17
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
---

# Plan-review record: Diet chart v3 (`diet-chart-v3`)

Plan: `docs/plans/diet-chart-v3.md` (revision 4). Execution mode (§4.12.7): inline, one worktree (`.claude/worktrees/diet-chart-v3`). Tier M
(§4.12.6): more than two product files; the profile strategy is written only through the existing door (`handleDietStrategyTap` ->
`UserProfileNotifier.setDietStrategy`), no migration, no Edge Function, no new stored profile value, no kill switch (§4.6 is not triggered:
nothing here is payment, sync, auth, an AI prompt or the plan generator, which stays byte-identical, goldens G1 / G3 untouched).

**Scope:** the "your plan vs target" totals row; the strategy that follows the plan (a pick that adds carbs and leaves the day fitting only a less
strict strategy asks, accepting writes the profile strategy and keeps the edited plan without regenerating or saving it; "Back to Keto"); the
swap sheet showing every alternative plus "Search any food" (own foods, protein powders for adults, portion sheet); ten swap-only vegan catalog
entries (`_foodLibraryVersion` 7). Out of scope, stated: the Portions / Grams toggle and the per-food weight audit (OI-517), meals per day.

## Rounds

| Round | Reviewer | Verdict | Material findings | Disposition |
|---|---|---|---|---|
| 1 | context-blind Sonnet on rev 1 | changes required | 3 P1 (the shift ignored the BEFORE-pick fit; three tests would break; own foods listed twice) + 3 P2 + 8 P3 | plan section 7; rev 2 |
| 2 | fresh context-blind Sonnet on rev 2 | changes required | 1 P1 that rev 2 itself introduced (own-foods filter needed `type`, which a cloud-restored row lacks) + 2 P2 + 10 P3 | plan section 8; rev 3 |
| 3 | third seat, delta check on rev 3 | one P2 | the N3 re-save keyed on `_saved` failed in the swap-A-then-swap-B sequence: the mechanism (three defects in two rounds) was REMOVED, not patched | plan section 9; rev 4 |

Every fix after round 3 is a deletion or a wording change with no new mechanism, so rev 4 was not given a fourth seat; the B-pass at the account tier
reads the built code (below). Measurements behind the design (section 2 of the plan) were taken on the real asset: the vegan swap pools, the
generated-plan carb ratios (worst 1.42, factor 1.5), and, after the build, the vegan breakfast-protein / side zero-option share (1 option and
59-68 % zero before; median 4 and 5, 0 % zero after).

## Build-time measurements (2026-11-17)

- Generator byte-identity: G1 (800 Balanced plans) and G3 (800 Keto plans) pass untouched. G2 (the swap hash) moves because the swap now offers the
  ten swap-only entries; the test keeps proving byte-identity with main on the catalog WITHOUT them (`mainCatalog`) and a new test pins that the entries reach a swap.
- Fit factor: 1900 generated Keto / Low carb plans over 10 archetypes (1200 to 3500 kcal), worst ratio 1.42 < 1.5.
- Totals row height 122.8 dp in the widget test (ceiling 128).

## Order of landing

Gate loop (analyze, the pre-commit gates), CI full suite through `land_pr --ci-only` on an open PR, B-pass (three context-blind seats, account tier),
then the merge only on the founder's own go. No APK is built by this batch.

## B-pass (account tier, self-initiated before the merge; CLAUDE.md 4.3)

CI-green head reviewed first (`6a0f5645`, PR 295): three context-blind Sonnet seats, read-only, with the recorded decisions and the known residue quoted:
seat A (strategy shift, async races, totals row), seat B (search, own foods, catalog, seed, portion math), seat C (tests, docs, registry, layout).
No P0, no P1; six P2 and a run of P3, all fixed in the batch (plan section 11). A fourth, fresh DELTA seat then read the fix diff (`6a0f5645..4442b7ee`):
no P0, no P1, two P2 and four P3, all fixed (plan section 11.1). Mutation record: plan section 10 (47 mutants, 46 red, one self-attested residue:
the post-write epoch re-check, plus the `_pickBusy` presence pin).
Review file: none written (account tier; the gate asks for one only at catastrophic). `bpass:` front-matter is not set: the record's `bpass: accepted` is required from
`platform` up, and the founder's merge go is the acceptance for this tier.
