// test/contracts/workout_write_durable_index_test.dart
//
// e4a8b1 — Fire-and-forget Hive puts in the workout write path lose data on an
// app close before Hive flushes. The exercise_log_index_<date> write was
// fire-and-forget (a `void _appendToIndex` dropping its put Future, called
// unawaited), so a just-logged exercise's ROW persisted (awaited) but its INDEX
// entry did not flush → the reader (index-based exerciseLogsForIstDate) showed
// it as "gone" after a restart while the orphaned row survived on disk. The
// is_pr rescan (_rescanAllPrsFor) had the same fire-and-forget put. Both are now
// async + awaited so they reach disk before the writer returns (+ before paint).
//
// A behavioral kill-before-flush test is not feasible (Hive's box close flushes
// pending writes, so a clean close+reopen cannot reproduce the process-kill
// race). The await is the regressable durability surface — pinned by source-grep.
//
// closes-diagnose: e4a8b1
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  final code = _strip(
      File('lib/core/services/workout_write_service.dart').readAsStringSync());

  group('workout write path — durable Hive writes (e4a8b1)', () {
    test('_appendToIndex is async + awaits its index put', () {
      expect(RegExp(r'Future<void>\s+_appendToIndex').hasMatch(code), isTrue,
          reason: '_appendToIndex must be async so its index put can be awaited');
      expect(RegExp(r'await\s+box\.put\(indexKey').hasMatch(code), isTrue,
          reason: 'the exercise_log_index put must be awaited (durable before '
              'the writer returns)');
    });

    test('logExercise awaits _appendToIndex (no fire-and-forget index write)',
        () {
      expect(code.contains('await _appendToIndex('), isTrue,
          reason: 'logExercise must await the index append so it is durable '
              'before the method returns + the UI paints');
      // The declaration is `_appendToIndex(Box box ...`; the call is
      // `_appendToIndex(box ...`. A call with a lowercase `box` arg that is NOT
      // preceded by `await ` is a forbidden fire-and-forget.
      expect(RegExp(r'(?<!await )_appendToIndex\(box').hasMatch(code), isFalse,
          reason: 'no fire-and-forget (unawaited) call to _appendToIndex may remain');
    });

    test('_rescanAllPrsFor is async + awaits its is_pr put + callers await it',
        () {
      expect(RegExp(r'Future<void>\s+_rescanAllPrsFor').hasMatch(code), isTrue,
          reason: '_rescanAllPrsFor must be async so its is_pr put can be awaited');
      expect(code.contains('await box.put(entry.key, mut)'), isTrue,
          reason: 'the is_pr rescan put must be awaited (durable before return)');
      expect(RegExp(r'(?<!await )_rescanAllPrsFor\(box').hasMatch(code), isFalse,
          reason: 'no fire-and-forget (unawaited) call to _rescanAllPrsFor may remain');
    });
  });
}
