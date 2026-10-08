# Batch 10 — Explainability layer (W3.1) — Focused Implementation Plan (HARDENED, post Round-1)

> Branch `workout-explainability-10` (off main `38706bae`, includes Batch 9). Blast
> radius **account** (Round-1 verified: `deload_evaluator.dart` + new `core/utils/deload_reason.dart`
> → account catch-all; NO `plan_engine/**`; adherence side is copy-only feature-tier; max=account).
> Ship-dark, **rides the parent flags** (no new kill-switch — "lower-ceremony ok"). Item **W3.1**
> LOCKED: a one-line "why" for the TWO dynamic mechanisms — (A) the DELOAD decision (W2.4) and
> (B) the ADHERENCE-GATE choice (W2.5). Wave-1 static choices stay unexplained.
>
> **Status: Round-1 ×2 review DONE (both `needs-changes`; ground truth 100% verified correct).
> All findings folded (§6). Round-2 pending on THIS hardened plan.**

## 0. What W3.1 is (LOCKED)

- **(A) Deload "why"** — a plain, non-shaming one-liner explaining why the week-4 recovery week
  was KEPT or LIFTED, derived from the deload eval's already-computed decision booleans and
  rendered in the phase-arc strip on the deload week.
- **(B) Adherence "why"** — a non-shaming COPY-ONLY lead-in in the repeat-vs-advance sheet
  explaining WHY the choice is being offered (an unfinished block), **without surfacing the raw
  completion % (which would violate the codified non-shaming brand soul — Round-1 R2-P2**).

Both are purely ADDITIVE and only appear when the parent feature already acted → inert when the
parent flag is OFF (no new kill-switch, no byte-change to today).

## 1. Ground truth (Round-1 ×2 VERIFIED — every §1 file:line confirmed correct)

### A. Deload decision (W2.4 / Batch 7-B-2)
- Decision `deload_evaluator.dart:123-124`: `shouldLift = notBackstop && notDeloadPhase &&
  readiness.good && e1rm.noFatigue` (SAFE polarity — any false → KEEP).
- Clauses: `notDeloadPhase` :111-112; `notBackstop` :117-119; `readiness` (`.good`/`.hadData`) :120→`_readinessGood`:151-165; `e1rm` (`.noFatigue`/`.hasCompoundEvidence`) :121.
- `firmKeep` discriminator already exists :137-140. LIFT rewrites wk4 rows + blob week_plans[3]
  (:216-217) + flag :128. FIRM KEEP sets marker :142 + flag :143 (nothing renderable). TRANSIENT
  insufficient-data keep sets NEITHER (re-evals next launch). No reason/telemetry exists today.
- Marker/flag keys `_kMarkerKey`/`_kFlagPrefix` :41-42 (workoutBox, per-user via `wrapUserScopedBox`).
- Eval gate :53-54 (`triggeredDeloadEnabled` + `readinessEnabled`). Render gate `enable_phase_arc`
  (`train_provider.dart:717`, `plan_engine_flags.dart:161`).
- Render seam `phase_arc_strip.dart` (mounted `train/screen.dart:312`, fed `phaseArcProvider`
  `train_provider.dart:715-722` → `currentWaveCharacters()`; `SizedBox.shrink()` when arc null :29).
- ⚠ **The eval keys its flag on the wk4 rows' own `phase` stamp** (`getWeek(4)→r['phase']`, ~:63-76).

### B. Adherence gate (W2.5 / Batch 8)
- Offer `graduation_screen.dart:589-593` (`adherenceGateEnabled && shouldOfferAdvanceChoice(rate, threshold)`).
  Sheet gate `advance_choice_sheet.dart:21-25` (`completionRate < threshold`); `AppConstants.phaseUnlockCompletionRate == 0.8` (`app_constants.dart:128`).
- `_AdvanceChoiceSheet` is a `const` StatelessWidget, NO params (:42-43); body copy :60-65
  (`"Run the same drills again to lock them in, or take on fresh orders. Either way, the next phase is yours."`).
- ⚠ **Brand soul (Round-1 R2-P2):** `advance_choice_sheet.dart:3-4` + the `phase_repeat_nudge`
  SoT DELIBERATELY avoid surfacing low adherence ("Non-shaming Navy framing … never 'you
  failed / you missed / low adherence'"). The gate fires ONLY below 80%, so any raw % shown is
  0–79% → surfacing it is shaming → REVERSES a codified Batch-8 decision. **Do not show the %.**

## 2. Design (HARDENED — deload substantive; adherence copy-only + non-shaming)

### 2a. Shared reason model (`lib/core/utils/deload_reason.dart`, pure)
`String deloadDecisionReason({required bool shouldLift, required bool notDeloadPhase,
required bool notBackstop, required bool readinessGood, required bool readinessHadData,
required bool e1rmNoFatigue, required bool e1rmHasEvidence})` — a single non-shaming Navy
one-liner. **Precedence STRUCTURAL-before-EVIDENCE (Round-1 A-P2), each evidence branch gated on
its had-data flag:**
1. `shouldLift` → `"Working week — you're recovered and progressing. Full volume restored."`
2. `!notDeloadPhase` (structural) → `"Scheduled recovery week — trust the taper."`
3. `!notBackstop` (structural) → `"Recovery week — it's been two blocks. Time to bank the gains."`
4. `!readinessGood && readinessHadData` (evidence) → `"Recovery week held — your check-ins flagged fatigue. Rest up."`
5. `!e1rmNoFatigue && e1rmHasEvidence` (evidence) → `"Recovery week held — your key lifts dipped. Bank the rest."`
6. else (insufficient data) → `"Recovery week — not enough recent data to lift it yet."`
Pure + total + unit-tested (truth-table).

### 2b. Deload reason persistence (`deload_evaluator.dart`, at the decision)
Compute the reason via `deloadDecisionReason(...)` from the in-scope booleans and persist it to
a per-user `workoutBox` key **keyed on the SAME phase the eval already uses for its flag**
(`deload_evaluated_for_phase_<P>`) — extract that phase derivation into a shared helper so the
reason-WRITER (eval) and the reason-READER (§2c read-service) go through ONE code path → writer
== reader by construction (Round-1 A-P1: pins the phase source, no drift). Key:
`deload_reason_phase_<P>` (String). Stamped on LIFT, FIRM-KEEP, AND the transient keep (so the
strip is never blank mid-transient — Round-1 confirmed this is SAFE: it touches neither the
marker nor the idempotency flag, so re-eval still fires). No blob write on keep. No migration.

### 2c. Deload reason render (`phase_arc_strip.dart` + a read-service method)
Add `WorkoutScheduleReadService.currentDeloadReason()` that uses the SAME shared phase helper as
§2b to read `deload_reason_phase_<P>`, returns null unless `triggeredDeloadEnabled` (Round-1 A-P2
kill-switch reversibility — a stale reason hides the moment the flag is turned OFF). Extend
`phaseArcProvider` to expose it. `PhaseArcStrip` renders a `textDim bodySm` line under the wave
Row ONLY when `getCurrentWeekNumber()==4` (the deload week — avoids showing a prior phase's reason
during weeks 1-3) AND the reason is non-null. Reason null / not-week-4 → no line → strip
byte-identical. ⚠ Composition (documented, never-worse): the reason shows only when
`enable_phase_arc` is ALSO ON — the phase arc is the correct home for a `week_character`
annotation; a second surface is scope creep. **Flag-flip runbook note:** enabling triggered_deload
WITHOUT enable_phase_arc lifts/keeps the deload with no on-screen "why".

### 2d. Adherence "why" — sheet COPY-ONLY (non-shaming; NO rate threading)
`_AdvanceChoiceSheet` stays a `const` no-params widget (Round-1 B-P1×4 all dissolve — no rate
param, no signature change, no test breaks). ADD a non-shaming lead-in line to the body that
explains the TRIGGER without a number, e.g. a mono eyebrow `"UNFINISHED BUSINESS"` + the body
reworded to lead with the why: `"This block's still got open sets. Run the same drills again to
lock them in, or take on fresh orders — either way, the next phase is yours."` The sheet only
renders when `offerChoice` (low adherence), so the copy can assume that context WITHOUT stating a
deficit %. **Final copy runs through the Wardroom brand soul + psychology-pass-fitness lens at
implementation** (§0 discipline; Round-1 R2-P2). The Home `phase_repeat_nudge_banner` copy
(`"Same drills, fresh start. Nail this phase and we'll step it up next time."`) is ALREADY a
non-shaming "why" → left verbatim (no change, no rate). No `markPhaseRepeatNudgePending` change,
no provider change, no new key.

## 3. Inertness / ship-dark
- Deload flag OFF → eval never runs → no `deload_reason_*` key → `currentDeloadReason()` returns
  null (also gated on the flag) → strip renders no line → byte-identical.
- Arc flag OFF → `PhaseArcStrip` → `SizedBox.shrink()` → not rendered.
- Not week 4 → no reason line.
- Adherence flag OFF → sheet never shown → the copy-only change is unreachable → byte-identical.
No new kill-switch. Adherence side is copy-only (no data path) → nothing to make inert beyond the
existing `offerChoice` gate.

## 4. SoT + tests + docs
- **SoT** `docs/sot_registry.yaml`: new `deload_decision_reason` — writer `deload_evaluator.dart`
  (`deload_reason_phase_*` via the shared phase helper), reader
  `WorkoutScheduleReadService.currentDeloadReason` → `phaseArcProvider` → `PhaseArcStrip`.
  behavioral_test_path (account tier REQUIRES it). The adherence half is copy-only → no SoT concept
  (no writer/reader pair); note it under the existing `advance_choice`/`phase_repeat_nudge` context.
- **Naming glossary / §3.3 Hive key registry**: register `deload_reason_phase_` prefix (confirm §3.3 wants it).
- **Behavioral tests**: `deload_reason_test.dart` (pure derivation truth-table — each clause →
  correct string + structural-before-evidence precedence + had-data gating); extend
  `deload_eval_behavioral_test.dart` with a **round-trip** (real `maybeEvaluate()` writes the reason
  → the REAL `currentDeloadReason()` reads it back for lift / firm-keep / transient / flag-OFF —
  NOT a source-grep, per Round-1 A-P1 + rule 21); `advance_choice_test.dart` gains a source-anchored
  assertion that the sheet body contains the non-shaming why lead-in (NO %). No UNIT-3 test breaks
  (the sheet signature is unchanged).
- **Nested CLAUDE.md** train + a deload-reason note.
- No diagnose-doc (`feat:`). No migration. ≥account ⇒ this plan-review record + a self-B-pass before merge.

## 5. Blast radius: **account** (Round-1 verified against `blast_radius.yaml`)
`deload_evaluator.dart` + new `core/utils/deload_reason.dart` → account (catch-all); render + sheet
files → feature. Max = account. Account requires regression_test + behavioral_test_path +
code_review_b_pass (all planned) — NOT feature_flag (that's platform) nor hermes. The branch-keyed
plan-review record gate (§4.12) applies at merge.

## 6. REVIEW ROUND 1 (×2 context-blind) — findings + resolutions
Both `needs-changes`; ground truth 100% verified correct. Findings folded:

| # | Sev | Finding | Resolution |
|---|---|---|---|
| A-P1 | P1 | Reader phase-source for `deload_reason_phase_<N>` unpinned / unproven == writer's `wk4[].phase` (writer/reader-drift class). | §2b/2c **shared phase helper** for both writer + reader (writer==reader by construction) + a **round-trip** behavioral test through the REAL provider. |
| A-P2 | P2 | Reason precedence surfaces evidence over dominant structural cause; fatigue/dip branches not gated on had-data. | §2a **structural-before-evidence** order + each evidence branch gated on `readinessHadData` / `e1rmHasEvidence`. |
| A-P2 | P2 | Blast radius mislabeled "platform-or-account". | §5 **account** (definitive). |
| A-P2 | P2 | Reason line gated on key-presence not the live flag → not cleanly reversible. | §2c `currentDeloadReason()` **gated on `triggeredDeloadEnabled`**. |
| B-P1 | P1 | Rate must be HOISTED not re-read at the nudge callsite (phase already advanced). | **MOOT** — §2d drops the rate entirely (copy-only). |
| B-P1 | P1 | `markPhaseRepeatNudgePending()` signature change breaks `phase_repeat_nudge_test.dart:128` regex. | **MOOT** — no signature change. |
| B-P1 | P1 | `required completionRate` breaks `advance_choice_test.dart:51` compile. | **MOOT** — sheet signature unchanged. |
| B-P1 | P1 | `phaseRepeatNudgeProvider` bool→record change breaks the provider + 7 assertions + SoT. | **MOOT** — provider untouched. |
| B-P2 | P2 | New `phase_repeat_nudge_rate` key not in `UserConfigMigrator.userScopedKeys`. | **MOOT** — no new key. |
| B-P2 | P2 | **Raw-% copy is SHAMING — reverses the codified non-shaming brand soul.** | §2d **copy-only non-shaming** trigger explanation (no %), routed through the Wardroom soul / psychology-pass-fitness. |

**Net:** the deload half is substantive + hardened (phase-pinning + precedence + reversibility +
account); the adherence half is redesigned to a non-shaming copy-only lead-in, which dissolves ALL
four Round-1 B-P1s AND the brand-soul tension. Unit stays ONE coherent W3.1 slice (the adherence
simplification shrank it, not grew it — no split needed).

## 7. Open questions for the Round-2 reviewer (verify the hardening against code)
1. Verify the shared phase helper genuinely makes the reason writer==reader (read the eval's
   flag-phase derivation + the new `currentDeloadReason` — same source?). Does the round-trip test
   actually exercise both through the real objects?
2. Is rendering the reason only on `getCurrentWeekNumber()==4` correct (no stale-reason display in
   weeks 1-3; the eval has run by the time week 4 is visible)?
3. Is the `currentDeloadReason` flag-gate (`triggeredDeloadEnabled`) the right reversibility seam?
4. Is the copy-only adherence lead-in genuinely non-shaming + brand-consistent, and does it still
   satisfy W3.1's "explain why the choice appears"? Any residual test/inertness impact?
5. Any NEW defect the hardening introduced (§4.12)?

## 8. REVIEW ROUND 2 (context-blind, on the HARDENED plan) — CONVERGED

Round-2 verified the hardening against code. Confirmed: the A-P1 shared phase helper is
writer==reader by construction (eval's phase = `deload_evaluator.dart:66-76` `getWeek(4)→r['phase']`,
flag :81; the reader reads the same user-scoped `workoutBox`; a phase advance moves `plan_start_date`
→ `getCurrentWeekNumber` resets to 1-3 → the week-4 render gate shuts → NO stale cross-phase leak);
eval-timing sound (`day_rollover_service._doRolloverWithRef:181` awaits `maybeEvaluate()` BEFORE the
provider-invalidation block; cold-launch awaited before home nav → week-4-day-1 sees the reason
stamped); adherence copy-only breaks ZERO tests (sheet const/no-params unchanged; button labels
untouched); blast radius account. **Correction:** the `deload_reason_phase_*` key needs NO
`user_config_migrator` registration (it mirrors the existing un-registered deload keys) — §4 note dropped.

Two P2 folds (in-batch; do NOT block convergence):

| # | Sev | Finding | Resolution (fold into implementation) |
|---|---|---|---|
| R2-1 | P2 | Reason/arc DISPLAY DRIFT (the signature class): the reason is derived from the DECISION booleans + stamped in the `if (shouldLift)` branch, but the arc's wk-4 character comes from the ACTUAL mutation — `_liftWeekFour` leaves it `'deload'` (returns early ~:205) when every wk4 row is ineligible (all completed/past/swapped/stashless). `shouldLift==true` but `liftedAny==false` → strip shows a DELOAD node with a contradictory "Working week…" subtext. | **Stamp the reason from the ACTUAL OUTCOME.** Thread `liftedAny` out of `_liftWeekFour` (return `bool`). `deloadDecisionReason` gains `required bool liftedAny`: `shouldLift && liftedAny` → the working-week reason; `shouldLift && !liftedAny` → a POSITIVE "you'd already logged these sessions — solid." reason (matches the `deload` node the strip shows); `!shouldLift` → the keep branches (§2a). So the subtext always matches the displayed wave character. |
| R2-2 | P2 | The §4 copy test as a source-grep is weaker than available. | The sheet already renders in `advance_choice_test.dart`'s widget tests → assert the non-shaming lead-in with a real `find.textContaining(...)` widget assertion (strictly stronger). |

**VERDICT: CONVERGED** (review_rounds=2, ground_truth_verified=true). The 2 P2 folds are surgical.
Proceed to implement, then the self-initiated ≥account B-pass on the diff BEFORE the `--no-ff` merge (§4.3).
