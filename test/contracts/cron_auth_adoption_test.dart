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
  // Added 2026-07-26 (diagnose c3f8a1). Both were verify_jwt=true and so fell
  // outside this list's stated scope; the CRON_SECRET migration flips both to
  // verify_jwt=false, putting them squarely in scope.
  //
  // compute-coach-signals is the sharper case: it shipped with NO auth gate of
  // any kind, relying entirely on verify_jwt=true — which accepts ANY
  // project-signed JWT, including the anon key compiled into every APK. Any
  // app user could invoke it and drive up to 5000 RPC round-trips. Exactly the
  // F44 shape described below, and it stayed invisible for the same reason:
  // this list did not cover it.
  'compute-admin-metrics-daily',
  'compute-coach-signals',
  // Added 2026-07-26 (Hermes L23/L24, diagnose c3f8a1). weekly-recalc shipped
  // verify_jwt=false with NO auth gate at all while creating a service-role
  // client — any unauthenticated POST drove a full-fleet recalculation.
  //
  // It escaped every existing guard: nothing schedules it (zero cron.job rows,
  // so the cron registry never saw it) and its client constant
  // `weeklyRecalcFunction` is declared but never invoked (so no call-site grep
  // saw it either). It was ALSO already listed in _wiredCronFunctions in
  // cron_telemetry_adoption_test.dart — the two hand-maintained lists
  // disagreeing about whether it is a cron function is precisely what let it
  // sit ungated. Listing it here makes the gate a real contract for it.
  'weekly-recalc',
];

// Postgres-TRIGGER-dispatched verify_jwt=false Edge Functions (invoked via
// pg_net from a trigger, NOT pg_cron — so they are absent from `cron.job` and
// the SELECT above misses them). They are EQUALLY exposed: an unauthenticated
// POST drives the same privileged fan-out (Gemini cost + push + DB writes).
// F44 (audit-2026-06-07): proactive-coach-promotion shipped verify_jwt=false
// with NO auth gate precisely because this list did not exist — the adoption
// gate's pg_cron-only scope never required it. Adding it here makes the gate
// the regression guard for F44.
const _triggerDispatchedFunctions = <String>[
  'proactive-coach-promotion', // trg_dispatch_proactive_coach_promotion (migrations 073 → 078)
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

    for (final fn in [..._cronInvokedFunctions, ..._triggerDispatchedFunctions]) {
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
        // NB `[^)]*` (the original) could never match the multi-line form
        //     createClient(
        //       Deno.env.get("SUPABASE_URL")!,
        //       Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        //     )
        // because the `)` closing the first Deno.env.get terminates the class.
        // The gate-before-service-role-client assertion therefore silently
        // no-opped for every function written that way. Non-greedy [\s\S] with
        // a bound fixes it without risking a runaway match. (c3f8a1, 2026-07-26)
        final svcRoleClientRegex = RegExp(
          r'createClient\s*\([\s\S]{0,240}?SUPABASE_SERVICE_ROLE_KEY',
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
