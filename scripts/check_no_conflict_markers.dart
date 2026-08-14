// Gate — no unresolved git conflict markers in tracked files.
//
// Born 2026-08-14 after three conflict markers were found COMMITTED on `main` in
// `docs/audit/open_issues.md` (merge `5d1c6f12`). Diagnose-doc: `c9f4e2`.
//
// INPUT SET — say it out loud, because a gate pointed at the wrong set is the
// failure mode this repo keeps shipping:
//   Every path `git ls-files` reports, read from the WORKING TREE.
//   NOT the staged diff. A staged-scoped gate passes vacuously when nothing is
//   staged — which is exactly how it would behave in CI, where the whole point
//   is to catch what already landed. Tracked-paths-from-the-working-tree behaves
//   identically in pre-commit and in CI, so there is no context in which this is
//   silently a no-op.
//
// The detection patterns are SYNTHESISED in the lib rather than written as
// literals, so this gate does not flag its own source or its own fixtures and
// therefore needs no path exclusions. See the lib header for why an exclusion
// would be a bypass rather than a fix.

import 'dart:convert';
import 'dart:io';

import 'no_conflict_markers_lib.dart';

const _tag = '[no-conflict-markers]';

/// `git ls-files -z` separates paths with NUL so that paths containing spaces
/// survive intact — this repo's own checkout path has several.
///
/// Built with [String.fromCharCode], never written as a raw byte: git classifies
/// any file carrying a NUL in its first 8000 bytes as BINARY, which silently
/// turns every future diff of this gate into "Binary files differ" and makes it
/// unreviewable. Measured, not theorised — the first draft of this file embedded
/// a literal NUL here and `git diff --numstat` reported `-  -` for it.
final _nul = String.fromCharCode(0);

void main(List<String> args) {
  final root = _repoRoot();
  if (root == null) {
    stderr.writeln('$_tag SKIP: not inside a git work tree.');
    exit(0);
  }

  final paths = _trackedFiles(root);
  if (paths.isEmpty) {
    // An empty input set reports nothing in the same colour as nothing-wrong.
    // Fail loudly instead: `git ls-files` returning nothing in a real checkout
    // means the enumeration broke, not that the repo is clean.
    stderr.writeln('$_tag FAIL: `git ls-files` returned no paths. The scan '
        'enumerated nothing, so a PASS here would be meaningless.');
    exit(1);
  }

  final result = scanPaths(
    paths: paths,
    readFile: (p) => _readTextOrNull('$root/$p'),
  );

  final skippedNote = result.skipped.isEmpty
      ? ''
      : ' (${result.skipped.length} binary/unreadable file(s) skipped)';

  if (result.conflicts.isEmpty) {
    stdout.writeln(
        '$_tag PASS — ${paths.length} tracked file(s) scanned$skippedNote.');
    exit(0);
  }

  final fileCount = result.conflicts.map((c) => c.path).toSet().length;
  stderr.writeln('$_tag FAIL — ${result.conflicts.length} unresolved conflict '
      'marker(s) in $fileCount file(s)$skippedNote:');
  for (final c in result.conflicts) {
    stderr.writeln('  $c');
  }
  stderr.writeln('');
  stderr.writeln('A merge was committed without resolving it. Fix the file — do '
      'NOT --no-verify past this. On 2026-08-14 exactly this reached `main` and '
      'sat there corrupting the OI board while every other gate passed green.');
  exit(1);
}

String? _repoRoot() {
  final r = Process.runSync('git', ['rev-parse', '--show-toplevel']);
  if (r.exitCode != 0) return null;
  final out = (r.stdout as String).trim();
  return out.isEmpty ? null : out;
}

List<String> _trackedFiles(String root) {
  final r = Process.runSync(
    'git',
    ['ls-files', '-z'],
    workingDirectory: root,
    stdoutEncoding: utf8,
  );
  if (r.exitCode != 0) return const [];
  return (r.stdout as String)
      .split(_nul)
      .where((p) => p.trim().isNotEmpty)
      .toList();
}

/// Returns the file's text, or null when it is absent or not decodable as UTF-8
/// (binary). Null means "could not look", and the caller records it separately
/// from "looked and found nothing".
String? _readTextOrNull(String absPath) {
  final f = File(absPath);
  if (!f.existsSync()) return null; // tracked but deleted in the working tree
  try {
    return utf8.decode(f.readAsBytesSync(), allowMalformed: false);
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}
