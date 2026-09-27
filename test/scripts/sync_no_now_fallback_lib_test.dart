import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/sync_no_now_fallback_lib.dart';

const _p = 'lib/core/services/sync/x.dart';

void main() {
  group('findNowFallbacks detects a now-fallback', () {
    test('`?? DateTime.now()` on one line, with its field', () {
      const src =
          "final p = {'created_at': row['created_at'] ?? DateTime.now().toUtc().toIso8601String()};";
      final findings = findNowFallbacks(_p, src);
      expect(findings, hasLength(1));
      expect(findings.single.field, 'created_at');
      expect(findings.single.line, 1);
      expect(findings.single.key, 'x.dart|created_at');
    });

    test('a `??` at the END of a line (the shape a one-line grep missed, plan D2)', () {
      const src = "final p = {\n  'read_at': entry['created_at'] as String? ??\n      DateTime.now().toUtc().toIso8601String(),\n};";
      final findings = findNowFallbacks(_p, src);
      expect(findings, hasLength(1));
      expect(findings.single.field, 'read_at');
      expect(findings.single.line, 2);
    });

    test('DateTime.timestamp(), nowWall() and istNow() are the same class', () {
      const src = "final a = {'x': r['x'] ?? DateTime.timestamp()};\n"
          "final b = {'y': r['y'] ?? nowWall()};\n"
          "final c = {'z': r['z'] ?? istNow()};";
      final findings = findNowFallbacks(_p, src);
      expect(findings, hasLength(3));
      expect(findings.map((f) => f.field), ['x', 'y', 'z']);
    });

    test('line numbers stay exact after a multi-line block comment', () {
      const src = "/* one\n two\n three */\nfinal p = {'created_at': a ?? DateTime.now()};";
      final findings = findNowFallbacks(_p, src);
      expect(findings, hasLength(1));
      expect(findings.single.line, 4);
    });
  });

  group('findNowFallbacks ignores', () {
    test('a now-fallback inside a // comment', () {
      const src = "// 'created_at': a ?? DateTime.now()\nfinal x = 1;";
      expect(findNowFallbacks(_p, src), isEmpty);
    });

    test('a now-fallback inside a /* */ comment', () {
      const src = "/* 'created_at': a ?? DateTime.now() */ final x = 1;";
      expect(findNowFallbacks(_p, src), isEmpty);
    });

    test('DateTime.now() that is not a ?? fallback', () {
      const src = "final p = {'synced_at': DateTime.now().toIso8601String()};";
      expect(findNowFallbacks(_p, src), isEmpty);
    });

    test('a // inside a string does not hide the code after it', () {
      const src =
          "final u = 'https://x.y'; final p = {'created_at': a ?? DateTime.now()};";
      expect(findNowFallbacks(_p, src), hasLength(1));
    });
  });

  test('isSyncLayerPath covers the sync layer and nothing else', () {
    expect(isSyncLayerPath('lib/core/services/sync_service.dart'), isTrue);
    expect(isSyncLayerPath('lib/core/services/sync/sync_workout.dart'), isTrue);
    expect(isSyncLayerPath(r'lib\core\services\sync\sync_health.dart'), isTrue);
    expect(isSyncLayerPath('lib/core/services/workout_write_service.dart'), isFalse);
    expect(isSyncLayerPath('lib/core/services/sync/README.md'), isFalse);
  });

  test('the real sync layer holds exactly the known baseline', () {
    // Plan D2: 14 sites. Each task that fixes sites removes their entries:
    // Task 14 completions, Task 16 template created_at, Task 17 saved meals,
    // Task 18 the five health sites, Task 19 coach + notifications +
    // onboarding replay. Empty after Task 19; Task 32 flips the gate to
    // hard-fail.
    const expected = <String>[
      'sync_coach.dart|created_at',
      'sync_health.dart|created_at',
      'sync_health.dart|created_at',
      'sync_health.dart|created_at',
      'sync_health.dart|created_at',
      'sync_health.dart|created_at',
      'sync_nutrition.dart|created_at',
      'sync_restore_completeness.dart|created_at',
      'sync_restore_completeness.dart|created_at',
      'sync_restore_completeness.dart|read_at',
      'sync_service.dart|phase_started_at',
      'sync_service.dart|plan_generated_at',
      'sync_workout.dart|created_at',
    ];
    final actual = <String>[];
    final files = <File>[
      File('lib/core/services/sync_service.dart'),
      ...Directory('lib/core/services/sync')
          .listSync(recursive: true)
          .whereType<File>(),
    ];
    for (final f in files) {
      final rel = f.path.replaceAll(r'\', '/');
      if (!isSyncLayerPath(rel)) continue;
      actual.addAll(findNowFallbacks(rel, f.readAsStringSync()).map((x) => x.key));
    }
    actual.sort();
    expect(actual, expected);
  });
}
