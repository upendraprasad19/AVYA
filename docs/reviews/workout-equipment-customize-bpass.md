---
branch: workout-equipment-customize
scope: ⑥ slice C1 — equipment-exclusions activation (profile field + Customize UI + central-read + cloud column, platform)
blast_radius: platform
reviewer: context-blind adversarial B-pass (self-initiated, §4.3)
verdict: accepted
---

# B-pass — ⑥ slice C1 equipment-exclusions activation

Context-blind adversarial review of the implemented diff (15 staged files, platform tier). Every load-bearing
claim verified against the actual code + THREE live confirmations: `flutter analyze` clean on all 5 changed
source files, all 19 tests green across the 3 test files, and an empirical probe settling the rule-21 crux.
**No P0/P1 defects.**

## Verified-clean (by bug class)
- **Central-read (`plan_generator.dart:105` + `training_history_analyzer.dart` `resolveEquipmentExclusions`) —
  CLEAN.** Flag OFF → `const {}` with NO Hive read (byte-identical to B1, confirmed by the passing behavioral
  test); flag ON + non-empty param → B1's `floorSanitizedExclusions(param)` path preserved; flag ON + empty →
  crash-safe profile read (try/catch → {}, mirrors `physiqueFocusMuscles`). The double
  `floorSanitizedExclusions(fromProfile(...))` is correct AND non-redundant (`fromProfile` crash-safe-coerces
  the raw `dynamic`; floor-strip removes none/bodyweight). Idempotent; floor never excludable.
- **EquipmentVocab helpers — CLEAN, no drift.** `tierItems` is a line-by-line VERBATIM match of the deleted
  `_getEquipmentList` switch (4 tiers + leading `none`); `_getEquipmentList` delegates with the preserved
  `?? const ['none','bodyweight']` fallback; `chipLabel` covers all 11 non-bodyweight canonical tokens (the
  contract test iterates canonicalTokens); `toggleExclusion` no-sentinel + growable; `pruneToTier` correct.
- **Edit-Profile UI — CLEAN.** Dual crash-safe initState seed; tier-change `pruneToTier`; empty-state
  `SizedBox.shrink()` with NO dangling gap; `computePlanChanged` params + call + changes-line present.
  Critically `updateProfile` is AWAITED (`:1701`) BEFORE `computePlanChanged` (`:1743`) + the reschedule → the
  central-read sees fresh Hive exclusions. Chip mirrors `_buildInjuriesChips`; color tokens valid.
- **Cloud — CLEAN.** Migration `104` = `text[] DEFAULT '{}'` (mirrors injuries' type, NOT its `ARRAY['none']`
  default); push line mirrors injuries (`is List ? … : <String>[]`); `live_schema_columns.json` updated;
  `applied_migrations.json` entry 104 hash matches `sha256sum` of the file; LF-only + `.gitattributes eol=lf`
  (no CRLF/CI divergence); restore is genuinely automatic (`_restoreUserProfile` bare `.select()` + non-null
  merge → no `_restoreXxx`, no column ref for the schema-col gate to trip).
- **Gate-19 — CLEAN.** `equipment_exclusions` added to `_alwaysOk` beside `physique_focus` (necessary — the new
  profile read lives in a file that also reads `exlog_*`).
- **Tests — CLEAN; rule-21 guard is GENUINE (empirically probed).** The reviewer confirmed the baseline
  full_gym/build_muscle/intermediate/phase-1 plan DOES prescribe a `cables` exercise, so the activation test
  (profile `['cables']`, flag ON, NO param → no cables) genuinely fails on a reverted seam (revert → param
  defaults `[]` → `{}` → cables survives → red). Vocab contract test sound; `edit_profile_plan_changed_test`
  updated (2 params + a new "only exclusions changed → true" case). All 19 pass.
- **Misc — CLEAN.** No unused import; no broken tier-string; correct design-system tokens; byte-identical-OFF
  verified; the only consumer is the Hive-direct central read (UI re-seeds from Hive in initState).

## P3 (already acknowledged in the plan; not blocking)
- Dark-flag reschedule no-op (changing exclusions offers a reschedule that regenerates an identical plan while
  the flag is dark) — accepted, matches pre-flip physique_focus behavior.
- Restore vs unsynced local exclusion: DB default `'{}'` (non-null) means restore's non-null merge overwrites an
  unsynced local exclusion with cloud `[]` — identical to how `injuries` (`DEFAULT ARRAY['none']`) already
  behaves; pre-existing accepted profile-merge semantics, ship-dark, not a C1 regression.
- Live-apply of migration 104 can't be verified from code — the ledger records it at the founder-authorized
  apply; a merge-time live-verification item, not a code defect (verified live via information_schema).

**Layers checked:** client code (central-read, EquipmentVocab, Edit-Profile UI), Hive write shape, Postgres
schema (migration + live column), sync push, gate scripts, tests. B-pass ACCEPTED.
