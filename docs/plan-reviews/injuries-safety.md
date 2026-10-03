---
branch: injuries-safety
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/injuries-safety-bpass.md
---

# Plan review — injuries-safety Ship 1 (U1 vocab + U2 universal-pool + U4 threading)

The smallest converged piece of the workout-generator overhaul's injury batch,
split out per §4.12 after the ×2 review of the original 5-unit plan kept
surfacing material issues. Ship 1 = U1 + U2 + U4 (inseparable — U2 is inert
without U1's canonical vocabulary and U4's threading). Ships 2 (U3 warmup/
cooldown injury filter) and Ship 3 (U5 onboarding chip) follow on this
foundation. Diagnose a1f6c3.

## Review rounds (≥2, on the design + the ground truth, BEFORE code)

- **Round 1 — ground-truth reviewer** (context-blind): corrected the plan's
  factual claims against live code + the exercise library — the 9 canonical
  tokens (lower_back=24 not 26; neck=1), the LIVE queryV4 match site
  (exercise_repository :290, not the dead legacy V3 path), the 2nd Edit-Profile
  write point, the muster/induction free-text writer, and that `splash_screen`
  ALREADY threads injuries (not a drop site).
- **Round 2 — design reviewer** (context-blind, on the hardened plan): returned
  "not ready as-is — harden + SPLIT" with 6 blocking findings, which is the
  §4.12 signal the unit was too large. All 6 folded in (see below) and the batch
  split into Ship 1/2/3. Per §4.12 the split IS the response — the large bundle
  was NOT re-reviewed a third time.

## The 6 design findings, resolved (converged)

1. **CRIT — U2 vs the Batch-0 `missing==0` gate:** empirically probed — the only
   unsafe pattern (shoulder_isolation) has injury-safe pool members (Arm Circles,
   Band Pull Apart), so filtering never empties a pool for any matrix persona;
   `missing` stays 0. For the general (all-contra) case, production returns null
   (safe omission) and the harness classifies `safelyOmitted` (gate PASS), proven
   by injury_safe_omission_test.dart. cascade_tracer + scorecard updated in
   lockstep. Measured: unsafe 2→0.
2. **CRIT — missed muster/induction writer:** induction_service `_bridgeToProfile`
   normalizes free-text at the SoT profile write.
3. **HIGH — threading under-enumerated / coach not deferred:** enumerated ALL
   generation entry points; 7 drop sites threaded incl. BOTH coach paths
   (regenerate + hotel); splash/preview/sim confirmed already-wired.
4. **HIGH — U2 inert without U1+U4:** shipped together (this record).
5. **HIGH — read-side alias, not boot normalizer:** InjuryVocab.normalize applied
   at read seams (chip render, central generateV4, muster write) — restore-safe,
   no migration.
6. **MED — U3 drop-not-substitute + can't be proven by the Batch-0 gate; U5
   explicit choice:** deferred to Ship 2/3 (documented decomposition, not a
   §4.2 deferral — each is its own converged unit).

## Ground-truth verification (true)

Self-verified against live code + the live library: the 9 canonical injury
tokens (node script over exercise_library.json — 115/258 rows); the 2 unsafe
personas + their pool options (empirical probe → both land on Arm Circles once
filtered); the 4 real `PlanGenerator.generate` sites + the 7 drop entry points
(grep + read each); `user_profile.injuries` is text[] (live_schema_columns.json,
no migration). Every cited line read directly, not taken from subagent prose.

## Verdict: converged

All behavioral tests green (injury_vocab_library_contract_test,
injury_filter_behavioral_test ×4, injury_safe_omission_test ×2); the Batch-0
scorecard gate drives unsafe 2→0 with 0 missing (baseline re-frozen);
flutter analyze clean; diagnose a1f6c3 validated; SoT concept
`injury_vocabulary_contract` added. B-pass on the implemented diff accepted
(docs/reviews/injuries-safety-bpass.md); its two P2 findings (crash-safe
`InjuryVocab.fromProfile` for the threaded reads; exact-name universal-pool
resolution + a production-path safe-omission test) were fixed in THIS batch, not
deferred (§4.2). No open issues.
