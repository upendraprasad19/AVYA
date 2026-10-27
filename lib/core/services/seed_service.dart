import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart' show Box;

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'singleton_lifecycle_registry.dart';

// Top-level function required by compute() — runs in a background isolate.
// Parses a JSON array string into a Map keyed by each item's 'id' field.
Map<String, dynamic> _parseJsonToIdMap(String jsonString) {
  final List<dynamic> items = json.decode(jsonString) as List<dynamic>;
  final Map<String, dynamic> result = {};
  for (final item in items) {
    final map = item as Map<String, dynamic>;
    final id = map['id'] as String?;
    if (id != null) result[id] = map;
  }
  return result;
}

/// Seeds bundled JSON assets into Hive on first launch.
///
/// Exercises (200+) and foods (5,000) are shipped inside the APK as JSON
/// and parsed into their respective Hive boxes exactly once.
///
/// JSON parsing runs in a background isolate via [compute] to avoid
/// blocking the main thread during first-launch seeding.
///
/// Uses granular flags (`seeded_exercises`, `seeded_foods`) so that if
/// one asset fails (corrupt file, disk full), the other can still succeed
/// and the failed one retries on next launch.
class SeedService {
  SeedService._() {
    _registerLifecycle();
  }
  static final SeedService _instance = SeedService._();

  /// Tech-debt audit 2026-05-20 / A7 (B5 D9-D10) — prefer
  /// `ref.read(seedServiceProvider)` over `.instance`. SeedService
  /// reads shared boxes (exerciseBox / foodBox), so the reset hook is
  /// a no-op today — the Provider exists for parity + future-proofing
  /// (a seed-version cache would gain a natural reset target here).
  @Deprecated(
      'Use ref.read(seedServiceProvider) — singleton path will be removed after full migration')
  static SeedService get instance => _instance;

  /// Tech-debt audit 2026-05-20 / A7 — register cross-account reset
  /// hook. SeedService reads exerciseBox + foodBox (shared, not
  /// user-scoped) so its operation is genuinely user-agnostic — there
  /// is no leak vector today. The hook is wired anyway for parity:
  /// any future cache (seed-version memo, parsed manifest) gains a
  /// canonical reset target.
  void _registerLifecycle() {
    SingletonLifecycleRegistry.register('SeedService', _onUserChanged);
  }

  /// A7 — invoked from [SingletonLifecycleRegistry.notifyUserChanged].
  /// No-op today (seed state is shared across users).
  void _onUserChanged() {
    // Intentionally empty — seed data is shared across all users.
  }

  static const String _exerciseAssetPath = 'assets/data/exercise_library.json';
  static const String _foodAssetPath = 'assets/data/food_database.json';

  /// Legacy flag — kept for backward compat with existing installs.
  static const String _seededKey = 'seeded';

  /// Granular flags — one per asset, so partial failures are retried.
  static const String _exercisesSeededKey = 'seeded_exercises';
  static const String _foodsSeededKey = 'seeded_foods';

  /// Bump this integer whenever the bundled exercise_library.json changes
  /// (new exercises added, existing exercises modified). On app launch, if the
  /// stored version is less than this, exercises are re-seeded. putAll() is
  /// idempotent — existing entries are overwritten with the same data while
  /// new entries are added.
  // v7 (⑥ slice A): equipment_needed normalized to EquipmentVocab.canonicalTokens.
  // v8 (Batch 13-A): gains-only equipment_tier deepening (90 rows) + 9 stubs E252-E260
  //   normalized to the 38-key schema (incl. injury tags — closes the E252 knee hole) +
  //   E261 Bodyweight Rear Delt Raise added. Re-seed heals the malformed stub rows in Hive.
  // v9 (Batch 13-B): comprehensive injury_contraindications tagging — 26 under-tagged rows
  //   gained tags + 2 existing rows deepened (GHD Sit Up, Good Morning). Closes the empty-[]
  //   safety holes (hinges/rows/overhead served to injured users). injury_contraindications
  //   is NOT a cloud column → no migration 074 re-apply.
  // v10 (OI-89): the equipment restore. 31 rows recovered the distinctions the
  //   2026-08 normalizer destroyed (87 tokens -> 11), 9 corrected by name evidence,
  //   12 new rows added, and equipment_tier RE-DERIVED from equipment_needed for
  //   every row -- the drop-side pass the 13-A entry said would come later. Without
  //   this bump the retag is inert for every existing install, which is the whole
  //   point: Chin Up keeps shipping to bodyweight users off the stale box.
  // v11 (exercise plates): demo_slug + demo_pair on 165 rows; the three dead
  // image URL fields removed. Re-seed rewrites every row in place via putAll.
  // v12 (Batch A library data repair, docs/plans/2026-10-22-library-data-repair.md):
  //   136 coaching-text rows un-shifted (OI-149) and every cue list split into
  //   one cue per item; 7 duplicate rows retired into their twins (name_aliases
  //   + merged_ids, and the prune below deletes them from existing installs);
  //   E172/E163 label typos; 19 start/end plate swaps; 2 wrong drawings removed.
  // v13 (Batch B1, docs/plans/2026-10-22-library-core-list-pool.md): core-list
  //   selection fields added to every row (core_levels, discipline,
  //   gym_availability, requires_coaching, high_impact; optional variant_family,
  //   slot_focus, slot_pattern, skill ladder keys); five safety-direction injury
  //   tags (Task 1b). New keys only, read by CoreListSelector behind
  //   enable_core_list_pool; no cloud column (plan Ruling 2).
  // v14 (injury re-check, docs/plans/2026-10-23-library-injury-recheck.md, d30de7):
  //   the founder rejected the 13-B "kept safe for variety" carve-out, so 104 rows
  //   gained 148 injury_contraindications tokens (additions only; Push Up is now
  //   wrist + shoulder, Chin Up elbow only). injury_contraindications is NOT a
  //   cloud column -> no migration. Without this bump the tags are inert for every
  //   existing install (library_seed_v14_upgrade_behavioral_test.dart).
  // v15 (Batch C1, docs/plans/2026-10-25-library-batch-c-new-rows.md): the library
  //   gains 629 rows (ids G####, N##) built from scripts/data/library_batch_c_source.json
  //   by scripts/add_library_batch_c_v15.js, each with injury tags from
  //   library_injury_additions_v15.json; E274 target_focus Upper Back -> Mid Back.
  //   Nothing is removed (Batch C2). Without this bump the new rows never reach an
  //   existing install (library_seed_v15_upgrade_behavioral_test.dart).
  // v16 (Batch M1, docs/plans/2026-10-27-library-batch-m1-media-data.md): the 617
  //   rows that have a Wardroom animation gain media_slug, media_version and
  //   media_source (scripts/data/library_media_v16.json, written by the media stage
  //   of scripts/add_library_batch_c_v15.js). Nothing reads them until Batch M2.
  //   A later media_version change reaches an installed copy only if this constant
  //   is bumped again (library_seed_v16_upgrade_behavioral_test.dart).
  static const int _exerciseLibraryVersion = 16;
  static const String _exerciseVersionKey = 'exercise_library_version';

  /// Bump this integer whenever the bundled food_database.json changes
  /// (new foods added, existing foods modified, schema extended). On app
  /// launch, if the stored version is less than this, foods are re-seeded.
  /// putAll() is idempotent — existing entries are overwritten with the
  /// same data while new entries are added.
  ///
  /// v3 (2026-09 meal-quality batch): every row gained `meal_fit` +
  /// `is_ultra_processed`. WITHOUT the bump, existing installs keep
  /// untagged v2 rows and the generator's quality filters silently no-op
  /// (missing field ⇒ UPF=false / matches-all) — plan-review round 1,
  /// finding 1.
  static const int _foodLibraryVersion = 3;
  static const String _foodVersionKey = 'food_library_version';

  final HiveService _hive = HiveService.instance;

  /// Checks if seed data has already been loaded; if not, seeds both
  /// exercise and food databases into Hive.
  ///
  /// On subsequent launches this returns immediately (fast path).
  /// Partial failures are handled: if exercises succeed but foods fail,
  /// exercises won't be re-seeded on the next launch.
  Future<void> seedIfNeeded() async {
    final configBox = _hive.configBox;

    // Fast path: both already seeded (or legacy flag from previous version).
    final alreadySeeded = configBox.get(_seededKey, defaultValue: false) as bool;
    final exercisesSeeded =
        configBox.get(_exercisesSeededKey, defaultValue: false) as bool;
    final foodsSeeded =
        configBox.get(_foodsSeededKey, defaultValue: false) as bool;

    // Check if exercise library needs a version upgrade (new exercises added).
    final storedExVersion =
        configBox.get(_exerciseVersionKey, defaultValue: 0) as int;
    final needExerciseUpgrade =
        exercisesSeeded && storedExVersion < _exerciseLibraryVersion;

    // Check if food library needs a version upgrade (new foods added).
    final storedFdVersion =
        configBox.get(_foodVersionKey, defaultValue: 0) as int;
    final needFoodUpgrade =
        foodsSeeded && storedFdVersion < _foodLibraryVersion;

    if (alreadySeeded &&
        exercisesSeeded &&
        foodsSeeded &&
        !needExerciseUpgrade &&
        !needFoodUpgrade) {
      return;
    }

    // If legacy flag is set but granular flags aren't, migrate.
    if (alreadySeeded && !exercisesSeeded) {
      await configBox.put(_exercisesSeededKey, true);
    }
    if (alreadySeeded && !foodsSeeded) {
      await configBox.put(_foodsSeededKey, true);
    }
    // Don't early-return here if a version upgrade is needed — legacy installs
    // may have alreadySeeded=true but stale library versions.
    if (alreadySeeded && !needExerciseUpgrade && !needFoodUpgrade) return;

    // Seed each asset independently — partial failures don't block the other.
    final needExercises = !exercisesSeeded || needExerciseUpgrade;
    final needFoods = !foodsSeeded || needFoodUpgrade;

    await Future.wait(
      [
        if (needExercises) _seedExercises(),
        if (needFoods) _seedFoods(),
      ],
      eagerError: false, // Let both complete even if one fails
    );

    // Mark individual success flags. The results list maps 1:1 with the
    // futures we passed in, but since we used conditional list entries,
    // we track success via try/catch inside each seed method instead.
    // (The actual success tracking is done by the methods themselves.)

    // If both granular flags are now set, mark legacy flag too.
    final exDone =
        configBox.get(_exercisesSeededKey, defaultValue: false) as bool;
    final fdDone =
        configBox.get(_foodsSeededKey, defaultValue: false) as bool;

    if (exDone && fdDone) {
      await configBox.put(_seededKey, true);
    }
  }

  /// The ids every bundled row lists in `merged_ids`: library rows retired into
  /// a kept twin, which must no longer exist in exerciseBox. An id the bundle
  /// still ships is never returned, so a bad edit cannot make the prune delete
  /// a row putAll has just written.
  @visibleForTesting
  static Set<String> retiredLibraryIds(Iterable<Object?> rows) {
    final merged = <String>{};
    final shipped = <String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final id = row['id'];
      if (id != null) shipped.add(id.toString());
      final ids = row['merged_ids'];
      if (ids is List) merged.addAll(ids.map((e) => e.toString()));
    }
    return merged.difference(shipped);
  }

  /// Deletes exactly [ids] from [box]. Only E-ids listed in `merged_ids` are
  /// ever passed, so community rows (UUID keys) are never touched.
  @visibleForTesting
  static Future<void> pruneRetired(Box<dynamic> box, Set<String> ids) =>
      box.deleteAll(ids.where(box.containsKey).toList());

  /// Reads [_exerciseAssetPath] from the asset bundle, parses it in a
  /// background isolate, then writes every exercise into exerciseBox keyed
  /// by its `id`, and prunes the retired ids.
  Future<void> _seedExercises() async {
    try {
      final jsonString = await rootBundle.loadString(_exerciseAssetPath);
      final entries = await compute(_parseJsonToIdMap, jsonString);
      await _hive.exerciseBox.putAll(entries);
      // putAll never deletes: a row retired into its twin would otherwise live
      // on in every existing install and keep being offered.
      await pruneRetired(_hive.exerciseBox, retiredLibraryIds(entries.values));
      await _hive.configBox.put(_exercisesSeededKey, true);
      await _hive.configBox.put(_exerciseVersionKey, _exerciseLibraryVersion);
      debugPrint('[SeedService] Exercises seeded: ${entries.length} items (v$_exerciseLibraryVersion)');
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[SeedService._seedExercises] FAILED: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'seed_service_seed_exercises'));
      // Will retry on next launch since _exercisesSeededKey stays false.
    }
  }

  /// Reads [_foodAssetPath] from the asset bundle, parses it in a
  /// background isolate, then writes every food item into foodBox keyed
  /// by its `id`.
  Future<void> _seedFoods() async {
    try {
      final jsonString = await rootBundle.loadString(_foodAssetPath);
      final entries = await compute(_parseJsonToIdMap, jsonString);
      await _hive.foodBox.putAll(entries);
      await _hive.configBox.put(_foodsSeededKey, true);
      await _hive.configBox.put(_foodVersionKey, _foodLibraryVersion);
      debugPrint(
        '[SeedService] Foods seeded: ${entries.length} items (v$_foodLibraryVersion)',
      );
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[SeedService._seedFoods] FAILED: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'seed_service_seed_foods'));
      // Will retry on next launch since _foodsSeededKey stays false.
    }
  }
}
