// test/contracts/security_definer_revoke_migration_test.dart
//
// c9b3e2 — Migration 090 revokes anon/authenticated EXECUTE on SECURITY DEFINER
// functions that were exposed over PostgREST (extend_subscription = free PRO for
// anyone, update_streak_progress = cross-account streak write, etc.). This CI
// source-grep pins the migration's hardening so it can't silently regress in the
// repo; the live behavioral proof is test/sql/security_definer_anon_revoke.sql
// (run via MCP post-apply).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mig = File(
    'supabase/migrations/090_revoke_anon_security_definer_execute.sql',
  ).readAsStringSync();

  String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  final flat = norm(mig);

  group('migration 090 — anon SECURITY DEFINER hardening (c9b3e2)', () {
    test('revokes EXECUTE from anon+authenticated on the service-only functions', () {
      for (final sig in [
        'public.extend_subscription(uuid, integer)',
        'public.redeem_referral_atomic(text, uuid, uuid, integer)',
        'public.increment_promo_used_count(text)',
        'public.auto_approve_community_item()',
        'public.update_user_subscription_status()',
        'public.handle_new_auth_user()',
        'public.rls_auto_enable()',
        'public.cron_call_log_cleanup_7d()',
      ]) {
        expect(
          flat.contains(norm('REVOKE EXECUTE ON FUNCTION $sig FROM anon, authenticated')),
          isTrue,
          reason: 'migration must REVOKE EXECUTE FROM anon, authenticated on $sig',
        );
      }
    });

    test('update_streak_progress: anon revoked + cross-account guard added, '
        'authenticated NOT revoked', () {
      expect(
        flat.contains(norm(
            'REVOKE EXECUTE ON FUNCTION public.update_streak_progress(uuid, bigint, integer, text[], text) FROM anon')),
        isTrue,
        reason: 'anon must be revoked from update_streak_progress',
      );
      // authenticated must be KEPT (self-write path) — so no "FROM anon, authenticated"
      // revoke for this function.
      expect(
        flat.contains(norm(
            'update_streak_progress(uuid, bigint, integer, text[], text) FROM anon, authenticated')),
        isFalse,
        reason: 'authenticated must retain EXECUTE on update_streak_progress',
      );
      expect(
        mig.contains('cross-account streak write blocked'),
        isTrue,
        reason: 'the function body must RAISE on a cross-account write',
      );
      expect(
        flat.contains(norm('IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN')),
        isTrue,
        reason: 'the guard condition must compare p_user_id against auth.uid()',
      );
    });

    test('search_path hardened on the advisor-flagged functions (spot-check)', () {
      for (final fn in [
        'public.match_memories(uuid, vector, integer, double precision)',
        'private.morning_alert_get_service_key()',
        'public.cron_call_log_cleanup_7d()',
      ]) {
        expect(
          flat.contains(norm('ALTER FUNCTION $fn SET search_path =')),
          isTrue,
          reason: 'migration must set a fixed search_path on $fn',
        );
      }
    });

    test('wrapped in a transaction (atomic apply)', () {
      expect(mig.contains('BEGIN;'), isTrue);
      expect(mig.contains('COMMIT;'), isTrue);
    });
  });

  // 090's `REVOKE ... FROM anon, authenticated` were no-ops (EXECUTE is inherited
  // from PUBLIC). Migration 091 is the EFFECTIVE revoke — pin it so the real fix
  // can't regress.
  group('migration 091 — effective REVOKE FROM PUBLIC + GRANT (c9b3e2)', () {
    final mig91 = File(
      'supabase/migrations/091_security_definer_revoke_from_public.sql',
    ).readAsStringSync();
    final flat91 = norm(mig91);

    test('revokes EXECUTE FROM PUBLIC on every previously-exposed function', () {
      for (final sig in [
        'public.extend_subscription(uuid, integer)',
        'public.redeem_referral_atomic(text, uuid, uuid, integer)',
        'public.increment_promo_used_count(text)',
        'public.cron_call_log_cleanup_7d()',
        'public.auto_approve_community_item()',
        'public.update_user_subscription_status()',
        'public.handle_new_auth_user()',
        'public.rls_auto_enable()',
        'public.update_streak_progress(uuid, bigint, integer, text[], text)',
      ]) {
        expect(
          flat91.contains(norm('REVOKE EXECUTE ON FUNCTION $sig FROM PUBLIC')),
          isTrue,
          reason: 'migration 091 must REVOKE EXECUTE FROM PUBLIC on $sig',
        );
      }
    });

    test('re-grants the service-callable functions to service_role', () {
      for (final sig in [
        'public.extend_subscription(uuid, integer)',
        'public.redeem_referral_atomic(text, uuid, uuid, integer)',
        'public.increment_promo_used_count(text)',
      ]) {
        expect(
          flat91.contains(norm('GRANT EXECUTE ON FUNCTION $sig TO service_role')),
          isTrue,
          reason: 'service_role must retain EXECUTE on $sig (Edge Functions)',
        );
      }
    });

    test('update_streak_progress re-granted to authenticated (self-write kept)', () {
      expect(
        flat91.contains(norm(
            'GRANT EXECUTE ON FUNCTION public.update_streak_progress(uuid, bigint, integer, text[], text) TO authenticated, service_role')),
        isTrue,
        reason: 'authenticated keeps EXECUTE on update_streak_progress (guarded)',
      );
    });
  });
}
