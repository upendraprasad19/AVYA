// OI-483: scripts/dart_race_retry_lib.dart, the Dart side of the native-assets race retry, plus the SWEEP PIN: every
// spawn of dart under scripts/ goes through it. A single-line grep missed five of these sites while the plan was
// written (the calls span lines), and three of them could block a commit, so the inventory is a test, not a claim.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/dart_race_retry_lib.dart';
import '../helpers/script_closure_fixture.dart';
import '../helpers/spawn.dart' show nativeAssetsRaceSignature;

const _race = (254, 'noise\nFile not formatted as yaml: .\n');

/// Runs [retryDartRace] over a scripted list of (status, stderr).
Future<({(int, String) last, int calls, List<String> notes, List<Duration> waits})> script(
  List<(int, String)> plan, {
  Map<String, String> environment = const {},
  bool Function()? stop,
}) async {
  var calls = 0;
  final notes = <String>[];
  final waits = <Duration>[];
  final last = await retryDartRace<(int, String)>(
    () async => plan[calls++ < plan.length ? calls - 1 : plan.length - 1],
    statusOf: (r) => r.$1,
    stderrOf: (r) => r.$2,
    label: 'x.dart',
    onNote: notes.add,
    backoff: (d) async => waits.add(d),
    stop: stop,
    environment: environment,
  );
  return (last: last, calls: calls, notes: notes, waits: waits);
}

// ---- the sweep ---------------------------------------------------------------------------------------------------

final _spawn = RegExp(r'''(?:Process\.(?:run|runSync|start)|\b_run)\(\s*(?:'dart'|"dart"|Platform\.resolvedExecutable)''');
final _wrappedBefore = RegExp(r'(?:retryDartRace(?:<[^>]*>)?|retryDartProcess)\(\s*\(\)\s*(?:async\s*)?=>\s*(?:await\s*)?$');

String _noComments(String source) =>
    source.split('\n').map((l) => l.trimLeft().startsWith('//') ? '' : l).join('\n');

/// The 1-based lines of every literal dart spawn in [source], split by whether the retry wraps it.
({List<int> wrapped, List<int> bare}) spawnsIn(String source) {
  final text = _noComments(source);
  final wrapped = <int>[];
  final bare = <int>[];
  for (final m in _spawn.allMatches(text)) {
    final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
    final before = text.substring(m.start < 200 ? 0 : m.start - 200, m.start);
    (_wrappedBefore.hasMatch(before) ? wrapped : bare).add(line);
  }
  return (wrapped: wrapped, bare: bare);
}

void main() {
  group('the predicate', () {
    test('needs the status AND the signature', () {
      expect(isNativeAssetsRace(254, 'File not formatted as yaml: .'), isTrue);
      expect(isNativeAssetsRace(254, 'x File not formatted as yaml y'), isTrue);
      expect(isNativeAssetsRace(254, 'Error: a compile error'), isFalse);
      expect(isNativeAssetsRace(1, 'File not formatted as yaml: .'), isFalse);
      expect(isNativeAssetsRace(255, 'File not formatted as yaml: .'), isFalse);
    });

    test('the kill switch is exactly `0`', () {
      expect(dartRaceRetryOff({'AVYA_DART_RUN_RETRY': '0'}), isTrue);
      for (final v in ['', 'false', 'off', '1', '00']) {
        expect(dartRaceRetryOff({'AVYA_DART_RUN_RETRY': v}), isFalse, reason: v);
      }
      expect(dartRaceRetryOff(const {}), isFalse);
    });

    test('the signature is one value in three places (a Flutter bump changes all of them)', () {
      expect(kNativeAssetsRaceSignature, nativeAssetsRaceSignature);
      expect(File('scripts/_dart_bin.sh').readAsStringSync(), contains('*"$kNativeAssetsRaceSignature"*'));
    });

    test('the note is the shell note: leading newline, retry N of 2, label, status, flattened stderr cut at 300', () {
      final n = dartRaceNote(1, 'x.dart', 'a\nb${'c' * 400}');
      expect(n, startsWith('\n[dart-run-retry] native-assets race: retry 1 of 2 | x.dart | exit=254 | stderr=a b'));
      expect(n.split('stderr=').last.length, 300);
      expect(n.substring(1), isNot(contains('\n')));
      expect(dartRaceNote(2, 'y', 'short'), endsWith('retry 2 of 2 | y | exit=254 | stderr=short'));
    });
  });

  group('the retry', () {
    test('a race then a success: 2 attempts, 1 note, 1 backoff of 1 s, the success returned', () async {
      final r = await script([_race, (0, '')]);
      expect(r.last, (0, ''));
      expect(r.calls, 2);
      expect(r.notes.single, contains('retry 1 of 2'));
      expect(r.waits, [const Duration(seconds: 1)]);
    });

    test('the budget: 3 attempts, 2 notes, 2 backoffs, the LAST result comes back so the caller fails as today', () async {
      final r = await script([_race, _race, (254, 'File not formatted as yaml: third'), (0, '')]);
      expect(r.calls, 3);
      expect(r.notes.length, 2);
      expect(r.waits.length, 2);
      expect(r.last.$2, contains('third'));
    });

    test('anything that is not the race is returned at once', () async {
      for (final other in [(0, ''), (1, 'boom'), (254, 'a compile error'), (1, 'File not formatted as yaml: .'), (255, 'File not formatted as yaml')]) {
        final r = await script([other, (0, 'never')]);
        expect(r.calls, 1, reason: '$other');
        expect(r.last, other);
        expect(r.notes, isEmpty);
        expect(r.waits, isEmpty);
      }
    });

    test('the kill switch: one attempt, the race comes back, no note', () async {
      final r = await script([_race, (0, '')], environment: const {'AVYA_DART_RUN_RETRY': '0'});
      expect(r.calls, 1);
      expect(r.last, _race);
      expect(r.notes, isEmpty);
    });

    test('`stop` before a retry ends it with no note and no backoff', () async {
      final r = await script([_race, (0, '')], stop: () => true);
      expect(r.calls, 1);
      expect(r.notes, isEmpty);
      expect(r.waits, isEmpty);
    });

    test('`stop` turning true during the backoff ends it before the next attempt', () async {
      var checks = 0;
      final r = await script([_race, (0, '')], stop: () => ++checks > 1);
      expect(r.calls, 1);
      expect(r.notes.length, 1);
      expect(r.waits.length, 1);
    });

    test('retryDartProcess reads a ProcessResult', () async {
      var calls = 0;
      final notes = <String>[];
      final r = await retryDartProcess(
        () async => ++calls == 1 ? ProcessResult(1, 254, '', 'File not formatted as yaml: .') : ProcessResult(2, 0, 'ok', ''),
        label: 'x',
        onNote: notes.add,
        backoff: (_) async {},
        environment: const {},
      );
      expect(r.stdout, 'ok');
      expect(calls, 2);
      expect(notes.length, 1);
    });
  });

  group('the sweep pin', () {
    test('it fires: an unwrapped spawn across lines is bare, a wrapped one is not, a comment is neither', () {
      const bare = "final r = await Process.run(\n  'dart',\n  ['run', 'x'],\n);\n";
      expect(spawnsIn(bare).bare, [1]);
      expect(spawnsIn("r = Process.runSync(Platform.resolvedExecutable, ['x']);\n").bare, [1]);
      expect(spawnsIn("r = await _run(\n  Platform.resolvedExecutable,\n  [g],\n);\n").bare, [1]);
      const wrapped = "final r = await retryDartProcess(\n  () => Process.run(\n    'dart',\n    ['run'],\n  ),\n  label: 'x',\n);\n";
      expect(spawnsIn(wrapped).wrapped, [2]);
      expect(spawnsIn(wrapped).bare, isEmpty);
      expect(spawnsIn("x = retryDartRace<_C>(\n  () => _run(\n    Platform.resolvedExecutable,\n").wrapped, [2]);
      expect(spawnsIn("// Process.runSync(Platform.resolvedExecutable, ['run', gate])\n").bare, isEmpty);
      expect(spawnsIn("Process.run('git', ['status']);\n").bare, isEmpty);
    });

    test('every literal dart spawn under scripts/ is wrapped, except the one named exemption', () {
      final wrapped = <String>{};
      final bare = <String, List<int>>{};
      for (final f in Directory('scripts').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = spawnsIn(f.readAsStringSync());
        final name = f.path.replaceAll('\\', '/');
        if (s.wrapped.isNotEmpty) wrapped.add(name);
        if (s.bare.isNotEmpty) bare[name] = s.bare;
      }
      // git_safety_hook.dart's one spawn is the advisory plan-review precheck: a lost race is one spurious NOTE, and
      // importing the retry would add a file to the guard's compile closure, whose compile error is a silent 254.
      expect(bare.keys, ['scripts/git_safety_hook.dart'], reason: 'a new dart spawn must go through retryDartProcess: $bare');
      expect(bare['scripts/git_safety_hook.dart']!.length, 1);
      // Exact, so a regex that stopped matching cannot pass by finding nothing.
      expect(wrapped, {
        'scripts/batch_close_hook.dart',
        'scripts/check_adr_index_fresh.dart',
        'scripts/check_gate_index_fresh.dart',
        'scripts/check_incident_index_fresh.dart',
        'scripts/check_two_user_cross_account.dart',
        'scripts/land_pr.dart',
        'scripts/sync_with_main.dart',
      });
    });

    test('the guard\'s compile closure stays out of this lib, and the lib itself stays dependency-free', () {
      expect(scriptImportClosure(Directory.current.path, ['scripts/git_safety_hook.dart']),
          ['scripts/git_safety_hook.dart', 'scripts/git_safety_lib.dart']);
      final imports = RegExp(r'''^(?:import|export|part)\s+'([^']+)';''', multiLine: true)
          .allMatches(File('scripts/dart_race_retry_lib.dart').readAsStringSync())
          .map((m) => m.group(1))
          .toList();
      expect(imports, ['dart:io']);
    });

    test('land_pr gives the merge wrapper no timeout: a timeout is the only path to a SIGKILL, which would orphan the supervised dart', () {
      expect(File('scripts/land_pr.dart').readAsStringSync(), contains("final m = await _run('sh', args, cwd: top, stream: 'merge');"));
    });
  });
}
