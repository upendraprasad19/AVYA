import 'hive_service.dart';

/// Local diagnostic switch for the referrer counters block and the in-app
/// credit notice (unit C, `docs/plans/referral-unit-c-client.md` section 2.3).
///
/// `configBox['disable_referral_credit_notice']`, default false (= on). It is a
/// test/diagnostic seam, NOT a remote kill: no remote-config path exists for
/// it. The real remote off-switch is server-side,
/// `REVOKE EXECUTE ON FUNCTION public.referrer_summary() FROM authenticated`
/// (every client then gets 42501 and hides silently). When true, BOTH surfaces
/// yield nothing and the network read is skipped. An unopened box or missing
/// Hive reads "not disabled".
class ReferralFlags {
  ReferralFlags._();

  static bool get creditNoticeDisabled {
    try {
      final stored =
          HiveService.instance.configBox.get('disable_referral_credit_notice');
      return stored is bool ? stored : false;
    } catch (_) {
      return false;
    }
  }
}
