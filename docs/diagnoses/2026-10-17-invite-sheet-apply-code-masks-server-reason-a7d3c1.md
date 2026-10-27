---
bug_id: a7d3c1
date: 2026-10-17
batch: referral-unit-c-client
status: fixed
blast_radius: account
symptom: >
  In the Invite Friends sheet's "GOT A CODE?" box, any thrown error showed "Could not apply code. Please try again."
  A friend who already paid, an expired code, a self-referral and an already-redeemed code are all HTTP 400 from
  redeem-referral, and supabase_flutter throws a FunctionException on every non-2xx, so every one of them landed in that
  generic catch. Since migration 159 a friend who has ever paid is refused with a specific reason
  (referee_has_paid_plan); this sheet could not show it. A 200 always printed "+7 days PRO added!" even for an
  alreadyRedeemed replay, and the subscription was never re-verified, so the Home PRO state stayed stale for up to five
  minutes (verifyFromServer is cached).
concept: referral_redemption
sot_registry_entry: referral_redemption
writers: >
  supabase/functions/redeem-referral/index.ts (the 200 body {success:true,...,alreadyRedeemed?} and the 4xx {error});
  lib/features/profile/repositories/referral_repository.dart redeem() (the ONE place that unpacks FunctionException and
  the 200 body).
readers: >
  lib/features/profile/screens/invite_friends_sheet.dart _applyCode (was: a private second parser at the old :89-127 that
  called SupabaseService.callFunction directly, checked body['success'] and had a catch-all);
  lib/features/profile/screens/apply_referral_sheet.dart _submit (already on the repository).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (Edge Function call and UI messages)
sync_methods: []
restore_methods: []
cloud_table: referral_redemptions, subscriptions
cloud_columns: >
  referral_redemptions(referee_id, referrer_id, code, days_granted_each); subscriptions(user_id, plan, status, end_date)
contract_test_path: test/contracts/referral_unit_c_surfaces_test.dart
ist_handling: not_applicable
provider_invalidations:
  - referralEligibilityProvider (invalidated on a fresh success; the apply sheet never did)
telemetry_op_types:
  success: []
  failure:
    - referral_repository_redeem
related_bugs:
  - d2b9e6
recurrence: >
  Recurrence of d2b9e6 (2026-06-13): "the client masked the 4xx as a generic Network error". d2b9e6 fixed
  ReferralRepository.redeem and the onboarding caller and pinned only that the invite sheet KEYS OFF body['success'], which
  froze the second, private parser in place. Same class: a second reader of one writer's contract that nobody converged.
  The known-good fix (route every caller through ReferralRepository.redeem) is applied, and the pin that protected the
  duplicate (referral_redeem_success_contract_test, "invite_friends_sheet success-detection reads body['success']") is
  repointed to assert the opposite: the sheet no longer parses the body.
cross_account_guard: true
forbidden_patterns_checked:
  - "a screen calling SupabaseService.callFunction('redeem-referral') directly (the repository is the only caller; pinned by referral_repository_only_test)"
  - "a catch-all that replaces a server reason with a generic message"
  - "'+7 days PRO added!' on a 200 without checking alreadyRedeemed"
  - "verifyFromServer() without force: true right after a grant (cached for 5 minutes, subscription_service.dart:1021)"
proposed_fix: >
  invite_friends_sheet._applyCode calls ReferralRepository.instance.redeem(code); on success it calls
  ref.read(subscriptionServiceProvider).verifyFromServer(force: true) (try/catch, the grant is real either way) and
  invalidates referralEligibilityProvider; alreadyRedeemed shows "Code already applied." and does nothing else; a failure
  shows result.errorMessage (the server's own reason). The telemetry event profile_apply_referral_code_failed is replaced
  by the repository's referral_repository_redeem (grep: no reader of the old name in lib/, test/ or docs/). The sibling
  apply_referral_sheet gets verifyFromServer(force: true) as well.
regression_test_planned: >
  test/contracts/referral_unit_c_surfaces_test.dart group InviteFriendsSheet: a paid friend's 400 shows the server's
  reason and not the generic text; alreadyRedeemed says so and never claims +7 days; a fresh success verifies with
  force: true and rebuilds the eligibility provider. Presence pins in referral_unit_c_lifecycle_and_pins_test.dart and the
  repointed referral_repository_only_test / referral_redeem_success_contract_test.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "invite_friends_sheet._applyCode routed through ReferralRepository.redeem; flutter analyze lib/ clean for the touched files" }
  - { tier: 2, layer: hive_local_state, status: not_applicable, evidence: "the redemption writes no Hive key; the new referral_credit_seen_days scalar is a separate concept (referral_credit_notice)" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: verified, evidence: "redeem-referral is unchanged by this batch; its 200/4xx body shapes are the ones the repository already parses (referral_redeem_success_contract_test)" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "the repository unpacks FunctionException.details['error'] and the 200 body's error / alreadyRedeemed; the sheet now consumes exactly that result. The live end-to-end check with a real user session is OI-348 row B1 (filed on branch `pending-checks-oi`)." }
impact_analysis: >
  Account tier (a referral PRO grant and its messages). Only the Invite Friends sheet's apply box was wrong; the apply
  sheet and onboarding already used the repository. Before unit C a paid friend saw a generic failure that looked like a
  transient error and retried; the +7 days claim on a replay was false.
---

# The Invite Friends sheet masks the server's reason for a refused referral code (a7d3c1)

## What happened
`invite_friends_sheet._applyCode` had its own copy of the redeem call and its own parsing: it called
`SupabaseService.callFunction('redeem-referral')`, read `body['success']`, and wrapped everything in a `catch` that
printed "Could not apply code. Please try again." `callFunction` rethrows a `FunctionException` for every non-2xx, so
the Edge Function's specific 4xx reasons never reached the screen; a 200 always claimed "+7 days PRO added!".

## Root cause (writer and reader by file:line)
Writer: `redeem-referral/index.ts` (200 `{success:true,alreadyRedeemed?}` / 4xx `{error}`). Readers: the repository
`redeem()` (correct since d2b9e6) and the sheet's private parser (`invite_friends_sheet.dart`, the old `_applyCode`).
d2b9e6 repaired one reader and pinned the other in place.

## Fix
Route the sheet through `ReferralRepository.redeem`, verify with `force: true`, invalidate the eligibility provider,
show the server's reason, say "Code already applied." for a replay. Repoint the pin that froze the duplicate.

## Verification
- `test/contracts/referral_unit_c_surfaces_test.dart` (InviteFriendsSheet group), `referral_unit_c_lifecycle_and_pins_test.dart`,
  repointed `referral_repository_only_test.dart` and `referral_redeem_success_contract_test.dart`.
- Mutation (rule 21): the direct-call mutant (a live `callFunction('redeem-referral')` back in the sheet) reddens `referral_repository_only_test`; dropping `verifyFromServer(force: true)` reddens the surfaces and pins tests (2); making a replay claim +7 days reddens the surfaces test (1). 25 of 25 mutants of the whole unit were caught (see the ledger row C11).
- Live check with a real user session: OI-348 row B1 (filed on branch `pending-checks-oi`).

## See also
- docs/diagnoses/2026-06-13-referral-rls-context-d2b9e6.md (the recurrence source)
- docs/plans/referral-unit-c-client.md
