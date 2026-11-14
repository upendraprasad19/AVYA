// Diet plan Unit 3a (2026-11-14, docs/plans/diet-strategy.md §3.3 / §4 test
// 6): the carb and fat TARGETS are read raw only by the three strategy-aware
// readers and the existing writers / sync / restore files. A new screen that
// reads `profile['carb_grams']` itself would show Balanced carbs under a KETO
// label, so a new raw reader fails here and must go through
// macroTargetsProvider / DailyNutritionData (or effectiveMacroTargets).
//
// PRESENCE class (a source scan, stated): an index read `['carb_grams']`,
// `['carbs_grams']` or `['fat_grams']` (either quote) or a `.get('...')` of
// one anywhere under lib/. Map-literal keys
// (`'carb_grams': x`, the writers) are not index reads. Positive controls
// prove the pattern sees the spellings a real reader would use.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Index reads in either quote style, and `.get('...')` / `["..."]` (B-pass
// seat C finding 4). Still a PRESENCE scan: a key built from a variable is
// not seen, which the stated limit in docs/sot_registry.yaml names.
final _rawRead = RegExp(
    r'''(\[\s*|\.get\(\s*)['"](carb_grams|carbs_grams|fat_grams)['"]\s*[\]\),]''');

/// Files allowed to index the raw keys, and why.
const _allowed = <String, String>{
  // The three strategy-aware readers (plan §3.3).
  'lib/features/nutrition/providers/nutrition_provider.dart':
      '_resolveNutritionTargets / resolveBaseMacroPack (the helper runs here)',
  'lib/features/home/providers/home_provider.dart':
      'NutritionSummaryNotifier (the helper on a complete pack)',
  'lib/features/ai_coach/services/ai_snapshot_builder.dart':
      'daily_targets (the helper via _dietStrategyTargets)',
  // Writers, sync and restore: they move the stored Balanced pack, never show it.
  'lib/core/services/sync/sync_profile.dart': 'profile push',
  'lib/core/services/sync_service.dart': 'onboarding replay push',
  'lib/features/onboarding/providers/onboarding_provider.dart':
      'onboarding cloud payload',
  'lib/shared/repositories/user_repository.dart':
      'ensureComputedTargets completeness check (no production caller)',
};

List<String> _offenders(Map<String, String> sources) {
  final out = <String>[];
  sources.forEach((path, src) {
    if (_allowed.containsKey(path)) return;
    final lines = src.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (_rawRead.hasMatch(lines[i])) out.add('$path:${i + 1}');
    }
  });
  return out;
}

void main() {
  test('no raw carb/fat target reader outside the allow-list', () {
    final sources = <String, String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      sources[f.path.replaceAll(r'\', '/')] = f.readAsStringSync();
    }
    expect(sources.length, greaterThan(300),
        reason: 'precondition: the scan saw the tree');
    for (final path in _allowed.keys) {
      expect(sources.containsKey(path), isTrue,
          reason: 'stale allow-list entry: $path');
      expect(_rawRead.hasMatch(sources[path]!), isTrue,
          reason: '$path no longer reads the keys: drop it from the list');
    }
    expect(_offenders(sources), isEmpty);
  });

  test('positive control: the pattern catches every reader spelling', () {
    final fake = {
      'lib/features/x/a.dart': "final c = profile['carb_grams'];",
      'lib/features/x/b.dart': "final c = (p?['carbs_grams'] as num?);",
      'lib/features/x/c.dart': "final f = profile[ 'fat_grams' ];",
      'lib/features/x/d.dart': "final ok = {'carb_grams': 1, 'fat_grams': 2};",
      'lib/features/x/e.dart': 'final c = profile["carb_grams"];',
      'lib/features/x/f.dart': "final c = box.get('fat_grams');",
      'lib/features/x/g.dart': 'final c = box.get("carbs_grams", '
          'defaultValue: 0);',
      'lib/features/x/h.dart': "final s = 'carb_grams';",
    };
    expect(_offenders(fake), [
      'lib/features/x/a.dart:1',
      'lib/features/x/b.dart:1',
      'lib/features/x/c.dart:1',
      'lib/features/x/e.dart:1',
      'lib/features/x/f.dart:1',
      'lib/features/x/g.dart:1',
    ]);
  });
}
