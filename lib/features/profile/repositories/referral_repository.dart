import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

/// Outcome of a `redeem-referral` Edge Function call.
///
/// `success` is `true` only when the server returned HTTP 200 with no
/// `error` field. `errorMessage` is the server-supplied user-facing copy
/// when present, or a generic fallback otherwise.
class RedemptionResult {
  final bool success;
  final String? errorMessage;
  final bool alreadyRedeemed;

  const RedemptionResult({
    required this.success,
    this.errorMessage,
    this.alreadyRedeemed = false,
  });

  const RedemptionResult.ok({this.alreadyRedeemed = false})
      : success = true,
        errorMessage = null;

  const RedemptionResult.failure(this.errorMessage)
      : success = false,
        alreadyRedeemed = false;
}

/// Referral repository — wraps all direct Supabase calls related to
/// referral_redemptions table reads + redeem-referral Edge Function
/// invocations. Created 2026-05-21 (audit A5) to satisfy CLAUDE.md
/// rule #4 ("no Supabase from widgets / providers").
///
/// All methods are network-only reads/invokes and are safe to call
/// concurrently — no shared mutable state.
class ReferralRepository {
  ReferralRepository._();
  static final ReferralRepository instance = ReferralRepository._();

  /// Returns `true` when [userId] already has a row in
  /// `referral_redemptions` (i.e. the 7-day welcome trial was claimed).
  ///
  /// Returns `false` on either "no row" or any network/transport
  /// failure — eligibility is non-critical and silently degrades to
  /// "not redeemed" (matches the pre-A5 inline behaviour). Failures
  /// are telemetered through [ErrorTelemetry.recordNonFatal] so silent
  /// regressions still leave a server-side trail.
  Future<bool> hasRedeemed(String userId) async {
    try {
      final row = await SupabaseService.instance.client
          .from('referral_redemptions')
          .select('id')
          .eq('referee_id', userId)
          .maybeSingle();
      return row != null;
    } catch (e, stack) {
      // Non-fatal — assume not redeemed if query fails. Fire-and-forget
      // telemetry (ErrorTelemetry.recordNonFatal is safe to drop).
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        stack,
        reason: 'referral_repository_has_redeemed',
        extra: {'user_id': userId},
      ));
      return false;
    }
  }

  /// Invokes the `redeem-referral` Edge Function with [code].
  ///
  /// Returns a [RedemptionResult]:
  ///   - `success: true` when the function returns HTTP 200 with no
  ///     error field (covers both fresh redeem + 23505 race fallback
  ///     where `alreadyRedeemed: true`).
  ///   - `success: false` with the server-supplied `error` message
  ///     when the function returns a 4xx/5xx OR a 200 body with an
  ///     `error` field.
  ///   - `success: false` with a generic "Network error" message on
  ///     any transport-level failure.
  ///
  /// Caller is responsible for any post-success side effects
  /// (e.g. `SubscriptionService.verifyFromServer()`).
  Future<RedemptionResult> redeem(String code) async {
    try {
      // §2.31: callFunction refreshes the JWT before the authed invoke.
      final response = await SupabaseService.instance.callFunction(
        'redeem-referral',
        body: {'code': code},
      );
      final body = response.data as Map?;
      if (response.status == 200) {
        // Server returns either { ok:true, ... } or { error: ... }.
        final errorMsg = body?['error'] as String?;
        if (errorMsg != null) {
          return RedemptionResult.failure(errorMsg);
        }
        final alreadyRedeemed =
            body?['alreadyRedeemed'] == true || body?['already_redeemed'] == true;
        return RedemptionResult.ok(alreadyRedeemed: alreadyRedeemed);
      }
      final errorMsg = (body?['error'] as String?) ??
          'Could not apply that code. Please try again.';
      return RedemptionResult.failure(errorMsg);
    } on FunctionException catch (e, stack) {
      // supabase_flutter THROWS FunctionException on any non-2xx, so the EF's 4xx
      // validation responses (unrecognized / expired / self-referral / already-
      // redeemed / not-a-new-recruit) never reach the status==200 branch above —
      // they land HERE. Surface the SERVER's user-facing copy (details['error'])
      // instead of a generic "Network error" that hides WHY the code failed.
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        stack,
        reason: 'referral_repository_redeem',
        extra: {'status': e.status.toString()},
      ));
      final details = e.details;
      final serverMsg = (details is Map) ? details['error'] as String? : null;
      return RedemptionResult.failure(
          serverMsg ?? 'Could not apply that code. Please try again.');
    } catch (e, stack) {
      // True transport failure (no HTTP response).
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        stack,
        reason: 'referral_repository_redeem',
        extra: {'code_format': code.length.toString()},
      ));
      return const RedemptionResult.failure(
          'Network error. Try again in a moment.');
    }
  }
}
