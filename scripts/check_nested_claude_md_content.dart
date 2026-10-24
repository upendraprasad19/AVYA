// Gate: 44
//
// Gate 44 — Nested CLAUDE.md content quality
// =============================================
// Fails if any `lib/**/CLAUDE.md` or `supabase/**/CLAUDE.md` is still in
// "Milestone-2 scaffold" state. Established 2026-05-21 (tech-debt audit
// 2026-05-20 B5 D2 Doc3 + Doc10 + Doc12 closure).
//
// The 13 nested CLAUDE.md files were created 2026-05-18 as scaffolds with
// placeholder text like `(populated in Milestone 2)`. This gate enforces
// that they have been fleshed out with real content drawn from the
// codebase + SoT registry + root CLAUDE.md pointer table (§7).
//
// Rules:
//   - Each file must be ≥ MIN_LINES (40) lines long.
//   - No file may contain the literal scaffold markers (case-sensitive).
//
// Wired into:
//   - scripts/pre-commit.sh dynamic check_*.dart loop.
//   - .github/workflows/test.yml CI gate suite.
//
// To bypass during development: run with `--warn-only`. Pre-commit hook
// drops the warn-only flag once stable.
//
// Bug class: documentation-rot (Audit 2026-05-20 finding Doc3).
// See: docs/audit/2026_05_20_audit_closures.yaml entry Doc3 / Doc10 / Doc12.

import 'dart:io';

const int kMinLines = 40;

const List<String> kForbiddenMarkers = [
  'Milestone-2 scaffold',
  '(populated in Milestone',
  'MIGRATION IN PROGRESS — content from CLAUDE.md will be moved here in Milestone',
];

// Header-section names that are themselves fine ("## Single-source-of-truth
// contracts" is a legitimate H2) but if IMMEDIATELY followed by `(populated`
// we flag the placeholder. Captured by kForbiddenMarkers above — no
// additional regex needed.

Future<void> main(List<String> args) async {
  final bool warnOnly = args.contains('--warn-only');
  final List<String> failures = <String>[];

  final roots = <String>['lib', 'supabase'];
  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      continue;
    }
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      // Use path separators normalized to forward-slash for portable matching.
      final pathFwd = entity.path.replaceAll(r'\', '/');
      if (!pathFwd.endsWith('/CLAUDE.md')) continue;

      final content = await entity.readAsString();
      final lineCount = '\n'.allMatches(content).length + 1;

      if (lineCount < kMinLines) {
        failures.add(
          '$pathFwd: only $lineCount lines (min $kMinLines). Add real '
          'content per root CLAUDE.md §7 pointer table.',
        );
      }

      for (final marker in kForbiddenMarkers) {
        if (content.contains(marker)) {
          failures.add(
            '$pathFwd: contains scaffold marker "$marker". Replace with '
            'real content drawn from docs/sot_registry.yaml + the feature '
            'directory code.',
          );
        }
      }
    }
  }

  if (failures.isEmpty) {
    stdout.writeln(
      '[check_nested_claude_md_content] PASS — all nested CLAUDE.md files '
      'have real content (≥$kMinLines lines, no scaffold markers).',
    );
    exit(0);
  }

  final header = warnOnly
      ? '[check_nested_claude_md_content] WARN (warn-only mode):'
      : '[check_nested_claude_md_content] FAIL:';
  stderr.writeln(header);
  for (final f in failures) {
    stderr.writeln('  - $f');
  }
  stderr.writeln(
    '\nFix: open each flagged file and replace the scaffold/placeholder '
    'section with real content. See root CLAUDE.md §7 for what each '
    'nested file should cover. Min line count: $kMinLines.',
  );
  exit(warnOnly ? 0 : 1);
}
