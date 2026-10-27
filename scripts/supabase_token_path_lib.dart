// scripts/supabase_token_path_lib.dart
//
// Dart twin of .claude/token_path.js: which Supabase Management-API token file to read.
// Same candidate order, same git lookup (the MAIN worktree = first entry of
// `git worktree list --porcelain`, with inherited GIT_* variables scrubbed), pinned against
// each other by test/scripts/token_path_resolver_test.dart.
//
// Order: this tree's `.supabase/`, the main worktree's `.supabase/`, then the LEGACY
// `supabase/.supabase/` paths. On the VPS the legacy file holds a REVOKED token (HTTP 401,
// verified 2026-10-02); on the founder's Windows clone it is unverified, so it stays a
// last-resort candidate and its use is reported via [TokenFile.legacy].
library;

import 'dart:io';

const tokenFileName = 'supabase access token.txt';

class TokenFile {
  const TokenFile(this.path, {required this.legacy, this.primaryError});
  final String path;
  final bool legacy;

  /// Set when the main worktree could not be located AND this looks like a linked worktree.
  final String? primaryError;
}

Map<String, String> _scrubbedGitEnv() {
  final env = Map<String, String>.from(Platform.environment);
  for (final k in const ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR']) {
    env.remove(k);
  }
  return env;
}

String _join(List<String> parts) => parts.join(Platform.pathSeparator);

/// The tree root: `git rev-parse --show-toplevel` from [fromDir] (falls back to [fromDir]).
String repoRootFrom(String fromDir) {
  try {
    final r = Process.runSync('git', ['rev-parse', '--show-toplevel'],
        workingDirectory: fromDir, environment: _scrubbedGitEnv(), includeParentEnvironment: false);
    final out = (r.stdout as String).trim();
    if (r.exitCode == 0 && out.isNotEmpty) return Directory(out).absolute.path;
  } catch (_) {}
  return Directory(fromDir).absolute.path;
}

/// The MAIN worktree root, or null with [error] explaining why.
({String? root, String? error}) primaryRoot(String repoRoot, {String git = 'git'}) {
  try {
    final r = Process.runSync(git, ['worktree', 'list', '--porcelain'],
        workingDirectory: repoRoot, environment: _scrubbedGitEnv(), includeParentEnvironment: false);
    if (r.exitCode != 0) {
      final msg = (r.stderr as String).trim().split('\n').first;
      return (root: null, error: msg.length > 200 ? msg.substring(0, 200) : msg);
    }
    for (final line in (r.stdout as String).split(RegExp(r'\r?\n'))) {
      if (line.startsWith('worktree ')) {
        return (root: line.substring('worktree '.length).trim(), error: null);
      }
    }
    return (root: null, error: 'git worktree list printed no worktree line');
  } catch (e) {
    return (root: null, error: e.toString());
  }
}

/// Ordered candidates (existing or not); the LEGACY `supabase/.supabase` entries come last.
/// `legacy` is decided from the slot a path was built for, never by parsing it back (a repo
/// whose own directory is named `supabase` would fool that). [git] overrides the git executable
/// (tests use it to prove the git-failed branch).
List<({String path, bool legacy})> candidateEntries(String repoRoot, {String git = 'git'}) {
  final root = Directory(repoRoot).absolute.path;
  final primary = primaryRoot(root, git: git).root;
  final hasOther = primary != null && Directory(primary).absolute.path != root;
  final p = hasOther ? Directory(primary).absolute.path : null;
  return [
    (path: _join([root, '.supabase', tokenFileName]), legacy: false),
    if (p != null) (path: _join([p, '.supabase', tokenFileName]), legacy: false),
    (path: _join([root, 'supabase', '.supabase', tokenFileName]), legacy: true),
    if (p != null) (path: _join([p, 'supabase', '.supabase', tokenFileName]), legacy: true),
  ];
}

/// Ordered candidate token file paths (existing or not); the last ones are the LEGACY paths.
List<String> candidateTokenFiles(String repoRoot, {String git = 'git'}) =>
    [for (final e in candidateEntries(repoRoot, git: git)) e.path];

/// First candidate that is a regular file, or null.
TokenFile? resolveTokenFile(String repoRoot, {String git = 'git'}) {
  final root = Directory(repoRoot).absolute.path;
  final err = primaryRoot(root, git: git).error;
  final linked = root.replaceAll(r'\', '/').contains('/.claude/worktrees/');
  for (final e in candidateEntries(root, git: git)) {
    if (File(e.path).existsSync()) {  // file-only: a token file, never a directory
      return TokenFile(e.path, legacy: e.legacy, primaryError: linked ? err : null);
    }
  }
  return null;
}
