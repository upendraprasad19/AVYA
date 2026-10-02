@Timeout(Duration(seconds: 120))
library;

// .claude/token_path.js decides which Supabase Management-API token the host-shell deploy
// tools read. Two token files exist on the VPS and only the repo-ROOT one works (the old
// supabase/.supabase/ one returned HTTP 401 on 2026-10-02 and cost a deploy session its
// time). Pinned here against REAL temp directories (behavioural, not source-grep):
//   - the root `.supabase/` file wins over the dead legacy one when both exist,
//   - the dead legacy file is a last resort and is reported as `legacy`,
//   - from a LINKED git worktree (which has neither gitignored file) the PRIMARY worktree's
//     root token is found through the git common dir.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _name = 'supabase access token.txt';

Map<String, dynamic>? _resolve(String repoRoot) {
  final script = p.absolute('.claude/token_path.js');
  final r = Process.runSync('node', [
    '-e',
    "const t=require(${jsonEncode(script)});"
        "const r=t.resolveTokenFile(${jsonEncode(repoRoot)});"
        'console.log(JSON.stringify(r));',
  ]);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  final out = (r.stdout as String).trim();
  return out == 'null' ? null : jsonDecode(out) as Map<String, dynamic>;
}

void _write(Directory root, String rel) {
  final f = File(p.join(root.path, rel, _name));
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('sbp_test\n');
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('token_path_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the repo-root token wins over the dead legacy one', () {
    _write(tmp, '.supabase');
    _write(tmp, 'supabase/.supabase');
    final r = _resolve(tmp.path)!;
    expect(r['path'], p.join(tmp.path, '.supabase', _name));
    expect(r['legacy'], isFalse);
  });

  test('only the legacy file present: used last, flagged legacy', () {
    _write(tmp, 'supabase/.supabase');
    final r = _resolve(tmp.path)!;
    expect(r['path'], p.join(tmp.path, 'supabase', '.supabase', _name));
    expect(r['legacy'], isTrue);
  });

  test('no token file anywhere resolves to null', () {
    expect(_resolve(tmp.path), isNull);
  });

  test('a linked worktree finds the PRIMARY worktree root token', () {
    final primary = Directory(p.join(tmp.path, 'primary'))..createSync();
    ProcessResult git(List<String> a, String dir) =>
        Process.runSync('git', a, workingDirectory: dir);
    expect(git(['init', '-q'], primary.path).exitCode, 0);
    File(p.join(primary.path, 'f')).writeAsStringSync('x');
    git(['add', '.'], primary.path);
    expect(
        git([
          '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'x',
        ], primary.path)
            .exitCode,
        0);
    final linked = p.join(tmp.path, 'linked');
    expect(git(['worktree', 'add', '-q', linked, '-b', 'wt'], primary.path).exitCode, 0);
    _write(primary, '.supabase'); // gitignored in the real repo, so the linked tree has none
    final r = _resolve(linked)!;
    expect(File(r['path'] as String).resolveSymbolicLinksSync(),
        File(p.join(primary.path, '.supabase', _name)).resolveSymbolicLinksSync());
    expect(r['legacy'], isFalse);
  });
}
