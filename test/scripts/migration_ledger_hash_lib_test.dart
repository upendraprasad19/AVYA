// test/scripts/migration_ledger_hash_lib_test.dart
//
// PURE tests for scripts/migration_ledger_hash_lib.dart (OI-135 + OI-137 step 1).
// The e2e counterpart (check_applied_migrations_ledger_e2e_test.dart) proves the gate
// binary actually CALLS this lib; this file proves the lib is correct.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_ledger_hash_lib.dart';

String _hex(String s) => sha256Hex(utf8.encode(s));

Map<String, dynamic> _entry(String id, String hash, {String? slug}) => {
      'migration': id,
      'applied_at': '2026-09-29T00:00:00+05:30',
      'hash': hash,
      'applier': 'test',
      'slug': ?slug,
    };

void main() {
  group('sha256Hex (pure Dart, no package:crypto)', () {
    // Expected values generated with Python hashlib, not typed from memory.
    const vectors = <(String, String, String)>[
    ('', '', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
    ('abc', 'abc', 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'),
    ('abcdbcde…(448-bit NIST)', 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq', '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'),
    ('896-bit NIST', 'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu', 'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1'),
    ('55 x a (padding boundary)', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318'),
    ('56 x a (padding boundary)', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a'),
    ('64 x a (block boundary)', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb'),
    ];
    for (final v in vectors) {
      test('vector: ${v.$1}', () => expect(_hex(v.$2), v.$3));
    }

    test('matches `sha256sum` on a REAL applied migration (file is immutable, so its ledger hash is a fixed oracle)', () {
      // Migration 151's ledger hash was produced by `sha256sum` when it was applied.
      final bytes = File('supabase/migrations/151_workout_log_exercises_delete_trigger_insert_path.sql').readAsBytesSync();
      expect(sha256Hex(bytes), '995363ee5dacbf0e2368cbf3b6af8526eec345fad18f8528e897312d07c044ca');
    });

    test('handles bytes >= 0x80 (no sign or UTF-8 confusion)', () {
      expect(sha256Hex(List<int>.generate(256, (i) => i)),
          '40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880');
    });
  });

  group('line-ending forms', () {
    test('toLf collapses CRLF, leaves a lone CR and a lone LF', () {
      expect(utf8.decode(toLf(utf8.encode('a\r\nb\rc\nd'))), 'a\nb\rc\nd');
    });
    test('toCrlf expands every LF, and is idempotent on CRLF input', () {
      expect(utf8.decode(toCrlf(utf8.encode('a\nb'))), 'a\r\nb');
      expect(utf8.decode(toCrlf(utf8.encode('a\r\nb'))), 'a\r\nb');
    });
    test('canonicalLedgerHash is the LF form regardless of input endings', () {
      final lf = canonicalLedgerHash(utf8.encode('x\ny\n'));
      expect(canonicalLedgerHash(utf8.encode('x\r\ny\r\n')), lf);
      expect(lf, 'sha256:${_hex('x\ny\n')}');
    });
  });

  group('classifyHash (OI-137: a literal `sha256:%s` once passed the gate)', () {
    test('real', () => expect(classifyHash('sha256:${'a' * 64}'), HashShape.real));
    test('sentinel', () => expect(classifyHash('unverifiable:no-artifact'), HashShape.sentinel));
    for (final bad in <Object?>[
      'sha256:%s', 'sha256:', 'sha256:x', 'TODO', '', null, 42,
      'sha256:${'A' * 64}', // uppercase hex is not what any writer emits
      'sha256:${'a' * 63}', 'sha256:${'a' * 65}',
      'unverifiable:', 'unverifiable:Has Caps', 'unverifiable:a b',
    ]) {
      test('malformed: $bad', () => expect(classifyHash(bad), HashShape.malformed));
    }
  });

  group('resolveMigrationFiles (resolver is NOT the 3-digit number grammar)', () {
    const names = [
      '050_workout_templates_unique_user_name.sql',
      '050b_workout_templates_unique_user_name.sql',
      '145_alert_sql_job_failures.sql',
      '145_workout_templates_stable_delete.sql',
      '20260328000001_video_renders.sql',
      '20260330_create_promo_codes.sql',
      'all_migrations_combined.sql',
      'CLAUDE.md',
    ];
    test('timestamp-scheme ids resolve (three real ledger ids are timestamps)', () {
      expect(resolveMigrationFiles('20260328000001', null, names), ['20260328000001_video_renders.sql']);
      expect(resolveMigrationFiles('20260330', null, names), ['20260330_create_promo_codes.sql']);
    });
    test('`050` does not swallow `050b` (the underscore is part of the prefix)', () {
      expect(resolveMigrationFiles('050', null, names), ['050_workout_templates_unique_user_name.sql']);
      expect(resolveMigrationFiles('050b', null, names), ['050b_workout_templates_unique_user_name.sql']);
    });
    test('two files, slug disambiguates; no slug => both (caller reports ambiguity)', () {
      expect(resolveMigrationFiles('145', 'alert_sql_job_failures', names), ['145_alert_sql_job_failures.sql']);
      expect(resolveMigrationFiles('145', null, names).length, 2);
    });
    test('only `.sql` files resolve: a same-prefix .md or .sql.bak is not a migration (B-pass A16)', () {
      expect(resolveMigrationFiles('057', null, ['057_notes.md', '057_x.sql.bak']), isEmpty);
      expect(resolveMigrationFiles('057', null, ['057_notes.md', '057_x.sql', '057_x.sql.bak']), ['057_x.sql']);
    });
    test('nothing resolves to all_migrations_combined.sql or CLAUDE.md', () {
      expect(resolveMigrationFiles('all', null, names), isEmpty);
      expect(resolveMigrationFiles('CLAUDE', null, names), isEmpty);
    });
  });

  group('verifyLedgerHashes', () {
    final v1 = utf8.encode('select 1;\nselect 2;\n');
    final v1Crlf = toCrlf(v1);
    final lf = canonicalLedgerHash(v1);
    final crlf = 'sha256:${sha256Hex(v1Crlf)}';

    List<String> run(List<Map<String, dynamic>> ledger, Map<String, List<int>> files,
            {Map<String, String> grandfathered = const {}}) =>
        verifyLedgerHashes(ledger, files, grandfathered: grandfathered);

    test('a null or MISSING `hash` is a violation inside the lib itself, not only in the gate\'s key check (B-pass A20)', () {
      final nullHash = {'migration': '200', 'applied_at': 'x', 'hash': null, 'applier': 't'};
      final noHash = {'migration': '201', 'applied_at': 'x', 'applier': 't'};
      final v = run([nullHash, noHash], {'200_a.sql': v1, '201_a.sql': v1});
      expect(v, hasLength(2));
      expect(v.every((m) => m.contains('is not `sha256:<64 hex>`')), isTrue, reason: '$v');
    });
    test('LF-form hash passes', () {
      expect(run([_entry('200', lf)], {'200_a.sql': v1}), isEmpty);
    });
    test('CRLF-form hash passes (56 real entries were hashed on a CRLF working copy)', () {
      expect(crlf, isNot(lf), reason: 'fixture must actually differ between forms');
      expect(run([_entry('200', crlf)], {'200_a.sql': v1}), isEmpty);
      // ...and the FILE being CRLF on disk is equally fine.
      expect(run([_entry('200', lf)], {'200_a.sql': v1Crlf}), isEmpty);
    });
    test('a hash matching neither form FAILS and prints the expected LF hash', () {
      final v = run([_entry('200', 'sha256:${'0' * 64}')], {'200_a.sql': v1});
      expect(v, hasLength(1));
      expect(v.single, contains(lf));
      expect(v.single, contains('immutable'));
    });
    test('a one-byte edit to the file after hashing FAILS', () {
      final v = run([_entry('200', lf)], {'200_a.sql': utf8.encode('select 1;\nselect 3;\n')});
      expect(v, hasLength(1));
    });
    test('literal `sha256:%s` (the OI-137 incident) FAILS', () {
      final v = run([_entry('121', 'sha256:%s')], {'121_a.sql': v1});
      expect(v.single, contains('not `sha256:<64 hex>`'));
    });
    test('sentinel with no file passes (120b / 123b)', () {
      expect(run([_entry('120b', 'unverifiable:no-artifact')], {'120_a.sql': v1}), isEmpty);
    });
    test('sentinel BESIDE an existing file FAILS — it must not become the new escape hatch', () {
      final v = run([_entry('200', 'unverifiable:whatever')], {'200_a.sql': v1});
      expect(v.single, contains('HAS a file'));
    });
    test('real hash with no file FAILS', () {
      final v = run([_entry('999', lf)], {'200_a.sql': v1});
      expect(v.single, contains('no top-level'));
    });
    test('two candidate files and no slug is AMBIGUOUS, never silently skipped', () {
      final v = run([_entry('145', lf)], {'145_a.sql': v1, '145_b.sql': v1});
      expect(v.single, contains('ambiguous'));
    });
    test('two candidate files, slug given, resolves and verifies each independently', () {
      expect(
        run([_entry('145', lf, slug: 'a'), _entry('145', canonicalLedgerHash(utf8.encode('other')), slug: 'b')],
            {'145_a.sql': v1, '145_b.sql': utf8.encode('other')}),
        isEmpty,
      );
    });
    test('timestamp-scheme ledger ids verify (three real ones exist)', () {
      expect(run([_entry('20260330', lf)], {'20260330_create_promo_codes.sql': v1}), isEmpty);
    });

    group('grandfather map (closed, pinned by name)', () {
      final drifted = utf8.encode('changed after apply\n');
      final pin = sha256Hex(toLf(drifted));
      test('a grandfathered entry whose file still equals its pin passes', () {
        expect(run([_entry('057', 'sha256:${'1' * 64}')], {'057_a.sql': drifted}, grandfathered: {'057': pin}), isEmpty);
      });
      test('further editing a grandfathered file FAILS (pin drift) — exemption is not a blank cheque', () {
        final v = run([_entry('057', 'sha256:${'1' * 64}')], {'057_a.sql': utf8.encode('edited again\n')},
            grandfathered: {'057': pin});
        expect(v.single, contains('changed since it was pinned'));
      });
      test('STALE exemption: ledger hash now matches the file => FAILS so the list can only shrink', () {
        final v = run([_entry('057', canonicalLedgerHash(drifted))], {'057_a.sql': drifted}, grandfathered: {'057': pin});
        expect(v.single, contains('STALE'));
      });
      test('STALE exemption also fires on the CRLF form of the ledger hash', () {
        final v = run([_entry('057', 'sha256:${sha256Hex(toCrlf(drifted))}')], {'057_a.sql': drifted},
            grandfathered: {'057': pin});
        expect(v.single, contains('STALE'));
      });
      test('the pin is compared on the LF-NORMALISED bytes: a CRLF checkout of a pinned file still passes', () {
        // B-pass A10: fixtures were LF-only, so hashing the raw bytes here stayed green.
        final crlfBytes = toCrlf(drifted);
        expect(sha256Hex(crlfBytes), isNot(pin), reason: 'fixture: raw CRLF bytes must differ from the LF pin');
        expect(run([_entry('057', 'sha256:${'1' * 64}')], {'057_a.sql': crlfBytes}, grandfathered: {'057': pin}), isEmpty);
      });
      test('a grandfathered id with no ledger entry is reported', () {
        final v = run([], {'057_a.sql': drifted}, grandfathered: {'057': pin});
        expect(v.single, contains('no such ledger entry'));
      });
    });
  });

  group('the REAL ledger and tree', () {
    test('verifies clean, and the grandfather list is exactly the five known drifts', () {
      final ledger = (jsonDecode(File('backups/applied_migrations.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
      final files = <String, List<int>>{
        for (final f in Directory('supabase/migrations').listSync().whereType<File>())
          if (f.path.endsWith('.sql')) f.uri.pathSegments.last: f.readAsBytesSync(),
      };
      expect(verifyLedgerHashes(ledger, files), isEmpty);
      expect(grandfatheredLedgerHashDrift.keys.toSet(), {'057', '069', '070', '108', '123'});
    });
  });
}
