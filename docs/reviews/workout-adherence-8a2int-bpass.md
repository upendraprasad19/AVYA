---
reviewed_at: 2026-07-18T00:55:00+05:30
staged_against: 2c1916685e89
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 3
verdict: accepted
---

# Code Review (B-pass) — ⑧ UNIT 2-int (repeat-content scheduling) — staging 2c1916685e89

Fresh Sonnet reviewer, context-blind, read all 6 staged files + every existing caller of
`generateAndSchedule`/`autoGenerateNextPhaseIfNeeded` + the box-ownership contracts. **Caught a real
P1 cross-account isolation bug + a real test-coverage gap; both fixed in-batch (§4.2).**

## Finding 1 — P1 — `last_phase_profile` in the SHARED configBox, not user-scoped — FIXED
- **claim:** the write used `_hive.configBox.put('last_phase_profile', …)`. `configBox` is a DEVICE-shared
  box (`hive_service.dart` / `hive_user_session.dart` document it as NOT per-user); `last_phase_profile`
  is per-user data (the user's own goal/equipment/days/experience). On a multi-account device, User B's
  G5 gate would read User A's stale baseline → wrong faithfulness decision (the exact class the
  effectiveExp NEW-1 fix guards against). The sibling `plan_start_date`/`plan_end_date` in the SAME
  method already route through `MigratedKey` (userBox) for this reason.
- **disposition:** ACCEPTED. Fixed: write via `MigratedKey.write('last_phase_profile', …)` + read via
  `MigratedKey.read<Map>('last_phase_profile')` (user-scoped userBox, configBox fallback pre-session);
  registered `'last_phase_profile'` in `UserConfigMigrator.userScopedKeys`. Tests updated to read/reset
  via `MigratedKey`.

## Finding 2 — P1 — the production path (facade `autoGenerateNextPhaseIfNeeded(repeatContent:true)` + the pre-overwrite ordering) was untested — FIXED
- **claim:** the 10 original tests hit only the pure `repeatPinsFrom` + direct `generateAndSchedule`; NO
  test called `autoGenerateNextPhaseIfNeeded(repeatContent:true)` — so the facade `repeatContent` forward
  (the Round-1 P1b catch), the "read getWeek BEFORE plan_start overwrite" ordering, `_buildRepeatPins`,
  and the `effectiveLevel` computation had zero regression coverage.
- **disposition:** ACCEPTED. Added an e2e test: seed an EXPIRED prior phase 2 → advance via the FACADE
  `WorkoutScheduleService.instance.autoGenerateNextPhaseIfNeeded(goal:'recompose', currentPhase:2,
  repeatContent:true)` (flag ON) → assert the new phase's wk1/wk2 rows reproduce the prior A/B selection,
  stamped phase 3. This exercises the facade thread + the pre-overwrite ordering + `_buildRepeatPins` +
  `effectiveLevel` AND the recompose→build_muscle planGoal mapping (folding in Finding 3).

## Finding 3 — P2 — tautological "mapped goal" pure test — FIXED
- **claim:** the test passed the literal `'build_muscle'` (== the helper default), identical to the base
  match case; it never exercised the `FitnessGoals.of(goal).planGoal` mapping (which lives in the wrapper,
  not the pure core).
- **disposition:** ACCEPTED. Deleted the tautological pure test; the mapping is now proven end-to-end by
  the Finding-2 e2e test (goal `recompose` → planGoal `build_muscle` matches the stored baseline → pins).

## Standard lenses + adversarial checks — clean (verified, not assumed)
The reviewer confirmed: SHIP-DARK byte-identity (all 7 existing callers pass neither new param → null/
false; write + extraction each independently flag-gated with `&&`); G5 sufficiency (frame shape is a pure
function of {planGoal, daysPerWeek, effectiveExp}; equipment is the separate cross-tier-faithfulness
dimension; `==` on `num` is value-based so an int/double coercion is safe); extraction ordering correct
(synchronous before the `await generateAndSchedule`); `whereType<Map>()` safe against Hive
`Map<dynamic,dynamic>`; the `reduce` fully guarded by the empty-check; wrapper→pure args 1:1;
`isPhaseExpired` interaction fine; phase-1 pin is by-design (UNIT 3 decides the trigger). writer_reader_drift
clean; no `.functions.invoke`; blast_radius platform correct; no secrets; the one new async write is awaited.

## Post-fix verification
`flutter analyze` clean; 10/10 behavioral (7 pure repeatPinsFrom + 3 Hive incl. the new e2e facade path).
**Verdict: accepted.**
