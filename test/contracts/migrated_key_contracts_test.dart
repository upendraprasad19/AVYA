// test/contracts/migrated_key_contracts_test.dart
//
// Contract (E.13 — Audit 2026-05-16 framework deliverable):
// Every key passed to `MigratedKey.read|write|delete(...)` in lib/ must
// either be:
//   (a) Listed in `UserConfigMigrator.userScopedKeys`, OR
//   (b) Listed in `UserConfigMigrator._intentionallyShared`.
//
// docs/architecture/sync.md "User-scoped Hive keys (MigratedKey discipline)" pins
// this rule. Drift = a key that's user-specific but never migrated from
// configBox → userBox on devices upgrading past the migration flag.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Set<String> userScopedKeys;
  late Set<String> intentionallyShared;
  late List<String> migratedKeyCallsites;

  setUpAll(() {
    final migratorSrc = File('lib/core/services/user_config_migrator.dart')
        .readAsStringSync();

    userScopedKeys = _parseListNamed(migratorSrc, 'userScopedKeys');
    intentionallyShared = _parseListNamed(migratorSrc, '_intentionallyShared');

    // Source-grep lib/ for MigratedKey.<read|write|delete>('<key>'...).
    migratedKeyCallsites = [];
    final libDir = Directory('lib');
    if (libDir.existsSync()) {
      final pat = RegExp(
          r"""MigratedKey\.(read|readWithDefault|containsKey|write|delete)(?:<[^>]+>)?\(\s*['"]([a-zA-Z_][a-zA-Z0-9_]*)['"]""");
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // Skip the migrator + helper themselves.
        if (entity.path.endsWith('migrated_key.dart')) continue;
        if (entity.path.endsWith('user_config_migrator.dart')) continue;
        final content = entity.readAsStringSync();
        for (final m in pat.allMatches(content)) {
          migratedKeyCallsites.add(m.group(2)!);
        }
      }
    }
  });

  test('userScopedKeys parsed and non-empty', () {
    expect(userScopedKeys, isNotEmpty,
        reason: 'failed to parse userScopedKeys from user_config_migrator.dart');
  });

  test('every MigratedKey.* key is in userScopedKeys or _intentionallyShared',
      () {
    final allowed = {...userScopedKeys, ...intentionallyShared};
    final unauthorized = <String>{};
    for (final k in migratedKeyCallsites) {
      if (!allowed.contains(k)) unauthorized.add(k);
    }
    expect(
      unauthorized,
      isEmpty,
      reason: 'Keys read/written via MigratedKey that are NOT in '
          'UserConfigMigrator.userScopedKeys nor _intentionallyShared:\n'
          '  ${unauthorized.join(", ")}\n\n'
          'Fix: append the key to userScopedKeys (and bump _flagKey to '
          're-trigger migration) OR to _intentionallyShared if it must '
          'cross sessions by design.',
    );
  });
}

Set<String> _parseListNamed(String src, String name) {
  // Matches:
  //   static const List<String> <name> = [ ... ];
  final m = RegExp(
    'static\\s+const\\s+List<String>\\s+$name\\s*=\\s*\\[([\\s\\S]*?)\\];',
  ).firstMatch(src);
  if (m == null) return <String>{};
  // Strip line comments.
  final body = m.group(1)!
      .split('\n')
      .map((l) {
        final idx = l.indexOf('//');
        return idx < 0 ? l : l.substring(0, idx);
      })
      .join('\n');
  final out = <String>{};
  for (final mm in RegExp(r"""['"]([a-zA-Z_][a-zA-Z0-9_]*)['"]""")
      .allMatches(body)) {
    out.add(mm.group(1)!);
  }
  return out;
}
