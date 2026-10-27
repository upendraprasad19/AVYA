// scripts/version_bump_git_lib.dart
//
// The git-reading half of the version-bump exemption (OI-275 batch B2,
// docs/plans/2026-10-10-release-cycle-speedup.md section 3).
//
// WHERE THIS CODE USED TO LIVE. `check_plan_review_record_exists.dart` (the CI
// keystone gate) read the before/after blobs and tree modes of the two version
// files itself, in the loop that judges commits pushed STRAIGHT to main (OI-58a),
// using private helpers. The decision that consumes them, `isVersionBumpCommit`,
// lives in `plan_review_record_lib.dart`, which has "No imports on purpose" so it
// stays trivially unit-testable - which is why the Process-using readers could not
// move there. They live here instead, public, so that THREE callers share one
// implementation:
//   1. the gate's direct-commit loop   (rangeIsVersionBump('<sha>^', sha)),
//   2. the gate's MERGE loop           (rangeIsVersionBump('<sha>^1', sha)) - new,
//   3. scripts/version_bump_range.dart  - the tiny CLI behind safe_merge.sh's
//      absent-record advisory, which previously never mirrored the exemption (OI-222).
// Three callers on three copies of "is this a bump?" is exactly how a bypass is
// fixed in two places and left open in the third.
//
// WHY A MERGE NEEDS THE EXEMPTION TOO. A version bump reaches main either as a
// direct commit (judged per commit, exempt by content since OI-58a) or - the flow
// the release-cycle speedup makes cheap, because a branch push no longer runs the
// local suite - as a PR merge. The merge commit's net change against main's previous
// tip is those same two version lines, but the merge loop demanded a converged
// plan-review record plus a B-pass for it, because the bump touches a `platform`
// path (pubspec.yaml). That record describes a plan; a bump has none. The exemption
// is decided by CONTENT only (the merge SUBJECT is not consulted: OI-58b is
// untouched), and it is all-or-nothing: a bump plus any other file - including a
// docs record - is not a bump.
//
// FAIL-CLOSED. Every function here returns `null` / `false` when git cannot answer.
// A false from [rangeIsVersionBump] means "not exempt", so the caller falls through
// to the normal record requirement; nothing here can turn a git failure into an
// exemption.

import 'dart:convert';
import 'dart:io';

import 'plan_review_record_lib.dart';

/// Runs git and returns its stdout, trimmed, or NULL when git itself failed.
/// (Same contract as the gate's own `_gitOrNull`: "no output" and "git could not
/// answer" must stay distinguishable.)
String? _gitOrNull(List<String> args) {
  final r = Process.runSync('git', args);
  return r.exitCode == 0 ? (r.stdout as String).trim() : null;
}

/// Reads a blob VERBATIM - no trimming, no lossy decoding.
///
/// Round-2 review P1-3 + P2-2 of the gate-input-family batch, two bugs in one line
/// of plumbing:
///
///   `Process.runSync`'s default `stdoutEncoding` is, on Linux, a STRICT
///   `Utf8Decoder` - it THROWS on the first invalid byte. The gate reads
///   `git show <rev>:<path>` for changed paths and this repo tracks 79 binary files,
///   so a push touching any PNG would have crashed CI with an uncaught
///   FormatException. Windows never saw it: its ACP decoder is total.
///
///   A trimmed read silently breaks the byte-identity contract `isVersionBumpCommit`
///   documents - leading/trailing whitespace changes were accepted as
///   "byte-identical".
///
/// DO NOT "fix" the first half with `allowMalformed: true`: verified that both 0x80
/// and 0x81 decode to U+FFFD under that flag, which would convert a loud crash into a
/// silent byte-equality COLLISION. Bytes are read raw and decoded strictly; a blob
/// that is not valid UTF-8 returns null, and every caller treats null as "cannot
/// judge this" rather than "nothing to see".
///
/// A leading UTF-8 byte-order mark is KEPT (B-pass F4 of OI-275 batch B2). Dart's
/// `Utf8Decoder` silently drops one (verified: `EF BB BF 6E` and `6E` decode to the same
/// string), so a bump commit that also ADDED or REMOVED a BOM on `pubspec.yaml` compared
/// byte-equal after normalisation and was called a bare version bump - the "byte-identical"
/// claim the exemption makes was false for exactly those three bytes. The decoder's result is
/// re-prefixed with U+FEFF when the raw bytes start with the BOM, so a BOM on one side only
/// breaks equality and a BOM on both sides compares equal.
String? gitBlobAt(String rev, String path) {
  final r = Process.runSync('git', ['show', '$rev:$path'], stdoutEncoding: null);
  if (r.exitCode != 0) return null;
  final bytes = r.stdout as List<int>;
  try {
    final text = const Utf8Decoder(allowMalformed: false).convert(bytes);
    final hasBom = bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
    return hasBom ? '\uFEFF$text' : text;
  } on FormatException {
    return null; // binary or non-UTF-8 - not something we can compare textually
  }
}

/// The git tree MODE of [path] at [rev] (`100644`, `120000`, ...), or null.
///
/// B-pass P0-2 of the gate-input-family batch: `git show <rev>:<path>` returns a
/// symlink's TARGET TEXT as if it were file content, so a `pubspec.yaml` converted to
/// a symlink pointing at a string that reads like a bumped pubspec was granted the
/// exemption. Content cannot see that; the mode can.
String? gitModeAt(String rev, String path) {
  final out = _gitOrNull(['ls-tree', rev, '--', path]);
  if (out == null || out.isEmpty) return null;
  final m = RegExp(r'^(\d{6})\s').firstMatch(out.trimLeft());
  return m?.group(1);
}

/// Changed paths between two revs (two-dot: `from..to`), EXACTLY as git stores them, or
/// NULL when git could not answer.
///
/// Four things are load-bearing:
///
///   `--no-renames` (round-2 P1-1 of the gate-input-family batch): with rename detection
///   on, `--name-only` prints ONLY the destination, so deleting a governed file by
///   renaming it out of the way made it invisible to the tier computation. Verified: a
///   commit renaming a `platform` path into `docs/` graded `feature` and was skipped
///   entirely.
///
///   `-z` (round-2 P1-2, and OI-275 batch B2, diagnose 34e764): paths come NUL-separated
///   and verbatim. By default git C-quotes non-ASCII paths (`"lib/core/r\303\251sum\303\251.dart"`),
///   which the glob matcher anchors `^...$` against and so missed, grading a `platform`
///   file with an accented name `feature` (the first fix was `-c core.quotePath=false`).
///   `-z` also removes the OTHER way a path was changed on its way in: this function used
///   to trim every line (and `_gitOrNull` trims the whole output), so ` pubspec.yaml`
///   - a distinct, valid git path with a LEADING space, holding anything - became the
///   real `pubspec.yaml` and rode along on a genuine bump under the exemption. A decision
///   that waives a review must be made on the bytes git stores, so there is no trim here
///   and no line splitting that a newline in a name could confuse.
///
///   `--ignore-submodules=none` (B-pass F1 of OI-275 batch B2, diagnose 34e764 instance 5):
///   `git diff` consults the repository's `.gitmodules` for a per-submodule
///   `ignore = all` and, when it finds one, OMITS that submodule's pointer move from the
///   path list altogether - `--name-only` included. `.gitmodules` is a tracked file the
///   pusher writes (feature tier, so landing it needs no record), which makes "which paths
///   changed" an answer the commit author can edit: a bump commit that also moves a gitlink
///   at `vendor/x` listed only `pubspec.yaml` and `app_constants.dart` and was called a
///   bare version bump, and the same hidden path never reached the tier computation.
///   Verified by execution. The flag overrides the setting (git's own documentation:
///   "none ... can be used to override any settings of the ignore option in git-config or
///   gitmodules"). CI never inits submodules and this repo has none, so the payload is
///   inert today; the hole is the path list lying, which is exactly what the exemption
///   forbids.
///
///   Strict UTF-8: a path that is not valid UTF-8 returns NULL ("git could not answer"),
///   on every platform. The default decoder is strict on Linux and lenient on Windows,
///   and `allowMalformed` would collapse distinct invalid bytes into one U+FFFD.
List<String>? diffPathsBetween(String from, String to) {
  final r = Process.runSync(
      'git',
      [
        'diff',
        '--no-renames',
        '--ignore-submodules=none',
        '--name-only',
        '-z',
        '$from..$to',
      ],
      stdoutEncoding: null);
  if (r.exitCode != 0) return null;
  final String text;
  try {
    text = const Utf8Decoder(allowMalformed: false).convert(r.stdout as List<int>);
  } on FormatException {
    return null;
  }
  return text.split('\u0000').where((s) => s.isNotEmpty).toList();
}

/// True when the NET change from [baseRev] to [headRev] is nothing but a version
/// bump: every changed path is one of [versionBumpPaths], each such file is
/// byte-identical to its base once the single version token is normalised, and at
/// least one version token actually changed (see [isVersionBumpCommit] for the full
/// contract: the same regular-file mode on both sides, exactly one token, no create/delete).
///
/// For a direct commit pass `('<sha>^', sha)`; for a merge commit pass
/// `('<sha>^1', sha)` - its net diff against the previous tip of the branch it
/// landed on, which includes whatever the merge itself wrote resolving conflicts.
/// For a branch that has not been merged yet pass the merge base and the branch tip.
///
/// Returns false - never throws - when git cannot answer, when a file cannot be read
/// as UTF-8 text, or when a mode is not a regular file or differs between the sides.
bool rangeIsVersionBump(String baseRev, String headRev) {
  final paths = diffPathsBetween(baseRev, headRev);
  if (paths == null || paths.isEmpty) return false;

  // Fetch each touched version file's BEFORE and AFTER blob. Deliberately not a
  // diff: attempt 3 of OI-58a parsed diff text and independent review broke it three
  // ways in one pass, all from the same root - the diff text is written by the thing
  // being checked. Paths are a cheap precondition inside [isVersionBumpCommit], never
  // the decision.
  final bumpFiles = <VersionBumpFile>[];
  for (final p in paths) {
    if (!versionBumpPaths.contains(p)) continue;
    // `git show <rev>:<path>` fails when the path is absent at that rev; a create or
    // delete is not a bump, so an unreadable side is refused outright.
    final before = gitBlobAt(baseRev, p);
    final after = gitBlobAt(headRev, p);
    if (before == null || after == null) return false;
    bumpFiles.add((
      path: p,
      before: before,
      after: after,
      beforeMode: gitModeAt(baseRev, p),
      afterMode: gitModeAt(headRev, p),
    ));
  }
  return isVersionBumpCommit(paths, bumpFiles);
}
