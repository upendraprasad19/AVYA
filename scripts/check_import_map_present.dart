// scripts/check_import_map_present.dart
//
// Gate 27 (Tech-debt audit 2026-05-20, findings D2, D3): assert
// `supabase/functions/import_map.json` exists + pins every shared
// dependency to a fixed version (no floating `@N` shapes).
//
// The audit finding: `@supabase/supabase-js` is variously `@2.39.0`,
// `@2.39.3`, and floating `@2` across ~30 Edge Function files. Floating
// pins resolve to whatever esm.sh serves at request time → silent behavior
// drift. Standard fix: import_map.json with aliases pinned once.
//
// This gate enforces:
//   1. supabase/functions/import_map.json exists.
//   2. It includes (at minimum) pins for: @supabase/supabase-js, std,
//      zod, jose.
//   3. No Edge Function file imports a floating @N pin like
//      `@supabase/supabase-js@2` (must be `@2.X.Y`).
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final violations = <String>[];

  final importMap = File('supabase/functions/import_map.json');
  final required = ['@supabase/supabase-js', 'std/', 'zod', 'jose'];

  if (!importMap.existsSync()) {
    violations.add('MISSING: supabase/functions/import_map.json — every Edge Function inlines URL pins (drift hazard).');
  } else {
    try {
      final json = jsonDecode(importMap.readAsStringSync()) as Map<String, dynamic>;
      final imports = (json['imports'] as Map?)?.cast<String, dynamic>() ?? {};
      for (final key in required) {
        if (!imports.keys.any((k) => k.startsWith(key))) {
          violations.add('import_map.json missing required pin: $key');
        }
      }
      // Assert no floating @N in import_map values.
      for (final entry in imports.entries) {
        final value = entry.value.toString();
        // Detect `@N` immediately followed by non-digit (i.e., `@2/` or `@2"`)
        // — not `@2.39.3`.
        if (RegExp(r'@\d+(?:[/?"]|$)').hasMatch(value) && !value.contains('@std')) {
          violations.add('import_map.json floating pin: ${entry.key} → $value');
        }
      }
    } catch (e) {
      violations.add('import_map.json parse error: $e');
    }
  }

  // Scan Edge Function source for floating @N pins.
  // (Only flag when import_map.json exists — otherwise the missing-map
  // violation above already covers it.)
  if (importMap.existsSync()) {
    final dir = Directory('supabase/functions');
    if (dir.existsSync()) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.ts')) continue;
        if (entity.path.contains('_payload_')) continue;
        final content = entity.readAsStringSync();
        // Pattern: `@supabase/supabase-js@2"` or `@supabase/supabase-js@2'`
        // — a pin with no minor/patch. Allow `@std@N.M.K`.
        final floating = RegExp(r"""@supabase/supabase-js@\d+(?:["'/]|\s)""");
        if (floating.hasMatch(content)) {
          violations.add('floating supabase-js pin in ${entity.path}');
        }
      }
    }
  }

  final tag = warnOnly ? '[Gate 27 WARN]' : '[Gate 27]';
  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: import_map.json present + pinned; no floating @N supabase-js imports.');
    exit(0);
  }
  stderr.writeln('$tag FAIL:');
  for (final v in violations.take(20)) {
    stderr.writeln('  - $v');
  }
  if (violations.length > 20) stderr.writeln('  ... and ${violations.length - 20} more');
  exit(warnOnly ? 0 : 1);
}
