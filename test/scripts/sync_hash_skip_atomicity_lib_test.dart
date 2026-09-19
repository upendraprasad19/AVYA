// Pure-logic tests for scripts/check_sync_hash_skip_atomicity.dart's core
// checker (scripts/sync_hash_skip_atomicity_lib.dart). CLAUDE.md §4.11/rule
// 24 — a matching e2e test lives at
// test/scripts/sync_hash_skip_atomicity_e2e_test.dart.
import 'package:flutter_test/flutter_test.dart';
import '../../scripts/sync_hash_skip_atomicity_lib.dart';

void main() {
  group('checkDomainAtomicity', () {
    test('vacuously fine when the mechanism does not exist yet', () {
      expect(checkDomainAtomicity('class Foo {}', exlogSpec), isNull);
    });

    test('gate reports a violation as non-null (ledger red-path form)', () {
      // OI-204 C1 fixture: unconditional store, no flag at all.
      final v = checkDomainAtomicity(
        'Future<void> _syncExerciseLogs(String userId) async {\n'
        '  exlogHashIndex[key] = fp;\n'
        '}\n',
        exlogSpec,
      );
      final isViolation = v != null;
      expect(isViolation, isTrue);
    });

    test('passes on a correctly-guarded, correctly-counted exlog fixture', () {
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  for (final key in workoutBox.keys) {
    try {
      bool exlogBundleSynced = true;
      await upsertSummary();
      if (resolvedSets.isNotEmpty) {
        try {
          await upsertSets();
        } catch (e) {
          exlogBundleSynced = false;
        }
      }
      if (exlogBundleSynced) {
        exlogHashIndex[key] = fp;
      }
    } catch (e) {}
  }
}
''';
      expect(checkDomainAtomicity(source, exlogSpec), isNull);
    });

    test('passes when the guard is a compound condition (real shape: flag && extra check)',
        () {
      // Matches the actual Task 2/3 code shape (spec §5.4's fingerprint-failure
      // safety net adds `&& fp != null` alongside the flag).
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  bool exlogBundleSynced = true;
  String? fp;
  try {
    await upsertSets();
  } catch (e) {
    exlogBundleSynced = false;
  }
  if (exlogBundleSynced && fp != null) {
    exlogHashIndex[key] = fp;
  }
}
''';
      expect(checkDomainAtomicity(source, exlogSpec), isNull);
    });

    test(
        'passes when the fixture includes the preamble hydration loop AND the '
        'skip-check read (OI-204 C1 regression: a naive substring match on the '
        'store prefix false-positives on both — neither is a store)', () {
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  final Map<String, String> exlogHashIndex = <String, String>{};
  final rawIndex = workoutBox.get(SyncService._exlogHashIndexKey);
  if (rawIndex is Map) {
    rawIndex.forEach((k, v) {
      if (k is String && v is String) exlogHashIndex[k] = v;
    });
  }
  for (final key in workoutBox.keys) {
    bool exlogBundleSynced = true;
    String? fp;
    try {
      shouldSkip = SyncService.exlogShouldSkipUpsert(
        killSwitchDisabled: exlogHashSkipDisabled,
        storedFingerprint: exlogHashIndex[key],
        currentFingerprint: computedFp,
      );
      await upsertSets();
    } catch (e) {
      exlogBundleSynced = false;
    }
    if (exlogBundleSynced && fp != null) {
      exlogHashIndex[key] = fp;
    }
  }
}
''';
      expect(checkDomainAtomicity(source, exlogSpec), isNull);
    });

    test('FAILS when the guard is inverted (if (!flag) is backwards, not a guard)', () {
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  bool exlogBundleSynced = true;
  try {
    await upsertSets();
  } catch (e) {
    exlogBundleSynced = false;
  }
  if (!exlogBundleSynced) {
    exlogHashIndex[key] = fp;
  }
}
''';
      final v = checkDomainAtomicity(source, exlogSpec);
      expect(v, isNotNull);
      expect(v!.message, contains('not visibly guarded'));
    });

    test('FAILS when the store is unconditional (flag never declared)', () {
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  exlogHashIndex[key] = fp;
}
''';
      final v = checkDomainAtomicity(source, exlogSpec);
      expect(v, isNotNull);
      expect(v!.message, contains('never declared true'));
    });

    test('FAILS when the store is not guarded by the flag', () {
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  bool exlogBundleSynced = true;
  try {
    await upsertSets();
  } catch (e) {
    exlogBundleSynced = false;
  }
  exlogHashIndex[key] = fp;
}
''';
      final v = checkDomainAtomicity(source, exlogSpec);
      expect(v, isNotNull);
      expect(v!.message, contains('not visibly guarded'));
    });

    test(
        'FAILS when the store is unconditional AND split across two lines '
        '(OI-204 B-pass Finding 1, 2026-09-19: dart-format wraps a long line, '
        'defeating a naive per-line guard scan)', () {
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  bool exlogBundleSynced = true;
  try {
    await upsertSets();
  } catch (e) {
    exlogBundleSynced = false;
  }
  exlogHashIndex[key] =
      fp;
}
''';
      final v = checkDomainAtomicity(source, exlogSpec);
      expect(v, isNotNull);
      expect(v!.message, contains('not visibly guarded'));
    });

    test(
        'passes when a CORRECTLY-guarded store is split across two lines '
        '(the Finding-1 fix must not newly false-positive on a legitimate '
        'dart-format wrap)', () {
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  bool exlogBundleSynced = true;
  try {
    await upsertSets();
  } catch (e) {
    exlogBundleSynced = false;
  }
  if (exlogBundleSynced) {
    exlogHashIndex[key] =
        fp;
  }
}
''';
      expect(checkDomainAtomicity(source, exlogSpec), isNull);
    });

    test('FAILS when a swallowing catch forgets to set the flag false (exlog, expects 1)', () {
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  bool exlogBundleSynced = true;
  try {
    await upsertSets();
  } catch (e) {
    // forgot: exlogBundleSynced = false;
  }
  if (exlogBundleSynced) {
    exlogHashIndex[key] = fp;
  }
}
''';
      final v = checkDomainAtomicity(source, exlogSpec);
      expect(v, isNotNull);
      expect(v!.message, contains('expected exactly 1'));
    });

    test('FAILS on nlog fixture with only 1 of 2 expected flag-false sites', () {
      const source = '''
Future<void> _syncNutritionLogs(String userId) async {
  bool nlogSlotSynced = true;
  try {
    await upsertItem();
  } catch (e) {
    nlogSlotSynced = false;
  }
  try {
    await vacuum();
  } catch (e) {
    // forgot: nlogSlotSynced = false;
  }
  if (nlogSlotSynced) {
    nlogHashIndex[slotId] = nlogFp;
  }
}
''';
      final v = checkDomainAtomicity(source, nlogSpec);
      expect(v, isNotNull);
      expect(v!.message, contains('expected exactly 2'));
    });

    test('passes on a correctly-guarded nlog fixture (2 flag-false sites)', () {
      const source = '''
Future<void> _syncNutritionLogs(String userId) async {
  bool nlogSlotSynced = true;
  try {
    await upsertItem();
  } catch (e) {
    nlogSlotSynced = false;
  }
  try {
    await vacuum();
  } catch (e) {
    nlogSlotSynced = false;
  }
  if (nlogSlotSynced) {
    nlogHashIndex[slotId] = nlogFp;
  }
}
''';
      expect(checkDomainAtomicity(source, nlogSpec), isNull);
    });

    test(
        'passes when the nlog fixture includes the preamble hydration loop '
        'AND the skip-check read (OI-204 C1 regression, nlog side)', () {
      const source = '''
Future<void> _syncNutritionLogs(String userId) async {
  final Map<String, String> nlogHashIndex = <String, String>{};
  final rawIndex = _hive.nutritionBox.get(SyncService._nlogHashIndexKey);
  if (rawIndex is Map) {
    rawIndex.forEach((k, v) {
      if (k is String && v is String) nlogHashIndex[k] = v;
    });
  }
  for (final log in logsToSync) {
    bool nlogSlotSynced = true;
    String? nlogFp;
    try {
      nlogShouldSkip = SyncService.nlogShouldSkipUpsert(
        killSwitchDisabled: nlogHashSkipDisabled,
        storedFingerprint: nlogHashIndex[slotId],
        currentFingerprint: computedFp,
      );
      await upsertItem();
    } catch (e) {
      nlogSlotSynced = false;
    }
    try {
      await vacuum();
    } catch (e) {
      nlogSlotSynced = false;
    }
    if (nlogSlotSynced) {
      nlogHashIndex[slotId] = nlogFp;
    }
  }
}
''';
      expect(checkDomainAtomicity(source, nlogSpec), isNull);
    });

    test('comment-strip: a commented-out store line cannot mask an unguarded real one', () {
      const source = '''
Future<void> _syncExerciseLogs(String userId) async {
  bool exlogBundleSynced = true;
  // exlogHashIndex[key] = fp; (old approach)
  exlogHashIndex[key] = fp;
}
''';
      final v = checkDomainAtomicity(source, exlogSpec);
      expect(v, isNotNull);
    });
  });
}
