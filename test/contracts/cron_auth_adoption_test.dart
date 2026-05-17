// Contract test — every cron-invoked Edge Function MUST gate the request
// with `isAuthorizedCronCall(req)` from `_shared/cron_auth.ts` BEFORE
// any privileged work (service-role client creation, telemetry write,
// AI calls, push fan-out, database mutations).
//
// Closes OI-31 (audit-2026-05-17 Hermes F6). OI-21 closure earlier today
// wired telemetry (logCronStart / logCronEnd) into 14 cron functions but
// 3 of them still lacked the auth gate — public POSTs could trigger
// expensive fan-outs (morning-alert: AI generation + push to every user;
// rolling-context: Gemini summarization across all users with >50 msgs;
// expiry-reminder: push to every PRO expiring within 3 days).
//
// Lens L4 in `docs/audit/LENS_REGISTRY.md` (now split: L4a auth + L4b
// telemetry).
//
// **Scope:** active pg_cron-invoked verify_jwt=false Edge Functions.
// verify_jwt=true functions accept caller JWTs and have their own
// per-function auth (`auth.getUser()`); cron functions that share
// verify_jwt=true also accept the cron's service-role JWT — separate
// concern, tracked elsewhere.
//
// When a new cron Edge Function ships, add its slug to
// `_cronInvokedFunctions` and ensure its `index.ts` imports + calls
// `isAuthorizedCronCall` per the canonical pattern in clean-orphan-media.

import 'dart:io';
import 'package:test/test.dart';

// Cron-invoked verify_jwt=false Edge Functions as of 2026-05-17.
// Authoritative source: SELECT cron.job WHERE active AND fn_slug IS NOT NULL.
const _cronInvokedFunctions = <String>[
  'clean-orphan-media',
  'evaluate-rank-promotions',
  'expiry-reminder',
  'i-see-you-callout',
  'morning-alert',
  'plateau-alert',
  'pr-detection',
  'promote-community-item',
  'protein-gap-alert',
  're-engagement',
  'rolling-context',
  'streak-guardian',
  'weekly-recap-ready',
  'workout-window-closing',
];

const _functionsDir = 'supabase/functions';

void main() {
  group('cron_auth adoption contract', () {
    test('_shared/cron_auth.ts exists with isAuthorizedCronCall export', () {
      final helper = File('$_functionsDir/_shared/cron_auth.ts');
      expect(helper.existsSync(), isTrue,
          reason: 'expected $_functionsDir/_shared/cron_auth.ts');
      final src = helper.readAsStringSync();
      expect(
        src.contains('export') &&
            src.contains('function isAuthorizedCronCall'),
        isTrue,
        reason:
            'expected exported function `isAuthorizedCronCall` in cron_auth.ts',
      );
    });

    for (final fn in _cronInvokedFunctions) {
      test('$fn imports isAuthorizedCronCall from _shared/cron_auth.ts', () {
        final path = '$_functionsDir/$fn/index.ts';
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'expected $path');
        final src = file.readAsStringSync();
        final importRegex = RegExp(
          r'import\s+\{[^}]*isAuthorizedCronCall[^}]*\}\s+from\s+["' "'" r']\.\./_shared/cron_auth\.ts["' "'" r']',
        );
        expect(
          importRegex.hasMatch(src),
          isTrue,
          reason:
              '$fn missing import `isAuthorizedCronCall` from "../_shared/cron_auth.ts"',
        );
      });

      test('$fn calls await isAuthorizedCronCall(req) before privileged work',
          () {
        final path = '$_functionsDir/$fn/index.ts';
        final src = File(path).readAsStringSync();
        // Auth gate must appear in source.
        final callRegex = RegExp(r'await\s+isAuthorizedCronCall\s*\(\s*req\s*\)');
        expect(
          callRegex.hasMatch(src),
          isTrue,
          reason:
              '$fn missing `await isAuthorizedCronCall(req)` call. Canonical '
              'pattern: `if (!await isAuthorizedCronCall(req)) { return 401; }` '
              'right after CORS handling, BEFORE service-role createClient.',
        );

        // The auth gate must come BEFORE the first service-role
        // createClient — otherwise we leak resources to unauthorized callers.
        final callIdx = callRegex.firstMatch(src)!.start;
        final svcRoleClientRegex = RegExp(
          r'createClient\s*\([^)]*SUPABASE_SERVICE_ROLE_KEY',
          multiLine: true,
        );
        final svcClientMatch = svcRoleClientRegex.firstMatch(src);
        if (svcClientMatch != null) {
          expect(
            callIdx < svcClientMatch.start,
            isTrue,
            reason:
                '$fn calls `createClient(SUPABASE_SERVICE_ROLE_KEY)` BEFORE '
                'the auth gate. Move the gate up so unauthorized callers '
                'don\'t spin up a service-role client.',
          );
        }
      });
    }
  });
}
