// scripts/check_hive_first_pattern.dart
// Gate — discipline v3 Phase 3, 2026-09-23. Fitness App's equivalent of
// ICANBEFITTER's Rule 2 AST gate: CLAUDE.md §4.4 rule 4, "Repository pattern
// for all data access. Never call Supabase or Hive directly from widgets."
//
// REPORT MODE ONLY -- always exits 0. This is a debt-tracking gate, not a
// blocking one: CLAUDE.md §4.11's pattern (a new gate baselines --warn-only
// before ever hard-failing) plus the source-grep-can't-converge lesson (code-
// review skill lens 6) both argue against ever flipping this one to hard-fail
// without a real AST parser backing it: `.client.from(` could in principle
// belong to some future non-Supabase client with a `.from()` method of its
// own, and tightening the pattern to chase that never converges.
//
// ⚠ NO baseline-raising mechanism exists for this gate yet (the ICANBEFITTER
// audit's "baseline-raising gate" -- check-baseline-notes.mjs equivalent -- is
// Phase 2 scope, still separately incomplete; it is NOT built here). This gate
// only prints a count every run; nothing yet alarms if that count grows.
//
// VERIFIED against the real codebase (2026-09-23, before writing this file):
// grep '\.client\.from\(' lib/ matched 27 call sites across 9 files, ALL of
// them `_supabase.client.from(` / `SupabaseService.instance.client.from(` /
// `_s.client.from(` -- no unrelated client's `.from()` collided. Zero false
// positives measured on the real tree, not assumed.
//
// Pure logic kept INLINE (not a separate _lib.dart) -- matching this repo's
// own convention (see scripts/check_hooks_installed.dart's parseInstalledHooks):
// a `check_*_lib.dart` name would itself match the `scripts/check_*.dart` glob
// pre-commit.sh's gate loop and the rule-24 ledger both scan, and would be
// invoked as a (broken, main()-less) standalone gate.

import 'dart:convert';
import 'dart:io';

/// Matches `supabase.from(` and `<anything>.client.from(` -- the two real
/// call shapes this codebase uses for direct Supabase table access (verified
/// against every live call site before this gate was written; see header).
final RegExp supabaseFromCall = RegExp(r'\b(?:supabase|client)\.from\(');

/// Directories where direct Supabase access is the REPOSITORY/SERVICE layer
/// itself, not a violation of the pattern -- CLAUDE.md §7 names
/// `lib/core/services/CLAUDE.md` as "WriteServices, sync fan-out, Hive
/// contracts", and `lib/shared/repositories/` + `lib/features/*/repositories/`
/// are the named repository layer (rule 4's own vocabulary).
const List<String> allowedDirPrefixes = [
  'lib/core/services/',
  'lib/shared/repositories/',
];

final RegExp _featureRepositoriesDir =
    RegExp(r'^lib/features/[^/]+/repositories/');

/// True when [relativePath] (forward-slash or backslash, repo-relative) is
/// inside the recognised data-access layer.
bool isAllowedPath(String relativePath) {
  final norm = relativePath.replaceAll('\\', '/');
  if (allowedDirPrefixes.any(norm.startsWith)) return true;
  return _featureRepositoriesDir.hasMatch(norm);
}

/// Newline-preserving comment strip (keeps line numbers accurate) -- per
/// feedback_source_grep_strip_comments_first.md, reused from the identical
/// helper already living in check_edge_function_auth_pattern.dart and
/// check_snapshot_contract.dart (this repo's own convention is one small
/// copy per gate script, not a shared import, for exactly this kind of
/// single-purpose helper).
String stripLineComments(String src) {
  return src.split('\n').map((line) {
    var l = line.replaceAll(RegExp(r'/\*.*?\*/'), '');
    final m = RegExp(r'(?<!:)//').firstMatch(l);
    return m == null ? l : l.substring(0, m.start);
  }).join('\n');
}

/// One violating call site.
class Violation {
  final String file;
  final int line; // 1-indexed
  const Violation(this.file, this.line);
  @override
  String toString() => '$file:$line';
}

/// Pure scan over an in-memory {relativePath: content} map -- no I/O, so a
/// test can drive it directly with fabricated files (rule 21's lesson: a
/// function no test can reach protects nothing).
List<Violation> findViolations(Map<String, String> filesByPath) {
  final violations = <Violation>[];
  filesByPath.forEach((path, rawContent) {
    if (isAllowedPath(path)) return;
    final content = stripLineComments(rawContent);
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (supabaseFromCall.hasMatch(lines[i])) {
        violations.add(Violation(path, i + 1));
      }
    }
  });
  return violations;
}

/// Walks the real `lib/` tree relative to [repoRoot] and returns violations.
/// Kept separate from [findViolations] so the scan itself needs no test --
/// only the pure logic does.
List<Violation> scanLibDirectory(String repoRoot) {
  final libDir = Directory('$repoRoot/lib');
  if (!libDir.existsSync()) return const [];
  final filesByPath = <String, String>{};
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relative =
        entity.path.substring(repoRoot.length + 1).replaceAll('\\', '/');
    try {
      filesByPath[relative] = entity.readAsStringSync(encoding: utf8);
    } catch (_) {
      continue; // unreadable file -- skip, do not fail the whole scan over it
    }
  }
  return findViolations(filesByPath);
}

void main(List<String> args) {
  try {
    final repoRootResult = Process.runSync('git', ['rev-parse', '--show-toplevel']);
    if (repoRootResult.exitCode != 0) {
      exit(0); // fail open -- cannot resolve the repo root
    }
    final repoRoot = (repoRootResult.stdout as String).trim();
    final violations = scanLibDirectory(repoRoot);

    if (violations.isEmpty) {
      stdout.writeln('[check-hive-first-pattern] PASS: 0 direct Supabase calls outside '
          'lib/core/services/, lib/shared/repositories/, lib/features/*/repositories/.');
      exit(0);
    }

    stdout.writeln('[check-hive-first-pattern] REPORT: ${violations.length} direct Supabase '
        'call(s) outside the repository/service layer (CLAUDE.md §4.4 rule 4). Report mode '
        '-- does not block. Violations:');
    for (final v in violations) {
      stdout.writeln('  - $v');
    }
    exit(0); // report-mode: never fails the commit.
  } catch (_) {
    exit(0); // fail open
  }
}
