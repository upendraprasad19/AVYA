// Regression test for retired root §19 entry #55 (Class B, 2026-05-18
// declutter Milestone 4) — this test is the entry's surviving record.
//
// Pins the rule: All AI traffic moved to Gemini on 2026-04-18. `_shared/openrouter.ts`
// is deleted; `_shared/gemini.ts` is the only helper. No Edge Function source
// should reference `api.cerebras.ai`, `openrouter.ai`, or import the retired
// `_shared/openrouter` helper.
//
// Pre-fix evidence: commit `7646200` (2026-04-18) — full migration off
// Cerebras + OpenRouter to single Gemini provider. See also
// `docs/architecture/ai.md` model matrix. (The original comment attributed
// that §11 to `lib/CLAUDE.md`; it was root's — no nested contract file
// defines numbered sections.)
//
// Source-grep contract — strips comments first per
// feedback_source_grep_strip_comments_first.md. Migration notes in
// `ai-proxy/index.ts`, `rolling-context/index.ts`, etc. quote the retired
// provider names in comments; only un-stripped grep would false-positive.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strip TS/Dart line + block comments before source-grep.
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  test('§19 #55 — no Cerebras/OpenRouter references in supabase/functions/', () {
    final root = Directory('supabase/functions');
    expect(root.existsSync(), isTrue,
        reason: 'supabase/functions/ must exist for this test to run.');

    // Patterns that, if present in un-commented source, indicate a regression
    // back to the retired multi-provider AI cascade.
    const forbiddenPatterns = <String>[
      'api.cerebras.ai',
      'openrouter.ai',
      '../_shared/openrouter',
      './_shared/openrouter',
    ];

    final offenders = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.ts')) continue;
      final src = entity.readAsStringSync();
      final stripped = _stripComments(src);
      for (final pattern in forbiddenPatterns) {
        if (stripped.contains(pattern)) {
          offenders.add('${entity.path}: contains "$pattern" outside comments');
        }
      }
    }

    expect(offenders, isEmpty,
        reason:
            'Retired AI provider references found in Edge Function source. '
            'All AI traffic must route through `_shared/gemini.ts` '
            '(geminiChat helper). Restore at: see git log around 2026-04-18 '
            'commit 7646200 for the canonical migration shape.\n\n'
            'Offenders:\n  ${offenders.join("\n  ")}');
  });
}
