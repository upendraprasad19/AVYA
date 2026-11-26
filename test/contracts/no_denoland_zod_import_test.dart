// test/contracts/no_denoland_zod_import_test.dart
//
// Derive-only AI-coach batch (2026-05-31) — regression pin for the zod
// dependency-rot deploy blocker (diagnose 2026-05-31-zod-denoland-deploy-blocker).
//
// Root cause: `https://deno.land/x/zod@v3.25.76/mod.ts` was REMOVED from the
// deno.land/x registry upstream (now returns HTTP 404). Every Edge Function that
// imported zod from deno.land/x became un-deployable — the Supabase Edge bundler
// fails the deploy when a remote import 404s. This surfaced as two failed
// `ai-proxy` redeploys (HTTP 400 "Module not found ...zod...") and was a LATENT,
// platform-wide blocker for the whole AI tool surface.
//
// Fix: migrate every importer (24 inline `.ts` files + the canonical
// `import_map.json` pin) to the npm specifier `npm:zod@3.25.76`, which Supabase
// Edge (Deno) resolves natively.
//
// This test fails if ANY file under supabase/functions/ re-introduces a
// `deno.land/x/zod` import (inline or via the import map).
//
// Comment handling: we strip block comments and line comments BEFORE scanning so
// an explanatory comment mentioning the dead URL doesn't trigger a false
// positive. CRITICAL: the line-comment strip uses a colon-lookbehind
// (`(?<!:)//`) so it does NOT eat the `//` inside `https://...` URLs — a naive
// `//.*` strip would delete the very URL substring this test must detect.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no file under supabase/functions imports zod from deno.land/x', () {
    final dir = Directory('supabase/functions');
    expect(dir.existsSync(), isTrue,
        reason: 'supabase/functions/ must exist');

    final offenders = <String>[];

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll(r'\', '/');
      // Only scan TypeScript sources + the dependency pin file.
      final isTs = path.endsWith('.ts');
      final isImportMap = path.endsWith('import_map.json');
      if (!isTs && !isImportMap) continue;

      final stripped = _stripComments(entity.readAsStringSync());
      if (stripped.contains('deno.land/x/zod')) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Found deno.land/x/zod import(s) in:\n  ${offenders.join('\n  ')}\n'
          'That URL was removed upstream (HTTP 404) and BLOCKS Edge Function '
          'deploys. Use `npm:zod@3.25.76` instead (canonical pin in '
          'supabase/functions/import_map.json). See diagnose '
          '2026-05-31-zod-denoland-deploy-blocker.',
    );
  });

  test('import_map.json pins zod via the npm specifier', () {
    final file = File('supabase/functions/import_map.json');
    expect(file.existsSync(), isTrue);
    final src = file.readAsStringSync();
    expect(
      src.contains('"zod": "npm:zod@3.25.76"'),
      isTrue,
      reason: 'The canonical zod pin in import_map.json must be '
          '`npm:zod@3.25.76` (not a deno.land/x URL).',
    );
  });
}

/// Strips block comments and line comments. The line-comment regex uses a
/// negative lookbehind for `:` so it preserves the `//` inside URL schemes
/// (`https://`, `http://`) — otherwise it would delete the URL substring the
/// caller is trying to detect.
String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'(?<!:)//[^\n]*');
  out = out.replaceAll(line, '');
  return out;
}
