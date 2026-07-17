# Focused plan — ⑥ slice C1: equipment-exclusions activation (profile field + Customize UI + cloud)

> **STATUS: ×2 review CONVERGED (round-1 ×2 + round-2 on the hardened plan).** Round-2 verified all 5 round-1
> corrections correct against code + surfaced ONE new gate-hit (P2, folded below: the §1b central-read reads
> `profile['equipment_exclusions']` from `training_history_analyzer.dart` which also reads `exlog_*` → Gate-19
> `check_hive_map_field_drift` hard-fails unless `equipment_exclusions` is added to `_alwaysOk` at
> `check_hive_map_field_drift.dart:310`-adjacent, mirroring `physique_focus` — the ⑤ learning recurring). No
> P0/P1. Ready to implement. The user-facing ACTIVATION
> of B1's inert `equipmentExclusions` seam + B2's canonical stored data. Base off main @ `edf59bb1` (⑥ A+B1+B2
> all CI-green). Worktree `workout-equipment-customize`. Blast radius: **PLATFORM** (`plan_engine/**` + `sync/**`).
>
> **FOUNDER DECISIONS (2026-07-17):** (1) **Path 1 cloud-durable** — new `user_profile.equipment_exclusions`
> column; the migration apply = the one LIVE-PROD-APPLY PAUSE (§4.3). (2) **WU-2 SPLIT to ⑥ C2** — the ×2 review
> verified WU-2 (fix the `hasGymEquipment` always-false + honor exclusions in warmup/cardio) is a distinct,
> larger unit (needs `cardio machine` ADDED to the gym tier lists + a Batch-0 matrix regen + a `template_service`
> 3rd-caller migration + a generateV4-computes-the-signal redesign to stay byte-identical + not break the
> tier-string tests `shared_contracts_test.dart:825-835`). C2 is the IMMEDIATE next unit after C1 (its own plan +
> ×2 + B-pass) — NOT deferred. **This plan is C1 only.**

## What C1 ships (founder-locked "Tier + exclusions")
A user keeps their equipment TIER (onboarding) and, in Edit-Profile, opens a **"Customize"** multi-select to
SUBTRACT items they lack (e.g. `basic_gym` minus `cables`). The MAIN-plan generator (B1's filter) then never
prescribes an exercise requiring an excluded item. Exclusions can never drop below the bodyweight floor.

## Ground-truth (SELF-VERIFIED vs edf59bb1)
- **generateV4 central seam** `plan_generator.dart:78` (`equipmentExclusions` param, default `[]`) + `:100-102`
  (`equipmentExclusionSet = PlanEngineFlags.equipmentExclusionsEnabled ? floorSanitizedExclusions(param) : {}`;
  threaded to `pickV4` `:133`). Mirrors the injury seam `:92`. No caller passes exclusions → inert.
- **Central-read pattern (physique_focus, ⑤):** `TrainingHistoryAnalyzer.resolveBodyFocus`/`physiqueFocusMuscles()`
  reads the profile INSIDE generateV4, **flag-gated** (`physiqueFocusBringupEnabled ? physiqueFocusMuscles() :
  const []`, `training_history_analyzer.dart:149`) — zero caller edits, and NO Hive read on the ship-dark path.
  ALL 6 generateV4 entry points route through the one seam (2 direct: `preview_plan_provider.dart:94`,
  `graduation_screen.dart:339`; 4 via the `generate()` shim `plan_generator.dart:50`).
- **Tier→items** `_getEquipmentList` (`plan_generator.dart:241-261`), private, ONE prod caller (`:80`) + a test
  mirror (`generator_matrix.dart:110`). Each list begins with `'none'` (∉ `canonicalTokens`; `bodyweight` IS
  canonical). full_gym has no `cardio machine` (→ the WU-2/C2 finding).
- **Flag** `equipmentExclusionsEnabled` (`plan_engine_flags.dart:130-138`, `== true` default OFF). No runtime
  seed (grep `configBox.put('enable_`/`'disable_` = 0 in lib/); flip = a one-line getter edit to `disable_* != true`).
- **InjuryVocab chip pattern** (`injury_vocab.dart:40-90`): `chipTokens`/`_chipLabels`+`chipLabel`/`toggleChip`
  (none-sentinel). Exclusions need NO `none` sentinel (empty = exclude nothing).
- **Edit-Profile** (`edit_profile_screen.dart`, all self-verified by reviewer B): `_equipmentOptions` `:100-105`;
  equipment dropdown `:402-407`; injuries chips rendered `:426`; `updates` map `:1590-1621` (`'injuries'` `:1607`,
  `'equipment_access'` `:1601`); `updateProfile(updates)` `:1623` (awaited, writes Hive BEFORE the reschedule);
  `computePlanChanged(...)` `:1665-1680` (a top-level fn `:1877-1900`, required `injuries`/`originalInjuries`);
  reschedule `generateAndScheduleFromDate(injuries:_injuries)` `:1791/:1799`. `_injuries` seed is crash-safe
  `is List` `:175-185`; `_originalInjuries = List.of(_injuries)` `:234`.
- **CLOUD:** `user_profile` is flat dedicated columns, NO json blob (`equipment_access`/`physique_focus`/
  `injuries` are columns). `injuries` type = **`text[]`** (ARRAY/`_text`), DEFAULT `ARRAY['none']` — verified by
  reviewer B via a live `information_schema` query (`live_schema_columns.json` stores NAMES only, so the TYPE is
  NOT verifiable there — re-confirm live before writing the migration). Push `_syncUserProfile` is
  column-ENUMERATED (`sync_profile.dart:82-133`, `injuries` at `:106`); a missing line = not pushed; a nonexistent
  column = live 400. Restore `_restoreUserProfile` `.select()` ALL + merges non-null (`:245-295`) → a new column
  AUTO-restores, no `_restoreXxx`, no restore-completeness entry (injuries/physique_focus aren't in
  `test/sync/restore_completeness_test.dart` either).

## Design (both round-1 reviewers' findings folded)
### 1. EquipmentVocab PURE helpers (`equipment_vocab.dart`) + the tier map — NO Hive read here (P2-6)
`EquipmentVocab` is a pure value-normalizer with ZERO imports today — keep it that way. Add PURE statics:
- `static const Map<String,List<String>> tierItems` — the 4 tier lists VERBATIM (incl. leading `'none'`), so
  `_getEquipmentList` delegates to it (single source, anti-drift). Contract-test invariants (P2-4, corrected):
  `tierItems[t] ⊆ canonicalTokens ∪ {'none'}` (NOT `⊆ canonicalTokens` — `none` offends) AND
  `tierExcludableItems(t) ⊆ canonicalTokens`.
- `static List<String> tierExcludableItems(String tier)` → `tierItems[tier] minus {none, bodyweight}` (the chips).
- `static String chipLabel(String token)` (`pull-up bar`→"Pull-up Bar", `ez-bar`→"EZ-Bar", …).
- `static List<String> toggleExclusion(Iterable<String> current, String token)` — plain add/remove, growable.
- `static List<String> pruneToTier(Iterable<String> current, String tier)` (P2-7, the tier-change prune —
  `toggleExclusion` can't do it without a tier param) → keep only tokens in `tierExcludableItems(tier)`.
### 1b. The Hive-reading glue lives in the PLAN-ENGINE layer (mirror physique_focus, P2-6)
Add `TrainingHistoryAnalyzer.resolveEquipmentExclusions(List<String> param, {required bool flagEnabled})` (Hive-aware,
like `resolveBodyFocus`/`physiqueFocusMuscles`): **`if (!flagEnabled) return const <String>{};`** (P2-5 — no Hive
read on the ship-dark path); else `final raw = param.isNotEmpty ? param : <read userBox['profile']['equipment_
exclusions'] crash-safe via EquipmentVocab.fromProfile>; return EquipmentVocab.floorSanitizedExclusions(raw);`
Crash-safe try/catch→`{}` (mirror `physiqueFocusMuscles` `:104-116`). Behavior-tested directly (flag/param/profile
matrix) AND end-to-end (§Tests).

### 2. generateV4 seam — call the flag-gated helper (`plan_generator.dart:100-102`)
Replace the B1 line with:
```dart
final equipmentExclusionSet = TrainingHistoryAnalyzer.resolveEquipmentExclusions(
    equipmentExclusions, flagEnabled: PlanEngineFlags.equipmentExclusionsEnabled);
```
Flag-OFF → `{}` (no profile read) → byte-identical to B1 (the `{}` makes every downstream drop `.isNotEmpty`-inert).
The param stays a test/direct-caller override; production callers pass nothing → the profile read drives it. ZERO
edits to the 6 callers + the `generate()` shim.

### 3. Edit-Profile "Customize" multi-select (mirror `_buildInjuriesChips`)
- A collapsible "Customize equipment" section below the dropdown (`:407`) showing
  `EquipmentVocab.tierExcludableItems(_equipment)` as toggle chips (selected = excluded). **Empty-state (P2, B):**
  when the excludable set is empty (bodyweight tier → `[]`), HIDE the section (rule 13).
- **State (P2, B — dual seed):** `_equipmentExclusions` seeded CRASH-SAFE in `initState` via
  `EquipmentVocab.fromProfile(profile['equipment_exclusions'])` (legacy bare-String → no `_CastError`) AND
  `_originalEquipmentExclusions = List.of(_equipmentExclusions)` (the change-detector needs the twin).
- On tier change: `_equipmentExclusions = EquipmentVocab.pruneToTier(_equipmentExclusions, newTier)` (drop
  now-invalid exclusions) + re-derive the visible chips.
- Write `'equipment_exclusions': _equipmentExclusions` into `updates` (`:1590`). FREE (a plan-shaping preference).
- **`computePlanChanged` (P2, B — build-breaker):** add required `equipmentExclusions`/`originalEquipmentExclusions`
  params (mirror `injuries`/`originalInjuries` `:1890-1891`) + the `listEquals` check; pass them at the `:1665`
  call. **MUST update the existing test `test/profile/edit_profile_plan_changed_test.dart`** (its `callWith`
  helper `:7-39` + a new "only exclusions changed → true" case) — else `flutter analyze` fails → pre-commit blocks.

### 4. (removed) WU-2 → SPLIT to ⑥ C2 (founder 2026-07-17). C1 does NOT touch warmup/cooldown/cardio.

### 5. Flag ships DARK; flip is a post-APK follow-up
C1 ships with `enable_equipment_exclusions` still OFF (byte-identical). Behavioral tests force it ON via configBox
(B1 precedent). The flip (getter → `disable_equipment_exclusions != true`) is a one-line follow-up after APK-verify.

### 6. CLOUD — Path 1 cloud-durable
Migration `ALTER TABLE user_profile ADD COLUMN equipment_exclusions text[] DEFAULT '{}'::text[]` — **`text[]`
(mirror injuries' TYPE) but DEFAULT `'{}'` NOT `ARRAY['none']` (P2, B — exclusions have no `none` sentinel; empty =
exclude nothing).** Re-confirm the `injuries` type live before writing. One push line at `sync_profile.dart`
(~:106-adjacent, `p['equipment_exclusions'] is List ? … : <String>[]`) + regen `live_schema_columns.json` in the
SAME commit as the apply (§4.5). Restore is AUTO (blob-select). **Ordering (P1, B — the gate does NOT backstop
this):** `check_schema_column_refs.dart:209` only matches an INLINE `.upsert({…}` literal, so the variable-payload
`.upsert(payload,…)` in `_syncUserProfile` is invisible to it — a premature column ref would NOT trip the gate. So
the apply-BEFORE-push-line ordering is enforced by DISCIPLINE (apply to prod → regen → add the push line → commit)
+ §4.5 pairing, NOT the gate. **The migration apply = the founder-authorized LIVE-PROD-APPLY PAUSE (§4.3):** build
+ ×2 + implement ALL local code first (gates green, no cloud-column ref yet), THEN request the explicit apply go;
on go → apply → regen → push line → commit the whole batch ATOMICALLY (no local-only intermediate).

## Tests + SoT
- `test/contracts/equipment_chip_vocab_contract_test.dart` — the CORRECTED invariants (§1) + `chipLabel` totality +
  `toggleExclusion`/`pruneToTier` behavior.
- `test/contracts/equipment_exclusions_activation_behavioral_test.dart` (P2-8, the rule-21 artifact) — open
  `userBox`, WRITE `profile['equipment_exclusions']`, force the flag ON, call `generateV4` **WITHOUT the param** →
  assert the excluded exercise is dropped; flag-OFF byte-identical; empty-profile no-op. (A unit test of the helper
  alone is INSUFFICIENT — reverting the generateV4 seam would still pass, the ⑤ revert-passes trap.)
- Update `test/profile/edit_profile_plan_changed_test.dart` (the required-param addition).
- SoT `equipment_exclusion_filter`: add the profile WRITER (`edit_profile_screen.dart` updates map) + the
  central-read READER (`TrainingHistoryAnalyzer.resolveEquipmentExclusions` @ generateV4 `:100`); register the
  `equipment_exclusions` profile field. Fix the pre-existing `:90`→`:92`/`:100-102` line-ref drift (P3, B) in the
  same commit.
- P3 (cross-tier stale exclusion, B): a stale `full_gym` exclusion for a `basic_gym` user is INERT (the tier
  omits that exercise anyway); `pruneToTier` covers the UI path. Document the inertness in the SoT note (do NOT
  prune at the generateV4 seam — the read is already inert + keeps the seam minimal; round-2 accepted inertness).

## Gates + implementation notes (round-2 folded)
- **Gate-19 (MUST, P2 — the ⑤ learning recurring):** add `'equipment_exclusions'` to the `_alwaysOk` list in
  `scripts/check_hive_map_field_drift.dart` (~:310, beside `'physique_focus'`, with a mirroring comment) IN the
  same commit — the new `resolveEquipmentExclusions` read of `profile['equipment_exclusions']` from
  `training_history_analyzer.dart` (which also reads `exlog_*`/`schedule_*`) is otherwise mis-attributed + hard-fails
  pre-commit + CI. (The reader-manifest Gate-18 is NOT a second hit — the profile singleton has no key-prefix, like
  `physique_focus`.)
- **§1 + §2 are ATOMIC (P3):** §2 removes the sole `EquipmentVocab` reference in `plan_generator.dart` (`:101`);
  §1's `_getEquipmentList → EquipmentVocab.tierItems` delegation re-adds it — do both together or `flutter analyze`
  fails on an unused import. `training_history_analyzer.dart` needs a NEW `import '...equipment_vocab.dart'`.
- **`_getEquipmentList` byte-identity (P3):** the delegation MUST preserve the `default:` fallback —
  `tierItems[equipment] ?? const ['none','bodyweight']` for an unknown tier.
- **Dark-flag reschedule wart (P3, accepted):** adding `equipmentExclusions` to `computePlanChanged` means changing
  exclusions offers a reschedule that (flag-dark) regenerates an identical plan — a harmless no-op prompt that
  self-resolves at the flag-flip. Acceptable (matches how physique_focus behaved pre-flip).

## Review focus (round-2 — verify the HARDENED plan)
1. The flag-gated helper is byte-identical flag-OFF (NO Hive read) + the profile read drives production; EquipmentVocab
   stays pure (no hive_service import); the glue is behavior-tested + the end-to-end rule-21 test is the real artifact.
2. `tierItems`/`tierExcludableItems`/`pruneToTier`/`chipLabel`/`toggleExclusion` invariants (corrected `none` subset).
3. UI: dual crash-safe initState seed; tier-change prune; empty-state; `computePlanChanged` + its test update; the
   reschedule picks up the freshly-saved exclusions (updateProfile awaited before the reschedule).
4. Migration `text[] DEFAULT '{}'`; apply→regen→push-line ordering is discipline-enforced (gate blind); restore auto.
5. No pick-path/B1 regression; the split of WU-2 leaves no exclusion-leak in C1's scope (C1 is main-plan only).
