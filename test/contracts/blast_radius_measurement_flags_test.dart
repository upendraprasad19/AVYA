@Timeout(Duration(minutes: 3))
library;

// L2b Landing B (section 4.6 / blast radius) - the ship-dark flag file of the
// body-measurements sheet is PLATFORM tier by an exact-path rule that sits ABOVE
// the lib/core/services/** account catch-all (first match wins). Three
// questions, each its own test:
//   1. CLASSIFICATION  the classifier's own public functions (parseRegistry /
//                      tierFor) put the file at platform, and a look-alike
//                      sibling stays at the account catch-all (the rule is
//                      exact, not a glob that promotes future files unseen).
//   2. ORDER           the rule precedes the catch-all.
//   3. ROT             the path exists (an exact-path rule that names a missing
//                      file protects nothing; a rename must update the rule).
//
// Plan: docs/plans/coach-measurement-sheet-ui.md (section 4.6)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `as classifier`: that script also defines main().
import '../../scripts/blast_radius_from_diff.dart' as classifier;

const _flagFile = 'lib/core/services/measurement_flags.dart';
const _catchAll = 'lib/core/services/**';

void main() {
  late ({String defaultTier, List<classifier.TierRule> rules}) reg;

  setUpAll(() {
    reg = classifier.parseRegistry(
        File('docs/blast_radius.yaml').readAsStringSync());
  });

  test('the flag file is platform', () {
    expect(classifier.tierFor(_flagFile, reg), 'platform');
  });

  test('a look-alike sibling stays at the account catch-all (the rule is '
      'exact)', () {
    for (final p in [
      'lib/core/services/measurement_flags_extra.dart',
      'lib/core/services/measurement_other.dart',
      'lib/core/services/sub/measurement_flags.dart',
    ]) {
      expect(classifier.tierFor(p, reg), 'account', reason: p);
    }
  });

  test('the rule is an exact path, with no wildcard', () {
    final rules = reg.rules.where((r) => r.glob == _flagFile).toList();
    expect(rules, hasLength(1));
    expect(rules.single.tier, 'platform');
    expect(rules.single.glob.contains('*'), isFalse);
  });

  test('the rule is declared before the lib/core/services/** catch-all', () {
    final flag = reg.rules.indexWhere((r) => r.glob == _flagFile);
    final catchAll = reg.rules.indexWhere((r) => r.glob == _catchAll);
    expect(flag, greaterThanOrEqualTo(0));
    expect(catchAll, greaterThanOrEqualTo(0));
    expect(flag, lessThan(catchAll));
  });

  test('the path exists on disk (an exact-path rule must not rot)', () {
    expect(File(_flagFile).existsSync(), isTrue);
  });
}
