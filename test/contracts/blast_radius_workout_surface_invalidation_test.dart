@Timeout(Duration(minutes: 3))
library;

// train-coach-log-refresh (OI-370), B-pass fb5048e68fae F12a: the one list the
// three account-tier coach write paths refresh Train through is ACCOUNT tier
// by an exact-path rule that sits ABOVE the lib/features/train/** feature
// catch-all (first match wins). Same three questions as
// blast_radius_measurement_flags_test.dart: classification, order, rot.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `as classifier`: that script also defines main().
import '../../scripts/blast_radius_from_diff.dart' as classifier;

const _file = 'lib/features/train/providers/workout_surface_invalidation.dart';
const _catchAll = 'lib/features/train/**';

void main() {
  late ({String defaultTier, List<classifier.TierRule> rules}) reg;

  setUpAll(() {
    reg = classifier.parseRegistry(
        File('docs/blast_radius.yaml').readAsStringSync());
  });

  test('the helper is account', () {
    expect(classifier.tierFor(_file, reg), 'account');
  });

  test('a look-alike sibling stays at the feature catch-all (the rule is '
      'exact)', () {
    for (final p in [
      'lib/features/train/providers/workout_surface_invalidation_extra.dart',
      'lib/features/train/providers/train_provider.dart',
    ]) {
      expect(classifier.tierFor(p, reg), 'feature', reason: p);
    }
  });

  test('the rule is an exact path, with no wildcard', () {
    final rules = reg.rules.where((r) => r.glob == _file).toList();
    expect(rules, hasLength(1));
    expect(rules.single.tier, 'account');
  });

  test('the rule is declared before the lib/features/train/** catch-all', () {
    final at = reg.rules.indexWhere((r) => r.glob == _file);
    final catchAll = reg.rules.indexWhere((r) => r.glob == _catchAll);
    expect(at, greaterThanOrEqualTo(0));
    expect(catchAll, greaterThanOrEqualTo(0));
    expect(at, lessThan(catchAll));
  });

  test('the path exists on disk (an exact-path rule must not rot)', () {
    expect(File(_file).existsSync(), isTrue);
  });
}
