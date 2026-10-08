---
bug_id: 2d1c8a
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 / B2 continuation (finding A5)
status: shipped
symptom: |
  Three profile-tab readers (referral_eligibility_provider,
  promotion_history_provider) and one apply-referral writer
  (apply_referral_sheet) bypassed the repository pattern and
  called Supabase directly from the provider / widget layer:
    - apply_referral_sheet.dart:61
      → Supabase.instance.client.functions.invoke('redeem-referral', ...)
    - referral_eligibility_provider.dart:45
      → .from('referral_redemptions').select('id').eq('referee_id', ...)
    - promotion_history_provider.dart:36
      → .from('rank_promotions').select('rank_code, achieved_at')...
  All three sites violated CLAUDE.md rule #4 ("no Supabase from
  widgets / providers"). Gate 36
  (scripts/check_widget_no_direct_supabase.dart) was in WARN mode
  for the apply_referral_sheet hit; the two provider hits flew
  below the widget-only gate's radar (it scans
  lib/**/screens/** + lib/**/widgets/**, not providers/). Same
  architectural asymmetry that produced pre-Test-#6 workout/
  nutrition writer drift — every domain that doesn't have a
  repository chokepoint eventually grows a silent invariant
  bypass.
concept: referral_redemption
sot_registry_entry: referral_redemption
writers:
  - { file: lib/features/profile/repositories/referral_repository.dart, method: ReferralRepository.redeem, line: 82 }
  - { file: lib/features/profile/repositories/referral_repository.dart, method: ReferralRepository.hasRedeemed, line: 50 }
  - { file: lib/features/profile/repositories/rank_promotion_repository.dart, method: RankPromotionRepository.getRecent, line: 29 }
readers:
  - { file: lib/features/profile/providers/referral_eligibility_provider.dart, method_or_widget: referralEligibilityProvider via ReferralRepository.hasRedeemed, line: 43 }
  - { file: lib/features/profile/screens/apply_referral_sheet.dart, method_or_widget: _submit via ReferralRepository.redeem, line: 60 }
  - { file: lib/features/profile/providers/promotion_history_provider.dart, method_or_widget: promotionHistoryProvider via RankPromotionRepository.getRecent, line: 37 }
hive_key_prefix: none
hive_key_formula: "n/a — network-only reads, no Hive cache layer (intentional — eligibility + promotion log are server-authoritative and cheap)"
sync_methods: [n/a]
restore_methods: [n/a]
cloud_table: referral_redemptions + rank_promotions
cloud_columns: [referral_redemptions.id, referral_redemptions.referee_id, referral_redemptions.referrer_user_id, referral_redemptions.code, referral_redemptions.created_at, rank_promotions.id, rank_promotions.user_id, rank_promotions.rank_code, rank_promotions.achieved_at, rank_promotions.trigger]
contract_test_path: test/contracts/referral_repository_only_test.dart
ist_handling:
  - { file: lib/features/profile/repositories/referral_repository.dart, line: 50, fn: "n/a — both tables store server-authored timestamps in UTC; client never writes either timestamp directly. The 7-day eligibility window in ReferralEligibility.computeDaysRemaining still uses DateTime.now() (pre-A5 behaviour preserved) because the comparison is purely client-side display." }
provider_invalidations: [referralEligibilityProvider, promotionHistoryProvider]
telemetry_op_types:
  success: []
  failure: [referral_repository_has_redeemed, referral_repository_redeem, rank_promotion_repository_get_recent]
cross_account_guard: SupabaseService.instance.currentUser is the only identity source — repositories accept userId as a parameter and the caller (provider) derives it from the live session. Repository never caches userId. When the auth session changes, authUserIdTokenProvider invalidates the two callers (referralEligibilityProvider, promotionHistoryProvider), forcing a fresh call with the new userId.
forbidden_patterns_checked:
  - { pattern: "Supabase\\.instance\\.client\\.functions\\.invoke\\(\\s*'redeem-referral'", absent: true }
  - { pattern: "\\.from\\('referral_redemptions'\\)", absent: true }
  - { pattern: "\\.from\\('rank_promotions'\\)", absent: true }
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "Two new repositories created at lib/features/profile/repositories/{referral,rank_promotion}_repository.dart (110 + 50 lines). Three call sites migrated. flutter analyze --no-fatal-infos on 5 touched files: 'No issues found!'" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Both repositories are network-only — there is no Hive cache layer for referral_redemptions or rank_promotions. Pre-A5 inline code also had no Hive cache; behaviour preserved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change. Cloud tables referral_redemptions + rank_promotions unchanged." }
  - { tier: 6, name: edge_function_code, status: not_applicable, evidence: "redeem-referral Edge Function source unchanged. Repository.redeem wraps the existing v? deploy with no API-shape change (still POSTs {code: string}, still receives {ok|alreadyRedeemed|error: ...})." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "RLS unchanged — referral_redemptions is JWT-scoped via referee_id = auth.uid() (server-side INSERT path via Edge Function uses service-role); rank_promotions has user_id = auth.uid() SELECT policy. Repository reads inherit the same RLS context as the pre-A5 inline calls." }
  - { tier: 9, name: provider_invalidation, status: verified, evidence: "Both providers (referralEligibilityProvider, promotionHistoryProvider) still watch authUserIdTokenProvider for auth-change invalidation — that wiring is unchanged." }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "Gate 36 (scripts/check_widget_no_direct_supabase.dart) flipped from WARN (1 hit on apply_referral_sheet.dart:61) to PASS. test/contracts/referral_repository_only_test.dart + test/contracts/rank_promotion_repository_only_test.dart: 5/5 PASS. dart run scripts/check_reader_manifest_complete.dart: PASS (25 manifest-complete concepts, 2 newly added)." }
impact_analysis:
  callers_audited:
    - lib/features/profile/providers/referral_eligibility_provider.dart (referral_redemptions SELECT)
    - lib/features/profile/providers/promotion_history_provider.dart (rank_promotions SELECT)
    - lib/features/profile/screens/apply_referral_sheet.dart (redeem-referral Edge Function invoke)
  callers_updated_in_this_batch:
    - lib/features/profile/providers/referral_eligibility_provider.dart (now calls ReferralRepository.instance.hasRedeemed; dropped supabase_flutter direct import)
    - lib/features/profile/providers/promotion_history_provider.dart (now calls RankPromotionRepository.instance.getRecent)
    - lib/features/profile/screens/apply_referral_sheet.dart (now calls ReferralRepository.instance.redeem; dropped supabase_flutter import)
  callers_unchanged:
    - All other consumers of ReferralEligibility / PromotionRecord — the public surface of both providers is byte-identical.
proposed_fix: |
  Create two new repository classes under lib/features/profile/
  repositories/ mirroring SubmissionsRepository's shape (static
  `instance` singleton, no Riverpod injection — these are thin
  transport layers):

    1. ReferralRepository
       - Future<bool> hasRedeemed(String userId) — wraps the
         referral_redemptions SELECT.
       - Future<RedemptionResult> redeem(String code) — wraps the
         redeem-referral Edge Function invoke. Returns a typed
         result so callers don't pattern-match on raw HTTP shape.

    2. RankPromotionRepository
       - Future<List<PromotionRecord>> getRecent(String userId,
         {int limit = 5}) — wraps the rank_promotions SELECT.

  Both repositories swallow exceptions + telemeter through
  ErrorTelemetry.recordNonFatal (fire-and-forget via unawaited;
  H-42 telemetry contract). Failures return the same "neutral"
  values as the pre-A5 inline catch blocks (false / empty list /
  generic error message) — eligibility CTA + promotion history
  sheet are non-critical surfaces that must never block on a
  network blip.

  Migrate all three callers. Drop `import 'package:supabase_flutter
  /supabase_flutter.dart'` from the apply-referral sheet (it has
  no other use post-migration).

  Add two source-grep contract tests under test/contracts/
  pinning the ban + the repository's canonical methods. Add two
  new SoT registry concepts (referral_redemption,
  rank_promotion_log) with reader_manifest_complete: true.
regression_test_planned:
  - test/contracts/referral_repository_only_test.dart — source-grep contract pinning (a) apply_referral_sheet.dart no longer contains Supabase.instance.client.functions.invoke; (b) it no longer imports supabase_flutter; (c) it imports ReferralRepository + calls .redeem; (d) referral_eligibility_provider no longer contains .from('referral_redemptions') + calls .hasRedeemed; (e) ReferralRepository file exists with both canonical methods + ErrorTelemetry.recordNonFatal in error paths.
  - test/contracts/rank_promotion_repository_only_test.dart — source-grep contract pinning (a) promotion_history_provider no longer contains .from('rank_promotions') + calls .getRecent; (b) RankPromotionRepository file exists with canonical method + ErrorTelemetry.recordNonFatal in error path.
---
# Body

## What changed

Created two new repository classes:

| File | Lines | Public surface |
|---|---|---|
| `lib/features/profile/repositories/referral_repository.dart` | ~115 | `hasRedeemed(userId)` + `redeem(code)` + `RedemptionResult` |
| `lib/features/profile/repositories/rank_promotion_repository.dart` | ~50 | `getRecent(userId, limit:5)` |

Migrated three call sites:

| Site | Before | After |
|---|---|---|
| `apply_referral_sheet.dart:61` | `await Supabase.instance.client.functions.invoke('redeem-referral', ...)` + manual response.status branching | `await ReferralRepository.instance.redeem(code)` → `RedemptionResult` |
| `referral_eligibility_provider.dart:45` | `await supabase.from('referral_redemptions').select('id').eq('referee_id', user.id).maybeSingle()` + try/catch returning null | `await ReferralRepository.instance.hasRedeemed(user.id)` |
| `promotion_history_provider.dart:36` | `await SupabaseService.instance.client.from('rank_promotions')...` + try/catch returning const [] | `await RankPromotionRepository.instance.getRecent(user.id)` |

## Why not gold-plating

Same rationale as A4 (ProfileWriteService). The pre-A5 inline calls
worked. The reason to consolidate now is the next invariant we know
is coming: any future change to referral telemetry (e.g. "every
failed redeem must increment a server-side fraud counter"), retry
policy, or auth-error handling (e.g. "if `Authentication required`,
silently bounce to re-auth") would otherwise land in three
different files and inevitably miss at least one. The repository
gives us one chokepoint.

`hasRedeemed` and `getRecent` are also the two surfaces most likely
to grow caching next (eligibility CTA fires on every Profile-tab
open; promotion sheet fires on every rank-detail tap). With the
repository in place, a future `_cachedEligibility` field lands in
one place.

## Gate 36 status

Before: `[Gate 36] WARN (B2-transitional): 1 direct Supabase call(s)
from UI layer: lib/features/profile/screens/apply_referral_sheet.dart:61`

After: `[Gate 36] PASS: no direct Supabase calls in lib/**/screens/**
or lib/**/widgets/**.`

The two provider hits were not Gate 36 scope (it scans screens +
widgets only) but the contract tests now pin all three.

## Test output

```
00:00 +5: All tests passed!
```

Two new contract files, 5 tests total (3 + 2).

## SoT registry

Two new entries appended:

  - `referral_redemption` (writers: redeem-referral Edge Function +
    `ReferralRepository.redeem`; readers: hasRedeemed +
    referralEligibilityProvider + apply_referral_sheet).
  - `rank_promotion_log` (writer: server-side promotion job;
    readers: getRecent + promotionHistoryProvider).

Both with `reader_manifest_complete: true`.

`dart run scripts/check_reader_manifest_complete.dart`: PASS.
