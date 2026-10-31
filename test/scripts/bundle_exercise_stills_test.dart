// test/scripts/bundle_exercise_stills_test.dart
//
// Batch M2a (plan Task 2): scripts/bundle_exercise_stills.js --check. The copy mode needs the founder's folder (never in a
// worktree) so only the --check mode is spawned here: it passes on the repo copy, and a copy with ONE flipped byte makes it
// exit non-zero and name the slug (this is the mutation proof of the hash check).
//
// Run: flutter test test/scripts/bundle_exercise_stills_test.dart
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const _tool = 'scripts/bundle_exercise_stills.js';

/// THE one spawn of the tool in this file.
Future<ProcessResult> _run(List<String> args) {
  return runSpawnAsync(
    'node',
    [_tool, ...args],
    why: 'bundle_exercise_stills.js ${args.join(' ')}',
    report: (_) {},
  ).timeout(const Duration(seconds: 90), onTimeout: () => throw TimeoutException('tool run timed out'));
}

void main() {
  test('--check passes on the repo copy and needs no --src', () async {
    final r = await _run(['--check']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('--check on a copy with ONE flipped byte exits non-zero and names the slug', () async {
    final table = jsonDecode(File('scripts/data/library_media_v16.json').readAsStringSync()) as Map<String, dynamic>;
    final slug = (table['files'] as Map<String, dynamic>).keys.toList()..sort();
    final victim = slug.first;
    final tmp = Directory.systemTemp.createTempSync('stills_check_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final f in Directory('assets/exercise_stills').listSync().whereType<File>()) {
      f.copySync('${tmp.path}/${f.uri.pathSegments.last}');
    }
    final target = File('${tmp.path}/$victim.webp');
    final bytes = target.readAsBytesSync();
    bytes[bytes.length - 1] ^= 0xFF;
    target.writeAsBytesSync(bytes);

    final r = await _run(['--check', '--dir', tmp.path]);
    expect(r.exitCode, isNot(0), reason: 'a flipped byte must fail the hash check\n${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains(victim));
  });

  test('--check on a folder missing a still names the slug', () async {
    final tmp = Directory.systemTemp.createTempSync('stills_missing_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final files = Directory('assets/exercise_stills').listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files.skip(1)) {
      f.copySync('${tmp.path}/${f.uri.pathSegments.last}');
    }
    final missing = files.first.uri.pathSegments.last.replaceAll('.webp', '');
    final r = await _run(['--check', '--dir', tmp.path]);
    expect(r.exitCode, isNot(0), reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains(missing));
  });

  test('copy mode without --src is refused with a usage message (exit 2)', () async {
    final tmp = Directory.systemTemp.createTempSync('stills_nosrc_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final r = await _run(['--dir', tmp.path]);
    expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('--src'));
  });
}
