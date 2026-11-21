// test/contracts/restore_user_snapshot_freezes_projection_parity_test.dart
//
// Hermes C11 (2026-07-30, cross-device-progress-lock / OI-45 / e6b9c4).
//
// restore-user-snapshot/index.ts's single-call "freezes" bundle projection
// and SyncService._restoreFreezes's own direct-network-read `.select(...)`
// column list are two independent, hand-written strings that MUST name the
// same columns (the "H-1 shape contract" both sites already comment about) —
// _restoreFreezes accepts either a network read OR the EF's pre-fetched
// bundle interchangeably (see `preFetched` param), so a column present on
// one side and missing on the other silently drops a field on whichever
// path is taken.
//
// Hermes L39 (2026-07-30) found this drift is currently REAL at the
// deploy level (the live EF still serves the OLD 4-col projection; this
// repo's source is already 5-col, adding streak_progress_version — a
// separate, already-tracked residual pending an explicit EF redeploy) —
// but ALSO found nothing pins the two REPO-SOURCE strings together, so the
// next person to touch either side has no mechanical signal if they drift.
// This test is that signal, scoped to what's testable today without a live
// EF fetch: the checked-in source strings, not the deployed function.
//
// Why a source-grep contract test (not a runtime call)? Same reasoning as
// test/contracts/high_priority_op_types_parity_test.dart — the two sides
// live in different languages/runtimes (Dart client vs Deno Edge Function)
// and can't be import-linked.
//
// Fix path when this test fails:
//   1. Decide which side is correct (usually: whichever added the new
//      column most recently).
//   2. Edit the other side's projection string to match.
//   3. If the EF side changed, redeploy restore-user-snapshot (separate
//      explicit §4.3 authorization, per CLAUDE.md).

import 'dart:io';

import 'package:test/test.dart';

/// Extract the comma-separated column list from the "freezes" `.select(...)`
/// call in `supabase/functions/restore-user-snapshot/index.ts`.
Set<String> _parseEfFreezesProjection() {
  final file = File('supabase/functions/restore-user-snapshot/index.ts');
  expect(file.existsSync(), isTrue,
      reason: 'restore-user-snapshot/index.ts must exist at the canonical path');
  final src = file.readAsStringSync();

  final anchor = src.indexOf('tables["freezes"]');
  expect(anchor, greaterThan(0),
      reason: 'tables["freezes"] assignment not found — did the EF get restructured?');
  final selectStart = src.indexOf('.select(', anchor);
  expect(selectStart, greaterThan(anchor), reason: '.select( not found after tables["freezes"]');
  final selectEnd = src.indexOf(')', selectStart);
  expect(selectEnd, greaterThan(selectStart), reason: 'closing ) of .select( not found');

  return _columnSetFromQuotedBody(src.substring(selectStart, selectEnd));
}

/// Extract the comma-separated column list from `_restoreFreezes`'s own
/// `.select(...)` call in `sync_restore_completeness.dart` — the Dart
/// string is built from several ADJACENT string literals (implicit
/// concatenation across lines), so every quoted segment between `.select(`
/// and the matching `)` must be concatenated before splitting on commas.
Set<String> _parseClientFreezesProjection() {
  final file =
      File('lib/core/services/sync/sync_restore_completeness.dart');
  expect(file.existsSync(), isTrue,
      reason: 'sync_restore_completeness.dart must exist at the canonical path');
  final src = file.readAsStringSync();

  final anchor = src.indexOf('Future<void> _restoreFreezes(');
  expect(anchor, greaterThan(0), reason: '_restoreFreezes method not found');
  final selectStart = src.indexOf('.select(', anchor);
  expect(selectStart, greaterThan(anchor),
      reason: '.select( not found inside _restoreFreezes');
  // The select body ends at the `)` immediately before `.eq(` — walk back
  // from `.eq(` to find it, since the select body itself spans several
  // adjacent string literals with no nested parens to confuse a naive
  // forward scan for `)`.
  final eqStart = src.indexOf('.eq(', selectStart);
  expect(eqStart, greaterThan(selectStart),
      reason: '.eq( not found after .select( in _restoreFreezes');
  final closeParen = src.lastIndexOf(')', eqStart);
  expect(closeParen, greaterThan(selectStart),
      reason: 'closing ) of .select( not found before .eq( in _restoreFreezes');

  return _columnSetFromQuotedBody(src.substring(selectStart, closeParen));
}

/// Strip `//` line comments, concatenate every single-quoted string literal
/// in [body], then split the result on commas into a trimmed column-name set.
Set<String> _columnSetFromQuotedBody(String body) {
  final withoutComments = body
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx < 0 ? line : line.substring(0, idx);
      })
      .join('\n');

  final buffer = StringBuffer();
  final stringLiteralRe = RegExp(r'''['"]([^'"]*)['"]''');
  for (final m in stringLiteralRe.allMatches(withoutComments)) {
    buffer.write(m.group(1));
  }

  return buffer
      .toString()
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
}

void main() {
  group('restore-user-snapshot EF <-> _restoreFreezes projection parity (H-1)', () {
    test('EF freezes bundle and client _restoreFreezes select the same columns', () {
      final ef = _parseEfFreezesProjection();
      final client = _parseClientFreezesProjection();

      expect(ef, isNotEmpty,
          reason: 'EF freezes projection parsed to an empty set — parser broken '
              'or the EF was restructured');
      expect(client, isNotEmpty,
          reason: '_restoreFreezes select parsed to an empty set — parser broken '
              'or the method was restructured');

      final onlyInEf = ef.difference(client);
      final onlyInClient = client.difference(ef);

      expect(onlyInEf, isEmpty,
          reason: 'restore-user-snapshot freezes projection has columns '
              '_restoreFreezes never reads: $onlyInEf. Either the client is '
              'silently dropping a field the EF sends, or the EF projects a '
              'stale/extra column — reconcile both sides.');
      expect(onlyInClient, isEmpty,
          reason: '_restoreFreezes reads columns the EF freezes projection '
              'never sends: $onlyInClient. On the single-call restore path '
              'these fields silently stay unset from the EF bundle (falls back '
              'to whatever preFetched provided, which may be null for that '
              'key) — add the column to the EF projection and redeploy.');
    });

    test('freezes projection carries streak_progress_version (Unit 3b / e6b9c4)', () {
      final ef = _parseEfFreezesProjection();
      final client = _parseClientFreezesProjection();
      expect(ef, contains('streak_progress_version'),
          reason: 'the optimistic-lock version must ride along in the freezes '
              'bundle so a fresh restore adopts the cloud version instead of '
              'defaulting to 0 (see diagnose 2026-07-30-cross-device-progress-'
              'optimistic-lock-e6b9c4.md)');
      expect(client, contains('streak_progress_version'));
    });
  });
}
