// test/scripts/blast_radius_content_rules_lib_test.dart
//
// Tests for the content-aware blast-radius escalation rule. Imports the
// library directly (no subprocess) so the suite runs under `flutter test`
// without PATH or process-spawning issues — matches the precedent in
// test/scripts/validate_diagnose_doc_test.dart.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/blast_radius_content_rules_lib.dart';

void main() {
  group('isMigrationSqlPath', () {
    test('matches a top-level migration .sql file', () {
      expect(isMigrationSqlPath('supabase/migrations/106_foo.sql'), isTrue);
    });

    test('matches a nested migration .sql file (041_chunks/)', () {
      expect(
        isMigrationSqlPath('supabase/migrations/041_chunks/041_00_alter.sql'),
        isTrue,
      );
    });

    test('rejects a non-.sql file under migrations/', () {
      expect(isMigrationSqlPath('supabase/migrations/CLAUDE.md'), isFalse);
    });

    test('rejects a .sql file outside supabase/migrations/', () {
      expect(isMigrationSqlPath('supabase/functions/foo/index.sql'), isFalse);
    });

    test('normalizes backslashes (Windows paths)', () {
      expect(
        isMigrationSqlPath(r'supabase\migrations\106_foo.sql'),
        isTrue,
      );
    });
  });

  group('containsSecurityDefiner', () {
    test('matches the exact repo syntax', () {
      expect(
        containsSecurityDefiner(
            'create function foo() returns void security definer as \$\$...'),
        isTrue,
      );
    });

    test('is case-insensitive', () {
      expect(containsSecurityDefiner('SECURITY DEFINER'), isTrue);
    });

    test('tolerates extra whitespace between the two words', () {
      expect(containsSecurityDefiner('security   definer'), isTrue);
    });

    test('returns false when absent', () {
      expect(containsSecurityDefiner('create table foo (id uuid);'), isFalse);
    });
  });

  group('contentForcesCatastrophic — injected fakes', () {
    test('true: eligible path + SECURITY DEFINER content', () {
      final result = contentForcesCatastrophic(
        'supabase/migrations/999_innocuous_name.sql',
        fileExists: (_) => true,
        readFile: (_) => 'create function f() security definer as \$\$ \$\$;',
      );
      expect(result, isTrue);
    });

    test('false: eligible path but no SECURITY DEFINER content', () {
      final result = contentForcesCatastrophic(
        'supabase/migrations/999_plain.sql',
        fileExists: (_) => true,
        readFile: (_) => 'create table foo (id uuid);',
      );
      expect(result, isFalse);
    });

    test('false: non-migration path, even with SECURITY DEFINER content', () {
      final result = contentForcesCatastrophic(
        'lib/features/auth/providers/auth_provider.dart',
        fileExists: (_) => true,
        readFile: (_) => 'security definer',
      );
      expect(result, isFalse);
    });

    test('false: deleted-in-diff (file no longer exists) — fails open', () {
      final result = contentForcesCatastrophic(
        'supabase/migrations/999_deleted.sql',
        fileExists: (_) => false,
        readFile: (_) =>
            throw StateError('must not be called when fileExists is false'),
      );
      expect(result, isFalse);
    });

    test('false: unreadable file — fails open', () {
      final result = contentForcesCatastrophic(
        'supabase/migrations/999_unreadable.sql',
        fileExists: (_) => true,
        readFile: (_) => throw const FileSystemExceptionStub(),
      );
      expect(result, isFalse);
    });
  });

  group('contentForcesCatastrophic — real disk I/O against this repo\'s own migrations', () {
    test('true: 053_security_definer_hardening.sql (real SECURITY DEFINER migration)', () {
      expect(
        contentForcesCatastrophic(
            'supabase/migrations/053_security_definer_hardening.sql'),
        isTrue,
      );
    });

    test('false: 001_create_users.sql (real migration, no SECURITY DEFINER)', () {
      expect(
        contentForcesCatastrophic('supabase/migrations/001_create_users.sql'),
        isFalse,
      );
    });

    test('false: a real migration path that does not exist on disk', () {
      expect(
        contentForcesCatastrophic(
            'supabase/migrations/999999_does_not_exist.sql'),
        isFalse,
      );
    });
  });
}

/// Minimal stand-in so the "unreadable file" test doesn't depend on
/// dart:io's FileSystemException constructor shape.
class FileSystemExceptionStub implements Exception {
  const FileSystemExceptionStub();
}
