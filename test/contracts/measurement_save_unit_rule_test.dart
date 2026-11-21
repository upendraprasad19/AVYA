// L2b Landing B (B2) - the unit write after a save is guarded by a TOKEN
// agreement, not by an owner comparison. PURE: the rule, plus a comment-stripped
// function-sliced pin of how `save` reads the token. The behavioural wiring row
// (a token flip while `save` waits) is in
// test/contracts/measurement_write_batch_behavioral_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';

import '../helpers/dart_source_slice.dart';

void main() {
  group('shouldRememberUnit - every false row has exactly ONE clause false', () {
    test('saved, a real token, unchanged -> true', () {
      expect(
        shouldRememberUnit(saved: true, tokenBefore: 'u1', tokenNow: 'u1'),
        isTrue,
      );
    });

    test('saved is false (the other two clauses hold) -> false', () {
      expect(
        shouldRememberUnit(saved: false, tokenBefore: 'u1', tokenNow: 'u1'),
        isFalse,
      );
    });

    test('the token before is the anonymous sentinel and nothing else is wrong '
        '-> false (the only row that kills a dropped sentinel clause)', () {
      expect(
        shouldRememberUnit(
            saved: true, tokenBefore: '<anon>', tokenNow: '<anon>'),
        isFalse,
      );
    });

    test('the token changed (the other two clauses hold) -> false', () {
      expect(
        shouldRememberUnit(saved: true, tokenBefore: 'u1', tokenNow: 'u2'),
        isFalse,
      );
    });

    test('the token became anonymous during the write -> false', () {
      expect(
        shouldRememberUnit(saved: true, tokenBefore: 'u1', tokenNow: '<anon>'),
        isFalse,
      );
    });
  });

  group('MeasurementWriteNotifier.save - how it reads the token (presence pin)',
      () {
    late String body;

    setUpAll(() {
      final src = stripDartComments(File(
        'lib/features/profile/providers/body_measurements_provider.dart',
      ).readAsStringSync());
      body = functionBody(src, 'Future<WriteResult> save(');
    });

    test('the token is read exactly twice: before the write and after it', () {
      expect(countOf(body, 'ref.read(authUserIdTokenProvider)'), 2);
      final before = body.indexOf('final tokenBefore = ref.read(');
      final write = body.indexOf('await HealthWriteService.instance.logMeasurements(');
      final now = body.indexOf('final tokenNow = ref.read(');
      expect(before, greaterThanOrEqualTo(0));
      expect(write, greaterThan(before));
      expect(now, greaterThan(write));
    });

    test('the unit is written only through shouldRememberUnit, with the real '
        'inputs, inside its if-block', () {
      final guard = body.indexOf('shouldRememberUnit(');
      expect(guard, greaterThanOrEqualTo(0));
      // The arguments of the call itself (not anywhere in the function).
      var depth = 0;
      var end = -1;
      for (var i = guard + 'shouldRememberUnit'.length; i < body.length; i++) {
        if (body[i] == '(') depth++;
        if (body[i] == ')') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
      final args = body.substring(guard, end);
      expect(args.contains('saved: result.success'), isTrue);
      expect(args.contains('tokenBefore: tokenBefore'), isTrue);
      expect(args.contains('tokenNow: tokenNow'), isTrue);
      final write = RegExp(r"MigratedKey\.write\(\s*'body_measurement_sheet_unit'")
          .firstMatch(body);
      expect(write, isNotNull);
      expect(write!.start, greaterThan(end));
      expect(_depthAt(body, write.start), 2,
          reason: 'inside the if-block, not at the top level of save');
    });

    test('the provider is invalidated AFTER the awaited write, through the '
        "notifier's own Ref, as a top-level statement (no `if` around it)", () {
      final write = body.indexOf('await HealthWriteService.instance.logMeasurements(');
      final invalidate = body.indexOf('ref.invalidate(bodyMeasurementsProvider)');
      expect(invalidate, greaterThan(write));
      expect(countOf(body, 'ref.invalidate(bodyMeasurementsProvider)'), 1);
      expect(_depthAt(body, invalidate), 1,
          reason: 'not inside any block of save');
      // What precedes the statement is the end of another statement or block,
      // never a condition (`if (x) ref.invalidate(...)`) or an `else`.
      final before = body.substring(0, invalidate).trimRight();
      expect(before.endsWith(';') || before.endsWith('}'), isTrue,
          reason: 'found: ...${before.substring(before.length - 12)}');
    });
  });
}

/// Brace depth of [body] at [index] (the body's own opening brace is depth 1).
int _depthAt(String body, int index) {
  var depth = 0;
  for (var i = 0; i < index; i++) {
    if (body[i] == '{') depth++;
    if (body[i] == '}') depth--;
  }
  return depth;
}
