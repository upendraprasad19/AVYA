---
branch: workout-equipment-customize
scope: ⑥ slice C1 — equipment-exclusions activation (profile field + Edit-Profile Customize UI + central-read + cloud column)
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-equipment-customize-bpass.md
---

# Plan-review record — ⑥ slice C1 (equipment-exclusions activation)

Plan: [`docs/plans/equipment-exclusions-activation-batch.md`](../plans/equipment-exclusions-activation-batch.md).
§4.12 ×2 context-blind review (round-1 = 2 reviewers on the settled plan; round-2 on the hardened plan). Every
load-bearing claim verified against `plan_generator.dart` / `equipment_vocab.dart` / `training_history_analyzer.dart`
/ `edit_profile_screen.dart` / `sync_profile.dart` / the gate scripts / live schema (never subagent prose).
**Converged — implementing.** PLATFORM tier (`plan_engine/**` + `sync/**`). WU-2 SPLIT to ⑥ C2 (founder). The
migration apply is the founder-authorized LIVE-PROD-APPLY pause. `bpass: accepted` added after the pre-merge B-pass.

## Founder decisions (2026-07-17)
- **Path 1 cloud-durable** — new `user_profile.equipment_exclusions text[]` column (survives reinstall like every
  other preference). Migration apply = the one live-prod-apply pause.
- **WU-2 → ⑥ C2** — the ×2 review verified WU-2 is a distinct larger unit (gym-cardio pools normalize to
  `cardio machine` which no tier emits → a tier-composition change + Batch-0 matrix regen; a 3rd `attach` caller
  `template_service` passes the tier-string + would regress; tier-string tests `shared_contracts_test.dart:825`
  break → a generateV4-computes-the-signal redesign). Founder split it to C2 (immediate-next unit, own plan+×2+B-pass).

## Ground-truth verified (self + reviewers, against code)
- **Central-read (physique_focus ⑤ pattern):** the exclusion set is derived ONCE in generateV4 (`:100-102`,
  mirroring the injury seam `:92`), flag-gated. The Hive-reading glue goes in a PLAN-ENGINE helper
  `TrainingHistoryAnalyzer.resolveEquipmentExclusions(param, {flagEnabled})` (mirrors `resolveBodyFocus`/
  `physiqueFocusMuscles` — `training_history_analyzer.dart` already imports `hive_service.dart:5` + reads
  `userBox.get('profile')` `:106`), NOT in the pure import-free `EquipmentVocab`. Flag-OFF → `const {}` (NO Hive
  read) → byte-identical to B1. Zero edits to the 6 generateV4 callers + the `generate()` shim.
- **Corrected contract invariant:** each `_getEquipmentList` tier begins with `'none'` (∉ `canonicalTokens`;
  `bodyweight` IS canonical), so `tierItems ⊆ canonicalTokens ∪ {'none'}` (NOT `⊆ canonicalTokens`) +
  `tierExcludableItems (= tier − {none,bodyweight}) ⊆ canonicalTokens`.
- **UI:** mirror `_buildInjuriesChips`; dual crash-safe initState seed (`_equipmentExclusions` via
  `EquipmentVocab.fromProfile` + `_originalEquipmentExclusions`); tier-change `pruneToTier`; empty-state hide at
  bodyweight tier; write `equipment_exclusions` into the `updates` map (`:1590`) + add required params to
  `computePlanChanged` (`:1877-1900`) — which BREAKS its sole test caller `edit_profile_plan_changed_test.dart:23`
  unless updated in-scope (build-breaker). `updateProfile` (`:1623`, awaited) writes Hive BEFORE the reschedule
  (`:1791`), so the central read sees the fresh exclusions.
- **Cloud:** `user_profile` is flat columns, no json blob. `injuries` type = `text[]` (verified via live
  `information_schema`; `live_schema_columns.json` stores NAMES only). Migration `ADD COLUMN equipment_exclusions
  text[] DEFAULT '{}'` (NOT injuries' `ARRAY['none']` — exclusions have no `none` sentinel). Push is
  column-enumerated (`sync_profile.dart:106`); restore auto (blob `.select()` merge → no `_restoreXxx`, no
  restore-completeness entry). **Ordering is DISCIPLINE-enforced not gate-enforced:** `check_schema_column_refs.dart:209`
  only matches an inline `.upsert({` — the variable-payload `.upsert(payload,…)` is invisible → apply → regen →
  push-line → commit, in that order (the gate won't backstop a premature column ref).
- **Gate-19 (the ⑤ learning):** `resolveEquipmentExclusions` reading `profile['equipment_exclusions']` from
  `training_history_analyzer.dart` (also reads `exlog_*`) trips `check_hive_map_field_drift` unless
  `equipment_exclusions` is added to `_alwaysOk` (`:310`-adjacent, beside `physique_focus`), same commit. Gate-18
  reader-manifest is NOT a second hit (profile singleton, no key-prefix).

## Round 1 (×2 context-blind, on the settled plan)
Both **needs-revision, no re-architecture** for the core. Engine reviewer: WU-2 has 3 P1s → distinct unit (→ C2
split); §1 invariant `tierItems ⊆ canonicalTokens` false (`none`); flag-gate the profile read; layer the Hive
read in TrainingHistoryAnalyzer not EquipmentVocab; the rule-21 test must be end-to-end (profile→generateV4-no-param),
not a helper unit test (⑤ revert-passes trap); `toggleExclusion` needs a separate `pruneToTier`. UI/cloud reviewer:
migration `text[] DEFAULT '{}'` not `ARRAY['none']`; the check_schema_column_refs gate is blind to the variable
payload (ordering is discipline); `computePlanChanged` test is a build-breaker; dual crash-safe initState seed;
bodyweight empty-state. All folded.

## Round 2 (context-blind, on the HARDENED plan)
**Converged.** All 5 corrections verified correct against code (layering, invariants, test-update, migration
default + gate-blind ordering, rule-21 end-to-end). ONE new gate-hit surfaced + folded: Gate-19 `_alwaysOk`
(the ⑤ learning recurring). P3 polish (§1/§2 atomicity → unused-import; `_getEquipmentList` default fallback
preserve; SoT `:90`→`:92` line-ref; dark-flag reschedule no-op accepted). No P0/P1.

## Verdict: converged
The exclusions activation (pure EquipmentVocab helpers + a flag-gated plan-engine central-read helper byte-identical
dark-ship, Customize UI mirroring the injury chips with dual seed + tier-prune + empty-state, the `computePlanChanged`
+ test update, the `text[] DEFAULT '{}'` cloud column applied-before-push-line, Gate-19 allowlist) is correct and
implementable as specified. B-pass runs on the implemented diff before the `--no-ff` merge (§4.3 / platform).
