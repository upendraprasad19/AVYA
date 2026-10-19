import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, FunctionResponse, PostgrestException;

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_retry_controller.dart'
    show httpStatusOfError, isOutageShapedFailure;
import 'package:icanbefitter/features/profile/models/referrer_summary.dart';

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

/// Whether a failed `referrer_summary()` call is an EXPECTED absence rather
/// than a defect worth a `client_errors` row: the function does not exist yet
/// (PGRST202 / HTTP 404, before migration 160), the session lapsed (`28000`,
/// PGRST301, HTTP 401), EXECUTE was revoked (`42501`: the server-side off switch), or
/// the network/backend did not answer at all (the shapes
/// `isOutageShapedFailure` already classifies, including the web ones
/// `ClientException` / `XMLHttpRequest error`). All of these hide the surface
/// silently; before migration 160 every Home session would otherwise write a
/// row, and an offline phone must not flood telemetry.
bool isExpectedReferrerSummaryAbsence(Object error) {
  if (error is PostgrestException) {
    final code = error.code;
    if (code == 'PGRST202' ||
        code == 'PGRST301' ||
        code == '28000' ||
        code == '42501') {
      return true;
    }
  }
  final status = httpStatusOfError(error);
  if (status == 401 || status == 404) return true;
  if (error.toString().contains('ClientException')) return true;
  return isOutageShapedFailure(error);
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

  /// Test seam: replaces the `referrer_summary` RPC. Always null in production.
  @visibleForTesting
  static Future<dynamic> Function()? summaryRpcForTest;

  /// Reads the signed-in user's referrer aggregates (unit C, migration 160).
  ///
  /// ONE call to `public.referrer_summary()`; `null` means UNKNOWN (any throw,
  /// a NULL or a malformed body): the surface hides itself and never shows a
  /// wrong number. Expected absences (function missing, lapsed session,
  /// revoked EXECUTE, offline) return `null` silently; any other failure is
  /// telemetered under `referral_repository_summary`. Deliberate exceptions to
  /// "error states have a retry" (a non-critical decoration, refreshed on the
  /// next trigger) and to Hive-first (cloud-only aggregates with no local
  /// store; nothing blocks on them).
  Future<ReferrerSummary?> referrerSummary() async {
    try {
      final seam = summaryRpcForTest;
      final dynamic raw;
      if (seam != null) {
        raw = await seam();
      } else {
        await SupabaseService.instance.ensureFreshToken();
        raw = await SupabaseService.instance.client
            .rpc('referrer_summary')
            .timeout(const Duration(seconds: 15));
      }
      return ReferrerSummary.tryParse(raw);
    } catch (e, stack) {
      if (!isExpectedReferrerSummaryAbsence(e)) {
        unawaited(ErrorTelemetry.recordNonFatal(
          e,
          stack,
          reason: 'referral_repository_summary',
        ));
      }
      return null;
    }
  }

  /// Test seam: replaces the `redeem-referral` call (the sheets' widget tests
  /// have no Supabase client). Always null in production.
  @visibleForTesting
  static Future<FunctionResponse> Function(String code)? redeemCallForTest;

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
      final seam = redeemCallForTest;
      final response = seam != null
          ? await seam(code)
          : await SupabaseService.instance.callFunction(
              'redeem-referral',
              body: {'code': code},
            );
      final body = response.data as Map?;
      if (response.status == 200) {
        // Server returns either { success:true, ... } or { error: ... }.
        // (Said `ok:true` until 2026-08-16; the EF has always emitted
        // `success` — redeem-referral/index.ts (23505 race + fresh return). Harmless here
        // because this branch keys off `error` and never reads either flag,
        // but a comment naming a field that does not exist is how the next
        // reader writes `body['ok']`.)
        final errorMsg = body?['error'] as String?;
        if (errorMsg != null) {
          return RedemptionResult.failure(errorMsg);
        }
        // Fail CLOSED (unit C B-pass F5): the function sends success:true on
        // every 200 it means as a success (and on the 23505 replay), so a 200
        // without it (a proxy page, an empty body) is not a grant and must not
        // be announced as "+7 days PRO added".
        if (body?['success'] != true) {
          return const RedemptionResult.failure(
              'Could not confirm that code. Please try again.');
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
