// test/contracts/completed_title_follows_log_test.dart
//
// OI-284 (plan docs/plans/swap-title-and-launch-refresh.md v3). After a
// cross-device day swap, a phone's COMPLETED non-template schedule row kept
// its pre-swap title: `mergeScheduleEntry` returns a local completed row
// unchanged (plan_integrity_reconciler.dart:105-107) and the status overlay
// spreads `...existingMap` (sync_workout.dart:2562-2589), while the completed
// card / receipt read the performed LOG (`wlog_<date>`). CompletedTitleHealer
// makes the row's title follow that log, locally, after a successful restore.
//
// Writer: WorkoutWriteService.markCompleted / _restoreWorkoutLogs (wlog_<date>).
// Reader: Train row, Home Today widget (schedule_<date>.workout_name).
//
// Real Hive, no mocks of the unit under test. Every guard is a test of its own:
// a guard that stops holding must redden exactly one of them.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/completed_title_healer.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_flags.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const date = '2026-10-01';
  const sKey = 'schedule_$date';
  const wKey = 'wlog_$date';
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('completed_title_heal_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.workoutBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Box<dynamic> box() => HiveService.instance.workoutBox;

  Map<String, dynamic> row({
    String name = 'Push + Core',
    String status = 'completed',
    String type = 'workout',
    String? templateId,
  }) => {
    'date': date,
    'workout_name': name,
    'status': status,
    'type': type,
    'week': 3,
    'day_of_week': 3,
    'exercises': [
      {'name': 'Bench Press', 'sets': 3},
    ],
    'workout_focus': 'push',
    'arranged_at_ms': 1790820779225,
    'is_swapped': true,
    'original_date': '2026-10-02',
    'completed_at_ms': 1790835965473,
    if (templateId != null) 'template_id': templateId,
  };

  Map<String, dynamic> wlog({
    String name = 'PULL + CORE',
    String? source,
    String type = 'workout_log',
  }) => {
    'id': wKey,
    'type': type,
    'workout_name': name,
    'date': date,
    'duration_seconds': 3000,
    if (source != null) 'source': source,
  };

  Map<String, dynamic> rowNow() =>
      Map<String, dynamic>.from(box().get(sKey) as Map);

  /// Counts real writes to [sKey] via box.watch.
  Future<int> writesDuring(Future<void> Function() body) async {
    var n = 0;
    final sub = box().watch(key: sKey).listen((_) => n++);
    await body();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    return n;
  }

  group('heal (founder fixture)', () {
    for (final source in <String?>['cloud_restore', null]) {
      test(
        'completed non-template row takes the log name (wlog source=$source)',
        () async {
          await box().put(sKey, row());
          await box().put(wKey, wlog(source: source));
          final before = rowNow();

          final healed = await CompletedTitleHealer.run();

          expect(healed, 1);
          final after = rowNow();
          expect(after['workout_name'], 'PULL + CORE');
          // ONLY the title changed: status, completion metadata, markers,
          // exercises, focus, type, week — all byte-identical.
          expect(after..remove('workout_name'), before..remove('workout_name'));
        },
      );
    }

    test('second run is a no-op with zero writes', () async {
      await box().put(sKey, row());
      await box().put(wKey, wlog());
      await CompletedTitleHealer.run();
      final n = await writesDuring(() async {
        expect(await CompletedTitleHealer.run(), 0);
      });
      expect(n, 0);
    });

    test(
      'a restore writer re-putting the stale title is healed again',
      () async {
        await box().put(sKey, row());
        await box().put(wKey, wlog());
        await CompletedTitleHealer.run();
        // A lockless restore writer that read the row BEFORE the heal writes the
        // stale title back (plan section 3, "lockless restore writers").
        await box().put(sKey, rowNow()..['workout_name'] = 'Push + Core');
        expect(await CompletedTitleHealer.run(), 1);
        expect(rowNow()['workout_name'], 'PULL + CORE');
      },
    );

    test(
      'a double-completed date follows the single local wlog slot (the card)',
      () async {
        // Restore keeps ONE cloud row per date in wlog_<date> (OI-302); the
        // heal agrees with what the completed card reads from that slot.
        await box().put(sKey, row(name: 'Pull + Core'));
        await box().put(
          wKey,
          wlog(name: 'OLDER SESSION NAME', source: 'cloud_restore'),
        );
        expect(await CompletedTitleHealer.run(), 1);
        expect(rowNow()['workout_name'], 'OLDER SESSION NAME');
      },
    );
  });

  group('guards — each leaves the row untouched with 0 writes', () {
    Future<void> expectUntouched(
      Map<String, dynamic> r,
      Map<String, dynamic>? w,
    ) async {
      await box().put(sKey, r);
      if (w != null) await box().put(wKey, w);
      final before = rowNow();
      final n = await writesDuring(() async {
        expect(await CompletedTitleHealer.run(), 0);
      });
      expect(n, 0);
      expect(rowNow(), before);
    }

    test('placeholder name "Workout"', () async {
      await expectUntouched(row(), wlog(name: 'Workout'));
    });

    test('placeholder name "Chat Workout" (any case)', () async {
      await expectUntouched(row(), wlog(name: '  chat WORKOUT '));
    });

    test('synthetic wlog (cloud_restore_completion)', () async {
      await expectUntouched(row(), wlog(source: 'cloud_restore_completion'));
    });

    test('template row (the overlay owns its title)', () async {
      await expectUntouched(row(templateId: 'tmpl_abc'), wlog());
    });

    test('planned row', () async {
      await expectUntouched(row(status: 'planned'), wlog());
    });

    test('logged-type row', () async {
      await expectUntouched(row(type: 'logged'), wlog());
    });

    test('no wlog', () async {
      await expectUntouched(row(), null);
    });

    test('wlog that is not a workout_log', () async {
      await expectUntouched(row(), wlog(type: 'something_else'));
    });

    test('case-only difference (Train writes upper-case log names)', () async {
      await expectUntouched(
        row(name: 'Pull + Core'),
        wlog(name: 'PULL + CORE'),
      );
    });

    test('empty / whitespace wlog name', () async {
      await expectUntouched(row(), wlog(name: '   '));
    });
  });

  group('one unhealable row never aborts the pass', () {
    // The pass-level catch would absorb a removed `is! Map` guard and report
    // 0 with no writes, so an earlier bad row must not starve a later one.
    test(
      'an earlier completed row with no wlog does not stop a later heal',
      () async {
        await box().put('schedule_2026-09-29', {
          ...row(),
          'date': '2026-09-29',
          'workout_name': 'Legs',
        });
        await box().put(sKey, row());
        await box().put(wKey, wlog());
        expect(await CompletedTitleHealer.run(), 1);
        expect(rowNow()['workout_name'], 'PULL + CORE');
      },
    );

    test('a non-Map value under an earlier schedule_ key is skipped', () async {
      await box().put('schedule_2026-09-29', 'garbage');
      await box().put(sKey, row());
      await box().put(wKey, wlog());
      expect(await CompletedTitleHealer.run(), 1);
      expect(rowNow()['workout_name'], 'PULL + CORE');
    });

    test('a wlog that is not a Map is skipped', () async {
      await box().put('schedule_2026-09-29', {...row(), 'date': '2026-09-29'});
      await box().put('wlog_2026-09-29', 'garbage');
      await box().put(sKey, row());
      await box().put(wKey, wlog());
      expect(await CompletedTitleHealer.run(), 1);
    });
  });

  group('kill switch and account switch', () {
    test(
      'disable_completed_title_heal closes the pass (byte-identical)',
      () async {
        await HiveService.instance.configBox.put(
          'disable_completed_title_heal',
          true,
        );
        await box().put(sKey, row());
        await box().put(wKey, wlog());
        final before = rowNow();
        expect(SyncFlags.completedTitleHealEnabled, isFalse);
        expect(await SyncService.healCompletedTitlesAfterRestore(), 0);
        expect(rowNow(), before);
      },
    );

    test('a closed box (account switch) is swallowed, returns 0', () async {
      await box().put(sKey, row());
      await box().put(wKey, wlog());
      await HiveUserSession.closeAll();
      expect(await CompletedTitleHealer.run(), 0);
    });
  });

  group('restore hooks', () {
    test(
      'heal runs only for a SUCCEEDED restore, and never touches the decay tick',
      () async {
        final completedBefore = SyncService.instance.restoreCompletedTick.value;
        expect(
          SyncService.shouldHealAfterRestore(RestoreResult.success()),
          isTrue,
        );
        expect(
          SyncService.shouldHealAfterRestore(RestoreResult.cancelled()),
          isFalse,
        );
        expect(
          SyncService.shouldHealAfterRestore(RestoreResult.failed('x')),
          isFalse,
        );

        await box().put(sKey, row());
        await box().put(wKey, wlog());
        expect(await SyncService.healCompletedTitlesAfterRestore(), 1);
        // `restoreCompletedTick` is the repaint tick the background heal bumps
        // AFTER its streak reckon (`DayRolloverObserver.
        // reckonAndNotifyAfterRestore`, b4e7a1 — the decay gate itself is the
        // per-account restore marker now): the title heal must NOT bump it, or
        // listeners would repaint before the reckon's debit lands.
        expect(
          SyncService.instance.restoreCompletedTick.value,
          completedBefore,
        );
      },
    );

    test('flag closed: the decision says no heal even for a success', () async {
      await HiveService.instance.configBox.put(
        'disable_completed_title_heal',
        true,
      );
      expect(
        SyncService.shouldHealAfterRestore(RestoreResult.success()),
        isFalse,
      );
    });

    test(
      'placement parity: wrapper heals on a decided success; the no-local-logs '
      'tail heals after its restore ops; no other entry bypasses the wrapper',
      () {
        final src = File(
          'lib/core/services/sync_service.dart',
        ).readAsStringSync();

        // 1. The public entry delegates to the core and heals only through the
        //    decision seam (so the success-only + kill-switch rules are the ones
        //    the hook test above exercises).
        final wrapper = _methodBody(
          src,
          'Future<RestoreResult> restoreFromCloudForUser()',
        );
        expect(wrapper.contains('_restoreFromCloudForUserCore()'), isTrue);
        // The heal sits directly inside a NON-negated `if (decision) { ... }`:
        // a `!shouldHealAfterRestore(result)` would heal every failure and no
        // success while every substring check still passed.
        expect(
          RegExp(
            r'if \(shouldHealAfterRestore\(result\)\)\s*\{\s*'
            r'await healCompletedTitlesAfterRestore\(\);\s*\}',
          ).hasMatch(wrapper),
          isTrue,
          reason:
              'the wrapper must heal exactly under '
              'if (shouldHealAfterRestore(result)) { await heal...(); }',
        );

        // 2. The core is private to the wrapper: any other caller would restore
        //    WITHOUT the heal.
        final coreRefs = _libFiles()
            .expand(
              (f) => RegExp(
                r'_restoreFromCloudForUserCore\(',
              ).allMatches(f.readAsStringSync()).map((_) => f.path),
            )
            .toList();
        expect(
          coreRefs,
          [
            'lib/core/services/sync_service.dart',
            'lib/core/services/sync_service.dart',
          ],
          reason: 'the core is declared once and called once (the wrapper)',
        );

        // 3. restoreFromCloud heals AFTER its restore ops, inside the try.
        final plain = _methodBody(
          src,
          'Future<void> restoreFromCloud(String userId)',
        );
        final heal = plain.indexOf('await healCompletedTitlesAfterRestore()');
        expect(
          heal,
          greaterThanOrEqualTo(0),
          reason: 'the no-local-logs restoreFromCloud tail must heal',
        );
        expect(
          heal,
          greaterThan(plain.lastIndexOf('Future.wait')),
          reason: 'the heal must run after the restore ops, not before them',
        );

        // 4. Restore-entry census. A public caller of restoreFromCloud /
        //    restoreFromCloudForUser is hooked by construction (both heal
        //    themselves), so what can bypass the heal is a NEW method that
        //    restores wlog_/schedule_ rows directly. Pin the known call sites
        //    of the two restore ops: a new one changes the count and must
        //    either call CompletedTitleHealer.run() or be added here with a
        //    reason. sync_workout.dart's three are the *ForSyncDomain entry
        //    points, flag-gated OFF (documented in completed_title_healer.dart).
        final decl = RegExp(r'^\s*(?:Future<[^>]*>|void)\s+_restore');
        final callSites = <String, int>{};
        for (final f in _libFiles()) {
          for (final line in f.readAsLinesSync()) {
            if (line.trimLeft().startsWith('//') || decl.hasMatch(line)) {
              continue;
            }
            if (line.contains('_restoreWorkoutLogs(') ||
                line.contains('_restoreScheduledWorkouts(')) {
              callSites[f.path] = (callSites[f.path] ?? 0) + 1;
            }
          }
        }
        expect(
          callSites,
          {
            'lib/core/services/sync_service.dart': 6,
            'lib/core/services/sync/sync_workout.dart': 3,
          },
          reason:
              'a new restore entry for logs/schedule rows must run '
              'CompletedTitleHealer.run() after restoring (see its header)',
        );
      },
    );
  });

  group('placeholder-name set guard', () {
    // The heal must never rename a row to a name that is not the performed
    // workout's. Every STRING LITERAL that can feed markCompleted's
    // workoutName in lib/ must be in kPlaceholderWorkoutNames (or be a real
    // name). Scans the ENCLOSING FUNCTION BODY of each production call site:
    // two callers bind `?? 'Workout'` to a local first. It cannot see
    // COMPUTED names (state.workoutDay?.name) — see the plan, section 3.
    const callers = <String, String>{
      'lib/features/ai_coach/services/tool_dispatcher.dart': 'markCompleted(',
      'lib/features/ai_coach/providers/ai_coach_provider.dart':
          'markCompleted(',
      'lib/features/train/providers/train_provider.dart': 'markCompleted(',
      'lib/features/dev/simulation_service.dart': 'markCompleted(',
      'lib/features/ai_coach/services/conversational_log_handler.dart':
          'markCompleted(',
    };

    test('the set is exactly the two known fallbacks', () {
      expect(kPlaceholderWorkoutNames, {'workout', 'chat workout'});
    });

    test(
      'every string literal feeding a production markCompleted workoutName '
      'is a placeholder or an allowlisted real name; every site has a source',
      () {
        // Real, non-placeholder literal names a caller may pass (none today).
        const realNameAllowlist = <String>{};
        // Only lines that BIND the name (`workoutName: ...` / `workoutName = ...`)
        // count: the enclosing function holds unrelated `?? '...'` literals.
        final literal = RegExp(r"""(?:\?\?\s*|workoutName:\s*)'([^']+)'""");

        // Census: the production callers of WorkoutWriteService.markCompleted
        // are exactly the five scanned here — a sixth must be added to
        // [callers] (and its name source classified) or this fails.
        final found = _libFiles()
            .where(
              (f) => f.readAsStringSync().contains(
                'WorkoutWriteService.instance.markCompleted(',
              ),
            )
            .map((f) => f.path)
            .toSet();
        expect(found, callers.keys.toSet());

        for (final e in callers.entries) {
          final src = File(e.key).readAsStringSync();
          final at = src.indexOf('WorkoutWriteService.instance.${e.value}');
          expect(
            at,
            greaterThanOrEqualTo(0),
            reason: '${e.key} lost its markCompleted call',
          );
          final body = _enclosingMemberBody(src, at);
          var sources = 0;
          final binding = body
              .split('\n')
              .where((l) => l.contains('workoutName'))
              .join('\n');
          for (final m in literal.allMatches(binding)) {
            sources++;
            final lit = m.group(1)!.trim().toLowerCase();
            expect(
              kPlaceholderWorkoutNames.contains(lit) ||
                  realNameAllowlist.contains(lit),
              isTrue,
              reason:
                  '${e.key}: literal "$lit" feeds workoutName but is neither '
                  'in kPlaceholderWorkoutNames nor a known real name',
            );
          }
          if (binding.contains('kChatWorkoutName')) {
            sources++;
            expect(
              kPlaceholderWorkoutNames.contains(kChatWorkoutName.toLowerCase()),
              isTrue,
              reason: 'kChatWorkoutName must be a placeholder',
            );
          }
          expect(
            sources,
            greaterThan(0),
            reason:
                '${e.key}: no name source recognised in the enclosing '
                'function — the scan went blind; classify the new source',
          );
        }
      },
    );

    test(
      'conversational_log_handler uses the shared constant, not a private literal',
      () {
        final src = File(
          'lib/features/ai_coach/services/conversational_log_handler.dart',
        ).readAsStringSync();
        expect(
          src.contains('kChatWorkoutName'),
          isTrue,
          reason:
              'the chat handler must import the shared name so writer and '
              'heal share ONE definition',
        );
        expect(src.contains("workoutName: 'Chat Workout'"), isFalse);
      },
    );
  });
}

String _methodBody(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $signature');
  var depth = 0;
  var i = src.indexOf('{', start);
  final open = i;
  for (; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) break;
    }
  }
  return src.substring(open, i + 1);
}

// Paths are normalised to forward slashes at this ONE choke point: three
// assertions below compare `f.path` to `lib/...` literals, and on Windows
// `listSync` yields `lib\...`, which made them fail locally while CI (Linux)
// stayed green. `File('lib/x.dart')` opens fine on Windows.
Iterable<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => File(f.path.replaceAll('\\', '/')));

/// The body of the OUTERMOST function/member enclosing [at]: walks back over
/// lines that open a block at indent <= 2, and returns the nearest whose
/// brace-matched body actually contains [at] (a closed `for`/`if` block that
/// merely precedes the call is skipped). Closures inside it are included.
String _enclosingMemberBody(String src, int at) {
  final head = src.substring(0, at);
  final lines = head.split('\n');
  final opener = RegExp(r'^ {0,2}[^\s/}].*\{\s*$|^ {2}\}\).*\{\s*$');
  for (var i = lines.length - 1; i >= 0; i--) {
    if (!opener.hasMatch(lines[i])) continue;
    final startOffset = lines
        .sublist(0, i)
        .fold<int>(0, (n, l) => n + l.length + 1);
    final body = _methodBody(src.substring(startOffset), lines[i].trim());
    if (startOffset + body.length + lines[i].length > at) return body;
  }
  fail('no enclosing member found for offset $at');
}
