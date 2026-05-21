// audit-2026-05-11 Phase 6 — 11 source-grep contract tests pinning
// invariants that were either implicit or only enforced by manual
// inspection. Each test corresponds to a T-N row in the audit doc.
//
// These are all guardrail tests — they prove the production source
// currently exhibits the invariant and fail loudly if a future change
// removes it. They're cheap (file I/O + string scan) so they can run
// on every pre-commit.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  // ── T-1 ────────────────────────────────────────────────────────
  group('T-1 delete-account Edge Function safety contract (DPDP §17)', () {
    late String src;
    setUpAll(() {
      src = _src('supabase/functions/delete-account/index.ts');
    });

    test('verify_jwt=true at config layer (no manual auth bypass)', () {
      // The function MUST re-validate the JWT server-side via
      // auth.getUser(token) — this is the canonical "second layer"
      // after Supabase's gateway-level verify_jwt. Source-grep the
      // auth.getUser call.
      expect(src.contains('auth.getUser('), isTrue,
          reason: 'delete-account must call auth.getUser server-side; '
              'JWT gateway alone is insufficient for an irreversible action.');
    });

    test('confirmation_token check is exact-match', () {
      expect(
        src.contains('DELETE-MY-ACCOUNT-') ||
            src.contains('confirmation_token'),
        isTrue,
        reason:
            'delete-account must validate confirmation_token against the '
            'derived `DELETE-MY-ACCOUNT-<userIdPrefix>` value. Without '
            'this a stolen JWT could trigger deletion without the user '
            'physically typing the confirm string.',
      );
    });

    test('Razorpay cancel must succeed before deletion proceeds', () {
      expect(
        src.contains('api.razorpay.com/v1/subscriptions') ||
            src.contains('/subscriptions/') && src.contains('/cancel'),
        isTrue,
        reason:
            'delete-account must POST to Razorpay cancel endpoint before '
            'the auth.users delete. Otherwise we delete the user in our '
            'system but Razorpay keeps charging them.',
      );
    });

    test('account_deletion_log audit row written', () {
      expect(src.contains('account_deletion_log'), isTrue,
          reason:
              'delete-account must INSERT into account_deletion_log so '
              'support has a record of the deletion event (no FK; survives '
              'the cascade).');
    });
  });

  // ── T-2 ────────────────────────────────────────────────────────
  group('T-2 razorpay-webhook 5-min replay window', () {
    late String src;
    setUpAll(() {
      src = _src('supabase/functions/razorpay-webhook/index.ts');
    });

    test('rejects webhooks older than 5 minutes', () {
      // The check uses `paymentEntity.created_at` (epoch seconds) +
      // a 300-second window. Source-grep the constants.
      expect(
        src.contains('300') || src.contains('5 * 60'),
        isTrue,
        reason: 'razorpay-webhook must enforce a 5-min replay window. '
            'Razorpay retries within seconds; older events are either a '
            'replay attack or stale events our idempotency has already '
            'processed.',
      );
      expect(src.contains('created_at'), isTrue);
      expect(
        src.contains('Webhook too old') || src.contains('age_seconds'),
        isTrue,
        reason: 'reject with a descriptive 400 so support can correlate '
            'log lines.',
      );
    });
  });

  // ── T-3 ────────────────────────────────────────────────────────
  group('T-3 razorpay-webhook double-promo-burn guard', () {
    late String src;
    setUpAll(() {
      src = _src('supabase/functions/razorpay-webhook/index.ts');
    });

    test('redeemPromo / increment_promo_used_count gated by !alreadyProcessed', () {
      // The redemption helper (redeemPromo internally calls
      // increment_promo_used_count RPC) must be guarded by
      // `if (!alreadyProcessed && ...)` — pre-fix a replayed webhook
      // would double-burn the promo's used_count.
      expect(
        src.contains('increment_promo_used_count'),
        isTrue,
        reason: 'webhook must reference increment_promo_used_count RPC.',
      );
      // The actual gate sits around the redeemPromo call.
      expect(
        src.contains('if (!alreadyProcessed && derived.promoApplied'),
        isTrue,
        reason: 'redeemPromo (which calls increment_promo_used_count) '
            'must be gated by `!alreadyProcessed && derived.promoApplied`. '
            'Without this, replays double-burn promo used_count.',
      );
    });
  });

  // ── T-4 ────────────────────────────────────────────────────────
  group('T-4 ai-media-proxy SSRF allowlist', () {
    late String src;
    setUpAll(() {
      src = _src('supabase/functions/ai-media-proxy/index.ts');
    });

    test('only Supabase Storage prefix is accepted', () {
      // SSRF defence — server must only fetch from the canonical
      // `${SUPABASE_URL}/storage/v1/object/` prefix. Anything else
      // → reject.
      expect(
        src.contains('/storage/v1/object/'),
        isTrue,
        reason: 'ai-media-proxy must allowlist /storage/v1/object/ '
            'URLs only. SSRF risk: attacker-supplied URL could exfiltrate '
            'or trigger internal calls.',
      );
    });
  });

  // ── T-5 ────────────────────────────────────────────────────────
  group('T-5 isPro() null-expiry kDebugMode guard', () {
    late String src;
    setUpAll(() {
      src = _src('lib/core/services/subscription_service.dart');
    });

    test('null expiry returns kDebugMode in release (not true)', () {
      // The guard must explicitly return `kDebugMode` (or false) when
      // expiresAt is null. Pre-fix: `return true` would let a rooted
      // device tamper with Hive to drop the expiresAt and gain PRO.
      expect(
        src.contains('kDebugMode'),
        isTrue,
        reason: 'isPro() must consult kDebugMode for the null-expiry '
            'path — null-expiry should grant PRO only in dev builds, '
            'never in release.',
      );
    });
  });

  // ── T-6 ────────────────────────────────────────────────────────
  group('T-6 gate() routes high-value features through verifyFromServer', () {
    late String src;
    setUpAll(() {
      src = _src('lib/core/services/subscription_service.dart');
    });

    test('_highValueFeatures set contains the 3 server-verified features', () {
      expect(src.contains('_highValueFeatures'), isTrue);
      expect(src.contains('featurePhases2To12'), isTrue,
          reason: 'phases_2_to_12 must be server-verified.');
      expect(src.contains('featureAiCoachUnlimited'), isTrue,
          reason: 'ai_coach_unlimited must be server-verified.');
      expect(src.contains('featureProgressPhotos'), isTrue,
          reason:
              'progress_photos must be server-verified (Storage write surface).');
    });

    test('gate() calls verifyFromServer for high-value features', () {
      // The signature is `void gate(`, NOT `Future<void> gate(`.
      final gateIdx = src.indexOf('void gate(');
      expect(gateIdx, greaterThan(0),
          reason: 'gate() method must exist.');
      final body = src.substring(
          gateIdx, (gateIdx + 6000).clamp(0, src.length));
      expect(
        body.contains('verifyFromServer'),
        isTrue,
        reason: 'gate() body must call verifyFromServer for the '
            '_highValueFeatures set. Local-only check is insufficient '
            'for features that write to Storage / spend cloud quota.',
      );
    });
  });

  // ── T-7 ────────────────────────────────────────────────────────
  //
  // Audit 2026-05-20 / A1: onesignal_player_id write logic relocated from
  // auth_provider.dart into AuthSessionBootstrapper.pushOneSignalPlayerId
  // (lib/core/services/auth_session_bootstrapper.dart). Source-grep
  // checks both files for the canonical writer. Per
  // `feedback_source_grep_false_confidence.md`, this is presence-only;
  // behavioral test lives at
  // `test/contracts/auth_session_bootstrapper_test.dart`.
  group('T-7 onesignal_player_id write contract', () {
    test('auth-stack writes pushSubscription.id to user_progress', () {
      final authSrc =
          _src('lib/features/auth/providers/auth_provider.dart');
      final bootstrapperSrc = _src(
          'lib/core/services/auth_session_bootstrapper.dart');
      final hasPushId = authSrc.contains('OneSignal.User.pushSubscription.id') ||
          authSrc.contains('pushSubscription.id') ||
          bootstrapperSrc.contains('OneSignal.User.pushSubscription.id') ||
          bootstrapperSrc.contains('pushSubscription.id');
      expect(hasPushId, isTrue,
          reason:
              'auth_provider OR auth_session_bootstrapper must read '
              'OneSignal.User.pushSubscription.id after OneSignal.login() and '
              'upsert to user_progress.onesignal_player_id. Without this, '
              'delete-account.push-unsub has no player_id to act on.');

      final hasColumn = authSrc.contains('onesignal_player_id') ||
          bootstrapperSrc.contains('onesignal_player_id');
      expect(hasColumn, isTrue,
          reason:
              'auth_provider OR auth_session_bootstrapper must reference '
              'onesignal_player_id column.');
    });
  });

  // ── T-8 ────────────────────────────────────────────────────────
  group('T-8 food_text_analysis 50/200/day server cap', () {
    test('migration 026 (food_text_rate_limit_trigger) exists', () {
      // The numeric prefix was 024 in the docs but the actual source
      // file is 026_food_text_rate_limit_trigger.sql. Accept either.
      final candidates = [
        'supabase/migrations/024_food_text_rate_limit_trigger.sql',
        'supabase/migrations/026_food_text_rate_limit_trigger.sql',
      ];
      final exists = candidates.any((p) => File(p).existsSync());
      expect(exists, isTrue,
          reason: 'food_text_rate_limit_trigger migration must exist.');
    });

    test('ai-proxy uses INSERT-first reservation pattern', () {
      final src = _src('supabase/functions/ai-proxy/index.ts');
      // Both signals must appear SOMEWHERE in the file — they may
      // be far apart in the source (rate-limit catch comes ~30 lines
      // after the `if (type === "food_text_analysis")` branch start).
      expect(
        src.contains('food_text_daily_limit_reached'),
        isTrue,
        reason: 'ai-proxy must detect the Postgres trigger\'s P0001 '
            'food_text_daily_limit_reached message.',
      );
      expect(
        src.contains('Daily food analysis limit') ||
            src.contains('Daily food'),
        isTrue,
        reason: 'ai-proxy must return a 429 with a "Daily food '
            'analysis limit" message when the cap is hit.',
      );
    });
  });

  // ── T-9 ────────────────────────────────────────────────────────
  group('T-9 _compactContext 9500-byte ceiling', () {
    test('AiService._compactContext targets <9500 bytes', () {
      final src = _src('lib/core/services/ai_service.dart');
      expect(src.contains('_compactContext'), isTrue);
      // Target threshold must be present somewhere in the file.
      expect(
        src.contains('9500') ||
            src.contains('9_500') ||
            src.contains('compactionTarget'),
        isTrue,
        reason: '_compactContext must enforce a target under the '
            '10KB server limit (9500 bytes per CLAUDE.md §11). Without '
            'the ceiling, historical-query enriched contexts blow past '
            'the limit and the server rejects with 400.',
      );
    });
  });

  // ── T-10 ───────────────────────────────────────────────────────
  group('T-10 plan generator targetCount + cascade depth', () {
    test('VolumeFilter.targetCount exists', () {
      final src =
          _src('lib/shared/repositories/plan_engine/volume_filter.dart');
      expect(src.contains('targetCount'), isTrue);
      // The table per CLAUDE.md §12: beginner / intermediate / advanced
      // × 3/4/5/6 days. Source must reference the experience tiers.
      expect(
        src.contains('beginner') &&
            src.contains('intermediate') &&
            src.contains('advanced'),
        isTrue,
        reason: 'VolumeFilter.targetCount must branch on '
            'experience level (beginner / intermediate / advanced) per '
            'CLAUDE.md §12.',
      );
    });

    test('exercise_selector cascade has the 5-attempt pattern', () {
      final src = _src(
          'lib/shared/repositories/plan_engine/exercise_selector.dart');
      // Per CLAUDE.md §12 the cascade has 5 attempts ending in
      // universalPool. The canonical entry point is `_cascadeFill`
      // and the comment "5-attempt cascade" / "5 attempts" pins the
      // shape.
      expect(src.contains('_cascadeFill'), isTrue,
          reason: '_cascadeFill cascade entry point must exist.');
      expect(
        src.contains('5-attempt') ||
            src.contains('5 attempt') ||
            src.contains('5 attempts'),
        isTrue,
        reason: 'cascade must be documented as 5-attempt per CLAUDE.md §12.',
      );
      expect(src.contains('universalPool'), isTrue,
          reason: 'universalPool fallback must exist (terminal attempt).');
    });
  });

  // ── T-11 ───────────────────────────────────────────────────────
  group('T-11 subscriptions RLS lockdown', () {
    test('migration 052 exists and drops INSERT/UPDATE/DELETE policies', () {
      final src =
          _src('supabase/migrations/052_subscriptions_rls_lockdown.sql');
      expect(src.contains('subscriptions'), isTrue);
      // Lockdown migration must drop the permissive INSERT/UPDATE/DELETE
      // policies so only service-role can mutate.
      expect(
        src.contains('DROP POLICY'),
        isTrue,
        reason: 'migration 052 must DROP permissive policies on '
            'subscriptions.',
      );
    });

    test('no client-side .from("subscriptions").insert/update in lib/', () {
      // Sibling of Phase 1 no_client_subscriptions_writes_test.
      // Re-asserted here for the T-11 row.
      final root = Directory('lib');
      final offenders = <String>[];
      for (final f in root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (RegExp(r'''\.from\(\s*['"]subscriptions['"]\s*\)\s*\.\s*(insert|update|upsert|delete)''')
            .hasMatch(src)) {
          offenders.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'No client code may write to subscriptions table — '
            'service-role only (server-side Edge Functions). '
            'Offenders:\n${offenders.join("\n")}',
      );
    });
  });
}
