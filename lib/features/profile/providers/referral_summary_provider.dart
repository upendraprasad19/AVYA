import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/referral_flags.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/models/referrer_summary.dart';
import 'package:icanbefitter/features/profile/repositories/referral_repository.dart';
import 'package:icanbefitter/features/profile/services/referral_credit_notice_rules.dart';

/// The user-scoped Hive scalar behind the credit notice: the lifetime
/// `days_earned` total the user has already been told about (or silently
/// baselined to). Registered in `UserConfigMigrator.userScopedKeys`.
const String kReferralCreditSeenKey = 'referral_credit_seen_days';

/// Minimum gap between two app-resume checks of the credit notice.
const Duration kReferralNoticeResumeThrottle = Duration(hours: 6);

typedef ReferrerSummaryCall = Future<ReferrerSummary?> Function();

/// ONE in-flight `referrer_summary()` call per account, shared by every
/// trigger (the counters block, Home mount, resume, restore tick, the sheet).
/// Keyed by the auth token so account B never joins account A's call.
class ReferrerSummaryGate {
  ReferrerSummaryGate._();

  static final Map<String, Future<ReferrerSummary?>> _inflight = {};

  static Future<ReferrerSummary?> fetch(
    String token, {
    ReferrerSummaryCall? call,
  }) {
    final running = _inflight[token];
    if (running != null) return running;
    final started = (call ?? ReferralRepository.instance.referrerSummary)();
    _inflight[token] = started;
    unawaited(started.then<void>((_) {
      if (identical(_inflight[token], started)) _inflight.remove(token);
    }, onError: (Object _) {
      if (identical(_inflight[token], started)) _inflight.remove(token);
    }));
    return started;
  }

  static void resetForTest() => _inflight.clear();
}

/// The referrer's aggregates for the invite sheet's counters block. `null` =
/// unknown (also: anonymous, switched off); the block hides itself.
final referrerSummaryProvider =
    FutureProvider.autoDispose<ReferrerSummary?>((ref) async {
  final token = ref.watch(authUserIdTokenProvider); // c4055a
  if (token == '<anon>' || ReferralFlags.creditNoticeDisabled) return null;
  final summary = await ReferrerSummaryGate.fetch(token);
  // A summary that completes after an account swap is never handed to the new
  // account (Riverpod also discards a stale future; this is the explicit guard).
  if (!ref.mounted || ref.read(authUserIdTokenProvider) != token) return null;
  return summary;
});

/// A pending "you earned N PRO days" announcement.
class ReferralCreditNotice {
  /// Days to announce (the difference since the last total the user saw).
  final int days;

  /// The lifetime total to store once the user dismisses or taps through.
  final int totalDaysEarned;

  const ReferralCreditNotice({required this.days, required this.totalDaysEarned});

  @override
  bool operator ==(Object other) =>
      other is ReferralCreditNotice &&
      other.days == days &&
      other.totalDaysEarned == totalDaysEarned;

  @override
  int get hashCode => Object.hash(days, totalDaysEarned);
}

/// Decides, per account, whether to announce a referral credit in-app
/// (founder decision 2026-10-16: in-app on next open, no push; first run
/// silent). `build()` is total and yields `null` for anonymous / switched off.
///
/// Per-account state (the resume stamp and the "verified for N" memory) is
/// reset in [build], which re-runs on every auth change; every `await` below
/// captures the token first and drops its result if the token changed.
class ReferralCreditNoticeNotifier extends Notifier<ReferralCreditNotice?> {
  DateTime? _lastResumeCheck;
  int? _verifiedForTotal;

  /// The forced entitlement verify for [_verifiedForTotal]. EVERY concurrent
  /// check awaits this same future, so no trigger can show the card before the
  /// PRO days it announces are verified (B-pass seat A, finding 1).
  Future<void>? _verifying;

  @override
  ReferralCreditNotice? build() {
    ref.watch(authUserIdTokenProvider); // c4055a
    _lastResumeCheck = null;
    _verifiedForTotal = null;
    _verifying = null;
    return null;
  }

  bool _sameAccount(String token) {
    try {
      return ref.mounted && ref.read(authUserIdTokenProvider) == token;
    } catch (_) {
      return false;
    }
  }

  /// Runs one evaluation. [fromResume] applies the 6-hour throttle. Safe to
  /// call from any trigger concurrently: the network call is single-flight.
  Future<void> check({
    bool fromResume = false,
    ReferrerSummaryCall? callForTest,
    DateTime? nowForTest,
  }) async {
    final token = ref.read(authUserIdTokenProvider);
    if (token == '<anon>' || ReferralFlags.creditNoticeDisabled) return;
    final now = nowForTest ?? DateTime.now();
    if (fromResume) {
      final last = _lastResumeCheck;
      if (last != null && now.difference(last) < kReferralNoticeResumeThrottle) {
        return;
      }
    }
    final summary = await ReferrerSummaryGate.fetch(token, call: callForTest);
    if (summary == null || !_sameAccount(token)) return;
    // Stamped only after a READ that answered: a resume that found the phone
    // offline must not suppress the next six hours of resume checks.
    if (fromResume) _lastResumeCheck = now;

    final stored = MigratedKey.read<dynamic>(kReferralCreditSeenKey);
    final decision = creditNoticeFor(
      daysEarned: summary.daysEarned,
      seen: stored is int ? stored : null,
    );

    final silent = decision.storeSeenSilently;
    if (silent != null) {
      await _writeSeen(token, silent);
      return;
    }
    if (decision.announceDays <= 0) return;

    // Verify the entitlement ONCE per detected total, so the notice never
    // precedes the PRO days it announces and a repeated trigger never refetches.
    if (_verifiedForTotal != summary.daysEarned) {
      _verifiedForTotal = summary.daysEarned;
      _verifying = _forceVerify();
    }
    await _verifying;
    if (!_sameAccount(token)) return;

    // Re-decide after the wait: a dismissal (or a silent re-baseline) that
    // landed while the verify was in flight must not be overwritten by this
    // call's stale decision.
    final storedNow = MigratedKey.read<dynamic>(kReferralCreditSeenKey);
    final again = creditNoticeFor(
      daysEarned: summary.daysEarned,
      seen: storedNow is int ? storedNow : null,
    );
    if (again.announceDays <= 0) return;
    state = ReferralCreditNotice(
      days: again.announceDays,
      totalDaysEarned: summary.daysEarned,
    );
  }

  Future<void> _forceVerify() async {
    try {
      await ref.read(subscriptionServiceProvider).verifyFromServer(force: true);
    } catch (_) {
      // The notice is still true; the entitlement catches up on its own path.
    }
  }

  /// The close affordance, or a tap through to the invite sheet: stores the
  /// total the user has now seen and hides the card.
  Future<void> dismiss() async {
    final shown = state;
    if (shown == null) return;
    final token = ref.read(authUserIdTokenProvider);
    state = null;
    await _writeSeen(token, shown.totalDaysEarned);
  }

  Future<void> _writeSeen(String token, int total) async {
    // Without a session owner the key would land in the SHARED configBox.
    if (HiveUserSession.currentOwnerFullId == null) return;
    if (!_sameAccount(token)) return;
    await MigratedKey.write(kReferralCreditSeenKey, total);
  }
}

final referralCreditNoticeProvider =
    NotifierProvider<ReferralCreditNoticeNotifier, ReferralCreditNotice?>(
        ReferralCreditNoticeNotifier.new);
