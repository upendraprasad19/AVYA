// test/contracts/high_priority_op_types_parity_test.dart
//
// Audit 2026-05-16 / E.14.E + E.13 coordination.
// Closes F10.4 (Agent 7 findings) — silent client/server drift on the
// HIGH_PRIORITY_OP_TYPES allowlist. A HIGH op_type on one side and
// LOW on the other is a silent observability bug: the server inserts
// past the rate limit and the client drops it (or vice versa).
//
// Why a source-grep contract test (not a runtime constant compare)?
// The two lists live in two different languages (Dart + TypeScript)
// and two different runtimes (Flutter app + Deno Edge Function), so
// they can't be import-linked. We parse the strings literally out of
// both files and assert set equality.
//
// Fix path when this test fails:
//   1. Decide which list is correct.
//   2. Edit the other side to match.
//   3. Server-side: redeploy `log-client-error` Edge Function.
//   4. Client-side: bump APK + ship.
//
// CLAUDE.md §19 reference: APK Test #16.1 / Theme D + audit
// 2026-05-16 / F10.4 / E.14.E.

import 'dart:io';

import 'package:test/test.dart';

/// Parse the contents of [filePath] for `highPriorityOpTypes` literal
/// strings in a Dart `static const List<String> highPriorityOpTypes = [...]`
/// declaration. Returns the (order-preserving) literal values.
Set<String> _parseDartHighPriorityList() {
  final file = File('lib/core/services/error_telemetry.dart');
  expect(file.existsSync(), isTrue,
      reason: 'error_telemetry.dart must exist at the canonical path');
  final src = file.readAsStringSync();

  // Find the highPriorityOpTypes block — `static const List<String> '
  // highPriorityOpTypes = [`...`];`. The list contents span multiple
  // lines with comments; strip line comments before string-extraction.
  final blockStart = src.indexOf('highPriorityOpTypes = [');
  expect(blockStart, greaterThan(0),
      reason: 'highPriorityOpTypes declaration not found');
  final blockEnd = src.indexOf('];', blockStart);
  expect(blockEnd, greaterThan(blockStart),
      reason: 'highPriorityOpTypes closing bracket not found');
  final body = src.substring(blockStart, blockEnd);

  return _extractQuotedStrings(body);
}

Set<String> _parseTsHighPriorityList() {
  final file = File('supabase/functions/log-client-error/index.ts');
  expect(file.existsSync(), isTrue,
      reason: 'log-client-error/index.ts must exist at the canonical path');
  final src = file.readAsStringSync();

  // The TS list:
  //   const HIGH_PRIORITY_OP_TYPES: readonly string[] = [
  //     "crash_", ...
  //   ];
  final blockStart = src.indexOf('HIGH_PRIORITY_OP_TYPES');
  expect(blockStart, greaterThan(0),
      reason: 'HIGH_PRIORITY_OP_TYPES declaration not found');
  final openBracket = src.indexOf('[', blockStart);
  expect(openBracket, greaterThan(blockStart),
      reason: 'HIGH_PRIORITY_OP_TYPES open bracket not found');
  final closeBracket = src.indexOf('];', openBracket);
  expect(closeBracket, greaterThan(openBracket),
      reason: 'HIGH_PRIORITY_OP_TYPES close bracket not found');
  final body = src.substring(openBracket, closeBracket);

  return _extractQuotedStrings(body);
}

/// Strip `//` line comments then return every single- or double-quoted
/// string literal from [body] as a Set.
Set<String> _extractQuotedStrings(String body) {
  // Drop line comments.
  final stripped = body
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        if (idx < 0) return line;
        // Make sure the `//` isn't inside a string. Cheap check: if there's
        // a quote before the `//`, treat the line as code-only-with-comment
        // by truncating to the comment marker. Our list bodies don't have
        // strings with `//` in them, so this is safe enough.
        return line.substring(0, idx);
      })
      .join('\n');

  // Match 'foo' OR "foo" (no escape handling needed — none of our
  // op_types embed quotes).
  final regex = RegExp("['\"]([A-Za-z0-9_]+)['\"]");
  final out = <String>{};
  for (final m in regex.allMatches(stripped)) {
    final v = m.group(1);
    if (v != null && v.isNotEmpty) out.add(v);
  }
  return out;
}

void main() {
  group('HIGH_PRIORITY_OP_TYPES parity (client ↔ server)', () {
    test('client and server lists contain the same op_types', () {
      final client = _parseDartHighPriorityList();
      final server = _parseTsHighPriorityList();

      // Both must be non-empty (sanity).
      expect(client, isNotEmpty,
          reason: 'client highPriorityOpTypes parsed to an empty set — '
              'parser broken or file shape changed');
      expect(server, isNotEmpty,
          reason: 'server HIGH_PRIORITY_OP_TYPES parsed to an empty set — '
              'parser broken or file shape changed');

      // Set equality. The error message names the drift explicitly so
      // ops can fix it without re-running with prints.
      final onlyInClient = client.difference(server);
      final onlyInServer = server.difference(client);

      expect(onlyInClient, isEmpty,
          reason:
              'HIGH_PRIORITY_OP_TYPES drift — present in client only: '
              '$onlyInClient. Either add to server (supabase/functions/'
              'log-client-error/index.ts) and redeploy, or remove from '
              'client (lib/core/services/error_telemetry.dart).');
      expect(onlyInServer, isEmpty,
          reason:
              'HIGH_PRIORITY_OP_TYPES drift — present in server only: '
              '$onlyInServer. Either add to client and bump APK, or '
              'remove from server and redeploy.');
    });

    test(
      'audit-checkpoint count — minimum 17 entries (E.14.E baseline)',
      () {
        final client = _parseDartHighPriorityList();
        final server = _parseTsHighPriorityList();
        // The audit baseline (2026-05-16) is 17/18. If either drops
        // below 17, someone deleted an op_type without a clear reason.
        expect(client.length, greaterThanOrEqualTo(17),
            reason: 'client highPriorityOpTypes shrank below audit baseline');
        expect(server.length, greaterThanOrEqualTo(17),
            reason: 'server HIGH_PRIORITY_OP_TYPES shrank below audit baseline');
      },
    );
  });
}
