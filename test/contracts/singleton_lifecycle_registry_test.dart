// Tech-debt audit 2026-05-20 finding A7 — behavioral contract for
// SingletonLifecycleRegistry + the 7 wired singletons.
//
// A7 (score 14): seven `static .instance` services hold mutable state
// that leaks across HiveUserSession swaps. Full Riverpod conversion is
// a multi-day refactor; this batch ships a narrow scaffold:
//   - SingletonLifecycleRegistry — process-wide callback table.
//   - Each singleton registers a `_onUserChanged` callback in its
//     private constructor.
//   - HiveUserSession invokes SingletonLifecycleRegistry.notifyUserChanged()
//     after every user swap (open/close/delete).
//
// This test pins:
//   1. register() + notifyUserChanged() invokes registered callbacks.
//   2. Multiple registers all fire on a single notify (insertion order).
//   3. A throwing callback doesn't stop the others (H-42 contract).
//   4. Idempotent re-register replaces the previous callback.
//   5. Source-grep: every one of the 7 named singletons registers itself.
//   6. Source-grep: HiveUserSession.dart calls notifyUserChanged after
//      every user-flip (open / close / delete).
//
// Run: flutter test test/contracts/singleton_lifecycle_registry_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';

void main() {
  group('SingletonLifecycleRegistry (behavioral)', () {
    setUp(() {
      SingletonLifecycleRegistry.resetForTesting();
    });

    tearDown(() {
      SingletonLifecycleRegistry.resetForTesting();
    });

    test('register() + notifyUserChanged() invokes the callback', () {
      var fired = 0;
      SingletonLifecycleRegistry.register('test_one', () {
        fired++;
      });

      expect(fired, 0, reason: 'callback should not fire on register alone');

      SingletonLifecycleRegistry.notifyUserChanged();

      expect(fired, 1);
    });

    test('multiple registers all fire on a single notify', () {
      final fireLog = <String>[];
      SingletonLifecycleRegistry.register('a', () => fireLog.add('a'));
      SingletonLifecycleRegistry.register('b', () => fireLog.add('b'));
      SingletonLifecycleRegistry.register('c', () => fireLog.add('c'));

      SingletonLifecycleRegistry.notifyUserChanged();

      expect(fireLog, equals(['a', 'b', 'c']),
          reason: 'callbacks fire in insertion order');
      expect(SingletonLifecycleRegistry.count, 3);
    });

    test('notifyUserChanged is repeatable — fires every time', () {
      var fired = 0;
      SingletonLifecycleRegistry.register('repeat', () {
        fired++;
      });

      SingletonLifecycleRegistry.notifyUserChanged();
      SingletonLifecycleRegistry.notifyUserChanged();
      SingletonLifecycleRegistry.notifyUserChanged();

      expect(fired, 3);
    });

    test('throwing callback does not stop the others (H-42 contract)', () {
      var sawA = false;
      var sawC = false;

      SingletonLifecycleRegistry.register('a', () {
        sawA = true;
      });
      SingletonLifecycleRegistry.register('b_throws', () {
        throw StateError('intentional in test');
      });
      SingletonLifecycleRegistry.register('c', () {
        sawC = true;
      });

      // Must not throw out of notifyUserChanged.
      expect(SingletonLifecycleRegistry.notifyUserChanged, returnsNormally);
      expect(sawA, isTrue, reason: 'callback before throwing one fires');
      expect(sawC, isTrue, reason: 'callback after throwing one still fires');
    });

    test('re-register with same name replaces the previous callback', () {
      var firstFired = 0;
      var secondFired = 0;

      SingletonLifecycleRegistry.register('singleton_x', () {
        firstFired++;
      });
      SingletonLifecycleRegistry.register('singleton_x', () {
        secondFired++;
      });

      SingletonLifecycleRegistry.notifyUserChanged();

      expect(firstFired, 0,
          reason: 'first callback overwritten — must not fire');
      expect(secondFired, 1);
      expect(SingletonLifecycleRegistry.count, 1,
          reason: 'same-name re-register does not grow the table');
    });

    test('registeredNames() reflects every active callback', () {
      SingletonLifecycleRegistry.register('alpha', () {});
      SingletonLifecycleRegistry.register('beta', () {});

      final names = SingletonLifecycleRegistry.registeredNames();
      expect(names, containsAll(['alpha', 'beta']));
      expect(names.length, 2);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Source-grep contracts — every one of the 7 wired singletons calls
  // SingletonLifecycleRegistry.register from its private constructor.
  // ────────────────────────────────────────────────────────────────
  group('A7 — every wired singleton registers itself', () {
    /// (file, expected_registry_name) pairs.
    const wired = <List<String>>[
      ['lib/core/services/sync_service.dart', 'SyncService'],
      ['lib/core/services/subscription_service.dart', 'SubscriptionService'],
      [
        'lib/core/services/workout_schedule_service.dart',
        'WorkoutScheduleService'
      ],
      ['lib/core/services/usage_counter_service.dart', 'UsageCounterService'],
      ['lib/core/services/ai_service.dart', 'AiService'],
      ['lib/core/services/razorpay_service.dart', 'RazorpayService'],
      ['lib/core/services/seed_service.dart', 'SeedService'],
    ];

    for (final entry in wired) {
      final path = entry[0];
      final name = entry[1];
      test('$name registers as "$name"', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'expected source $path');
        final source = file.readAsStringSync();

        // Strip /* ... */ and // comments before matching, per
        // feedback_source_grep_strip_comments_first.md. Also collapse
        // all whitespace so the contains() match tolerates the
        // dart-format auto-wrap (a long register() call can split
        // 'register(' from its first arg onto two lines).
        final stripped = source
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
            .replaceAll(RegExp(r'//[^\n]*'), '')
            .replaceAll(RegExp(r'\s+'), ' ');

        expect(
          stripped.contains(
              "SingletonLifecycleRegistry.register( '$name'") ||
              stripped.contains(
                  "SingletonLifecycleRegistry.register('$name'"),
          isTrue,
          reason: '$path must register with name "$name" from constructor',
        );
        expect(
          stripped.contains('_onUserChanged'),
          isTrue,
          reason: '$path must define a _onUserChanged reset hook',
        );
      });
    }
  });

  // ────────────────────────────────────────────────────────────────
  // Source-grep contract — HiveUserSession invokes notifyUserChanged
  // from every user-flip path (open / close / delete).
  // ────────────────────────────────────────────────────────────────
  group('A7 — HiveUserSession flips trigger notifyUserChanged', () {
    test('open / close / delete each invoke the notifier', () {
      final file = File('lib/core/services/hive_user_session.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      final stripped = source
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');

      // Three call sites — one per locked mutator.
      final occurrences =
          'SingletonLifecycleRegistry.notifyUserChanged()'.allMatches;
      final count = RegExp(r'SingletonLifecycleRegistry\.notifyUserChanged\(\)')
          .allMatches(stripped)
          .length;
      expect(
        count,
        greaterThanOrEqualTo(3),
        reason:
            'hive_user_session.dart must call notifyUserChanged() from '
            '_openForUserLocked + _closeAllLocked + '
            '_deleteAllFilesForCurrentUserLocked (3 occurrences min). '
            'Found $count. (helper var: ${occurrences.hashCode})',
      );
    });
  });
}
