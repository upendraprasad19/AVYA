// scripts/check_edge_function_scope.dart
// Gate — discipline v3 Phase 3, 2026-09-23. Fitness App's equivalent of
// ICANBEFITTER's Rule 3 AST gate: CLAUDE.md §4.4 rule 9, "Never expose API
// keys client-side. All AI calls go through Supabase Edge Functions."
//
// Unlike Rule 2's equivalent (check_hive_first_pattern.dart), which has a
// legitimate "allowed" layer (the repository/service dirs), rule 9 has NO
// allowed location in `lib/` at all -- an AI provider key or a direct call to
// an AI provider's endpoint is a violation wherever it appears client-side,
// full stop. Confirmed against CLAUDE.md §0's own env-var table: only
// SUPABASE_URL, SUPABASE_ANON_KEY and RAZORPAY_KEY_ID are ever passed to the
// client via --dart-define-from-file=.env; GEMINI_API_KEY, OPENAI_API_KEY,
// CEREBRAS_API_KEY_1/2/3 and RAZORPAY_KEY_SECRET are Edge Function secrets
// ONLY (§2a's "Credentials (Edge Function Secrets)" table) -- the client has
// no legitimate reason to reference any of those names at all.
//
// REPORT MODE ONLY -- always exits 0, mirroring check_hive_first_pattern.dart
// (§4.11 gate-before-refactor convention: baseline before ever hard-failing;
// this one has no real AST parser behind it either, only a source grep).
//
// ⚠ NO baseline-raising mechanism exists for this gate yet -- same caveat as
// check_hive_first_pattern.dart. Phase 2 scope, still separately incomplete.
//
// VERIFIED against the real codebase (2026-09-23, before writing this file):
// zero matches for any AI provider endpoint domain or key-env-var name
// anywhere in lib/; the only functions.invoke( call sites (the correct,
// allowed path) are lib/core/services/{sync_service,supabase_service,
// razorpay_service}.dart + lib/features/train/providers/video_render_provider.dart.
//
// Pure logic kept INLINE (not a separate _lib.dart) -- see
// check_hive_first_pattern.dart's header for why: a `check_*_lib.dart` name
// would match the gate-loop's own glob and be invoked as a broken standalone
// gate.

import 'dart:convert';
import 'dart:io';

/// Direct calls to an AI provider's own API domain -- these MUST go through
/// a Supabase Edge Function (`functions.invoke(...)`) instead.
final RegExp aiProviderEndpoint = RegExp(
  r'generativelanguage\.googleapis\.com|api\.openai\.com|api\.cerebras\.ai',
);

/// Names of secrets that are Edge-Function-only per CLAUDE.md §2a -- the
/// client never legitimately reads these by name.
final RegExp aiSecretKeyName = RegExp(
  r'\b(?:GEMINI_API_KEY|OPENAI_API_KEY|CEREBRAS_API_KEY_?\d?|RAZORPAY_KEY_SECRET)\b',
);

/// One violating line.
class ScopeViolation {
  final String file;
  final int line; // 1-indexed
  final String kind; // 'endpoint' | 'secret-key-name'
  const ScopeViolation(this.file, this.line, this.kind);
  @override
  String toString() => '$file:$line ($kind)';
}

/// Newline-preserving comment strip -- identical convention to
/// check_hive_first_pattern.dart's stripLineComments (per
/// feedback_source_grep_strip_comments_first.md; this repo's own convention
/// is one small copy per gate script rather than a shared import).
String stripLineComments(String src) {
  return src.split('\n').map((line) {
    var l = line.replaceAll(RegExp(r'/\*.*?\*/'), '');
    final m = RegExp(r'(?<!:)//').firstMatch(l);
    return m == null ? l : l.substring(0, m.start);
  }).join('\n');
}

/// Pure scan over an in-memory {relativePath: content} map. No allowlist --
/// rule 9 permits neither shape anywhere under lib/.
List<ScopeViolation> findViolations(Map<String, String> filesByPath) {
  final violations = <ScopeViolation>[];
  filesByPath.forEach((path, rawContent) {
    final content = stripLineComments(rawContent);
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (aiProviderEndpoint.hasMatch(line)) {
        violations.add(ScopeViolation(path, i + 1, 'endpoint'));
      }
      if (aiSecretKeyName.hasMatch(line)) {
        violations.add(ScopeViolation(path, i + 1, 'secret-key-name'));
      }
    }
  });
  return violations;
}

/// Walks the real `lib/` tree relative to [repoRoot] and returns violations.
List<ScopeViolation> scanLibDirectory(String repoRoot) {
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
      continue;
    }
  }
  return findViolations(filesByPath);
}

void main(List<String> args) {
  try {
    final repoRootResult = Process.runSync('git', ['rev-parse', '--show-toplevel']);
    if (repoRootResult.exitCode != 0) {
      exit(0);
    }
    final repoRoot = (repoRootResult.stdout as String).trim();
    final violations = scanLibDirectory(repoRoot);

    if (violations.isEmpty) {
      stdout.writeln('[check-edge-function-scope] PASS: 0 direct AI-provider endpoint '
          'calls or Edge-Function-only secret names in lib/.');
      exit(0);
    }

    stdout.writeln('[check-edge-function-scope] REPORT: ${violations.length} '
        'client-side AI-scope violation(s) (CLAUDE.md §4.4 rule 9). Report mode '
        '-- does not block. Violations:');
    for (final v in violations) {
      stdout.writeln('  - $v');
    }
    exit(0);
  } catch (_) {
    exit(0);
  }
}
