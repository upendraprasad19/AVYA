// scripts/merge_scope_lib.dart
//
// Pure helpers for the "merge scope" rule of scripts/check_code_review_pass_exists.dart
// (landing C1 of the merge-conflict-treadmill plan, docs/plans/sync-merge-scope.md; closes OI-413).
//
// THE PROBLEM. A branch that is behind origin/main is synced with `git merge origin/main`. When that
// merge conflicts, the human concludes it with `git commit`, which runs pre-commit, and the catastrophic
// review gate then classified `git diff --cached --name-only`: EVERYTHING main brought in. If main
// gained a catastrophic path the gate demanded a review of code that had already landed on main, and
// no honest review file can satisfy it (five trips recorded; the answer was a hand rebuild).
//
// THE RULE. While a merge is pending whose MERGE_HEAD is an ancestor of the commit that
// refs/remotes/origin/main names (the TIP), a staged path is GRADED only when its index entry
// (mode + object id, or absent) differs from HEAD's entry AND from the TIP's entry:
//
//   - equal to HEAD's: nothing new reaches the branch;
//   - equal to the TIP's: it is what main holds at that path today (landed through main's gates);
//   - equal to neither: git or the human produced something no reviewed state holds there, so it is
//     graded. The comparison is on ENTRIES at the committed path, so it does not matter HOW git got
//     there (rename, directory rename, add/add, conflict resolution, a clean combination of two
//     edits), and an old, interior or reverted MERGE_HEAD exempts nothing main does not hold now.
//
// Every failed precondition returns [Fallback]; the gate then grades the full staged list exactly as
// before. The function never throws. It uses only plumbing (`rev-parse`, `merge-base`, `diff-index`):
// no `index.lock`, no object writes, no `git merge-tree` (git 2.38), no `diff.*` porcelain config.
//
// The sets are compared as BYTE STRINGS (one char per byte): git orders names by UTF-8 bytes and
// Dart's String.compareTo by UTF-16 code units, and an undecodable name that is not in the commit
// must not disable scoping. The gate's staged list is the only decoded input (strictly, see
// [parseNulPaths]); graded paths are taken from it, so nothing here decodes a diff-index answer.
//
// The lib imports only dart:convert; git and the file system come in through [GitRun] and
// [ReadMergeHead] so every precondition is unit-testable with a fake.

import 'dart:convert';

/// One git invocation: the arguments after `git`. Null means the process could not run.
typedef GitRun = ({int exitCode, List<int> stdout})? Function(List<String> args);

/// The contents of the MERGE_HEAD file at [path]: null when the file is ABSENT (not a merge), a
/// thrown error when it exists but cannot be read.
typedef ReadMergeHead = String? Function(String path);

/// What [computeMergeScope] found.
sealed class MergeScope {
  const MergeScope();
}

/// No merge is pending (the MERGE_HEAD file is absent): nothing changes, no NOTE.
final class NotAMerge extends MergeScope {
  const NotAMerge();
}

/// A sync of origin/main: grade only [paths] (sorted; a subset of the staged list).
final class Scoped extends MergeScope {
  const Scoped(this.paths, {required this.tip, required this.mergeHead});
  final List<String> paths;
  final String tip;
  final String mergeHead;
}

/// A merge is pending but scoping does not apply: grade the full staged list, and say why.
final class Fallback extends MergeScope {
  const Fallback(this.reason);
  final String reason;
}

/// The reason string of a [Fallback] produced by the catch-all in [computeMergeScope]. A test that
/// expects any OTHER reason must not accept this one: it means a bug threw.
const String internalErrorReason = 'internal error';

/// `git diff --cached` argv for the staged list. Porcelain, so it also works with an unborn HEAD.
/// `--no-renames` (a rename out of a catastrophic path must list the source), `--ignore-submodules=none`
/// (a `.gitmodules` `ignore = all` must not hide a gitlink) and `-z` (no C-quoting).
const List<String> stagedPathsArgv = <String>[
  'diff',
  '--cached',
  '--no-renames',
  '--ignore-submodules=none',
  '--name-only',
  '-z',
];

/// `git diff-index` argv comparing the INDEX with [treeish]. Plumbing: no rename detection unless
/// `-M` (so `--no-renames` is not needed and would be inert), no `diff.*` porcelain configuration,
/// no `index.lock`. The trailing `--` stops git from reading a working-tree file that happens to be
/// named like the revision (a file called `HEAD`, or by the tip's hex name) as a path.
List<String> diffIndexArgv(String treeish) => <String>[
      'diff-index',
      '--cached',
      '--name-only',
      '-z',
      '--ignore-submodules=none',
      treeish,
      '--',
    ];

/// True for a full object name: exactly 40 or 64 lowercase hex digits, nothing else.
bool isFullHexObjectName(String s) => _hexName.hasMatch(s);

final RegExp _hexName = RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');

/// Splits NUL-separated git output into paths and decodes each one strictly. Null when any path is
/// not valid UTF-8 ("git could not answer": the default decoder is strict on Linux and lenient on
/// Windows, and `allowMalformed` would collapse distinct invalid byte runs into one U+FFFD).
/// Nothing is trimmed (a name may start or end with a space) and the final empty element is dropped.
///
/// Each path is decoded behind a one-byte sentinel: Dart's UTF-8 decoder discards a leading U+FEFF,
/// which would otherwise change a name that starts with a byte-order mark.
List<String>? parseNulPaths(List<int> bytes) {
  final out = <String>[];
  var start = 0;
  for (var i = 0; i <= bytes.length; i++) {
    if (i == bytes.length || bytes[i] == 0) {
      if (i > start) {
        final decoded = _decodeStrict(bytes.sublist(start, i));
        if (decoded == null) return null;
        out.add(decoded);
      }
      start = i + 1;
    }
  }
  return out;
}

String? _decodeStrict(List<int> pathBytes) {
  try {
    final s = const Utf8Decoder(allowMalformed: false).convert(<int>[0x78, ...pathBytes]);
    return s.substring(1);
  } on FormatException {
    return null;
  }
}

/// NUL-separated git output as "byte strings": one char per byte, so equality is byte equality and
/// nothing is decoded. The final empty element is dropped.
List<String> splitNulBytes(List<int> bytes) {
  final out = <String>[];
  var start = 0;
  for (var i = 0; i <= bytes.length; i++) {
    if (i == bytes.length || bytes[i] == 0) {
      if (i > start) out.add(String.fromCharCodes(bytes.sublist(start, i)));
      start = i + 1;
    }
  }
  return out;
}

/// A decoded path as the byte string of its UTF-8 encoding (the form [splitNulBytes] returns).
String byteString(String path) => String.fromCharCodes(utf8.encode(path));

/// [path] made safe to print on one terminal line: the backslash, C0 and C1 controls, DEL,
/// U+2028, U+2029 and the bidirectional controls (U+202A-U+202E, U+2066-U+2069) become `\xNN` or
/// `\uNNNN`, so a hostile file name cannot forge, split or reorder a NOTE line, and a name that
/// contains the literal text `\x0a` stays distinguishable from an escaped newline.
String escapeForNote(String path) {
  final b = StringBuffer();
  for (final r in path.runes) {
    if (r == 0x5c) {
      b.write(r'\\');
    } else if (r < 0x20 || r == 0x7f || (r >= 0x80 && r <= 0x9f)) {
      b.write('\\x${r.toRadixString(16).padLeft(2, '0')}');
    } else if (r == 0x2028 ||
        r == 0x2029 ||
        (r >= 0x202a && r <= 0x202e) ||
        (r >= 0x2066 && r <= 0x2069)) {
      b.write('\\u${r.toRadixString(16).padLeft(4, '0')}');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

String _short(String hex) => hex.length > 7 ? hex.substring(0, 7) : hex;

/// The NOTE line for [scope] ([stagedCount] = length of the full staged list), or null when no merge
/// is pending. Pure so a test reaches the exact text.
String? formatScopeNote(MergeScope scope, int stagedCount) {
  switch (scope) {
    case NotAMerge():
      return null;
    case Fallback(:final reason):
      return 'branch-sync scoping not applied ($reason): grading all $stagedCount staged path(s)';
    case Scoped(:final paths, :final tip, :final mergeHead):
      const shown = 20;
      final list = paths.take(shown).map(escapeForNote).join(', ');
      final more = paths.length > shown ? ', ... (+${paths.length - shown} more)' : '';
      final named = paths.isEmpty ? '' : ': $list$more';
      return 'branch sync of origin/main (tip ${_short(tip)}, MERGE_HEAD ${_short(mergeHead)}): '
          'grading ${paths.length} path(s) whose entry matches neither HEAD nor origin/main, of '
          '$stagedCount staged$named. Unmerged paths are graded.';
  }
}

/// Decides whether the staged paths of the commit in progress are graded in full or only the ones
/// that match neither HEAD nor origin/main. [staged] is the gate's own staged list (strictly decoded,
/// from [stagedPathsArgv]); the diff-index list against HEAD must equal it as a set, otherwise the
/// two reads disagree (intent-to-add, `diff.relative`, a different environment) and the answer is a
/// [Fallback].
///
/// Stops at the first failed condition and issues no further git call. Never throws.
MergeScope computeMergeScope(
  GitRun git, {
  required ReadMergeHead readMergeHead,
  required List<String> staged,
}) {
  try {
    // 1. Is a merge pending, and is it a plain two-parent one?
    final gp = git(const ['rev-parse', '--git-path', 'MERGE_HEAD']);
    if (gp == null) return const Fallback('git could not run');
    if (gp.exitCode != 0) return const Fallback('git rev-parse --git-path failed');
    var mergeHeadPath = utf8.decode(gp.stdout, allowMalformed: true);
    if (mergeHeadPath.endsWith('\n')) mergeHeadPath = mergeHeadPath.substring(0, mergeHeadPath.length - 1);
    if (mergeHeadPath.isEmpty) return const Fallback('git rev-parse --git-path printed nothing');

    final String? text;
    try {
      text = readMergeHead(mergeHeadPath);
    } catch (_) {
      return const Fallback('MERGE_HEAD unreadable');
    }
    if (text == null) return const NotAMerge();
    final lines = text.split('\n').where((l) => l.isNotEmpty).toList();
    if (lines.length != 1) {
      return Fallback('MERGE_HEAD has ${lines.length} lines (octopus merge or empty file)');
    }
    final mergeHead = lines.single;
    if (!isFullHexObjectName(mergeHead)) return const Fallback('MERGE_HEAD is not a full object name');

    // 2. The tip of origin/main, by its FULL ref name (a local branch or tag cannot shadow it).
    final tipRun = git(const ['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/main^{commit}']);
    if (tipRun == null) return const Fallback('git could not run');
    if (tipRun.exitCode != 0) return const Fallback('refs/remotes/origin/main is missing or not a commit');
    var tip = utf8.decode(tipRun.stdout, allowMalformed: true);
    if (tip.endsWith('\n')) tip = tip.substring(0, tip.length - 1);
    if (!isFullHexObjectName(tip)) {
      return const Fallback('refs/remotes/origin/main did not resolve to a full object name');
    }

    // 3. The merge is a sync of main.
    final anc = git(<String>['merge-base', '--is-ancestor', mergeHead, tip]);
    if (anc == null) return const Fallback('git could not run');
    if (anc.exitCode == 1) {
      return const Fallback('MERGE_HEAD is not an ancestor of origin/main (or the history is shallow)');
    }
    if (anc.exitCode != 0) return const Fallback('git merge-base --is-ancestor failed');

    // 4. The index against HEAD must be the staged list the gate already read.
    final headRun = git(diffIndexArgv('HEAD'));
    if (headRun == null) return const Fallback('git could not run');
    if (headRun.exitCode != 0) return const Fallback('git diff-index against HEAD failed');
    final headDiff = splitNulBytes(headRun.stdout).toSet();
    final stagedBytes = <String, String>{for (final p in staged) byteString(p): p};
    if (headDiff.length != stagedBytes.length || !headDiff.containsAll(stagedBytes.keys)) {
      return const Fallback('index reads disagree');
    }

    // 5. The index against the tip: a staged path in this list differs from main's entry too.
    final tipRunDiff = git(diffIndexArgv(tip));
    if (tipRunDiff == null) return const Fallback('git could not run');
    if (tipRunDiff.exitCode != 0) return const Fallback('git diff-index against origin/main failed');
    final tipDiff = splitNulBytes(tipRunDiff.stdout).toSet();

    final graded = <String>[
      for (final entry in stagedBytes.entries)
        if (tipDiff.contains(entry.key)) entry.value,
    ]..sort();
    return Scoped(graded, tip: tip, mergeHead: mergeHead);
  } catch (_) {
    return const Fallback(internalErrorReason);
  }
}
