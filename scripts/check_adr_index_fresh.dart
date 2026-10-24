// Gate: confirms docs/adr/INDEX.md is up-to-date relative to docs/adr/NNNN-*.md.
//
// Mirrors the pattern of `scripts/check_diagnose_index_fresh.dart`.
//
// Exit 0 if INDEX.md matches what `build_adr_index.dart` would produce.
// Exit 1 if a regeneration is needed (with a hint to run the builder).

import 'dart:io';

void main() async {
  final indexPath = 'docs/adr/INDEX.md';
  final indexFile = File(indexPath);
  if (!indexFile.existsSync()) {
    stderr.writeln('FAIL: $indexPath does not exist. '
        'Run: dart run scripts/build_adr_index.dart');
    exit(1);
  }
  final expectedBefore = indexFile.readAsStringSync();

  // Run the builder in a subprocess to a temp location, then compare.
  final tmpDir = Directory.systemTemp.createTempSync('adr_idx_');
  try {
    // Copy current adr/ dir into tmp? Simpler: rebuild in place, compare,
    // then restore.
    final builderResult = await Process.run(
      'dart',
      ['run', 'scripts/build_adr_index.dart'],
      runInShell: true,
    );
    if (builderResult.exitCode != 0) {
      stderr.writeln('FAIL: builder errored:');
      stderr.writeln(builderResult.stderr);
      exit(1);
    }
    final regenerated = indexFile.readAsStringSync();
    if (regenerated != expectedBefore) {
      // The builder already wrote the fresh version. We rolled forward.
      // Tell the user to commit the new INDEX.md.
      stderr.writeln('FAIL: $indexPath was stale. '
          'It has been regenerated. Stage and commit the change:');
      stderr.writeln('  git add $indexPath');
      exit(1);
    }
    stdout.writeln('OK: $indexPath is up to date.');
    exit(0);
  } finally {
    tmpDir.deleteSync(recursive: true);
  }
}
