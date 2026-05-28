// Gate: confirms docs/incidents/INDEX.md is up-to-date.
//
// Mirrors check_adr_index_fresh.dart pattern.

import 'dart:io';

void main() async {
  final indexPath = 'docs/incidents/INDEX.md';
  final indexFile = File(indexPath);
  if (!indexFile.existsSync()) {
    stderr.writeln('FAIL: $indexPath does not exist. '
        'Run: dart run scripts/build_incident_index.dart');
    exit(1);
  }
  final before = indexFile.readAsStringSync();

  final result = await Process.run(
    'dart',
    ['run', 'scripts/build_incident_index.dart'],
    runInShell: true,
  );
  if (result.exitCode != 0) {
    stderr.writeln('FAIL: builder errored:');
    stderr.writeln(result.stderr);
    exit(1);
  }
  final after = indexFile.readAsStringSync();
  if (after != before) {
    stderr.writeln('FAIL: $indexPath was stale. Regenerated. '
        'Stage + commit:');
    stderr.writeln('  git add $indexPath');
    exit(1);
  }
  stdout.writeln('OK: $indexPath is up to date.');
  exit(0);
}
