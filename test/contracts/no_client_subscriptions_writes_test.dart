import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Audit C-1 contract — closes-diagnose: 2026-05-11-audit-c1-subscriptions
///
/// Asserts that no Dart code in `lib/` writes to the `subscriptions` table
/// directly via PostgREST. Migration 052 dropped the open RLS write
/// policies; any client-side `.from('subscriptions').(insert|update|
/// upsert|delete)` call would now fail at runtime, but more importantly,
/// it would mean someone is trying to bypass the Edge Function payment
/// path (razorpay-webhook / verify-payment / create-razorpay-order).
///
/// Subscriptions writes MUST flow through service-role-gated Edge
/// Functions. CLAUDE.md §16 (payment security rules).
void main() {
  group('Audit C-1 · no client-side subscriptions writes', () {
    test('no .from(subscriptions).insert/update/upsert/delete in lib/', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'Run from project root');

      // Pattern: `.from('subscriptions')` (single OR double quotes) followed
      // by any whitespace / chained calls / method-cascade syntax, then
      // `.insert(`, `.update(`, `.upsert(`, or `.delete(`. Allows up to
      // ~200 chars of intervening chain (method cascades, .select() calls).
      final pattern = RegExp(
        r'''\.from\(\s*['"]subscriptions['"]\s*\)[\s\S]{0,200}?\.(insert|update|upsert|delete)\s*\(''',
        multiLine: true,
      );

      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final content = entity.readAsStringSync();
        // Strip Dart line comments to avoid false positives on commented-out code.
        final stripped =
            content.replaceAll(RegExp(r'//[^\n]*'), '').replaceAll(
                  RegExp(r'/\*[\s\S]*?\*/'),
                  '',
                );

        for (final m in pattern.allMatches(stripped)) {
          // Compute approximate line number in the ORIGINAL file
          // (post-strip indices won't match pre-strip lines exactly, so
          // emit the matched snippet for human review).
          final snippet = m.group(0)!.replaceAll('\n', ' ').trim();
          offenders.add('${entity.path}: $snippet');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: '''
Audit C-1: no client-side subscriptions writes allowed.

Migration 052 dropped the subscriptions_{insert,update,delete}_own
policies. Subscription writes MUST go through:
  - razorpay-webhook (Edge Function, service-role)
  - verify-payment (Edge Function, service-role)
  - create-razorpay-order (Edge Function, service-role)
  - delete-account (Edge Function, service-role)

If you need to add a new subscription write path, route it through an
Edge Function with explicit JWT validation + business-rule check.
NEVER expose a direct PostgREST write path to client code.

Offending files:
${offenders.join('\n')}
''',
      );
    });

    test('no .from(subscriptions).delete() in any non-Edge-Function source',
        () {
      // Belt-and-suspenders: also scan `supabase/functions/` for ANY
      // service-role-keyed direct delete on subscriptions, which would
      // bypass the audit row in account_deletion_log.
      final fnDir = Directory('supabase/functions');
      expect(fnDir.existsSync(), isTrue);

      // The ONLY Edge Function permitted to DELETE from subscriptions is
      // delete-account (as part of the DPDP §17 cascade flow). Every other
      // function must only INSERT / UPDATE / SELECT.
      final pattern = RegExp(
        r'''\.from\(\s*['"]subscriptions['"]\s*\)[\s\S]{0,200}?\.delete\s*\(''',
        multiLine: true,
      );

      final unexpectedDeletes = <String>[];
      for (final entity in fnDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.ts')) continue;
        // Allowlist: delete-account is permitted to delete subscription rows
        // as part of the hard-erasure flow (though current implementation
        // relies on auth.users CASCADE rather than direct delete).
        if (entity.path.contains(RegExp(r'delete-account[/\\]'))) continue;

        final content = entity.readAsStringSync();
        final stripped = content
            .replaceAll(RegExp(r'//[^\n]*'), '')
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

        for (final m in pattern.allMatches(stripped)) {
          final snippet = m.group(0)!.replaceAll('\n', ' ').trim();
          unexpectedDeletes.add('${entity.path}: $snippet');
        }
      }

      expect(
        unexpectedDeletes,
        isEmpty,
        reason: '''
Audit C-1: only delete-account may DELETE from subscriptions.

Razorpay-webhook / verify-payment / create-razorpay-order are insert/
update/select-only paths. A delete here suggests cleanup-on-failure
logic that should instead use status='cancelled' to preserve audit trail.

Offenders:
${unexpectedDeletes.join('\n')}
''',
      );
    });
  });
}
