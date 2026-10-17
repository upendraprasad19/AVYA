// Contract test — `const supabaseClient = createClient(...)` in
// `razorpay-webhook/index.ts` MUST appear BEFORE the first
// `await supabaseClient.from(...)` usage in the same file.
//
// Closes OI-26 (audit-2026-05-17 Hermes F1). Pre-fix the const lived ~130
// lines after its first use inside the same `serve(async (req) => {...})`
// handler body. Same function body, top-down execution → TDZ →
// `ReferenceError: Cannot access 'supabaseClient' before initialization`
// on every webhook invocation that wasn't an early-return (HMAC fail / age
// fail). Razorpay retried for 24h; users paying never unlocked PRO.
//
// closes-diagnose: see `docs/diagnoses/2026-05-17-oi-26-razorpay-webhook-tdz-*.md`

import 'dart:io';
import 'package:test/test.dart';

const _path = 'supabase/functions/razorpay-webhook/index.ts';

void main() {
  group('razorpay-webhook supabaseClient declaration order', () {
    test('const supabaseClient = createClient appears before first use '
        'INSIDE the serve handler body', () {
      final file = File(_path);
      expect(file.existsSync(), isTrue, reason: 'expected $_path');
      final src = file.readAsStringSync();

      // The TDZ bug is scoped to the serve handler body — module-level
      // helper functions (`derivePlanFromAmount`, `computeExpectedAmount`,
      // `redeemPromoCode`) take `supabaseClient` as a parameter, so their
      // `await supabaseClient.from(...)` calls appear EARLIER in the
      // source but bind to a parameter, not the handler-scope const. We
      // restrict the order check to inside the serve handler.
      final serveStart = RegExp(
        r'serve\s*\(\s*async\s*\(\s*req\s*:\s*Request\s*\)\s*=>\s*\{',
      ).firstMatch(src);
      expect(
        serveStart,
        isNotNull,
        reason: 'expected `serve(async (req: Request) => {` handler entry',
      );
      final handler = src.substring(serveStart!.end);

      final declRegex = RegExp(
        r'const\s+supabaseClient\s*=\s*createClient\s*\(',
        multiLine: true,
      );
      final declMatch = declRegex.firstMatch(handler);
      expect(
        declMatch,
        isNotNull,
        reason:
            'declaration "const supabaseClient = createClient(" not found '
            'inside the serve handler body',
      );
      final declIdx = declMatch!.start;

      // First H-19-style usage inside the handler. Allow newline +
      // indentation between `supabaseClient` and `.from(` — chained
      // PostgREST builders span multiple lines.
      final firstUseRegex = RegExp(
        r'await\s+supabaseClient\s*\.\s*from\s*\(',
        multiLine: true,
      );
      final useMatch = firstUseRegex.firstMatch(handler);
      expect(
        useMatch,
        isNotNull,
        reason:
            'first usage "await supabaseClient.from(" not found inside the '
            'serve handler body (regression: code path was removed?)',
      );
      final firstUseIdx = useMatch!.start;

      expect(
        declIdx < firstUseIdx,
        isTrue,
        reason:
            'TDZ regression: const declaration appears at handler-relative '
            'offset $declIdx but first use is at handler-relative offset '
            '$firstUseIdx. Declaration must come first in source AND execution '
            'order. See OI-26 (audit-2026-05-17 Hermes F1).',
      );
    });

    test('exactly one const supabaseClient declaration (no shadowing)', () {
      final src = File(_path).readAsStringSync();
      final declRegex = RegExp(
        r'const\s+supabaseClient\s*=\s*createClient\s*\(',
        multiLine: true,
      );
      final matches = declRegex.allMatches(src).toList();
      expect(
        matches.length,
        equals(1),
        reason:
            'expected exactly one const supabaseClient = createClient(...) '
            'declaration; found ${matches.length}. Multiple declarations risk '
            'shadowing + the OI-26 fix being silently reverted.',
      );
    });
  });
}
