---
branch: workout-adherence-8a3a2
scope: ⑧ Batch 8 · UNIT 3-a2 (W2.5) — ship-dark auto-path plumbing: splash repeat-default + autoGenerateNextPhaseIfNeeded `({generated,repeated})` return + local-only phase-repeat nudge (the 2nd of the UNIT 3 three-way split)
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-adherence-8a3a2-bpass.md
---

# Plan-review record — ⑧ UNIT 3-a2 (ship-dark repeat-default + nudge)

Plan: `scratchpad/batch8_unit3a2_plan.md` (full ×2 detail). §4.12 ×2 context-blind review.
**Converged — implemented.** ACCOUNT tier (core read-service + shared helper + auth-adjacent splash path +
home nudge; no plan_engine/payment/RLS/migration). NOT a `fix:` (a NEW ship-dark capability) → no
diagnose-doc. No migration (config-only). **INERT while `enable_adherence_gate` OFF** (repeatContent stays
false → byte-identical to 3-a1). Consumes 2-int's `repeatContent`/`_buildRepeatPins` + D1's
`currentPhaseCompletionRate()`.

## Ground-truth verified (against code, file:line)
- `autoGenerateNextPhaseIfNeeded` (`workout_schedule_read_service.dart:438`, facade `:132`) returned
  `Future<bool>`; `pins = repeatContent && adherenceGateEnabled ? _buildRepeatPins : null` (`:468`);
  `return true` (`:492`). `pins != null` ⟺ a faithful G5-gated repeat pin map was built.
- `currentPhaseCompletionRate()` (`:682`) — INERT double 0-1 (`phase<=1?4:scan5-12`), side-effect-free.
  Not on the facade → 3-a2 exposes a pass-through.
- Callers reading the bool: `pro_phase_advance.dart` (3-a1's helper), `simulation_service.dart:546`,
  facade `:145`, and the SoT test `repeat_content_scheduling_test.dart:300` (`expect(advanced, isTrue)`).
- `AppConstants.phaseUnlockCompletionRate = 0.8` (`app_constants.dart:128`); flag `enable_adherence_gate`
  (`plan_engine_flags.dart:197`); `last_phase_profile` ∈ `userScopedKeys` (`user_config_migrator.dart:83`);
  MigratedKey userBox-first; nudge home slot mirrors `_buildExpiryBanner` (`home_screen.dart:437/546`),
  which clears ONLY on `onDismiss` (`:553`) — the codified cross-account belt gates its write on
  `HiveUserSession.currentOwnerFullId != null` (`subscription_service.dart:365`; `home/CLAUDE.md:68`).

## ×2 review (two parallel context-blind reviewers, distinct lenses) — both needs-changes → all folded
**Review #1 (correctness / return-type ripple):** **[P1]** `repeat_content_scheduling_test.dart:300`
`expect(advanced, isTrue)` breaks on the record return (it is the SoT `behavioral_test_path`) → must become
`.generated` (+ a free `.repeated` pin). **[P2]** keep `advanceProPhaseIfExpired` as `Future<bool>` (a source
test pins the literal signature; the wrapper reads `.generated` internally). **[P2]** `pins != null` = "G5
passed + a pin built", not "every day identical" → soften the nudge copy. CLEAN: facade exposure needed +
short-circuit inert; shared-helper placement correct.
**Review #2 (writer/reader drift + cross-account + tests):** **[P1-A, the catch both #1 + I missed]** gate the
nudge WRITE on `HiveUserSession.currentOwnerFullId != null` — `ensureOpenedForCurrentSession` can return a
non-null uid while the owner is null (openForUser threw), so `MigratedKey.write` would fall back to the
DEVICE-shared configBox and leak User A's nudge to User B (the codified expiry-banner P0 class). **[P1-B]**
confirms #1's test edit. **[P1-C]** clear the nudge ONLY on explicit dismiss (never in build) — the reader must
survive a rebuild. **[P2-D]** register the nudge `reader_manifest_complete: false` (Gate-18's detector matches
`.get/.put`, not `MigratedKey` → a `true` passes vacuously). **[P2-F]** refresh the existing
`repeat_content_scheduling` SoT entry (return-type touches its writers). **[P2-H]** `simulation_service:546`
calls the read-service directly → intentionally no repeat/nudge (dev sim). CLEAN: no new box → restore/box
gates untripped; local-only holds.

## Converged design (implemented)
- Return type `Future<({bool generated, bool repeated})>` (read-service + facade); `repeated = pins != null`.
  Callers → `.generated` (helper + `simulation_service`); the SoT test asserts `.generated`/`.repeated`.
- `advanceProPhaseIfExpired`: `repeatContent = adherenceGateEnabled && currentPhaseCompletionRate() < 0.8`
  (short-circuit → OFF never runs the ≤12× loop); on `result.repeated && currentOwnerFullId != null` →
  `await MigratedKey.write('phase_repeat_nudge_pending', true)`. Wrapper stays `Future<bool>`.
- `phaseRepeatNudgeProvider` (`home_provider`) reads the flag on build, `dismiss()` clears (never in build);
  `_buildRepeatNudge` → dismissible non-shaming `PhaseRepeatNudgeBanner` (Wardroom). Key registered in
  `userScopedKeys`. SoT: new `phase_repeat_nudge` (reader_manifest_complete:false) + refreshed
  `repeat_content_scheduling`.

## Verdict: converged
`flutter analyze` clean on all 8 touched lib files (No issues found). **12/12** behavioral — `phase_repeat_nudge_test.dart`
(2: user-scoped round-trip + survives-rebuild-until-dismiss; cross-account no-leak) + `repeat_content_scheduling_test.dart`
(10, incl. the record `.generated`/`.repeated` pin + the flag-OFF `last_phase_profile`-not-written inertness).
Ship-dark inertness verified byte-identical when OFF. Both parallel reviews needs-changes but all folds use
CODIFIED patterns (expiry-banner cross-account belt + dismiss-clear) — mechanism sound, not a split signal; the
self-B-pass on the IMPLEMENTED diff re-checks the corrections (§4.12 intent). B-pass runs before the `--no-ff`
merge; see `bpass_review`. Merge gated on 3-a1 CI green.
