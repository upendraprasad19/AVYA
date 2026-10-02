@Timeout(Duration(seconds: 180))
library;

// .claude/token_path.js (the deploy tools) and scripts/supabase_token_path_lib.dart (the live-SQL
// runner) decide which Supabase Management-API token file to read. Two token files exist on the
// VPS and only the repo-ROOT `.supabase/` one works (the older supabase/.supabase/ one returned HTTP
// 401 on 2026-10-02 and cost a deploy session its time). Both resolvers are pinned here against
// REAL temp directories and a REAL linked git worktree (behavioural, not source-grep), and against
// each other (same fixtures, same expected answer):
//   - the root token wins over the legacy one, in this tree AND in the primary worktree,
//   - a legacy file is a last resort and is reported as `legacy`,
//   - the realistic VPS shape (linked worktree with nothing, primary with BOTH files) picks the
//     primary's ROOT token, never the primary's legacy one,
//   - an inherited GIT_DIR cannot misdirect the primary lookup.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/supabase_token_path_lib.dart' as dart_resolver;

const _name = dart_resolver.tokenFileName;
final _sep = Platform.pathSeparator;
String _join(List<String> p) => p.join(_sep);

class _Answer {
  _Answer(this.path, this.legacy, [this.primaryError]);
  final String path;
  final bool legacy;
  final String? primaryError;
}

/// A git executable that does not exist: proves the git-failed branch of both resolvers.
const _noGit = '/nonexistent/git-for-token-path-test';

_Answer? _viaNode(String repoRoot, {Map<String, String>? env, String? git}) {
  final script = File('.claude/token_path.js').absolute.path;
  final r = Process.runSync(
    'node',
    [
      '-e',
      'const t=require(${jsonEncode(script)});'
          'const r=t.resolveTokenFile(${jsonEncode(repoRoot)}${git == null ? '' : ',{git:${jsonEncode(git)}}'});'
          'console.log(JSON.stringify(r));',
    ],
    environment: env,
  );
  expect(r.exitCode, 0, reason: '${r.stderr}');
  final out = (r.stdout as String).trim();
  if (out == 'null') return null;
  final m = jsonDecode(out) as Map<String, dynamic>;
  return _Answer(m['path'] as String, m['legacy'] as bool, m['primaryError'] as String?);
}

_Answer? _viaDart(String repoRoot, {String? git}) {
  final r = git == null
      ? dart_resolver.resolveTokenFile(repoRoot)
      : dart_resolver.resolveTokenFile(repoRoot, git: git);
  return r == null ? null : _Answer(r.path, r.legacy, r.primaryError);
}

String _real(String p) => File(p).resolveSymbolicLinksSync();

void _write(String root, List<String> rel) {
  final f = File(_join([root, ...rel, _name]));
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('sbp_test\n');
}

ProcessResult _git(List<String> a, String dir) => Process.runSync('git', [
      '-c', 'commit.gpgsign=false', '-c', 'user.email=t@t', '-c', 'user.name=t', ...a,
    ], workingDirectory: dir);

/// A primary repo with one commit and a LINKED worktree of it. Neither token file exists yet.
({String primary, String linked}) _repoWithLinkedWorktree(Directory tmp) {
  final primary = _join([tmp.path, 'primary']);
  Directory(primary).createSync();
  expect(_git(['init', '-q'], primary).exitCode, 0);
  File(_join([primary, 'f'])).writeAsStringSync('x');
  _git(['add', '.'], primary);
  expect(_git(['commit', '-q', '-m', 'x'], primary).exitCode, 0);
  final linked = _join([tmp.path, 'linked']);
  expect(_git(['worktree', 'add', '-q', linked, '-b', 'wt'], primary).exitCode, 0);
  return (primary: primary, linked: linked);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('token_path_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final resolvers = <String, _Answer? Function(String)>{
    'node resolver': (root) => _viaNode(root),
    'dart resolver': (root) => _viaDart(root),
  };
  final gitless = <String, _Answer? Function(String)>{
    'node resolver': (root) => _viaNode(root, git: _noGit),
    'dart resolver': (root) => _viaDart(root, git: _noGit),
  };

  for (final entry in resolvers.entries) {
    group(entry.key, () {
      final resolve = entry.value;

      test('the repo-root token wins over the legacy one', () {
        _write(tmp.path, ['.supabase']);
        _write(tmp.path, ['supabase', '.supabase']);
        final r = resolve(tmp.path)!;
        expect(_real(r.path), _real(_join([tmp.path, '.supabase', _name])));
        expect(r.legacy, isFalse);
      });

      test('only the legacy file present: used last, flagged legacy', () {
        _write(tmp.path, ['supabase', '.supabase']);
        final r = resolve(tmp.path)!;
        expect(_real(r.path), _real(_join([tmp.path, 'supabase', '.supabase', _name])));
        expect(r.legacy, isTrue);
      });

      test('no token file anywhere resolves to null', () {
        expect(resolve(tmp.path), isNull);
      });

      test('a DIRECTORY named like the token file is not a token (both twins agree)', () {
        Directory(_join([tmp.path, '.supabase', _name])).createSync(recursive: true);
        expect(resolve(tmp.path), isNull);
      });

      test('a repo whose own directory is named `supabase`: its root token is NOT legacy', () {
        final root = _join([tmp.path, 'supabase']);
        Directory(root).createSync();
        _write(root, ['.supabase']);
        final r = resolve(root)!;
        expect(_real(r.path), _real(_join([root, '.supabase', _name])));
        expect(r.legacy, isFalse);
      });

      test('VPS shape: linked worktree has nothing, primary has BOTH: the primary ROOT token wins', () {
        final w = _repoWithLinkedWorktree(tmp);
        _write(w.primary, ['.supabase']);
        _write(w.primary, ['supabase', '.supabase']);
        final r = resolve(w.linked)!;
        expect(_real(r.path), _real(_join([w.primary, '.supabase', _name])));
        expect(r.legacy, isFalse);
      });

      test('linked worktree, primary holds ONLY the legacy file: it is returned, flagged legacy', () {
        final w = _repoWithLinkedWorktree(tmp);
        _write(w.primary, ['supabase', '.supabase']);
        final r = resolve(w.linked)!;
        expect(_real(r.path), _real(_join([w.primary, 'supabase', '.supabase', _name])));
        expect(r.legacy, isTrue);
      });

      test('this tree\'s own root token beats the primary\'s', () {
        final w = _repoWithLinkedWorktree(tmp);
        _write(w.primary, ['.supabase']);
        _write(w.linked, ['.supabase']);
        final r = resolve(w.linked)!;
        expect(_real(r.path), _real(_join([w.linked, '.supabase', _name])));
      });
    });
  }

  for (final entry in gitless.entries) {
    group('${entry.key} with git unavailable', () {
      final resolve = entry.value;

      test('linked-worktree-shaped path: falls to the legacy file AND reports primaryError', () {
        final tree = _join([tmp.path, '.claude', 'worktrees', 'lnk']);
        Directory(tree).createSync(recursive: true);
        _write(tree, ['supabase', '.supabase']);
        final r = resolve(tree)!;
        expect(r.legacy, isTrue);
        expect(r.primaryError, isNotNull, reason: 'the silent fall-through to legacy must be reported');
        expect(r.primaryError, isNotEmpty);
      });

      test('a plain (non-linked) path with git unavailable reports no primaryError', () {
        _write(tmp.path, ['.supabase']);
        final r = resolve(tmp.path)!;
        expect(r.legacy, isFalse);
        expect(r.primaryError, isNull);
      });
    });
  }

  test('node: an inherited GIT_DIR cannot misdirect the primary lookup', () {
    final w = _repoWithLinkedWorktree(tmp);
    _write(w.primary, ['.supabase']);
    // A hook-style environment pointing at some OTHER repo's git dir.
    final other = Directory(_join([tmp.path, 'other']))..createSync();
    _git(['init', '-q'], other.path);
    final r = _viaNode(w.linked,
        env: {...Platform.environment, 'GIT_DIR': _join([other.path, '.git'])})!;
    expect(_real(r.path), _real(_join([w.primary, '.supabase', _name])));
  });
}
