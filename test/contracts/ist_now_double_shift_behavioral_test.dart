// test/contracts/ist_now_double_shift_behavioral_test.dart
//
// OI-494, diagnose 4f9b2e. `istNow()` returns the IST wall-clock COMPONENTS in
// a UTC-flagged DateTime (the instant plus 5:30). Every helper that builds a
// date key (`istDateStr`, `istDateOf`, `istMidnight`) and every WriteService
// `date:` argument applies the IST shift itself, so an `istNow()` value fed to
// one is shifted TWICE: from 18:30 IST on it reads as tomorrow, on EVERY
// device (an IST phone included, because the value is UTC-flagged).
//
// Behavioural cases (the clock is pinned through the `setTestClock` seam):
//   A. FoodLogNotifier.logFood (food search + the coach food card) writes the
//      nlog_ row on today's IST date at 18:31 and 23:59 IST.
//   B. AiSnapshotBuilder this_week_workouts: on a Sunday at 22:30 IST the week
//      window is Monday..Sunday of THIS week and Sunday is "today".
//   C. AiSnapshotBuilder step_history_7d: at 22:30 IST the newest entry is
//      today's step row, not tomorrow's.
//   E. ProfileWriteService stamps updated_at with the real UTC instant (it
//      wrote the IST clock reading with a Z suffix, 5:30 ahead).
// Guard (D): no `istNow` token in lib/ outside ist_date.dart (a call, a
// tear-off, a prefixed `x.istNow()`); a new one fails here and must be written
// with nowWall()/istTodayStr() instead. Comments are stripped by a
// string-aware scanner (D0 pins it), so a `//` inside a string literal cannot
// hide the rest of the line.
//
// Run under TZ=Asia/Kolkata AND TZ=UTC: the bug reproduces in both, so both
// must be green after the fix.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';

import '../helpers/hive_test_setup.dart';

/// The UTC instant for an IST wall time (IST = UTC + 5:30, no DST).
DateTime _ist(int y, int mo, int d, int h, int mi) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 5, minutes: 30));

/// Every `istNow` token outside comments: calls, tear-offs, `x.istNow()`.
final RegExp _istNowToken = RegExp(r'(?<![\w$])istNow(?![\w$])');

/// [src] with every comment removed. String literals (single, double, triple,
/// raw, and `${...}` interpolations, nested) are kept as written, so a `//`
/// inside a string is not read as a comment. Fails closed: a string's text is
/// kept, so `istNow` written inside a string still counts.
String _stripComments(String src) {
  final out = StringBuffer();
  // One frame per nesting level: 'code', or the quote that opened a string.
  // A code frame opened by `${` tracks its brace depth so its closing `}`
  // returns to the enclosing string.
  final quotes = <String>['code'];
  final raws = <bool>[false];
  final depths = <int>[0];
  final ident = RegExp(r'[\w$]');
  var i = 0;
  while (i < src.length) {
    final q = quotes.last;
    if (q == 'code') {
      if (src.startsWith('//', i)) {
        while (i < src.length && src[i] != '\n') {
          i++;
        }
        continue;
      }
      if (src.startsWith('/*', i)) {
        var depth = 1;
        i += 2;
        while (i < src.length && depth > 0) {
          if (src.startsWith('/*', i)) {
            depth++;
            i += 2;
          } else if (src.startsWith('*/', i)) {
            depth--;
            i += 2;
          } else {
            i++;
          }
        }
        out.write(' ');
        continue;
      }
      var raw = false;
      var j = i;
      if ((src[i] == 'r' || src[i] == 'R') &&
          i + 1 < src.length &&
          (src[i + 1] == "'" || src[i + 1] == '"') &&
          (i == 0 || !ident.hasMatch(src[i - 1]))) {
        raw = true;
        j = i + 1;
      }
      if (src[j] == "'" || src[j] == '"') {
        final quote = src.startsWith(src[j] * 3, j) ? src[j] * 3 : src[j];
        out.write(src.substring(i, j + quote.length));
        i = j + quote.length;
        quotes.add(quote);
        raws.add(raw);
        depths.add(0);
        continue;
      }
      if (src[i] == '{') {
        depths[depths.length - 1]++;
      } else if (src[i] == '}') {
        if (depths.last == 0 && quotes.length > 1) {
          // closes a `${` interpolation: back to the enclosing string
          quotes.removeLast();
          raws.removeLast();
          depths.removeLast();
        } else {
          depths[depths.length - 1]--;
        }
      }
      out.write(src[i]);
      i++;
      continue;
    }
    // inside a string literal
    if (!raws.last && src[i] == r'\' && i + 1 < src.length) {
      out.write(src.substring(i, i + 2));
      i += 2;
      continue;
    }
    if (src.startsWith(q, i)) {
      out.write(q);
      i += q.length;
      quotes.removeLast();
      raws.removeLast();
      depths.removeLast();
      continue;
    }
    if (!raws.last && src.startsWith(r'${', i)) {
      out.write(r'${');
      i += 2;
      quotes.add('code');
      raws.add(false);
      depths.add(0);
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    resetTestClock();
    await tearDownHiveForTests(tempDir);
  });

  group('A. logFood dates the meal on the IST day it was logged', () {
    for (final (label, h, mi) in [('18:31', 18, 31), ('23:59', 23, 59)]) {
      test('a food-search log at $label IST lands on 2026-11-11', () async {
        setTestClockTo(_ist(2026, 11, 11, h, mi));
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final r = await container.read(foodLogProvider.notifier).logFood(
              food: const {
                'name': 'Dal',
                'calories_per_100g': 120,
                'protein_per_100g': 7,
                'carbs_per_100g': 18,
                'fat_per_100g': 2,
              },
              mealType: 'Dinner',
              quantityG: 200,
            );
        expect(r.success, isTrue, reason: r.error);
        final row = HiveService.instance.nutritionBox.get(r.logKey) as Map?;
        expect(row, isNotNull, reason: 'row ${r.logKey} must exist');
        expect(row!['date'], '2026-11-11',
            reason: 'logged at $label IST (host zone '
                '${DateTime.now().timeZoneName}); the double shift dates it '
                '2026-11-12');
        expect(r.logKey, contains('2026-11-11'));
      });
    }

    test('a log at 18:29 IST was never affected (control)', () async {
      setTestClockTo(_ist(2026, 11, 11, 18, 29));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final r = await container.read(foodLogProvider.notifier).logFood(
            food: const {'name': 'Tea', 'calories_per_100g': 40},
            mealType: 'Snacks',
            quantityG: 150,
          );
      expect(r.success, isTrue, reason: r.error);
      final row = HiveService.instance.nutritionBox.get(r.logKey) as Map;
      expect(row['date'], '2026-11-11');
    });
  });

  group('B/C. coach snapshot on Sunday 2026-11-15 at 22:30 IST', () {
    setUp(() {
      setTestClockTo(_ist(2026, 11, 15, 22, 30));
      final wb = HiveService.instance.workoutBox;
      // Monday and Sunday of this week, plus the next Monday (outside).
      for (final d in ['2026-11-09', '2026-11-15', '2026-11-16']) {
        wb.put('wlog_$d', {'type': 'workout_log', 'date': d});
      }
      wb.put('exlog_2026-11-15_aaaa0001',
          {'date': '2026-11-15', 'exercise_name': 'Squat'});
      wb.put('exlog_2026-11-16_aaaa0002',
          {'date': '2026-11-16', 'exercise_name': 'Bench Press'});
      final hb = HiveService.instance.healthBox;
      hb.put('step_2026-11-15', {'type': 'step_log', 'steps': 8000});
      hb.put('step_2026-11-16', {'type': 'step_log', 'steps': 999});
    });

    test('B. the week is Mon 09..Sun 15 and Sunday is today', () {
      final ctx = AiSnapshotBuilder.instance.buildAiContext();
      final week = ctx['this_week_workouts'] as Map;
      expect(week['completed_this_week'], 2,
          reason: 'Mon 09 and Sun 15 are in the week; Mon 16 is not');
      expect(week['completed_today'], isTrue);
      expect(week['today_exercises'], ['Squat']);
    });

    test('C. the newest step entry is today, not tomorrow', () {
      // The base snapshot trims the 7-day step series; a step question
      // re-adds it (enrichContextForQuery), which is the path the coach uses.
      final ctx = AiSnapshotBuilder.instance.enrichContextForQuery(
          'how many steps did I walk this week?',
          AiSnapshotBuilder.instance.buildAiContext());
      final steps = (ctx['step_history_7d'] as List).cast<Map>();
      expect(steps, isNotEmpty);
      expect(steps.map((s) => s['date']), contains('2026-11-15'));
      expect(steps.map((s) => s['date']), isNot(contains('2026-11-16')));
    });
  });

  test('B2. at 03:00 IST on Monday 2026-11-16 the week starts that Monday',
      () {
    // 03:00 IST Monday is still Sunday in UTC: a device-local weekday (instead
    // of the IST weekday) starts the window a week early on a UTC host.
    setTestClockTo(_ist(2026, 11, 16, 3, 0));
    final wb = HiveService.instance.workoutBox;
    for (final d in ['2026-11-15', '2026-11-16']) {
      wb.put('wlog_$d', {'type': 'workout_log', 'date': d});
    }
    final week = AiSnapshotBuilder.instance.buildAiContext()['this_week_workouts']
        as Map;
    expect(week['completed_this_week'], 1,
        reason: 'only Mon 16 is in the week of 16..22 '
            '(host zone ${DateTime.now().timeZoneName})');
    expect(week['completed_today'], isTrue);
  });

  test('D0. the comment stripper keeps code after a // inside a string', () {
    int count(String src) => _istNowToken.allMatches(_stripComments(src)).length;
    // a URL in a string does not hide the rest of the line
    expect(count("final u = 'http://x'; final d = istNow();"), 1);
    expect(count('final u = "a//b"; final d = istNow();'), 1);
    expect(count(r"final u = r'c:\x//'; final d = istNow();"), 1);
    expect(count("final u = '''a // b'''; final d = istNow();"), 1);
    // an interpolation holding a string with // is code again after it ends
    expect(count(r"""final u = '${f("a//b")}'; final d = istNow();"""), 1);
    // comments are removed, nested block comments included
    expect(count('// istNow()\nfinal a = 1;'), 0);
    expect(count('/* istNow() /* istNow() */ istNow() */ final a = 1;'), 0);
    expect(count('/// docs mention istNow()\nfinal a = 1;'), 0);
    // a tear-off and an import-prefixed call both count
    expect(count('final f = istNow;'), 1);
    expect(count('final d = ist.istNow();'), 1);
    // other identifiers do not
    expect(count('final d = istNowUtc(); final e = myistNow();'), 0);
  });

  test('E. a profile write stamps updated_at with the real UTC instant', () async {
    // 22:30 IST on 2026-11-11 is 17:00 UTC. istNow().toIso8601String() wrote
    // '2026-11-11T22:30:00.000Z': the IST clock reading labelled as UTC.
    // The clock is pinned with a LOCAL DateTime, as DateTime.now() is in
    // release, so a stamp that drops .toUtc() prints no Z and fails here.
    setTestClockTo(_ist(2026, 11, 11, 22, 30).toLocal());
    await ProfileWriteService.instance
        .updateProfile({'primary_goal': 'fat_loss'}, skipSync: true);
    var stored = HiveService.instance.userBox.get('profile') as Map;
    expect(stored['updated_at'], '2026-11-11T17:00:00.000Z');

    setTestClockTo(_ist(2026, 11, 11, 23, 45).toLocal());
    await ProfileWriteService.instance.patchProfile({'height_cm': 175});
    stored = HiveService.instance.userBox.get('profile') as Map;
    expect(stored['updated_at'], '2026-11-11T18:15:00.000Z');
  });

  test('D. no istNow token in lib/ outside ist_date.dart', () {
    // Every former use was moved to nowWall() (OI-494, diagnose 4f9b2e). Keep
    // this map EMPTY: a per-file count cannot tell a components-only use from
    // one fed to istDateStr / a WriteService date: in the same file, so an
    // entry here would let an unsafe use replace a safe one unseen.
    const allowed = <String, int>{};
    final found = <String, int>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path == 'lib/core/utils/ist_date.dart') continue;
      final n =
          _istNowToken.allMatches(_stripComments(f.readAsStringSync())).length;
      if (n > 0) found[path] = n;
    }
    expect(found, allowed,
        reason: 'A new istNow use was added. For a date key use istTodayStr() '
            'or istDateStr(nowWall()); for a WriteService date: pass nowWall(); '
            'for a timestamp use nowWall().toUtc() (OI-494).');
  });
}
