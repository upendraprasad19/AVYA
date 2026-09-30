// test/scripts/check_applied_migrations_ledger_e2e_test.dart
//
// END-TO-END for scripts/check_applied_migrations_ledger.dart (Gate 39) after OI-135 /
// OI-137: runs the REAL gate binary against a throwaway repo. The pure lib test cannot prove
// main() actually CALLS the lib and exits non-zero — Gate 39 verified only that the `hash`
// KEY existed until 2026-09-29, and a literal `sha256:%s` passed it.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dart binary to spawn the gate with — NOT `Platform.resolvedExecutable`, which under
/// `flutter test` is flutter_tester and HANGS the suite instead of failing (same fallback
/// chain as check_migrations_applied_collision_e2e_test.dart).
String _dartBin() {
  final override = Platform.environment['DART_BIN_OVERRIDE'];
  if (override != null && File(override).existsSync()) return override;
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', ['dart'], stdoutEncoding: utf8);
  if (which.exitCode == 0) {
    final first = (which.stdout as String).split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) {
      final dir = File(first).parent.path.replaceAll(r'\', '/');
      for (final c in ['$dir/cache/dart-sdk/bin/dart.exe', '$dir/cache/dart-sdk/bin/dart']) {
        if (File(c).existsSync()) return c;
      }
    }
  }
  return 'dart';
}

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  // A surrounding git hook exports GIT_DIR / GIT_WORK_TREE, which override workingDirectory
  // and would point the child at the REAL repo (memory/feedback_mistake_git_hook_env_leak).
  env.removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  return env;
}

void main() {
  late Directory tmp;
  // The five grandfathered drifts (057/069/070/108/123) are a CLOSED list the gate insists on
  // seeing in the ledger — a grandfathered id with no entry is itself a violation — so every
  // fixture carries the REAL rows and the REAL files for them.
  final grandfatheredIds = {'057', '069', '070', '108', '123'};
  late List<Map<String, Object?>> realGrandfatheredRows;

  final repoRoot = Directory.current.path;
  final dart = _dartBin();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate39_hash_');
    Directory('${tmp.path}/supabase/migrations').createSync(recursive: true);
    Directory('${tmp.path}/backups').createSync(recursive: true);
    Directory('${tmp.path}/scripts').createSync(recursive: true);
    for (final f in ['check_applied_migrations_ledger.dart', 'migration_ledger_hash_lib.dart']) {
      File('$repoRoot/scripts/$f').copySync('${tmp.path}/scripts/$f');
    }
    final real = (jsonDecode(File('$repoRoot/backups/applied_migrations.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    realGrandfatheredRows = [
      for (final e in real)
        if (grandfatheredIds.contains(e['migration'])) Map<String, Object?>.from(e),
    ];
    for (final f in Directory('$repoRoot/supabase/migrations').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (grandfatheredIds.any((id) => name.startsWith('${id}_'))) f.copySync('${tmp.path}/supabase/migrations/$name');
    }
  });
  tearDown(() {
    // Hygiene, not an assertion: a lingering child handle must not stack a second failure.
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  void writeFile(String name, List<int> bytes) =>
      File('${tmp.path}/supabase/migrations/$name').writeAsBytesSync(bytes);

  String hashOf(List<int> bytes) => 'sha256:${_sha(bytes)}';

  void writeLedger(List<Map<String, Object?>> rows) => File('${tmp.path}/backups/applied_migrations.json')
      .writeAsStringSync(jsonEncode([...realGrandfatheredRows, ...rows]));

  Map<String, Object?> row(String id, String hash, {String? slug}) => {
        'migration': id,
        'applied_at': '2026-09-29T00:00:00+05:30',
        'hash': hash,
        'applier': 'test',
        'slug': ?slug,
      };

  ProcessResult run([List<String> extra = const []]) => Process.runSync(
        dart,
        ['scripts/check_applied_migrations_ledger.dart', ...extra],
        workingDirectory: tmp.path,
        environment: _cleanEnv(),
        includeParentEnvironment: false,
      );

  final body = utf8.encode('select 1;\n');

  test('matching LF hash passes', () {
    writeFile('200_a.sql', body);
    writeLedger([row('200', hashOf(body))]);
    final r = run();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('hashes verified'));
  });

  test('a hash recorded on a CRLF working copy still passes (56 real entries)', () {
    writeFile('200_a.sql', body);
    writeLedger([row('200', hashOf(utf8.encode('select 1;\r\n')))]);
    expect(run().exitCode, 0);
  });

  test('THE OI-137 INCIDENT: a literal `sha256:%s` FAILS the gate', () {
    writeFile('121_a.sql', body);
    writeLedger([row('121', 'sha256:%s')]);
    final r = run();
    expect(r.exitCode, 1);
    expect('${r.stderr}', contains('not `sha256:<64 hex>`'));
  });

  test('THE OI-135 CLASS: file edited after hashing (forgotten re-stamp) FAILS and prints the expected hash', () {
    writeFile('200_a.sql', utf8.encode('select 2;\n'));
    writeLedger([row('200', hashOf(body))]);
    final r = run();
    expect(r.exitCode, 1);
    expect('${r.stderr}', contains(hashOf(utf8.encode('select 2;\n'))));
  });

  test('--warn-only reports the violation but exits 0', () {
    writeFile('200_a.sql', utf8.encode('select 2;\n'));
    writeLedger([row('200', hashOf(body))]);
    final r = run(['--warn-only']);
    expect(r.exitCode, 0);
    expect('${r.stderr}', contains('violation'));
  });

  test('the grandfather PIN map is wired into the binary: 057 with an unpinned file FAILS', () {
    // Proves grandfatheredLedgerHashDrift reaches verifyLedgerHashes from main(): entry 057
    // is on the closed list, so a file that no longer equals its pin is a drift violation.
    // Overwrite the REAL 057 file with different content; the real ledger row stays.
    final real057 = Directory('${tmp.path}/supabase/migrations').listSync().whereType<File>().firstWhere((f) => f.uri.pathSegments.last.startsWith('057_'));
    real057.writeAsStringSync('not the pinned content\n');
    writeLedger([]);
    final r = run();
    expect(r.exitCode, 1);
    expect('${r.stderr}', contains('changed since it was pinned'));
  });

  test('sentinel for a fileless follow-up passes; beside a real file it FAILS', () {
    writeFile('120_a.sql', body);
    writeLedger([row('120', hashOf(body)), row('120b', 'unverifiable:no-artifact')]);
    expect(run().exitCode, 0);
    writeLedger([row('120', 'unverifiable:no-artifact')]);
    final r = run();
    expect(r.exitCode, 1);
    expect('${r.stderr}', contains('HAS a file'));
  });

  test('timestamp-scheme ledger ids resolve (a 3-digit-only resolver would fail 3 real entries)', () {
    writeFile('20260330_create_promo_codes.sql', body);
    writeLedger([row('20260330', hashOf(body))]);
    expect(run().exitCode, 0);
  });

  test('the REAL repo ledger passes the real gate (no drift on main)', () {
    final r = Process.runSync(dart, ['scripts/check_applied_migrations_ledger.dart'],
        workingDirectory: repoRoot, environment: _cleanEnv(), includeParentEnvironment: false);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });
}

/// sha256 hex via the SAME lib under test would make the oracle circular, so the e2e asks the
/// OS tool: python3 hashlib (always present on the dev + CI images).
String _sha(List<int> bytes) {
  final f = File('${Directory.systemTemp.path}/e2e_hash_${bytes.hashCode}_${DateTime.now().microsecondsSinceEpoch}.bin')
    ..writeAsBytesSync(bytes);
  try {
    final r = Process.runSync('python3', ['-c', 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())', f.path]);
    return (r.stdout as String).trim();
  } finally {
    f.deleteSync();
  }
}
