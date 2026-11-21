# OI-341 Piece B2b: the client for a stacked trial purchase (v3)

Branch `oi341-piece-b2b-client`, base `47cb142c`. Blast radius: **platform** for the whole diff (round 1 P2-4:
`supabase/functions/CLAUDE.md` and root `CLAUDE.md`-class docs are platform; `lib/core/services/razorpay_service.dart`
alone is account; measured with positional paths through `scripts/blast_radius_from_diff.dart`). Payment client, so
tier L (CLAUDE.md 4.12.6): full x2 plan review, `flutter analyze lib/` before every reviewer dispatch, the full gate loop
before the B-pass, and `bpass: accepted` in the plan-review record (platform). Execution mode (4.12.7): **inline**, one
worktree, one writer. Commit type `feat(payment)` (no defect on `main` is fixed: every changed behaviour only matters
once the door opens; the plan-pairing race closed in 2.3 is a latent hardening with no observed defect, recorded in
the ledger), so no diagnose-doc is owed; the closure ledger is
`docs/audit/oi341-piece-b2b-client.closure.yaml` (4.2, five or more units).

Starting point: `docs/plans/oi341-piece-b2-door.md` section 9. Every claim below was re-checked against `47cb142c` on
2026-10-22.

Review history:
- Round 1 (on v1): 1 P1, 8 P2, 5 P3; all folded into v2 (section 7).
- Round 2 (on v2): **0 P0, 0 P1**, 9 P2, 6 P3; verdict CONVERGED; all folded into v3 mechanically (section 8).
  Rounds 1 and 2 are the two reviews (4.12.1): **converged**.

## 0. Founder decisions and the order (binding)

- 2026-10-13: a referral-trial user may buy; the paid cycle starts when the free days end (stacking).
- 2026-10-20 answers: keep "RENEW TO STAY PRO" on the banner; no Profile `TrialUpgradeDoor`; add **"Your paid plan
  starts when your free days end."** to the paywall and to the Razorpay checkout description.
- 2026-10-21 order (founder "ok"), recorded here and amended into B2a's plan section 4 in this branch:
  1. Build B2b now: plan, x2 review, build, B-pass. **The branch is NOT merged.**
  2. ONE live session: B2a steps 1-3 (deploy the door and both writers with the switches unset, the alarm drill, the
     stacking flip); step 4a opens the door (`ENABLE_TRIAL_PURCHASE=true`, redeploy `create-razorpay-order`); **then
     merge B2b** (the web app redeploys on the merge, `vercel.json` `ignoreCommand`); step 4b is the stacked trial
     purchase made through the NEW web client, so one purchase tests the door and the client together; then the 90%
     code is deactivated, every payment refunded, tester rows cancelled (never deleted), each with its own go.
  3. Then `/build-apk` with the LIVE key ID in the VPS `.env`, and one phone purchase.
- **Hard constraint:** B2b must not merge before the door is open (the paywall line would be false on the web while
  the door is shut; B2a round 2 P1-A).
- **No client flag (CLAUDE.md 4.6, stated deviation, round 1 P2-9).** B2a 9.2 dropped the v1 configBox flag because it
  is per device, so it cannot roll back a fleet. The rollback here is the server door (B2a's door rollback), the
  ordering (merge only after the door opens) is the forcing function, and with no `stacks_after` (the door shut, today)
  the estimate and the checkout options are byte-identical to today's (tests T1, T5). Three things differ with the
  door shut (round 2 P2-8): a trial user's 409 copy and callback (2.3; today's state heal kept); the EST seal clamp
  (2.5; a referrer-extended paid row whose `expiresAt - planDays` is in the future now shows today); and the plan used
  for a confirmation is taken from that order's own record, captured before the first await (2.3). All three are
  display or latent-race hardening, none changes a charge or an entitlement.
- The app is not live; every account is a tester (CLAUDE.md section 1).

## 1. Facts (verified at `47cb142c`)

Server (B2a): **merged (PR #139), NOT deployed** (round 1 P1). `docs/audit/oi341-piece-b2-door.closure.yaml`
`L1-DOOR-DEPLOY` / `L2-WRITERS-DEPLOY` are `blocked_on_user`. What runs live today is the pre-B2a door (409 for any
active row, no `stacks_after` key). F1 and F2 describe the merged code, which goes live in live-session steps 1-4.
- F1. `create-razorpay-order/index.ts`: the guard read is `:146-175`; the door-OPEN 200 body (`:284-301`) always carries
  `stacks_after` (ISO string, the latest active trial end, or `null`); the door-SHUT body never has the key.
- F2. `alreadyPro(row)` `:93-103`: 409 with `error_code: "already_pro"`, `current_plan`, `current_expires_at`. Door SHUT:
  any active row answers, from the LATEST-ending row, so a user whose latest row is the trial gets
  `current_plan: "referral_trial"`. Door OPEN: only a paid row answers. `REFERRAL_TRIAL_PLAN` is `:64`.
- F3. The writers never read `stacks_after`; they compute the stacked end and return / store `end_date`.

Client:
- F4. `razorpay_service.dart:46` `_pendingPlan`, set at `:135` (before the order await), cleared in `_onUserChanged`
  `:60-64`.
- F5. `:148-196` the order call; the 200 body is read for `order_id` and `amount` only (`:188-189`).
- F6. 409 on TWO paths: the response path `:167-176` (dead in supabase_flutter ^2.16, kept for forward compatibility)
  and the `FunctionException` catch `:207-223`. Both call `_handleAlreadyProResponse` (`:408-426`: writes PRO state from
  `current_expires_at` with the server's `current_plan`, clears the in-flight flag, invalidates the providers, shows
  "You're already PRO — active until ...") then `onSuccess`. The heal exists for a false-negative local `isPro`
  (APK #12.2).
- F7. `buildRazorpayCheckoutOptions` `:317-340`, the single options source (native AND web); description at `:330`.
- F8. `_computeEndDate(plan)` `:675-680` = `DateTime.now() + 30/365 days`, local ISO (no `Z`). FOUR uses: optimistic
  `:505`; Phase 1 poll fallback `:783`; Phase 2 verify fallback `:853`; the retry tear-off `:957`
  (`payment_retry_attempt.dart:62,93,128,150`, signature `String Function(String plan)`).
- F9. `handlePaymentConfirmed` `:455-579`: both success paths land here WITH the order id (native
  `response.orderId` `:446`; web `parseWebSuccessPayload(raw).orderId`, `razorpay_web_checkout.dart:26`
  `razorpay_order_id`). It awaits the session refresh (`:474-486`) and only then reads `_pendingPlan` (`:504`);
  `_pollAndActivate` re-reads `_pendingPlan` at `:696`. A second `openCheckout` sets `_pendingPlan` (`:135`) at any of
  those awaits: the plan is ALREADY exposed to a later checkout today (round 1 P2-2).
- F10. `paywall_sheet.dart:500-535` the pricing cards; `:537-540` the promo section; no provider watched in `build`.
  Corrected (round 2 P2-4): the real sheet IS pumped by four widget tests (`test/widgets/swap_picker_sheet_test.dart`
  `:285-310`, `test/profile/user_photos_gate_behavioral_test.dart`, `progress_photos_screen_gate_test.dart`
  `:174-192`, `progress_photos_lapsed_flow_test.dart`); all override `subscriptionInfoProvider`, so the new
  `ref.watch(...select)` leaves them green. They warm Fraunces (`AppTypography.h1/h3`: `ward_letterhead.dart:100`,
  `ward_button.dart:107`, `_PricingCard`) as well as DM Sans and mono; the sheet needs no Hive; telemetry fires in
  `initState` and in `dispose` (`paywall_dismissed`, `:190`).
- F11. A trial user reaches the paywall through the Home expiry banner when under 7 days are left
  (`subscription_expiry_banner.dart:37`, `home_screen.dart:609-613` -> `PaywallSheet.genericUpgrade`;
  `expiryBannerSeverity`, `subscription_service.dart:~1171`). Corrected (round 1 P3-10): a trial is NOT always inside
  that window (`private.grant_referral_days`, migration 159 `:106-114`, extends the latest active row, and a referrer
  can hold a 30-day `referral_trial` row); the banner is also dismissable per day. A trial user with 7+ days left has
  no paywall entry: the founder's no-door decision. Other PRO-feature paywall entries do not open for a PRO user
  (the AI-coach upgrade item is `!isPro`; `profile_content.dart:210-221` is gated).
- F12. `SubscriptionInfoData` `profile_provider.dart:343-361`; `SubscriptionInfoNotifier` fills `plan` from
  `SubscriptionService.currentPlan`.
- F13. EST seal: `profile/screens/profile/screen.dart:242-254` `_estSealDate` (with `_ddMmYy` `:256-261`), used at
  `subscription_section.dart:23`.
- F14. Copy lives in `lib/core/copy/`; plan-name constants are not copy (round 1 P2-8): `lib/core/constants/`.
- F15. Referral timing copy: `ReferralCopy.inviteDescription` (`lib/core/copy/referral_copy.dart:10-14`) says "a week
  after their first payment"; no ~14-day figure; stays true once the door opens. Verified clean: no change.
- F16. `referral_trial` appears in `lib/` only in admin comments; no client constant exists.
- F17. The local plan comes from the server row with the LATEST `end_date` (`refreshFromSupabase` `:900-955`;
  `verifyFromServer` `:1072-1083`, `verify-subscription` returns that row's own `plan`, round 1 confirmed). A trial
  user's local plan is `referral_trial`; after a stacked purchase the paid row wins: plan `monthly`/`yearly`, expiry =
  trial end + plan days.

## 2. Design

### 2.1 Constants and copy

- `lib/core/constants/subscription_plans.dart` (new): `const String kReferralTrialPlan = 'referral_trial';`
- `lib/core/copy/payment_copy.dart` (new): `PaymentCopy.trialStackingNotice` = "Your paid plan starts when your free
  days end." (founder, verbatim) and `PaymentCopy.trialUpgradeUnavailable` = "Your free PRO days are still running.
  You can subscribe once they end." (shown only with the door SHUT; proposed to the founder 2026-10-22, may be
  reworded). Tone note (round 1 P3): both lines say the same thing in two states (open: "starts when they end"; shut:
  "subscribe once they end").

### 2.2 Pure pieces: `lib/core/services/payment_end_estimate.dart` (new)

- `DateTime? parseStacksAfter(Object? raw, {required DateTime now})`: only a `String` with a time part (`T` or a space)
  that ends in an explicit offset (`Z`, or `+hh:mm` / `-hh:mm` AFTER the time part, so a date-only `2026-10-29` cannot
  pass as an offset) and that `DateTime.tryParse` accepts; a value more than 3650 days (10 years) after `now` is refused (v3 said 400; widened after B-pass seat A P3-5: referral credits are uncapped, so a long trial is legitimate) (it feeds
  the local expiry until the server overwrites it, round 1 P3-12). Anything else gives `null`. It is TOTAL (never
  throws: it runs inside the order `try`). The server emits the raw `timestamptz` `end_date` (migration 006:12,
  `index.ts:176,294`): PostgREST renders `2026-11-16T10:00:00.123456+00:00` or a `Z` form
  (`_shared/subscription.ts:165`), both accepted.
- `String estimatePaidEndDate({required String plan, DateTime? stacksAfter, required DateTime now})`:
  `base = (stacksAfter != null && stacksAfter.isAfter(now)) ? stacksAfter : now`, then
  `base.toLocal().add(days).toIso8601String()` (365 for `yearly`, else 30). `toLocal()` on the chosen base in BOTH
  branches gives one string shape whatever zone the inputs carry. With `stacksAfter == null` and a local `now` the
  output equals today's `_computeEndDate` for that `now`.
- `class PendingCheckout { final String plan; final DateTime? stacksAfter; }` and a small store
  `class PendingCheckouts` (insertion-ordered map `orderId -> PendingCheckout`, at most 4 entries, oldest evicted;
  `record`, `lookup`, `clear`). `({String plan, DateTime? stacksAfter, bool matched}) resolveConfirmedCheckout({
  PendingCheckouts store, String? confirmedOrderId, String? pendingPlan})`: a non-empty id with a record -> that
  record's plan and stacks-after, `matched: true`; otherwise today's behaviour exactly: `plan = pendingPlan ??
  'monthly'`, `stacksAfter = null`, `matched: false` (an order we did not record never gets a stacked estimate).
  Keyed records survive a later `openCheckout` (round 2 P2-1: v2 nulled one record at every checkout, so an earlier
  payment confirmed after a later checkout started fell back to the later plan).
- `enum OrderConflict { alreadyPro, trialUpgradeUnavailable, other }` and
  `OrderConflict classifyOrderConflict(Map<String, dynamic> body)`: `error_code == 'already_pro'` and
  `current_plan == kReferralTrialPlan` -> `trialUpgradeUnavailable`; `error_code == 'already_pro'` otherwise ->
  `alreadyPro`; else `other`.
- `String checkoutDescription({required String plan, DateTime? stacksAfter})`: today's `'PRO Monthly Plan'` /
  `'PRO Yearly Plan'`; with `stacksAfter != null` it appends `'. '` + `PaymentCopy.trialStackingNotice`.

### 2.3 `razorpay_service.dart`

- `final PendingCheckouts _pendingCheckouts`: after the order fields validate (`:191-196`) a LOCAL
  `final stacksAfter = parseStacksAfter(data['stacks_after'], now: DateTime.now());` is computed and
  `_pendingCheckouts.record(orderId, PendingCheckout(plan, stacksAfter))`; cleared in `_onUserChanged` (never at the
  top of `openCheckout`: the key already prevents stale pairing). `_pendingPlan` stays (it still feeds today's
  fallback).
- The options builder gains `DateTime? stacksAfter` (named, optional; null = today's exact map); `openCheckout` passes
  the LOCAL `stacksAfter`.
- `handlePaymentConfirmed`, BEFORE its first await (after the existing `debugPrint` and the `ctx`/`messenger`
  captures, `:460-465`): `final resolved = resolveConfirmedCheckout(store: _pendingCheckouts, confirmedOrderId:
  orderId, pendingPlan: _pendingPlan);`. When the store is non-empty and `resolved.matched` is false, one
  `ErrorTelemetry.logEvent('razorpay_checkout_record_unmatched', message: 'has_order_id=<bool>')` (no ids; native UPI
  paths can omit the order id, and live step 4b needs to see which path ran, round 2 P3-5). The optimistic write uses
  `resolved.plan` and `estimatePaidEndDate(plan: resolved.plan, stacksAfter: resolved.stacksAfter, now:
  DateTime.now())`; `_pollAndActivate` and `_scheduleVerificationRetry` take `checkoutPlan` and `stacksAfter`
  parameters (`checkoutPlan`, because the inner `final plan` at `:779` / `:850` would shadow `plan`); no re-read of
  `_pendingPlan` at `:696`; the `:783` / `:853` fallbacks and the retry's `fallbackEndDate` become closures over the
  captured values, added AFTER the existing `userId:` / `orderId:` arguments of `scheduleVerificationRetries(` (the
  `payment_grace_window_derived_wiring_test` windows).
- `_computeEndDate` is deleted; every former use goes through `estimatePaidEndDate`.
- Both 409 paths call `classifyOrderConflict`. `alreadyPro`: today's path verbatim. `trialUpgradeUnavailable`: the SAME
  heal as today (`_handleAlreadyProResponse` gains `{bool trialUpgradeUnavailable = false}`: the write with the
  server's `current_plan` and `current_expires_at`, `clearPaymentInFlight`, the invalidation, all unchanged) and only
  the feedback and the callback differ: the informational PRO-styled snackbar shape (`_showAlreadyProFeedback`'s
  colours) with `PaymentCopy.trialUpgradeUnavailable`, then `onFailure` (no checkout opened). `other`: today's failure
  path. Stated edge (round 1 P2-3): with the door shut, a user holding a trial row that ends AFTER a non-stacked paid
  row gets the trial message although a paid row exists; reachable only from pre-stacking data, harmless (both say no
  purchase now).
- The server's stored `end_date` still overwrites the estimate on every path (F3).

### 2.4 Paywall line

- `SubscriptionInfoData.isReferralTrial` (pure getter): `isPro && plan == kReferralTrialPlan`.
- `paywall_sheet.dart`: under the pricing-card `Row`, when
  `ref.watch(subscriptionInfoProvider.select((s) => s.isReferralTrial))` is true, `SizedBox(stackS)` + one
  `Text(PaymentCopy.trialStackingNotice, key: ValueKey('paywall-trial-stacking-notice'))` (`AppTypography.bodySm`,
  `AppColors.textDim`, centred). Copy only; it gates nothing. False = today's tree.

### 2.5 EST seal

- `lib/features/profile/services/est_seal_date.dart` (new), pure: `String estSealDate({DateTime? expiresAt, String?
  plan, required DateTime now})` and `ddMmYy` moved there from `screen.dart:256` (round 1 P3-11; no provider import).
  `expiresAt == null` -> `now`; else `min(expiresAt - planDays, now)`, planDays 365 for `yearly`/`annual`, else 30.
  `_estSealDate` becomes a wrapper passing `subInfo.expiresAt`, `subInfo.plan`, `DateTime.now()`.
- Display only, in the DateTime's own zone (as today; not an IST date key, 4.5 does not apply).
- Stated: for a stacked purchase (expiry = trial end + 30) the clamp shows today until the trial ends, then the paid
  start. A `referral_trial` row still back-computes 30 days, so a 7-day trial user's seal can predate signup: today's
  behaviour, unchanged by this batch, written into the closure ledger as `verified_clean` with that reason.

### 2.6 Docs, registry, ledger (same commit)

- `docs/sot_registry.yaml` (round 2 P2-7: Gate 42 works per CONCEPT, with `behavioral_test_path` plus sibling
  `behavioral_test_path_<suffix>` keys): a NEW concept `trial_stacking_client_estimate` (writers: `openCheckout`'s
  record, `handlePaymentConfirmed`'s optimistic write; readers: `subscriptionInfoProvider`, the paywall line, the EST
  seal), `behavioral_test_path:` `test/core/payment_end_estimate_test.dart`, sibling
  `behavioral_test_path_paywall:` the widget test, `regression_test_wiring:` the wiring pins (precedent
  registry `:3770`); `trial_purchase_door`'s reader list names it. Every line range the registry cites in
  `razorpay_service.dart`, `profile_provider.dart`, `paywall_sheet.dart` and `profile/screens/profile/screen.dart`
  (incl. the single-line `line_range: 305`) is re-derived after the edit; the A7 lifecycle note gains
  `_pendingCheckouts`; the `service_providers.dart:166` comment too.
- `docs/architecture/payment.md` (rule 9's "B2b follows the door opening" -> the section 0 order; the client estimate;
  the trial-409 copy), `supabase/functions/CLAUDE.md` (`trial_purchase_door` reader), OI-341's "Blocked on"
  (`docs/audit/open_issues.md`), the B2a closure ledger rows that name B2b, `docs/plans/oi341-piece-b2-door.md`
  section 4 step 5 (replaced by the section 0 order) and sections 9.1 / 9.2 marked SUPERSEDED by this plan (they say
  the trial 409 skips `_handleAlreadyProResponse`, name `kTrialUpgradeUnavailable`, and put the copy under
  `constants/`; round 2 P2-9).
- `docs/naming_conventions.md`: `PaymentCopy`, `kReferralTrialPlan`, `PendingCheckout`, `PendingCheckouts`,
  `resolveConfirmedCheckout`, `estimatePaidEndDate`, `parseStacksAfter`, `classifyOrderConflict`, `OrderConflict`,
  `checkoutDescription`, `estSealDate`, `isReferralTrial`, `razorpay_checkout_record_unmatched`,
  `trial_stacking_client_estimate`.
- OI-348: after the build, a trial tester (under 7 days left, banner not dismissed today) sees the line on the paywall
  and in the checkout, buys, and the Profile card shows the stacked end and today's EST date.
- `lib/core/services/CLAUDE.md` and `lib/features/profile/CLAUDE.md`: one line each.
- Context-artifact budget re-checked after the nested CLAUDE.md edits (`--record` only if intended).
- `docs/audit/oi341-piece-b2b-client.closure.yaml`: one entry per unit (estimate, description, 409, paywall line, EST
  seal, constants parity, plan-pairing hardening, docs) `closed_in_commit`; `blocked_on_user`: the merge after the
  door opens, the live 4b purchase, the OI-348 device check, `/build-apk`, and the founder's sign-off on the
  `trialUpgradeUnavailable` wording (the Wardroom read is done in this batch; `oi341-purchase-in-trial.md:63` assigns
  user-visible copy review to Piece B); `verified_clean`: the referral copy (F15) and the trial seal back-computation.

## 3. Tests (each protection names a mutant that must redden it; every mutation confirmed applied with `grep -c`)

Paths follow the repo: pure service tests in `test/core/`, widget tests in `test/widgets/`. Run with
`TZ=Asia/Kolkata` (UTC goldens depend on the process zone, which cannot be switched in-process).

Before any move or rename: `grep -rn` `test/` for the old literal (4.9). Known: `test/contracts/
razorpay_409_already_pro_test.dart:51` asserts `contains("'already_pro'")` over the service source, which
`classifyOrderConflict` takes out of the service; it is REPOINTED (never loosened) to assert the literal in
`payment_end_estimate.dart` AND a `classifyOrderConflict(` call on each 409 path of the service (round 2 P2-2).
Verified to stay green: `razorpay_web_shared_success_handler_test`, `payment_grace_window_derived_wiring_test`
(argument windows kept), `subscription_payment_grace_window_writer_to_reader_test` (>= 4 `clearPaymentInFlight()`),
`razorpay_checkout_options_test`, the four widget tests that pump the sheet (F10).

`test/core/payment_end_estimate_test.dart` (pure; expected values are LITERAL golden strings):
- T1 `estimatePaidEndDate`: null -> golden `now+30` / `now+365` (mutant: 30 -> 31); future `stacksAfter` ->
  `stacksAfter+30` local (mutant: always `now`); past -> `now+30` (mutant: drop `isAfter`); `stacksAfter` 1 ms after
  `now` -> `stacksAfter+30` (killable boundary); yearly + stacked -> `+365` (mutant: plan check inverted); a
  `DateTime.utc` `now` gives the same local shape (mutant: drop `toLocal`). (v2's "equal instant" mutant was
  equivalent and is dropped, round 2 P2-3; the equal case stays as an unmutated row.)
- T2 `parseStacksAfter`: accepted `2026-11-16T10:00:00.123456+00:00` (the server's shape), a `Z` form, a `+05:30`
  form, a space-separated form with an offset, now+3649 days; refused: offset-less, date-only `2026-10-29`, `null`,
  absent, `42`, `'garbage'`, `''`, now+3651 days (mutants: drop the offset check; offset regex allowing `-29`; drop the
  clamp); never throws for any input.
- T3 `classifyOrderConflict` (mutants: drop the error_code check; swap the plan comparison).
- T4 `checkoutDescription`: null -> exactly `'PRO Monthly Plan'` / `'PRO Yearly Plan'`; past and future
  `stacksAfter` -> `'PRO Monthly Plan. Your paid plan starts when your free days end.'`; both under 255 chars
  (mutant: append only when future).
- T5 `buildRazorpayCheckoutOptions`: no `stacksAfter` -> the whole map equals a literal of today's map; with one, only
  `description` differs.
- T6 `PendingCheckouts` + `resolveConfirmedCheckout`: two records (A then B), confirm A -> A's plan and stacks-after
  (the round-2 interleaving; mutant: store keeps only the latest); unknown id -> `pendingPlan`, null, unmatched;
  null / empty id -> today's behaviour (mutant: skip the id lookup); a fifth record evicts the oldest (mutant: no
  bound); `clear` empties (mutant: no-op).

`test/contracts/referral_trial_plan_parity_test.dart` (round 2 P2-6): the Dart `kReferralTrialPlan` (imported) equals
the TS `REFERRAL_TRIAL_PLAN` (regex over `create-razorpay-order/index.ts`) and the plan literal in the body of the
LATEST migration defining `private.grant_referral_days` (every migration scanned in the repo's numbering order,
comments stripped, last definition wins (4.9); `test/helpers/migration_cap_reader.dart` used if it accepts the
schema-qualified name, otherwise the same rule written in the test) (mutants: Dart literal; TS literal).

`test/contracts/trial_stacking_client_wiring_test.dart` (comment-stripped source pins, presence only; carried by the
registry's `regression_test_wiring:`; the behaviour is T1-T6 and W1-W2):
- P1 both 409 paths call `classifyOrderConflict` and route `trialUpgradeUnavailable` before the `alreadyPro`
  `onSuccess` (mutant per path). The paywall's callbacks are no-ops (`paywall_sheet.dart:319-327`), so the callback
  choice is presence only (round 2 P3-6).
- P2 `resolveConfirmedCheckout(` sits in `handlePaymentConfirmed` BEFORE its first `await`; `_pendingPlan` /
  `_pendingCheckouts` are not read later in `handlePaymentConfirmed`, `_pollAndActivate` or
  `_scheduleVerificationRetry` (mutant: re-read `_pendingPlan` in `_pollAndActivate`).
- P3 `_pendingCheckouts.clear()` in `_onUserChanged` (mutant: removed); no `.clear()` in `openCheckout`.
- P4 no `_computeEndDate`; three `estimatePaidEndDate(` calls (the optimistic write, the poll/verify `fallbackEndDate`
  closure shared by both server-reply fallbacks, the retry closure), each with `stacksAfter: stacksAfter` (mutant: one
  passes `null`). (v3 said four calls; the four SITES use three calls, B-pass seat A P3-4.)
- P5 `openCheckout` passes the local `stacksAfter` to the builder and records it under the order id.
- P6 the trial branch calls `_handleAlreadyProResponse(..., trialUpgradeUnavailable: true)` (heal kept; mutant: the
  branch skips the call).

Widget `test/widgets/paywall_trial_stacking_notice_test.dart` (precedent `test/widgets/swap_picker_sheet_test.dart`
`:285-310`: warm Fraunces, DM Sans and mono; `subscriptionInfoProvider.overrideWith(() => _Sub(data))`; no Hive;
`ErrorTelemetry.debugOnLogEventForTests` stubbing the `initState` and `dispose` events):
- W1 trial (`isPro: true, plan: 'referral_trial'`) -> the keyed line with the exact text (mutants: getter false; line
  removed).
- W2 PRO monthly, free, and `isPro: false, plan: 'referral_trial'` -> no line (mutant: getter drops `isPro`).

`test/features/profile/est_seal_date_test.dart` (pure): null -> today; monthly in 10 days -> `expiry-30`; stacked
(trial end in 5 days + 30) -> today (mutant: drop `min`); yearly; `annual` alias (mutant: drop the alias); `'Yearly'`
mixed case keeps today's lowercase compare (mutant: drop `toLowerCase`).

Mutation run: a scratch script (compute every mutant first, assert each anchor occurs once, apply one at a time, run
only the named tests, restore in `finally`, byte-compare). Every mutant must go red; a survivor is a finding.

Full gate loop before the B-pass: `flutter analyze lib/`, `TZ=Asia/Kolkata flutter test --exclude-tags golden`,
`PRE_COMMIT_GATE_JOBS=1 sh scripts/pre-commit.sh`.

## 4. Not in B2b

Server code (B2a, merged). The live steps (founder gos, section 0). A client flag (section 0). `/build-apk`.

## 5. Risks

- R1. Between step 4a and the B2b merge, a trial user on the old web client gets `now+30` until the server's
  `end_date` lands (seconds). Accepted (B2a step 5).
- R2. `stacks_after` shapes an estimate only; offset-checked and clamped; the server overwrites it (F3).
- R3. The paywall line keys on the LOCAL plan; a stale local plan hides the line. Copy only; self-heals on refresh.
- R4. A door rollback leaves the merged client showing the line on a stale page until the trial-409 copy explains it
  (B2a 9.2).

## 7. Review round 1 dispositions (v1 -> v2)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | "Merged and deployed dark" is false; B2a deploys are live steps | Section 1 header corrected; section 0 step 2 names the deploys |
| 2 | P2 | Capture fixes stacksAfter, not plan; a later checkout pairs wrongly | `PendingCheckout` keyed by order id, resolved at the first statement; plan and stacksAfter passed down (2.2, 2.3, T6, P2) |
| 3 | P2 | Trial 409 drops the state heal; error-styled toast | Heal kept verbatim; informational snackbar; edge stated (2.3, P6) |
| 4 | P2 | Tier is platform, not account | Header restated; `bpass: accepted` required |
| 5 | P2 | No closure ledger | `docs/audit/oi341-piece-b2b-client.closure.yaml` (2.6) |
| 6 | P2 | Service wiring has no behavioural proof | Decisions extracted to pure functions (T6 added); pins declared presence-only with the reason |
| 7 | P2 | Paywall widget harness unnamed | Harness named; fallback stated (section 3) |
| 8 | P2 | `kReferralTrialPlan` has no parity pin; it is not copy | `lib/core/constants/subscription_plans.dart` + parity test |
| 9 | P2 | 4.6 deviation unstated | Stated in section 0 with B2a 9.2's reason |
| 10 | P3 | F11 "always in the amber window" false | F11 corrected; OI-348 wording conditioned |
| 11 | P3 | EST seal extraction details | Takes `(expiresAt, plan, now)`, moves `ddMmYy`, zone and trial back-computation stated, commit type stated |
| 12 | P3 | Estimate shape, golden strings, zones, parse hardening | `toLocal()` on both branches, literal goldens, inputs carry zones, offset check + 400-day clamp |
| 13 | P3 | Docs/registry consistency | Full list in 2.6 (OI board, payment.md rule 9, B2a ledger, registry ranges, A7 note, budget) |
| 14 | P3 | Stale citations | F1/F2/F6 corrected |

## 8. Review round 2 dispositions (v2 -> v3, mechanical only; verdict CONVERGED)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| P2-1 | P2 | One record nulled at every checkout; an earlier payment falls back to the later plan | `PendingCheckouts` store keyed by order id, bounded at 4, cleared only on user change (2.2, 2.3, T6) |
| P2-2 | P2 | `razorpay_409_already_pro_test.dart:51` reddens | Repointed, not loosened (section 3) |
| P2-3 | P2 | "Equal instant" mutant is equivalent | Dropped; a 1 ms boundary row added (T1) |
| P2-4 | P2 | F10 false; harness misses Fraunces and dispose telemetry | F10 corrected; precedent `swap_picker_sheet_test.dart`; fallback removed |
| P2-5 | P2 | T2 lacks the server's real timestamp shape | `+00:00` microsecond form accepted; date-only refused; offset after the time part (2.2, T2) |
| P2-6 | P2 | Parity read hard-pins migration 159; helper misses `private.` | Latest definition of `private.grant_referral_days`, comment-stripped (section 3) |
| P2-7 | P2 | Registry shape: per-concept keys, `presence_only` would mislabel the door | New concept `trial_stacking_client_estimate` with sibling key + `regression_test_wiring`; range list widened (2.6) |
| P2-8 | P2 | "One behaviour differs with the door shut" false | Section 0 lists all three |
| P2-9 | P2 | No copy-review row; parent 9.1/9.2 contradict v3 | Ledger row `blocked_on_user` for the wording; parent sections marked superseded (2.6) |
| P3-1..6 | P3 | "First statement" pin; `plan` shadowing; total parse; test dirs and TZ; EST lowercase; unmatched-record visibility; inert callbacks | All folded (2.2, 2.3, section 3) |
