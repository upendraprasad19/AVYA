---
bug_id: 9aa2c1
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 7 / Theme B)
status: shipped
symptom: |
  Founder promoted SD2 → LT recently. `RankService.evaluateAndPromote`
  successfully detected the rank change, wrote the `rank_promotions`
  cloud row, updated `user_profile.current_rank_code`, mirrored to
  Hive, and fired the `onStateChanged` callback (which app.dart wires
  to userProfileProvider invalidation so the rank chip refreshes).

  BUT: the founder never saw a celebration. The Plan F F-13
  `PromotionCelebrationScreen` widget exists in full at
  lib/features/profile/screens/promotion_celebration_screen.dart with
  animated insignia paint-on, ceremony text, baseline→today stats,
  share button, 30s auto-dismiss — and ZERO call sites across the
  entire codebase. Built but never wired.
concept: rank_promotion_celebration
sot_registry_entry: rank_promotion_log
writers:
  - { file: lib/core/services/rank_service.dart, method_or_widget: evaluateAndPromote — stamps userBox['pending_promotion_rank_code'] inside the currentCode != qualified.code branch + emits rank_promotion_pending_stamped telemetry, line: 160 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: setPendingPromotionRankCode helper (top-level userBox key, NOT inside the progress map to avoid cloud sync via F-NEW), line: 82 }
readers:
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: _maybeShowPendingPromotion — clears slot then pushes PromotionCelebrationScreen as a fullscreenDialog MaterialPageRoute on initTab + on AppLifecycleState.resumed, line: 138 }
  - { file: lib/features/profile/screens/promotion_celebration_screen.dart, method_or_widget: PromotionCelebrationScreen — pre-existing widget, unchanged this batch, line: 22 }
hive_key_prefix: "n/a — single Hive key `pending_promotion_rank_code`"
hive_key_formula: "userBox.put('pending_promotion_rank_code', rankCode)"
sync_methods: []
restore_methods: []
cloud_table: rank_promotion_log
cloud_columns: []
contract_test_path: test/contracts/promotion_celebration_wiring_test.dart
ist_handling:
  - { file: lib/shared/repositories/user_repository.dart, line: 82, source: "no date-key math — slot stores a rank_code String only" }
provider_invalidations: []
telemetry_op_types:
  success: [rank_promotion_pending_stamped, rank_promotion_celebration_shown]
  failure: [rank_service_pending_promotion_stamp]
cross_account_guard: UserRepository.setPendingPromotionRankCode routes through _hive.userBox which wraps via wrapUserScopedBox; signOut clears all user-scoped boxes so a stamp from user A cannot leak to user B.
forbidden_patterns_checked:
  - "stamping pending_promotion outside the rank-changed branch — would re-fire celebration on every evaluateAndPromote call (every workout completion)."
  - "Storing pending_promotion inside the progress map — would sync to cloud via F-NEW syncProgressNow, requiring a corresponding column."
  - "Clear-after-push pattern — re-firing AppLifecycleState.resumed would double-render the modal."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "user_repository.dart:82 + rank_service.dart:160 + home_screen.dart:138" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "userBox['pending_promotion_rank_code'] new key — top-level, not synced to cloud" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/promotion_celebration_wiring_test.dart — 13 assertions covering UserRepository helpers, RankService stamp + guard + telemetry, HomeScreen observer + lifecycle + clear-before-push + modal push" }
impact_analysis:
  callers_audited:
    - lib/core/services/rank_service.dart (evaluateAndPromote — only writer)
    - lib/features/home/screens/home_screen.dart (only reader)
  callers_updated_in_this_batch:
    - lib/core/services/rank_service.dart (stamp added)
    - lib/features/home/screens/home_screen.dart (observer + handler added)
    - lib/shared/repositories/user_repository.dart (3 helpers added)
  callers_unchanged:
    - lib/features/profile/screens/promotion_celebration_screen.dart (pre-existing widget, no behavioral change)
proposed_fix: |
  Three-layer one-shot Hive flag pattern:

  1. UserRepository helpers (user_repository.dart:82):
     - `_pendingPromotionKey = 'pending_promotion_rank_code'` constant.
     - `getPendingPromotionRankCode() → String?` reader.
     - `setPendingPromotionRankCode(String rankCode) → Future<void>` writer.
     - `clearPendingPromotionRankCode() → Future<void>` clearer.
     All route through `_hive.userBox` (top-level keys, NOT inside the
     progress map — keeps the flag out of cloud sync via F-NEW).

  2. RankService.evaluateAndPromote (rank_service.dart:160) — inside
     the `if (currentCode != qualified.code)` branch, AFTER the
     existing onStateChanged?.call():
     ```dart
     await UserRepository.instance.setPendingPromotionRankCode(qualified.code);
     unawaited(ErrorTelemetry.logEvent('rank_promotion_pending_stamped',
         message: 'rank_code=${qualified.code} prev_code=$currentCode'));
     ```
     try/catch + recordNonFatal on failure (non-fatal — the rank change
     already persisted; we'd just miss this one celebration).

  3. HomeScreen (home_screen.dart:138):
     - Mix in WidgetsBindingObserver. initState adds; dispose removes.
     - didChangeAppLifecycleState catches AppLifecycleState.resumed.
     - initTab fires _maybeShowPendingPromotion on first mount.
     - _maybeShowPendingPromotion reads slot, clears BEFORE push (so a
       resume during the celebration doesn't double-fire), and pushes
       PromotionCelebrationScreen as a MaterialPageRoute with
       fullscreenDialog: true.
     - Telemetry `rank_promotion_celebration_shown` emitted on every
       successful push so we can query "did founder see it?".
regression_test_planned:
  - test/contracts/promotion_celebration_wiring_test.dart — 13 assertions covering UserRepository helpers (const + 3 helper signatures + top-level-key invariant), RankService stamp inside changed-branch + telemetry, HomeScreen observer mixin + add/remove + lifecycle handler + initTab + clear-before-push ordering + modal instantiation + telemetry.
related_bugs:
  - ec4d27  # Theme F + F-NEW — same batch, same surface (post-promotion flow)
recurrence: |
  This is the second "widget built but never wired" instance per the
  audit lens registry (the previous: APK Test #2 / Q7 phase preview
  before the route was added). The "ship the widget, defer the
  wiring" anti-pattern is a feature-development gap that the no-
  deferrals rule catches in retrospect; the durable mitigation is the
  reader-manifest enumeration which already lists PromotionCelebrationScreen
  as a CALLED widget (post-fix).
---
# Body

## Why a top-level userBox key, not inside the progress map

The progress map (`userBox['progress']`) is synced to cloud via
`_syncUserProgress` at sync_profile.dart:153. After Theme F-NEW
(`UserRepository.updateProgress` now fires `syncProgressNow`), adding
`pending_promotion_rank_code` inside that map would (a) attempt a
cloud upsert of an undefined column on `user_progress`, (b) trigger
fresh sync failures captured by `recordNonFatal`. The top-level key
sidesteps both — it's purely client-side celebration state.

## Why clear BEFORE push (not after)

Consider the lifecycle:
1. RankService stamps the slot.
2. App is in background (e.g. screen locked).
3. User unlocks → AppLifecycleState.resumed fires.
4. _maybeShowPendingPromotion runs → pushes modal → modal animates.
5. User backgrounds the app during the celebration (e.g. checks Slack).
6. Returns → resumed fires AGAIN.
7. Without clear-before-push: slot still has the rank_code, we push
   the modal A SECOND TIME on top of the existing one.

Clear-then-push means step 7 is a no-op (slot is empty). The modal
already pushed in step 4 stays open; the user finishes celebrating
once.

## Why fullscreenDialog: true

The MaterialPageRoute fullscreenDialog flag adds the close-from-top
gesture and ensures the modal occupies the whole viewport (PromotionCelebrationScreen
is designed as a full-screen overlay, not a partial sheet). Matches
the "promotion day" ceremonial framing the existing widget already
encodes.

## Multi-device behavior — known semantic

If the user has installed the app on two devices simultaneously, the
celebration fires on whichever device's RankService runs
evaluateAndPromote first (device A). Device B's local Hive
won't have the slot stamped — RankService on B will read the cloud
`user_profile.current_rank_code` post-sync, see it matches qualified
rank, and skip the stamp branch entirely. So B sees the new rank
chip + ladder reflected but no modal.

This is the correct semantic for the current product: the
celebration is a UI moment tied to "the device where the workout
that triggered promotion happened". A multi-device synchronized
celebration would require moving the stamp into the `rank_promotions`
INSERT pg_net trigger pipeline that Theme C ships THIS BATCH for
the proactive coach message. That coupling is intentional — both
features want the same "fan out a promotion event to every device's
notification surface" infrastructure. The same Theme C migration +
edge function pattern would extend to a `proactive-promotion-modal`
event in a subsequent batch; the data model is already in
`rank_promotions` cloud table.

100% of users today are single-device per project telemetry. The
behavior described above is correct for that population. Multi-
device synchronized celebration is a product enhancement, not a
bug fix.
