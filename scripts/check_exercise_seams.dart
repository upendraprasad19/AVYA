// scripts/check_exercise_seams.dart
//
// ⑦ OI-89 Gate A — every exercise-emitting seam is enumerated, not eyeballed.
//
// Across four review rounds the seam count went 5 -> 7 -> 10 -> 11, each round
// finding one the last had missed. This gate pins the inventory so a NEW seam
// fails until someone decides what it does about equipment capability.
//
//   dart run scripts/check_exercise_seams.dart
//
// Exit 0 = inventory matches. Exit 1 = a seam was added, removed or moved.
import 'dart:io';

import 'exercise_seam_lib.dart';

void main() {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    stderr.writeln('SKIP: lib/ not found (run from repo root).');
    exit(0); // fail OPEN — an environment quirk must not wedge every commit
  }

  final files = <String, String>{};
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final rel = f.path.replaceAll(r'\', '/');
    files[rel] = f.readAsStringSync();
  }

  final sites = findSeamSites(files);
  final violations = seamViolations(sites);

  if (violations.isEmpty) {
    stdout.writeln('[exercise-seams] PASS — ${sites.length} seam site(s) across '
        '${seamAllowlist.length} allowlisted file(s); inventory unchanged.');
    exit(0);
  }

  stderr.writeln('[exercise-seams] FAIL — ${violations.length} violation(s):');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('Edit seamAllowlist in scripts/exercise_seam_lib.dart. The '
      'REASON field is the point: it records what each site does about '
      'equipment capability.');
  exit(1);
}
