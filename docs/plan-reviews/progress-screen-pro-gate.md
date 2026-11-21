---
branch: progress-screen-pro-gate
date: 2026-10-05
blast_radius: feature
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record — the Progress Photos screen enforces PRO itself (`progress-screen-pro-gate`)

Founder decision 2026-10-05, on the closing question of the Photos-hub batch: "PRO check on the Progress screen … I recommend the screen enforce PRO itself, since CLAUDE.md rule 19 lists progress photos as server-verified PRO. Should it?" The answer was "Explain and yes".
Plan: `docs/plans/progress-screen-pro-gate.md` (v3, after both rounds). Fix tier M (`SubscriptionService.gateAndVerify` is a seam symbol and the diff passes 100 lines, §4.12.6), blast radius `feature` (`lib/features/profile/**`, `lib/shared/widgets/**`, `test/**`, `docs/**`, `.claude/**`; computed by `scripts/blast_radius_from_diff.dart`), inline execution. Commit type `fix(profile):` with `closes-diagnose: b7c1e4`.

## Review rounds
- **R1** — a fresh, context-blind reviewer, read-only, on the v1 plan and the staged draft. Verdict **harden**; no P0/P1. 13 findings: 8 × P2 (a "no photo read" test that could not fail by behaviour because `list()` never throws; surviving mutants such as `checking` showing the lock or the button; an Add button that was re-entrant and opened two pickers; a user who upgraded from the locked card still seeing the lock; six stale "the screen has no gate" statements in three test files; a wrong premise that the typed address works on a cold load, when a fresh load goes through `/restoring` and lands on Home; a nested CLAUDE.md row telling the next agent to pass the paywall the id `progress_photos` instead of the display string; missing process records) and 5 × P3 (stale rationale, citations, `ProLockedOverlay`'s first use that could clip its button, an overclaim, a contradicting soft-lock sentence). All folded.
- **R2** — a fresh Opus context, a different reviewer who had not seen R1's report, read-only (114 tool calls), on the post-R1 plan and diff, after the full gate loop had run. Verdict **harden**; no P0/P1. 8 findings, all about PROOF rather than behaviour: 2 × P2 (the "one caller" pin counted calls with a bracket, so a tear-off such as `onPressed: _pickAndCapture` or a direct repository call passed all 29 tests; ledger row C6, PROF-09 and the nested CLAUDE.md test list cited a test, `progress_photo_quota_test.dart`, that was never written) and 6 × P3 (D11's "only a locked screen reacts" untested while the screen is checking; three overlay claims with no test; the §4.2 sibling sweep not recorded; a stale SoT line range; the Comparison screen wrongly listed as PRO and as a reader of progress photos, and an overclaim about a lapsed user; records hygiene). All folded, and its answers (a keyboard test that passed for a weak reason, a `reason:` naming the wrong detector, a refresh test that depended silently on `SubscriptionInfoData` having no `==`) too. R2 verified by reading the Riverpod and Flutter sources that `ref.listen` in `build` has no hazard (one re-run per purchase, no loop through `_downgradeLocally`), that `_gating` is released on every exit, and that the `debugOnListForTests` seam is safe.
- **Converged-after-fold is a SELF-ATTESTATION, not a third review.** No third round was run: both rounds are done and R2 found nothing above P2 and nothing that changes behaviour. What changed after R2 is tests and docs (five new tests, tighter pins, a doc comment on `ProLockedOverlay`), and that is checked by mutation round 3 (49 of 49 red, each new test red for the mutant written for it) and by the whole gate loop on the final tree, not by another reader.

## Ground truth
- Code, read at the base `01a34097` and the staged tree by both reviewers and the main thread: the screen, the hub, the router and the restoring screen, `SubscriptionService.gateAndVerify` and `verifyFromServer` (the 5-minute cache is stamped only after a 200 answer), the `ref.listen` and ProviderScope scheduling in `flutter_riverpod` 3.3.1 / `riverpod` 3.2.1, `ProLockedOverlay`, Flutter's focus, semantics and ink code, the three other doors of the same shape in `lib/` (Reports, Graduation: both `verified_clean`, ledger rows S1 and S2) and the `weekly-report` Edge Function's own PRO refusal. No live system was read or written: no database, no Edge Function, no network call.
- Run, not just read: the targeted file after every change; `flutter analyze lib/` (the same 60 existing infos, none in a touched file); the whole suite (7657 passed, 9 skipped on the pre-fold tree, re-run on the final tree before the commit; the count is in the commit message); the whole pre-commit gate loop; three mutation rounds in sandbox copies (21, 40 and 49 mutants, each confirmed applied by a marker count, restored and `cmp`-checked; the per-mutant table is in the diagnose-doc).
- Not verifiable here: anything on a device or in a browser. The web door (a typed address in an already-open tab) was read from the source, not tried; the founder's device check says so.

## §4.6 disposition (CLAUDE.md feature-flag protocol)
**Not applicable.** Not payment, sync, auth, an AI prompt or the plan generator: a client gate added to one screen, using the same `gateAndVerify` and the same feature constant as the hub row. Rollback is a revert of the merge commit.

## B-pass (§4.3)
**Not required** (it starts at blast radius `account`). Skipped on purpose: R2 reviewed the production diff as it ships, and the only production-code change after R2 is a doc comment on `ProLockedOverlay`; what R2 asked for was proof, which mutation round 3 supplies.

## Founder-owned, recorded in the ledger, not done
C5 a server-side PRO rule for `progress_photos` (a migration and a live apply, needs a separate go); C6 delete the repository's free-tier branch; C7 whether a lapsed user may still view and delete old photos. Nothing was applied live.
