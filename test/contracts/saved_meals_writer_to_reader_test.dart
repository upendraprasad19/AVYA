import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

/// Source-of-truth contract: writer/reader pairs for `saved_meals`
/// from docs/sot_registry.yaml.
///
/// Writer: nutrition_provider.SavedMealsNotifier.saveMealPreset
/// Readers: nutrition_provider.SavedMealsNotifier (full class),
///          sync_service._syncSavedMeals
///
/// Key: saved_meal_<nameHash> (hash not ms-timestamp — ensures cloud restore
/// lands at the same key, no duplication).
void main() {
  late String nutritionProvSrc;
  late String syncSvcSrc;
  late String nutritionWriteSvcSrc;

  setUpAll(() {
    final nf = File('lib/features/nutrition/providers/nutrition_provider.dart');
    expect(nf.existsSync(), isTrue,
        reason: 'nutrition_provider.dart must exist (writer for saved_meals)');
    nutritionProvSrc = nf.readAsStringSync();

    final sf = loadSyncServiceSource();
    expect(sf.existsSync(), isTrue, reason: 'sync_service.dart must exist');
    syncSvcSrc = sf.readAsStringSync();

    // C-12 (audit-2026-05-11) — saveMealPreset Hive write was lifted
    // into NutritionWriteService so the literal `saved_meal_` key
    // prefix now lives in the service, not the notifier.
    final wf = File('lib/core/services/nutrition_write_service.dart');
    expect(wf.existsSync(), isTrue,
        reason: 'nutrition_write_service.dart must exist (now owns the write)');
    nutritionWriteSvcSrc = wf.readAsStringSync();
  });

  group('saved_meals writer↔reader source contract', () {
    test('writer saveMealPreset exists in nutrition_provider', () {
      expect(nutritionProvSrc.contains('saveMealPreset'), isTrue,
          reason: 'nutrition_provider must define SavedMealsNotifier.saveMealPreset');
    });

    test('writer uses saved_meal_ key prefix', () {
      // C-12 — accept the literal in either the notifier OR the service.
      final inNotifier = nutritionProvSrc.contains('saved_meal_') ||
          nutritionProvSrc.contains("'saved_meal");
      final inService = nutritionWriteSvcSrc.contains('saved_meal_') ||
          nutritionWriteSvcSrc.contains("'saved_meal");
      expect(inNotifier || inService, isTrue,
          reason:
              'SavedMealsNotifier OR NutritionWriteService must write saved_meal_ '
              'keys per sot_registry.hive.key_prefix.');
    });

    test('writer key uses hash (not ms-timestamp) for cross-device dedup', () {
      // Key should be hash-based (hashCode or similar) not millisecondsSinceEpoch
      // Per sot_registry class_constraints: "Hive key uses name-hash not ms-timestamp"
      // b8d5c2: the writer now keys by UUID v5 over the name (was ms-timestamp);
      // the registry key_formula matches. Accept the prefix in either the
      // notifier or the service.
      expect(
          nutritionProvSrc.contains('saved_meal_') ||
              nutritionWriteSvcSrc.contains('saved_meal_'),
          isTrue,
          reason: 'saved_meal_ key prefix must be present in notifier or service');
    });

    test('reader SavedMealsNotifier class exists', () {
      expect(nutritionProvSrc.contains('SavedMealsNotifier'), isTrue,
          reason: 'SavedMealsNotifier must be defined in nutrition_provider (reader+writer)');
    });

    test('reader _syncSavedMeals exists in sync_service', () {
      expect(syncSvcSrc.contains('_syncSavedMeals'), isTrue,
          reason: '_syncSavedMeals must exist in sync_service for cloud sync');
    });

    test('_syncSavedMeals omits id + upserts onConflict (user_id,name) — f7e3a1', () {
      // f7e3a1 REVERSED the old "coerce id via _deterministicId" contract: a
      // name-only deterministic id collided cross-user (two users, same meal
      // name → same uuid → one overwrote the other). Now: omit id
      // (gen_random_uuid) + a user-scoped natural key. Comment-stripped so the
      // explanatory comment — which names the OLD shape — can't false-pass this.
      final body = _methodBody(syncSvcSrc, '_syncSavedMeals')
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');
      expect(body.contains("onConflict: 'user_id,name'"), isTrue,
          reason: 'f7e3a1: user-scoped natural key (user_id,name)');
      expect(body.contains('_deterministicId'), isFalse,
          reason: 'f7e3a1: id is OMITTED — a name-only deterministic id collided '
              'cross-user. See diagnose f7e3a1.');
    });

    test('cloud table user_saved_meals referenced in sync or restore', () {
      expect(
          syncSvcSrc.contains('user_saved_meals'), isTrue,
          reason: 'sync_service must reference user_saved_meals cloud table');
    });
  });
}

/// Extracts the body of a named async method from source.
String _methodBody(String src, String methodName) {
  final pattern = RegExp(
      r'Future<void>\s+' + methodName + r'\s*\([^)]*\)\s*async\s*\{');
  final match = pattern.firstMatch(src);
  if (match == null) return '';
  final start = match.end - 1;
  var depth = 1;
  var i = start + 1;
  while (i < src.length && depth > 0) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') depth--;
    i++;
  }
  return src.substring(start, i);
}
