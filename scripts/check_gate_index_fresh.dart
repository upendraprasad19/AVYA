// scripts/check_gate_index_fresh.dart
//
// Gate: confirms docs/audit/GATE_INDEX.md is up-to-date relative to its baked
// inputs. Mirrors check_adr_index_fresh.dart / check_diagnose_index_fresh.dart.
//
// SEPARATION OF CONCERNS — this gate checks FRESHNESS ONLY, never collisions.
// It always invokes the builder with `--warn-only`. Collision enforcement is
// the builder's job where `scripts/pre-commit.sh` runs it directly in the regen
// block, and that is sufficient: a collision can only be introduced by changing
// one of the baked inputs, which is exactly what fires the regen block.
//
// Without that split this gate would be a second, redundant collision surface
// that has to be flag-flipped in lockstep with the builder — and during the
// commit that introduces the registry (5 pre-existing collisions still live) it
// would block its own introducing commit, since this gate is auto-picked up by
// the `check_*.dart` loop and runs bare.
//
// Exit 0 when the on-disk index matches what the builder produces.
// Exit 1 when it was stale (the builder has already rewritten it — stage it).

import 'dart:io';

const _indexPath = 'docs/audit/GATE_INDEX.md';

void main() async {
  final indexFile = File(_indexPath);
  if (!indexFile.existsSync()) {
    stderr.writeln('[gate-index-fresh] FAIL: $_indexPath does not exist. '
        'Run: dart run scripts/build_gate_index.dart');
    exit(1);
  }
  final before = indexFile.readAsStringSync();

  final result = await Process.run(
    'dart',
    ['run', 'scripts/build_gate_index.dart', '--warn-only'],
    runInShell: true,
  );
  if (result.exitCode != 0) {
    stderr.writeln('[gate-index-fresh] FAIL: builder errored:');
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    exit(1);
  }

  final after = indexFile.readAsStringSync();
  if (after != before) {
    stderr.writeln('[gate-index-fresh] FAIL: $_indexPath was stale. '
        'It has been regenerated — stage and commit the change:');
    stderr.writeln('    git add $_indexPath');
    exit(1);
  }

  stdout.writeln('[gate-index-fresh] PASS — $_indexPath is up to date.');
  exit(0);
}
