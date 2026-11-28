// OI-473 (diagnose f7b3d1): test/sql/alert_cron_function_dead_edges_live_verify.sql
// rehearses the alert body by EXECUTING a copy of it (between its $b$ tags). A
// rehearsal that runs a stale copy proves nothing about what the migration
// installs, so this pins the two byte-for-byte, and pins the md5 the rehearsal
// asserts to that body.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

String? migrationBody(String sql) =>
    RegExp(r'command := \$\$(.*?)\$\$', dotAll: true).firstMatch(sql)?.group(1);

String? rehearsalBody(String sql) =>
    RegExp(r'INSERT INTO _b VALUES \(\$b\$(.*?)\$b\$\);', dotAll: true)
        .firstMatch(sql)
        ?.group(1);

void main() {
  group('parsers (fixtures)', () {
    test('migration body is the text between the command dollar tags', () {
      expect(migrationBody("x command := \$\$\n  SELECT 1;\n  \$\$\n);"),
          '\n  SELECT 1;\n  ');
      expect(migrationBody('no command here'), isNull);
    });

    test('rehearsal body is the text between the \$b\$ tags', () {
      expect(rehearsalBody("INSERT INTO _b VALUES (\$b\$\n  SELECT 1;\n  \$b\$);"),
          '\n  SELECT 1;\n  ');
      expect(rehearsalBody('nothing'), isNull);
    });
  });

  group('the real files', () {
    final mig = File('supabase/migrations/170_oi473_cron_dead_alert_edges.sql')
        .readAsStringSync();
    final reh =
        File('test/sql/alert_cron_function_dead_edges_live_verify.sql')
            .readAsStringSync();

    test('the rehearsal executes exactly the migration body', () {
      final m = migrationBody(mig);
      final r = rehearsalBody(reh);
      expect(m, isNotNull);
      expect(r, isNotNull);
      expect(r, m,
          reason: 'regenerate the rehearsal from the migration: the copy '
              'between the \$b\$ tags has drifted from `command := \$\$ ... \$\$`');
    });

    test('the md5 the rehearsal asserts is the md5 of that body', () {
      final m = migrationBody(mig)!;
      final want = md5.convert(utf8.encode(m)).toString();
      expect(reh, contains("md5(t) = '$want'"),
          reason: 'the md5 literal in the rehearsal is stale');
    });
  });
}
