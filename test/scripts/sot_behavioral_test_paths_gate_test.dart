// test/scripts/sot_behavioral_test_paths_gate_test.dart
//
// Rule 24 red-path coverage for Gate 42 (`scripts/check_sot_behavioral_test_paths.dart`),
// OI-195, gate-integrity batch 2026-09-19.
//
// WHAT THIS EXISTS TO CATCH. Before the fix the gate validated the SHAPE of
// every `behavioral_test_path:` value (non-empty, not tbd/todo, not `""`) and
// never opened the file it named. A concept could cite a test that was never
// written -- or a `presence_only: true` justification could cite a live-verify
// SQL file that did not exist yet (the OI-153 B-pass finding 2 shape) -- and
// the gate printed PASS. The other half of the same registry (writer/reader
// `file:` citations) had been resolved on disk by check_sot_registry_parity
// for months; the test half was not.
//
// WHY A SUBPROCESS TEST. Everything in the gate is inline in `main()` -- no
// exported symbol to import -- so a unit test would have to re-declare a COPY
// of the regexes and keep passing after the real ones regressed. This drives
// the REAL script with a throwaway fixture as CWD (the gate resolves
// `docs/sot_registry.yaml` and every cited path relative to CWD), the same
// shape as test/scripts/claude_md_citations_letter_suffix_test.dart.
//
// The fixture calls NO git, so this file is deliberately NOT registered in
// test/contracts/gate_e2e_env_hermetic_test.dart (that gate asserts a
// GIT_*-scrubbing env builder, which a plain temp dir has no need of).
//
// Run: flutter test test/scripts/sot_behavioral_test_paths_gate_test.dart

@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Dart binary to spawn the gate with.
///
/// NOT `Platform.resolvedExecutable`: under `flutter test` that resolves to
/// the flutter_tester binary, not dart, so the spawn never returns and the
/// suite HANGS rather than failing. The repo already documents this trap at
/// test/scripts/oi_numbering_lib_test.dart:284 after it cost that suite a
/// >10-minute hang — and it cost this one another before the note was found.
/// Prefer the SDK exe beside the Flutter wrapper (the wrapper takes the SDK
/// update lock and shells out to git on EVERY call); fall back to `dart`.
/// (Copied verbatim from test/scripts/cron_registry_snapshot_gate_test.dart.)
String dartBinOf() {
  final override = Platform.environment['DART_BIN_OVERRIDE'];
  if (override != null && File(override).existsSync()) return override;
  final which = Process.runSync(
    Platform.isWindows ? 'where' : 'which',
    ['dart'],
    stdoutEncoding: utf8,
  );
  if (which.exitCode == 0) {
    final first = (which.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) {
      final dir = File(first).parent.path.replaceAll(r'\', '/');
      for (final c in [
        '$dir/cache/dart-sdk/bin/dart.exe',
        '$dir/cache/dart-sdk/bin/dart',
      ]) {
        if (File(c).existsSync()) return c;
      }
    }
  }
  return 'dart';
}

/// One concept whose `behavioral_test_path:` carries a trailing `# comment`
/// exactly the way three real registry entries do (registry lines 3236, 6064,
/// 6350 at filing time) -- the gate must strip it before resolving.
String _registry({required String path, String extra = ''}) => '''
concepts:

  - concept: alpha
    domain: workout
    behavioral_test_path: $path  # a1b2c3 — trailing comment must be stripped
    writers:
      - file: lib/a.dart
        line_range: 1-5
$extra
''';

void main() {
  late String gate;
  late Directory fx;
  final dartBin = dartBinOf();

  setUpAll(() {
    gate =
        '${Directory.current.path}/scripts/check_sot_behavioral_test_paths.dart';
    expect(File(gate).existsSync(), isTrue,
        reason: 'the gate under test must exist at its known path');
  });

  setUp(() {
    fx = Directory.systemTemp.createTempSync('gate42_');
    Directory('${fx.path}/docs').createSync(recursive: true);
    Directory('${fx.path}/test/contracts').createSync(recursive: true);
    File('${fx.path}/test/contracts/real_test.dart')
        .writeAsStringSync('void main() {}\n');
  });

  // Cleanup is hygiene, not an assertion: a timed-out child can still hold a
  // Windows handle into the temp dir, and a throwing tearDown would stack a
  // second failure that hides the real one.
  tearDown(() {
    try {
      fx.deleteSync(recursive: true);
    } catch (_) {}
  });

  // The record field is `exitCode` ON PURPOSE: gate_test_ledger_lib.dart's
  // accepted red-path forms match the literal `exitCode,\s*1`; a field named
  // `code` would not count and the ledger promotion would be refused.
  ({int exitCode, String out}) run([List<String> extra = const []]) {
    final r = Process.runSync(
      dartBin,
      ['run', gate, ...extra],
      workingDirectory: fx.path,
      runInShell: true,
    );
    return (exitCode: r.exitCode, out: '${r.stdout}${r.stderr}');
  }

  void write(String yaml) =>
      File('${fx.path}/docs/sot_registry.yaml').writeAsStringSync(yaml);

  test('an existing path (with a trailing comment) passes', () {
    write(_registry(path: 'test/contracts/real_test.dart'));
    final r = run();
    expect(r.exitCode, 0, reason: r.out);
  });

  test('RED PATH: a behavioral_test_path that does not exist fails strict', () {
    write(_registry(path: 'test/contracts/ghost_test.dart'));
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('ghost_test.dart'),
        reason: 'the failure must NAME the missing path.\n${r.out}');
  });

  test('--warn-only downgrades the same miss to exit 0 and still NAMES it', () {
    // `[Gate 42 WARN] PASS:` already contains the word WARN, so asserting on
    // WARN would be vacuous; the path name is the assertion.
    write(_registry(path: 'test/contracts/ghost_test.dart'));
    final r = run(['--warn-only']);
    expect(r.exitCode, 0, reason: r.out);
    expect(r.out, contains('ghost_test.dart'),
        reason: 'warn-only must still name the miss.\n${r.out}');
  });

  test('RED PATH: a sibling behavioral_test_path_<suffix> key is resolved too',
      () {
    // registry line 826 (`behavioral_test_path_cqrs:`) is the live instance.
    write(_registry(
        path: 'test/contracts/real_test.dart',
        extra:
            '    behavioral_test_path_cqrs: test/contracts/missing_second_test.dart'));
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('missing_second_test.dart'), reason: r.out);
  });

  test(
      'RED PATH: presence_only trailing prose citing a repo path that does '
      'not exist fails', () {
    write('''
concepts:

  - concept: beta
    presence_only: true # covered by test/sql/nope.sql
    writers:
      - file: lib/b.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('test/sql/nope.sql'), reason: r.out);
  });

  test(
      'RED PATH: presence_only_reason block scalar citing a path that does '
      'not exist fails', () {
    // registry line 6082 is the live block: key indent 4, body indent 6,
    // terminated by the next key at indent 4.
    write('''
concepts:

  - concept: gamma
    presence_only: true
    presence_only_reason: |
      Static concept; pinned by docs/nope/absent.yaml instead.
    writers:
      - file: lib/c.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('docs/nope/absent.yaml'), reason: r.out);
  });

  test(
      'RED PATH: a blank line INSIDE the presence_only_reason block does not '
      'end it (YAML block scalars may contain blank lines)', () {
    write('''
concepts:

  - concept: epsilon
    presence_only: true
    presence_only_reason: |
      First paragraph, no citation.

      Second paragraph cites docs/nope/after_blank.yaml here.
    writers:
      - file: lib/e.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('docs/nope/after_blank.yaml'), reason: r.out);
  });

  test(
      'RED PATH: a PLAIN-scalar presence_only_reason citing a path that does '
      'not exist fails (same sink as the block form)', () {
    write('''
concepts:

  - concept: zeta
    presence_only: true
    presence_only_reason: "static; see test/sql/plain_nope.sql"
    writers:
      - file: lib/z.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('test/sql/plain_nope.sql'), reason: r.out);
  });

  test(
      'presence_only_reason block citing an existing path (with trailing '
      'punctuation) passes', () {
    write('''
concepts:

  - concept: delta
    presence_only: true
    presence_only_reason: |
      Static concept; pinned by test/contracts/real_test.dart.
    writers:
      - file: lib/d.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.exitCode, 0, reason: r.out);
  });
}
