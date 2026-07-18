# Plan-review record — `workout-plateau-12` (Batch 12-A, W3.5 plateau escalation · rung-2 +sets)

- **Batch:** 12-A of the workout-generator adaptive overhaul (W3.5 plateau detection + escalation, PRO). The **last** batch of the arc (12-B is the sibling follow-on).
- **Branch:** `workout-plateau-12` (off `544a1bbe`, Batch 11 COMPLETE tip).
- **Blast radius:** `platform` (`lib/shared/repositories/plan_engine/**` wholesale pin, `docs/blast_radius.yaml:67`). Requires regression_test + behavioral_test_path + code_review_b_pass + feature_flag.
- **Ship-dark flag:** `enable_plateau_escalation` (DEFAULT OFF → byte-identical inertness). Presupposes `enable_readiness` ON (see §2.1 flag-ordering).
- **review_rounds:** 2
- **ground_truth_verified:** true
- **verdict:** converged
- **bpass:** accepted
- **bpass_review:** docs/reviews/<hash>-review.md  <!-- filled at B-pass -->

---

## 0. Why Batch 12 is SPLIT (12-A here, 12-B next)

§4.12: "ship the smallest converged piece." Ground-truth verification surfaced a **material design correction** to the brainstorm's premise before a line was written — the "reserved 4th OR-slot" the deload rung was supposed to fill **does not exist**, and wiring it would be provably dead code (§1.1). That reframes the batch onto the phase-boundary path. Per the 7-B-1/7-B-2 and 11-A/B/C precedent, the ladder splits cleanly by risk:

| Sub-batch | Rung | Mechanism | Risk |
|---|---|---|---|
| **12-A (this)** | detector + rung-2 (+sets) | new `plateau_scan.dart` flat-window detector; merge `+1` into the W2.7 titration delta map (single `applyToWeeks`) | prescribed volume, clamped [MEV,MRV], composes with a shipped/tested seam |
| **12-B (next)** | rung-3 (rotation) + rung-1 explainability | plateaued exercise NAMES → `avoidNames` (fallback when +sets didn't apply); plateau mentioned in the deload "why" | soft selection bias |

Both sub-batches ride the **one** `enable_plateau_escalation` flag (DEFAULT OFF throughout the arc — flipped by the founder post-APK), so every intermediate state (12-A merged, 12-B not yet) is inert. Rung-1 (deload) needs **no code** — see §1.1.

---

## 1. GROUND TRUTH (verified against code, this session; ×2 Round-1 reviewers re-verified)

### 1.1 The deload rung-1 is ALREADY delivered by W2.4 — wiring it would be dead code (LOAD-BEARING CORRECTION — proof re-verified by BOTH Round-1 reviewers)

The brainstorm (F2, Round-3) said "*Batch 7 ships the 3-clause trigger with the 4th OR-slot reserved; Batch 12 wires the plateau clause in.*" **False against the shipped code.** `lib/core/services/deload_evaluator.dart:120-121`:

```dart
final shouldLift =
    notBackstop && notDeloadPhase && readiness.good && e1rm.noFatigue;
```

- `shouldLift` is a **4-clause AND** deciding whether to **un-deload** (lift week 4). No "3-clause OR with a reserved slot." A plateau rung would wire in as `shouldLift = … && !plateauKeep`, `plateauKeep = plateauPresent && _fatiguePresent`.
- **Proof it can never flip an outcome** (`_readinessGood` at `:167-181`; F2 fatigue = "persistent red/yellow readiness" = `_fatiguePresent`, §2.2):
  1. `shouldLift == true` today requires `readiness.good == true`.
  2. `readiness.good == true` ⟺ ≥3 check-ins in the **14-day** window AND majority green (`flagged*2 < len`, `flagged = count(level != green)`).
  3. `_fatiguePresent == true` ⟺ ≥3 check-ins (same 14-day window, same `flagged` count) AND strict-majority non-green (`flagged*2 > n`).
  4. (2) and (3) are mutually exclusive over the SAME data/window → whenever `shouldLift` is `true`, `_fatiguePresent` is `false` → `plateauKeep` false → `&& !plateauKeep` is `&& true` → no change. When `shouldLift` is `false`, it stays `false`. **∴ the clause can never flip an outcome. ∎**
  - Both Round-1 reviewers independently enumerated all five `_readinessGood` branches (empty / sparse<3 / majority-green / exact-half / majority-non-green) and confirmed no branch flips.
- **Consequence:** "deload when plateaued + fatigued" is **already** delivered by W2.4's `readiness.good` keep (persistent red/yellow ⟹ `readiness.good == false` ⟹ keep). **12-A does NOT touch `deload_evaluator.dart`** — *reducing* surface vs the subagent's plan. Ladder semantics preserved: fatigued-plateau → deload (W2.4); non-fatigued-plateau → +sets (rung-2, 12-A) → rotation (rung-3, 12-B).

### 1.2 rung-2 (+sets) merge site — exact

`lib/shared/repositories/plan_engine/plan_generator.dart:254-259` (Stage 4.5):

```dart
if (applyVolumeTitration) {
  weekPlans = VolumeTitration.applyToWeeks(
    weekPlans, VolumeTitration.resolveDeltas(phase: phase));
}
```

- `resolveDeltas({required int phase})` (`volume_titration.dart:54-120`) → `Map<String,int>` per-group ∈ {-1,+1}; `const {}` when `!enable_volume_titration` OR `phase < 2`.
- `applyToWeeks(weeks, deltas)` (`:167-172`) → pure; `if (deltas.isEmpty) return weeks;` (SAME ref). `_titrateWeek` clamps each group's weekly aggregate to `[_mevPerWeek=8, _mrvPerWeek=20]` (`:198,200,211,213`), one exercise/group/week (dedup `bumped`, `:179,243`).
- rung-2 = merge `+1` into the map for plateaued-eligible groups titration left absent, then a **single** `applyToWeeks`. `putIfAbsent(g, () => 1)` = the exact "no-double-bump / respect an existing −1" rule (Round-2 #11). The `[MEV,MRV]` clamp enforces "only below the ceiling."

### 1.3 The detector reuses shipped primitives (with drift-hygiene extraction per Round-1 B)

- `sessionMaxE1rm(Map log)` — shared Epley (`lib/core/utils/e1rm.dart:19`), already used by `DeloadE1rmScan` + `VolumeTitration`.
- **Extract the exlog→e1RM history builder + the compound predicate** (§2.2) — the exlog→(name→date→maxE1rm) map is currently hand-rolled in BOTH `deload_e1rm_scan.dart:55-72` and `volume_titration.dart:63-79`; a third copy in `plateau_scan.dart` would be the #1 writer/reader-drift class (the exact duplication `e1rm.dart:1-11` extracted `sessionMaxE1rm` to kill). So extract `buildE1rmByDate(box, cutoff:)` and `ExerciseRepository.isCompoundByExactName` to shared helpers and refactor all callers (behavior-preserving; pinned by the existing `deload_eval_behavioral_test` + `volume_titration_behavioral_test`).
- `muscleGroupOf(token)` — canonical library-token → major-group map (`muscle_groups.dart:40`), already shared. Plateau's per-row group aggregation is a thin `primary_muscles`→`muscleGroupOf` loop (same as titration's `_groupsForRow:148-158`, which is itself just a wrapper over the shared `muscleGroupOf` — NOT a drift point).
- **Fatigue predicate** (`_fatiguePresent`) — reads the SAME `healthBox` `readiness_*` rows via `ReadinessCheckin.fromMap` (`readiness.dart:49`) that `VolumeTitration._recovered` reads, **but the predicate/window mirror `deload_evaluator._readinessGood` (`:167-181`)**: count `.level != ReadinessLevel.green` (`readiness.dart` enum at `:15`, `.level` getter at `:36`) over the trailing 14 IST days (`istDateStr(nowWall().subtract(Duration(days:14)))`, `>=` compare), ≥3 sample. (NOT `_recovered`'s soreness-axis/35-day metric — that would break the §1.1 mutual-exclusivity proof.) No new plan_engine→`HealthReadService`/`SubscriptionService` dependency (reads `healthBox` directly, like titration).

### 1.4 opt-in threading — mirrors `applyVolumeTitration` across 5 sites (method names corrected per Round-1 A/B)

| Site | file:line | change |
|---|---|---|
| facade `generate` (declare + forward) | `plan_generator.dart:53`, `:71` | add `applyPlateauEscalation` (default false), forward to `generateV4` |
| `generateV4` (declare + consume) | `plan_generator.dart:101`, `:254` | add param; use in the Stage-4.5 merge |
| **`generateAndSchedule`** (declare + forward) | `workout_schedule_read_service.dart:97` (sig) / `:117` (param decl) / `:139` (forward) | add param, forward to `generate()` |
| `autoGenerateNextPhaseIfNeeded` (advance caller) | `workout_schedule_read_service.dart:498-515` (`applyVolumeTitration:` at `:513`) | `applyPlateauEscalation: pins == null` |
| `graduation_screen._onPro` (advance caller) | `graduation_screen.dart:662` | `applyPlateauEscalation: pins == null` |

- **NOT threaded (correct):** `generateAndScheduleFromDate` (`:248`, edit-profile regen — does not carry `applyVolumeTitration` either) and the `WorkoutScheduleService` facade (`workout_schedule_service.dart:78`, used by `auth_session_bootstrapper.dart:383` / `train_provider.dart:496`) — a reduced-surface waist. Coach-regen / previews never pass the intent.
- Both advance callers are PRO-gated (splash path: `pro_phase_advance.dart:61` explicit `isPro()` guard; graduation: `SubscriptionService.instance.gate(featurePhases2To12, …)`) and only reach `phase >= 2` (free = phase 1). Feature inherits the PRO gate WITHOUT an inline `isPro()` in plan_engine — identical to how W2.7 titration is PRO-gated. rung-2 additionally self-gates `phase >= 2`. **Verified by Round-1 B: no free-user +sets path.**

---

## 2. IMPLEMENTATION SPEC (12-A)

### 2.1 New flag — `plan_engine_flags.dart` (+ flag-ordering guard)

```dart
/// W3.5 (Batch 12 plateau escalation, PRO). rung-2 (+sets): at a fresh phase
/// advance, a plateaued major group (flat compound e1RM ≥3 sessions over ≥28d)
/// that is NOT already titration-bumped and NOT under persistent readiness fatigue
/// gains +1 weekly set (clamped ≤MRV via the shared applyToWeeks clamp). Ship-dark
/// DEFAULT OFF (§4.6). OFF → mergePlateauSetDeltas returns the input map unchanged
/// → applyToWeeks identity → byte-identical. Set `configBox['enable_plateau_escalation']=true`.
static bool get plateauEscalationEnabled { … configBox.get('enable_plateau_escalation') == true … catch → false }
```

**Flag-ordering (Round-1 B P2):** the fatigue gate needs `readiness_*` data (only present when `enable_readiness` is ON). So `plateauedGroups` **also gates on `readinessEnabled`** — mirroring the sibling guard at `deload_evaluator.dart:55-56` (`triggeredDeloadEnabled && readinessEnabled`; N1: the earlier draft mis-cited the flag docstring line). Plateau escalation presupposes readiness ON (readiness is an earlier overhaul batch; both flags flip post-APK). With readiness OFF, `plateauedGroups` returns `{}` (no blind +sets). The `!readinessEnabled` guard is checked BEFORE `_fatiguePresent()` in the short-circuit chain, so the fatigue read only runs when data can exist.

### 2.2 New file — `lib/shared/repositories/plan_engine/plateau_scan.dart` + two extractions

**Extractions (drift hygiene):**
- New `lib/shared/repositories/plan_engine/e1rm_history.dart` — `Map<String,Map<String,double>> buildE1rmByDate(Box workoutBox, {required String cutoff})` (the exlog→name→date→maxE1rm builder, byte-identical to the two current copies; the only per-caller difference was the cutoff, now a param). Refactor `DeloadE1rmScan.scan` (`:57-72`) and `VolumeTitration.resolveDeltas` (`:65-79`) to call it.
- `ExerciseRepository.isCompoundByExactName(String name)` — `exercise_type == 'compound'` exact match (List-or-String shape), custom/absent → false. Mirrors + replaces `DeloadE1rmScan._isCompound` (`:105-114`); `DeloadE1rmScan` refactored to call it. `PlateauScan` uses it.

**`plateau_scan.dart`** — pure, crash-safe (every path try/catch → `{}` = safe/no-escalation). Constants named + test-pinned:
```
_windowDays      = 63   // ≈2 phases; captures a ≥28-day flat span with margin
_minSessions     = 3    // ≥3 distinct dated sessions of the compound
_minSpanDays     = 28   // first→last session span ≥4 weeks
_flatRelRange    = 0.05 // (max−min)/max ≤ 5% over the qualifying sessions ⇒ flat
_readinessWindow = 14   // fatigue recency (mirrors _readinessGood)
_minReadiness    = 3
```
API:
- `Set<String> plateauedGroups({required int phase})` — eligible groups for +sets. `{}` when `!plateauEscalationEnabled` OR `!readinessEnabled` OR `phase < 2` OR `_fatiguePresent()` (fatigue → rung-1 deload territory, no +sets) OR no evidence. Else: `byExercise = buildE1rmByDate(box, cutoff: _windowDays-ago)`; for each exercise with `≥_minSessions` dated sessions, span `≥_minSpanDays`, `_isFlat(values)`, `repo.isCompoundByExactName(name)` → map `primary_muscles`→groups via `muscleGroupOf` → union.
- `Map<String,int> mergePlateauSetDeltas(Map<String,int> existing, {required int phase})`:
  ```dart
  final groups = plateauedGroups(phase: phase);
  if (groups.isEmpty) return existing;                 // same ref → byte-identical
  final out = Map<String, int>.from(existing);
  for (final g in groups) out.putIfAbsent(g, () => 1); // no override of −1/+1
  return out;
  ```
- `bool _fatiguePresent()` — `healthBox` `readiness_*` via `ReadinessCheckin.fromMap`, 14-day window; `n=rows`, `flagged=count(level != green)`; `return n >= _minReadiness && flagged*2 > n;`.
- `bool _isFlat(List<double> values)` — `(max−min)/max <= _flatRelRange` (division-safe: `sessionMaxE1rm` filters non-positive; `≥3` gate ⇒ non-empty).
- (12-B adds `plateauedExerciseNames({required int phase})` from the same scan — not exposed in 12-A.)

### 2.3 `plan_generator.dart` — Stage 4.5 merge (single apply)

```dart
// Stage 4.5: phase-boundary volume adjustments — W2.7 titration AND W3.5 plateau
// +sets. BOTH resolve to a per-group ±1 map applied via ONE applyToWeeks pass
// (two passes would double-bump a shared group). Each independently flag+opt-in
// gated; all-off → {} → applyToWeeks identity → byte-identical.
if (applyVolumeTitration || applyPlateauEscalation) {
  final base = applyVolumeTitration
      ? VolumeTitration.resolveDeltas(phase: phase)
      : const <String, int>{};
  final deltas = applyPlateauEscalation
      ? PlateauScan.mergePlateauSetDeltas(base, phase: phase)
      : base;
  weekPlans = VolumeTitration.applyToWeeks(weekPlans, deltas);
}
```

**Byte-identical proof** (`applyPlateauEscalation` default false except the two advance callers): titration-only caller → `base = resolveDeltas(...)`, `deltas = base` (same ref, no `Map.from`) → `applyToWeeks(weekPlans, base)` — identical to today's line. Both-false → block skipped. (Round-1 A+B both confirmed.)

### 2.4 SoT + tests + docs

- **SoT `docs/sot_registry.yaml`:** new concept `plateau_escalation` (writer `PlateauScan.mergePlateauSetDeltas` at `plan_generator.dart` Stage 4.5; reader `VolumeTitration.applyToWeeks`; `behavioral_test_path: test/contracts/plateau_escalation_behavioral_test.dart`). **Gate 18 (`check_reader_manifest_complete.dart`) greps for the literal `.startsWith('exlog_')` — after the extraction that string lives in `e1rm_history.dart`, NOT in `plateau_scan.dart` (which calls `buildE1rmByDate`) nor in the refactored `deload_e1rm_scan.dart`/`volume_titration.dart` (which lose the literal). So add `e1rm_history.dart` to the four existing `exlog_*` reader lists (`:136,248,1282,2792`)** — the new grep-match file (N2). `plateau_scan.dart` reads `readiness_*` → add it to the `readiness_*` reader manifest if one is enforced. (Keeping the now-string-less `deload_e1rm_scan.dart`/`volume_titration.dart` in those lists is harmless over-declaration — Gate 18 fails only on UNdeclared matches.)
- **`test/plan_generator/plateau_scan_test.dart` (pure):** flatness threshold; `_minSpanDays`; `_minSessions`; compound-only; `_fatiguePresent` majority/sparse/exact-half; deterministic; `buildE1rmByDate` construction pinned.
- **`test/contracts/plateau_escalation_behavioral_test.dart`** (mirror the `volume_titration_behavioral_test.dart` Hive harness — clock seam + guarded per-user boxes + library-seeded compound + `path_provider` mock, per `lib/core/services/CLAUDE.md`):
  1. flat-e1RM compound (≥3 sessions ≥28d) + no fatigue + `enable_plateau_escalation`+`enable_readiness` ON + phase≥2 → the group's weekly `sets` +1 vs flag OFF.
  2. **(Round-1 B P1) declining∧flat group (e.g. e1RM `[100,100,100,98]`, range 2% but latest<prior) → titration −1 wins, plateau NEVER adds → group nets −1.**
  3. no-double-bump when titration already +1'd the group.
  4. no +sets when `_fatiguePresent`.
  5. **byte-identical weeks when flag OFF.**
  6. below-MRV clamp respected (group at MRV → no bump).
  7. **(Round-1 B) phase<2 with flag ON → no +sets** (self-gate).
  8. readiness OFF (flag-ordering) → no +sets.
- **Refactor-equivalence:** re-run `deload_eval_behavioral_test` + `volume_titration_behavioral_test` after the `buildE1rmByDate`/`isCompoundByExactName` extraction — must stay green (byte-identical).
- **`lib/shared/repositories/plan_engine/CLAUDE.md`:** a "Plateau escalation (W3.5 — Batch 12-A)" paragraph; note rung-1 delivered by W2.4 (no deload_evaluator change), rung-3 deferred to 12-B, the shared `e1rm_history`/`isCompoundByExactName` extraction, `generator_matrix.dart`/`cascade_tracer.dart` NOT wired (no D3 scorecard movement).

### 2.5 Explicitly OUT of 12-A scope (terminal, not deferred)
- **rung-1 deload:** delivered by existing W2.4 (§1.1) — **no code, ever** (wiring it is dead code).
- **rung-3 rotation + rung-1 explainability:** 12-B (own branch, own ×2 review) — a founder-approved decomposition, NOT a deferral (§4.2). The `enable_plateau_escalation` flag stays OFF until both land + the founder flips post-APK, so the 12-A-only state is inert.
- **scorecard/mirror:** unchanged (frozen D3 baseline unmoved), consistent with W2.7/11-B.

---

## 3. Invariants / risk

- **Ship-dark:** `enable_plateau_escalation` default OFF → identity. Byte-identical verified for titration-only + both-off paths (§2.3), ×2 reviewers.
- **Safe polarity:** the only effect is `+1`, clamped ≤ MRV=20 by the existing `applyToWeeks`; never removes a set, never below MEV; `putIfAbsent` never overrides a titration −1 (a declining group is TRIMMED, never +set — pinned by test #2).
- **Net-new (not a no-op):** rung-2 adds where titration's stricter `_recovered` +1 gate does not (flat e1RM + <3 readiness rows). Confirmed by Round-1 A+B.
- **Flag-ordering:** requires `enable_readiness` ON so the fatigue gate has data (mirrors deload). Documented.
- **Drift (#1 class):** the shared `buildE1rmByDate`/`isCompoundByExactName` extraction removes the 3rd hand-rolled copy; the merged delta map is produced+consumed in one Stage-4.5 statement (no cross-file field contract).
- **PRO:** inherited from the two PRO-only, phase≥2 advance callers (`pro_phase_advance.dart:61` / graduation `gate`) + `phase >= 2` self-gate — consistent with W2.7.
- **Tuning notes (founder, non-blocking, safe direction):** (a) the 5% flatness threshold biases toward FALSE NEGATIVES (rep-driven e1RM noise can exceed 5%) → the feature under-fires rather than over-adds — the safe failure mode; tune down later if it never fires. (b) The 63-day window can flag a group whose compound was rotated out by variety (last trained >28d ago); the clamped +1 still lands on that group's CURRENT exercises — an accuracy quirk, not a safety issue.

---

## 4. REVIEW ROUNDS

### Round 1 — two context-blind reviewers (COMPLETE) — both `accept-with-fixes`, no P0

**Reviewer A (correctness):** independently reconstructed the full `_readinessGood` truth table → **§1.1 dead-code proof HOLDS** (dropping the deload rung is correct, no ladder gap). rung-2 net-new CONFIRMED; byte-identical, double-bump, single-apply, `phase` scoping all sound. Fixes: F1 (§1.4 `generateAndScheduleFromDate`→`generateAndSchedule` label + cite `:117` decl), F2 (§1.3 fatigue source is `_readinessGood`'s `level != green`, not `_recovered`'s soreness), F3 (enum `:15`, getter `:36`).

**Reviewer B (safety/gating):** verified **PRO gating airtight — no free-user +sets path** (`pro_phase_advance.dart:61` + graduation `gate(featurePhases2To12)` + facade waist); §1.1 proof CHECKS OUT; byte-identical + clamp + no-new-persistence sound. **P1:** declining∧flat composition untested → add the net-−1 case. **P2s:** §1.4 method mislabel (same as A-F1); §1.3 fatigue mis-cite (same as A-F2); flag-ordering (gate on `readinessEnabled`); drift hygiene (extract `_isCompound` + map-builder); SoT reader-list completeness; add phase<2 test + Hive-harness reuse.

**Resolution (ALL folded into §1–§3 above, self-verified where load-bearing):** §1.4 method name corrected (I re-read `:97/:117/:139/:248` myself — confirmed). §1.3 fatigue metric corrected to `_readinessGood`'s `level != green`/14d + enum line. `readinessEnabled` gate added to `plateauedGroups` (§2.1). `buildE1rmByDate` + `isCompoundByExactName` extraction added (§2.2), refactoring deload+titration (test-pinned). SoT reader lists (§2.4). Behavioral tests #2 (declining∧flat → net −1), #7 (phase<2), #8 (readiness OFF) added (§2.4). Tuning notes surfaced for the founder (§3).

### Round 2 — one context-blind reviewer on the HARDENED plan (COMPLETE) — `converged`, implement as-is

The reviewer traced each Round-1 correction against ground truth to find defects introduced BY the corrections (§4.12). Verified:
- **Extraction SAFE — provably behavior-identical.** Diffed the two hand-rolled loops line-by-line (`deload_e1rm_scan.dart:55-72` ≡ `volume_titration.dart:63-79`; only diff = split-vs-combined `||` guard, semantically identical; only per-caller diff = the cutoff, now a param). `isCompoundByExactName` = `getByExactName` + `_fieldContains('compound')` (`exercise_repository.dart:204-208`) reproduces `_isCompound` character-for-character. `e1rm.dart` stays pure (untouched); the Hive-`Box` helper is the SEPARATE `e1rm_history.dart` → no new cross-layer dep, no import cycle (acyclic). Behavioral tests + frozen scorecard unmoved (mandate: re-run both).
- **`readinessEnabled` gate CORRECT** — mirrors `deload_evaluator.dart:55-56`; short-circuits before `_fatiguePresent()`; testable (test #1 sets both flags ON, #8 pins readiness-OFF→no-op).
- **Fatigue metric SAFE — mutual-exclusivity airtight.** `_fatiguePresent` reads the SAME `healthBox` `readiness_*` via the SAME `ReadinessCheckin.fromMap`/14-day/`>=` cutoff `_readinessGood` reads (`health_read_service.dart:97-108`, no dedup/limit) → strict complements outside the shared empty/sparse/exact-half middle (both false there) → never both true → §1.1 proof preserved.
- **declining∧flat (test #2) CORRECT** — traced `[100,100,100,98]`: titration −1 (latest 98 < prior 100), plateau flat (2% ≤ 5%), `putIfAbsent` no-ops on the present key → nets −1. `putIfAbsent` can NEVER override an existing −1/+1 for ANY input; `Map.from(existing)` avoids the `const {}` unmodifiable throw.
- **Gate impact clean:** Gate 18 needs `e1rm_history.dart` in the 4 `exlog_` lists (N2, folded into §2.4); parity gate E.13 does NOT trip (no SoT entry cites these files by `line:`/`line_range:` — method-symbol cites only, all surviving); Gate 7 (completeness), Gate 43 (god-file, screens-only + net-removes-lines), Gate 26 (citation) all unaffected.

Nits (no re-round): **N1** (§2.1 flag-line citation → corrected to `deload_evaluator.dart:55-56`), **N2** (ensure `e1rm_history.dart` specifically lands in the 4 `exlog_` lists → clarified in §2.4). Both applied above.

### Convergence — CONVERGED

Two Round-1 reviewers (correctness + safety/gating) both returned `accept-with-fixes` with **no P0**; the hardening folded in every finding; Round-2 on the hardened plan found **no new material defect** (only two cosmetic/execution nits, now applied). Per §4.12, the absence of any *new* material issue on the hardened plan IS the convergence signal — and the unit is already the smallest shippable piece (rung-2 +sets only; rung-1 needs no code, rung-3 is 12-B). `verdict: converged` → implement as-is.
