// Recurrence guard for the exlog `type` filter drift (diagnose 81c4e2; prior
// instances 89d56c graduation stats, 39ead9 OI-39 train provider).
//
// Only the cloud restore writer (lib/core/services/sync/sync_workout.dart)
// stamps `type: 'exercise_log'` on an `exlog_*` row; the device writer
// `WorkoutWriteService.logExercise` never does. A reader that filters on
// `row['type'] == 'exercise_log'` therefore sees restored rows only and is
// blind to every workout logged on the phone. Readers walk exlog rows through
// `WorkoutReadService.exlogRows` (the `exlog_` key predicate) instead.
//
// This test bans the quoted LITERAL 'exercise_log' (either quote style, exact
// word) anywhere in lib/ (comments stripped), except the restore writer's ONE
// map entry `'type': 'exercise_log'` in sync_workout.dart. A spelling-based
// ban on the comparison was defeatable (B-pass F1: the pre-fix lifetime-volume
// reader read `final type = v['type']?.toString(); if (type != 'exercise_log')`,
// which no `['type'] ==` regex matches). A reader needs the literal to filter on
// it, whatever the spelling: a local variable, `?.toString()`, a `switch` case
// or a Dart 3 map pattern `case {'type': 'exercise_log'}`. Op-type strings such
// as 'upsert_exercise_log' are a different word and are not matched. The runtime
// guard for the three fixed readers is
// exlog_type_filter_reader_drift_behavioral_test.dart.
@Tags(['contract'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _exerciseLogLiteral = RegExp(r"""['"]exercise_log['"]""");

/// The restore writer's map entry, the one allowed use of the literal.
final RegExp _writerMapEntry = RegExp(r"""['"]type['"]\s*:\s*['"]exercise_log['"]\s*,?\s*$""");

/// The only file allowed to hold the literal, and only as [_writerMapEntry].
const String _writerFile = 'lib/core/services/sync/sync_workout.dart';

/// Returns `line:text` for every line of [source] that holds the quoted
/// literal `'exercise_log'`, ignoring `//` line comments and `/* */` block
/// comments. Each returned `text` is the comment-stripped line.
List<String> findExerciseLogLiterals(String source) {
  final hits = <String>[];
  var inBlock = false;
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (inBlock) {
      final end = line.indexOf('*/');
      if (end < 0) continue;
      line = line.substring(end + 2);
      inBlock = false;
    }
    while (true) {
      final start = line.indexOf('/*');
      if (start < 0) break;
      final end = line.indexOf('*/', start + 2);
      if (end < 0) {
        line = line.substring(0, start);
        inBlock = true;
        break;
      }
      line = line.substring(0, start) + line.substring(end + 2);
    }
    final slashes = line.indexOf('//');
    if (slashes >= 0) line = line.substring(0, slashes);
    if (_exerciseLogLiteral.hasMatch(line)) hits.add('${i + 1}:${line.trim()}');
  }
  return hits;
}

/// The offenders in one file: every literal outside [_writerFile]; inside it,
/// any hit that is not the map entry, or more than one hit.
List<String> offendersIn(String path, String source) {
  final hits = findExerciseLogLiterals(source);
  final normalized = path.replaceAll('\\', '/');
  if (!normalized.endsWith(_writerFile)) return hits;
  final bad = hits.where((h) {
    final text = h.substring(h.indexOf(':') + 1);
    return !_writerMapEntry.hasMatch(text) || text.contains('case');
  }).toList();
  if (hits.length > 1) return hits;
  return bad;
}

void main() {
  group('scanner (proves the ban can fire)', () {
    test('flags a type filter in every reader spelling', () {
      // The pre-fix lifetime-volume reader (B-pass F1).
      expect(
        findExerciseLogLiterals("final type = v['type']?.toString(); if (type != 'exercise_log') continue;"),
        hasLength(1),
      );
      expect(findExerciseLogLiterals("if (log['type'] != 'exercise_log') continue;"), hasLength(1));
      expect(findExerciseLogLiterals('if (m["type"] == "exercise_log") n++;'), hasLength(1));
      expect(findExerciseLogLiterals("if ('exercise_log' == row['type']) n++;"), hasLength(1));
      expect(findExerciseLogLiterals("if (row['type']?.toString() == 'exercise_log') n++;"), hasLength(1));
      expect(findExerciseLogLiterals("    case 'exercise_log':"), hasLength(1));
      expect(findExerciseLogLiterals("const kExerciseLog = 'exercise_log';"), hasLength(1));
    });

    test('ignores other words and comments', () {
      expect(findExerciseLogLiterals("_reportSyncFailure(opType: 'upsert_exercise_log');"), isEmpty);
      expect(findExerciseLogLiterals("final k = 'exercise_log_index_';"), isEmpty);
      expect(findExerciseLogLiterals("// filtered by log['type'] == 'exercise_log'"), isEmpty);
      expect(findExerciseLogLiterals("/* log['type'] == 'exercise_log' */ final x = 1;"), isEmpty);
      expect(
        findExerciseLogLiterals("/*\n log['type'] == 'exercise_log'\n*/\nfinal x = 1;"),
        isEmpty,
      );
    });

    test('the writer file may hold the map entry once, and nothing else', () {
      const entry = "          'type': 'exercise_log',";
      expect(offendersIn(_writerFile, 'final m = {\n$entry\n};'), isEmpty);
      expect(offendersIn('C:\\repo\\lib\\core\\services\\sync\\sync_workout.dart', 'x = {\n$entry\n};'), isEmpty);
      // The same entry in any other file is an offender.
      expect(offendersIn('lib/features/train/x.dart', 'final m = {\n$entry\n};'), hasLength(1));
      // A second use in the writer file, even another map entry, is an offender.
      expect(offendersIn(_writerFile, '$entry\n$entry'), hasLength(2));
      // A Dart 3 map pattern in the writer file is a reader, not the entry.
      expect(offendersIn(_writerFile, "    case {'type': 'exercise_log'}:"), hasLength(1));
      expect(offendersIn(_writerFile, "if (t == 'exercise_log') n++;"), hasLength(1));
    });
  });

  test('no file in lib/ uses the exercise_log literal outside the restore writer entry', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    var scanned = 0;
    var writerHits = 0;
    for (final f in files) {
      scanned++;
      final source = f.readAsStringSync();
      if (f.path.replaceAll('\\', '/').endsWith(_writerFile)) {
        writerHits = findExerciseLogLiterals(source).length;
      }
      for (final hit in offendersIn(f.path, source)) {
        offenders.add('${f.path}:$hit');
      }
    }
    expect(scanned, greaterThan(100), reason: 'the scan must actually read lib/');
    expect(writerHits, 1, reason: 'the restore writer stamps the type exactly once ($_writerFile)');
    expect(
      offenders,
      isEmpty,
      reason: 'Read exlog rows through WorkoutReadService.exlogRows (the exlog_ '
          'key predicate). Only the cloud restore stamps type: exercise_log, so '
          'a type filter is blind to device-logged rows (diagnose 81c4e2).',
    );
  });
}
