// Source-grep contract for subscriptions table RLS lockdown.
//
// Originally landed as T-11 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-11 subscriptions RLS lockdown', () {
    test('migration 052 exists and drops INSERT/UPDATE/DELETE policies', () {
      final src =
          _src('supabase/migrations/052_subscriptions_rls_lockdown.sql');
      expect(src.contains('subscriptions'), isTrue);
      // Lockdown migration must drop the permissive INSERT/UPDATE/DELETE
      // policies so only service-role can mutate.
      expect(
        src.contains('DROP POLICY'),
        isTrue,
        reason: 'migration 052 must DROP permissive policies on '
            'subscriptions.',
      );
    });

    test('no client-side .from("subscriptions").insert/update in lib/', () {
      // Sibling of Phase 1 no_client_subscriptions_writes_test.
      // Re-asserted here for the T-11 row.
      final root = Directory('lib');
      final offenders = <String>[];
      for (final f in root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (RegExp(r'''\.from\(\s*['"]subscriptions['"]\s*\)\s*\.\s*(insert|update|upsert|delete)''')
            .hasMatch(src)) {
          offenders.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'No client code may write to subscriptions table — '
            'service-role only (server-side Edge Functions). '
            'Offenders:\n${offenders.join("\n")}',
      );
    });
  });
}
