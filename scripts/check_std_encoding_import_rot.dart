// scripts/check_std_encoding_import_rot.dart
//
// Gate (prod incident 2026-06-08, diagnose d4c8e1): ban importing the REMOVED
// bare `encode` / `decode` named exports from deno.land/std `encoding/hex.ts`
// or `encoding/base64.ts` at std >= 0.210.0. Those exports were deprecated at
// 0.203 and REMOVED at 0.210 (replaced by encodeHex/decodeHex/encodeBase64/
// decodeBase64). Importing them from a >=0.210 module throws "no named export"
// at module load -> the Edge Function fails to BOOT (HTTP 503 BOOT_ERROR).
//
// Root cause this guards: commit ec01b46 (2026-05-20) bumped razorpay-webhook,
// verify-payment, ai-media-proxy, create-razorpay-order from std@0.177.0 ->
// 0.224.0 while keeping `import { encode as ... }`. The functions kept serving
// their pre-bump bundles, so the dead import stayed LATENT until the 2026-06-08
// audit deploy — when razorpay-webhook (the live payment webhook) was the first
// redeploy and went DOWN with a boot error. Deploy is the only thing that
// surfaces this; no unit test or `flutter analyze` sees a Deno import.
//
// Fix forward: encodeHex/encodeBase64 (std >= 0.210) OR pin the encoding import
// to std <= 0.208 (where `encode` still exists).
//
// Exit 0 = pass; Exit 1 = a dead encode/decode import from std >= 0.210.

import 'dart:io';

/// True if std [version] (e.g. "0.224.0") is >= 0.210.0, where the bare
/// `encode`/`decode` exports were removed from encoding/hex + base64.
bool _removedEncode(String version) {
  final parts = version.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  if (parts[0] > 0) return true; // 1.x and beyond
  return parts[1] >= 210;
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final dir = Directory('supabase/functions');
  if (!dir.existsSync()) {
    stdout.writeln('[Gate std-encode-rot] SKIP: supabase/functions not present.');
    exit(0);
  }
  final re = RegExp(
    r'''import\s*\{([^}]*)\}\s*from\s*['"]https://deno\.land/std@([0-9.]+)/encoding/(hex|base64)\.ts['"]''',
  );
  final violations = <String>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.ts')) continue;
    final norm = e.path.replaceAll('\\', '/');
    final src = e.readAsStringSync();
    for (final m in re.allMatches(src)) {
      final names = m.group(1)!;
      final version = m.group(2)!;
      final mod = m.group(3)!;
      // Dead exports are EXACTLY `encode` / `decode` (NOT encodeHex,
      // encodeBase64, decodeHex, decodeBase64). Strip any `as alias` first.
      final tokens = names
          .split(',')
          .map((t) => t.trim().split(RegExp(r'\s+as\s+')).first.trim());
      final dead = tokens.any((t) => t == 'encode' || t == 'decode');
      if (dead && _removedEncode(version)) {
        final lineNum = src.substring(0, m.start).split('\n').length;
        violations.add(
            '$norm:$lineNum — {$names} from std@$version/encoding/$mod '
            '(encode/decode REMOVED at std 0.210 -> BOOT_ERROR on deploy)');
      }
    }
  }
  if (violations.isEmpty) {
    stdout.writeln('[Gate std-encode-rot] PASS: no dead std encode/decode imports.');
    exit(0);
  }
  final tag = warnOnly ? '[Gate std-encode-rot WARN]' : '[Gate std-encode-rot FAIL]';
  stderr.writeln('$tag: ${violations.length} dead std encode/decode import(s):');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: encodeHex/encodeBase64 (std >= 0.210) OR pin the encoding '
      'import to std <= 0.208. See diagnose d4c8e1 (2026-06-08 razorpay-webhook '
      'BOOT_ERROR incident).');
  exit(warnOnly ? 0 : 1);
}
