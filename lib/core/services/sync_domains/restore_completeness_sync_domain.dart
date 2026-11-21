// lib/core/services/sync_domains/restore_completeness_sync_domain.dart
//
// [SyncDomain] wrapper for the restore-completeness part-file surfaces
// (audit 2026-05-20 / A6 — B5 D7-D8 batch).
//
// Wraps `lib/core/services/sync/sync_restore_completeness.dart` via the
// public forwarders on `SyncServiceRestoreCompleteness`. These surfaces
// were the Test #11 Theme-A additions — Hive-only state that vanished
// on reinstall (freezes / inbox / saved diet plan / rank promotions /
// referral codes / redemptions). The cloud columns / tables were added
// in migration 048 + later batches.
//
// Sub-surfaces:
//   - freezes              : syncFreezes              ↔ _restoreFreezes
//   - notifications_inbox  : syncNotificationsInboxEntry (per-entry)
//                              ↔ _restoreNotificationsInbox (bulk)
//   - saved_diet_plan      : syncSavedDietPlan        ↔ _restoreSavedDietPlan
//   - rank_promotions      : (push on RankPromotionRepository) ↔ _restoreRankPromotions
//   - referral_codes       : (push on ReferralRepository)      ↔ _restoreReferralCodes
//   - referral_redemptions : (push on ReferralRepository)      ↔ _restoreReferralRedemptions
//
// Push-side asymmetries are documented on the `restoreOnlyAllowlist`
// in `test/contracts/sync_domain_interface_test.dart` — the push
// counterparts live on dedicated repositories, not on SyncService.
// The wrapper's `push()` therefore covers only the SyncService-owned
// push surfaces (`syncFreezes` + `syncSavedDietPlan`); per-entry
// inbox push happens at NotificationInboxService.record site and is
// NOT a fan-out target.
//
// NOT YET WIRED — `SyncFlags.useDomainFor('restore_completeness')`
// defaults FALSE.

import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class RestoreCompletenessSyncDomain extends SyncDomainBase {
  RestoreCompletenessSyncDomain({SyncService? syncService})
      : _syncService = syncService ?? SyncService.instance;

  final SyncService _syncService;

  @override
  String get name => 'restore_completeness';

  @override
  Future<void> push() async {
    // Bulk fan-out of the SyncService-owned push surfaces with a
    // zero-arg, fire-and-forget contract. Per-entry inbox push and
    // per-save diet plan push (`syncSavedDietPlan(planJson)`) are
    // invoked at the mutation site, NOT in this orchestrator. Rank
    // + referral pushes live on dedicated repositories.
    await _syncService.syncFreezes();
  }

  @override
  Future<void> restore() async {
    // Step-C of restoreFromCloudForUser runs these sequentially per
    // the existing precedent (smaller / faster ops; cancellation
    // between steps must not leave Hive partial). Mirror that here.
    await _syncService.restoreFreezesForSyncDomain();
    await _syncService.restoreNotificationsInboxForSyncDomain();
    await _syncService.restoreSavedDietPlanForSyncDomain();
    await _syncService.restoreRankPromotionsForSyncDomain();
    await _syncService.restoreReferralCodesForSyncDomain();
    await _syncService.restoreReferralRedemptionsForSyncDomain();
  }
}
