# Focused plan — ⑥ slice B2: community-download equipment_needed write-normalize

> **STATUS: ×2 review CONVERGED (round-1 ×2 + round-2 on the hardened plan).** Round-2 verdict `converged`:
> the dead-chain is TRUE (B2 is consistency-only, NOT load-bearing correctness), crash-safe, idempotent, no
> live reader breaks — 3 P2 implementation-refinements only (test-seam reachability, default-ON note, lossiness
> note), all folded below; no redesign. One round-1 reviewer's "query() is a live reader → load-bearing
> correctness bug" was REFUTED and re-confirmed refuted in round-2: `query()`'s 3 callers are all inside the
> dead `ExerciseSelector.pick()` (0 callers — SELF-grep-verified `.pick(` = 0 in lib/ + `pickV4` is the only
> live selector at plan_generator.dart:124), so `query()` is unreachable in production. Corroborating: community
> rows lack `movement_pattern` → `queryV4` filter #1 (exercise_selector call → exercise_repository.dart) excludes
> them from SELECTION entirely; they reach the user only via shape-tolerant swap/display paths. Base off main @
> `95b9bd6e` (incl. ⑥ A + B1). Land gated on B1 CI-green.

**Tier: PLATFORM** (`lib/core/services/sync/sync_community.dart` → `sync/**`). `requires: [regression_test,
behavioral_test_path, code_review_b_pass, feature_flag]` + §4.12 record with `bpass: accepted`.

## Scope — the write-seam completion (consistency, defense-in-depth)
The community-DOWNLOAD sync writes cloud `user_custom_exercises` rows into the local `exerciseBox` with RAW
`equipment_needed`. Normalize it to canonical at the write seam via `EquipmentVocab.fromProfile` — mirroring
slice A's OWNED custom-write normalize (`workout_repository.dart:1375`) so STORED community data is canonical.

**Necessity (VERIFIED honest):** B1 already read-normalizes every `equipment_needed` via
`EquipmentVocab.fromProfile` at the ONLY live reader — the queryV4 exclusion seam (`exercise_repository.dart:283`
+ selector mirrors `:683`/`:899`). The V3 `query()` equipment-inclusion filter (`exercise_repository.dart:129-140`,
reads RAW, no normalize) has 3 callers (`exercise_selector.dart:265`/`:345`/`:442`) but ALL inside the DEAD
`ExerciseSelector.pick()` (`:61`), which has 0 callers (self-grep verified) — the live path is
`plan_generator.dart:124 → pickV4 → _cascadeFill → queryV4`. So `query()` is unreachable; B2 is NOT a
correctness dependency — it is the WRITE-side consistency completion + defense-in-depth (if `pick()` is ever
revived, or a future reader reads community `equipment_needed` without normalizing, canonical STORED data
protects it). Low-risk, one-seam.

## Ground-truth (SELF-VERIFIED)
- **The seam:** `lib/core/services/sync/sync_community.dart` (a `part of '../sync_service.dart'`)
  `syncCommunityItems` (`:444`) download loop `:499-505`:
  ```dart
  final map = Map<String, dynamic>.from(row as Map);
  final id = map['id']?.toString();
  if (id != null && id.isNotEmpty && exerciseBox.get(id) == null) {
    map['source'] = 'community';
    await exerciseBox.put(id, map);          // :504
  }
  ```
  `equipment_needed` = cloud `user_custom_exercises.equipment_needed` (Postgres `text[]` → Dart `List`).
- **fromProfile** (`equipment_vocab.dart:201-205`) is crash-safe (List / bare-String / null → never throws) +
  returns a canonical `List<String>` + idempotent — correct for the cloud List shape AND a legacy bare-String.
- **The sole two `exerciseBox` writers:** the seed (`seed_service.dart:177`, canonical since v7 / slice A) + this
  community-download (`:504`, the sole un-normalized one). B2 covers it.
- **NOT the upload/restore seams:** `_projectCustomExercise` (`:245-275`, own-custom UPLOAD → cloud, already
  canonical from slice A's write) + `_restoreCustomExercises` (`:321-386`, → `customBox`, own customs) — untouched.
  The `:55` read is `_backfillCustomEntityIds` on `customBox` (different method + box) — unaffected.
- **Live readers of community `equipment_needed`** (VERIFIED none breaks): the B1 queryV4 exclusion filter
  (fromProfile-normalized — now reads already-canonical, consistent); display-only shape-tolerant `parseEquipmentNeeded`
  (swap picker — nothing renders it, slice A); verbatim copies into swap/template (flow to display). The V3
  `query()` membership check (`:133-138`) lowercases both sides but is DEAD (pick() = 0 callers). No live reader
  exact-string-compares raw capitalized community `equipment_needed`.

## Design
1. **Pure, TEST-REACHABLE transform in `EquipmentVocab`** (P2-1 — `syncCommunityItems` reads live Supabase, so
   the transform must be reachable from `test/`; a private `_helper` in a `part of sync_service.dart` file is
   library-private → the rule-21 test would degrade to source-grep, the exact `feedback_source_grep_false_confidence`
   anti-pattern). Home it in `lib/core/utils/equipment_vocab.dart` as a PUBLIC static (mirrors the already-public
   `floorSanitizedExclusions` there):
   ```dart
   /// Normalizes [map]'s `equipment_needed` to canonical vocab (⑥ B2 community
   /// write-seam). Mutates + returns the same map. When [enabled] is false
   /// (kill-switch), returns it unchanged (verbatim raw store — prior behavior).
   static Map<String, dynamic> normalizedEquipmentRow(
     Map<String, dynamic> map, {bool enabled = true}) {
     if (enabled) map['equipment_needed'] = fromProfile(map['equipment_needed']);
     return map;
   }
   ```
   The download loop calls it INSIDE the id-guard, AFTER `map['source']='community'`, BEFORE the put (`:503→:504`),
   reading the flag at the call site (the sync-domain concern):
   ```dart
   map['source'] = 'community';
   await exerciseBox.put(id, EquipmentVocab.normalizedEquipmentRow(
     map,
     enabled: _hive.configBox.get('disable_community_equipment_normalize') != true,
   ));
   ```
   Import `EquipmentVocab` in `sync_community.dart`. (`_hive.configBox` is reachable — the file is
   `part of '../sync_service.dart'` and already uses `_hive`; getter `hive_service.dart:214`.)
2. **Kill-switch (COMMITTED — §4.6 / platform `requires: feature_flag`, no hedge):** flag key
   `disable_community_equipment_normalize`, read at the call site as `_hive.configBox.get(...) != true` — the
   house sync `disable_*` idiom (`sync_service.dart:217/240/274`, `sync_nutrition.dart:211`). **Default (unset) →
   normalize ON** (P2-2 — a DELIBERATE deviation from B1's ship-dark default-OFF: B2 changes only the STORED
   representation, not plan selection, and every live reader already tolerates canonical, so default-OFF would be
   a permanent no-op that never delivers the consistency value; default-ON is the only useful default). Because
   it ships live immediately, keep §4.6 verify discipline (confirm on the test account post-merge). `disable=true`
   → verbatim raw store = today's exact behavior (harmless — no live reader needs canonical STORED community data:
   query() is dead + B1 read-normalizes on the one live selection seam).

## Tests
- **Behavioral (platform behavioral_test_path)** — `test/contracts/community_equipment_normalize_behavioral_test.dart`,
  calls the PUBLIC `EquipmentVocab.normalizedEquipmentRow` directly (no live SyncService needed): a community-shaped
  map with `equipment_needed: ['Cable Machine']` → returned map has `['cables']`; bare-String `'Dumbbells'` →
  `['dumbbells']`; an OR-compound `'Barbell or Dumbbells'` → collapsed canonical (slice-A precedence); a canonical
  row stays canonical (idempotent); null/absent → `[]`, never crashes (the e9d1c7 read class); **`enabled:false` →
  map returned UNCHANGED (kill-switch branch proven, not source-grepped).** Plus a presence source-grep that the
  `sync_community.dart` download loop calls `EquipmentVocab.normalizedEquipmentRow` before `exerciseBox.put` (the
  one irreducible call-site line — the flag-read `!= true` — mirrors B1's guard-source-grep precedent).

## SoT
Extend the `equipment_vocab` concept's writers with the community-download writer (`sync_community.dart`
`syncCommunityItems` → `EquipmentVocab.normalizedEquipmentRow`), keyed to the shared behavioral_test_path.
Writer note MUST record: (P2-3) `normalize` DROPS unmappable tokens → an unmappable community equipment string
is stored as `[]` (lossy on that one field; consistent with the seed's slice-A behavior + B1's read-side drop —
accepted). Also note `query()` reads community `equipment_needed` raw but is DEAD (documented, not a live reader);
community rows lack `movement_pattern` so `queryV4` never selects them (swap/display only).

## Review focus (round-2 — verify the HARDENED plan)
1. The precise query()/pick() dead-chain (query() 3 callers all in pick(), pick() 0 callers) — B2 consistency-only.
2. Normalize INSIDE the id-guard, after source stamp, before put; only new downloads; upload/restore untouched.
3. fromProfile handles the cloud List + bare-String; crash-safe; idempotent.
4. Kill-switch COMMITTED (configBox `disable_*`, default normalize-ON); the extracted seam is behaviorally testable.
5. No live reader breaks; the seed-is-already-canonical invariant holds; legacy raw rows covered by B1 read-normalize.
