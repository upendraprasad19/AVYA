---
bug_id: e7b3c5
date: 2026-07-27
batch: sdk-identity-prompt-safety
status: fixed
blast_radius: account
symptom: >-
  Sign-out cleared Hive and Supabase but released nothing the device holds
  outside them. After user A signed out the handset was still
  OneSignal external_id = A and Crashlytics userIdentifier = A, so A's push
  notifications — carrying A's calories, streaks and coach messages — kept
  arriving on a phone A may have sold, returned or handed on. Three static
  onStateChanged callbacks holding the previous session's Riverpod closures
  also survived; one of the three had no clear site anywhere in the codebase.
concept: device_session_identity_binding
recurrence: >-
  Not a recurrence of a prior bug id, but a textbook instance of the
  incomplete-sweep class (feedback_ist_sweep_gap): the OI named a pair of
  callbacks, the first draft of this fix cleared exactly that pair, and
  RankService — installed in app.dart three lines below them — was missed.
  Same structural answer as a3d7b1: DERIVE the required set from the
  declarations instead of restating it, so a fourth callback joins the set
  automatically.
related_bugs: a3d7b1
sot_registry_entry: device_session_identity_binding
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method: _ensureLocalUser_OneSignal_login, line: 675 }
  - { file: lib/features/auth/providers/auth_provider.dart, method: _ensureLocalUser_crashlytics_setUserIdentifier, line: 655 }
  - { file: lib/features/auth/providers/auth_provider.dart, method: unbindSessionIdentity, line: 417 }
  - { file: lib/app.dart, method: AppState_dispose, line: 95 }
readers:
  - { file: lib/core/services/subscription_service.dart, method_or_widget: onStateChanged, line: 238 }
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: onStateChanged, line: 755 }
  - { file: lib/core/services/rank_service.dart, method_or_widget: onStateChanged, line: 53 }
hive_key_prefix: n/a — the bound identities live in the OneSignal + Crashlytics SDKs and in Dart static fields, never in Hive
hive_key_formula: n/a — no Hive key participates in this contract
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/signout_unbinds_sdk_identity_test.dart
ist_handling: []
provider_invalidations:
  - { callback: SubscriptionService.onStateChanged, invalidates: "subscriptionInfoProvider, messageLimitProvider" }
  - { callback: NutritionWriteService.onStateChanged, invalidates: "dailyNutritionProvider, nutritionSummaryProvider, recentFoodLogsProvider, macroTargetsProvider, aiInsightProvider, foodLogProvider" }
  - { callback: RankService.onStateChanged, invalidates: "userProfileProvider" }
telemetry_op_types:
  success: [auth_signed_out]
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: "a static onStateChanged declared in lib/ with no clear in unbindSessionIdentity", absent_after_fix: true }
  - { pattern: "a callback installed in app.dart initState with no matching clear in dispose", absent_after_fix: true }
  - { pattern: "an unbind running on a platform where the bind never ran (web OneSignal / debug Crashlytics)", absent_after_fix: true }
proposed_fix: >-
  Extract unbindSessionIdentity() from signOut() so it is directly callable in
  tests, and have it release every per-user identity the device holds outside
  Hive: OneSignal.logout() under the same !kIsWeb guard as the bind site,
  Crashlytics setUserIdentifier('') under the same !kDebugMode guard, and all
  three static onStateChanged callbacks. Each step keeps signOut()'s existing
  per-step try/catch so a third-party SDK throw cannot abort the rest of the
  sign-out. Separately restore set/clear symmetry in app.dart by clearing
  RankService.onStateChanged in dispose(), where it was installed but never
  released.
regression_test_planned:
  - test/contracts/signout_unbinds_sdk_identity_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "9/9 in the new contract test plus 4/4 in the pre-existing rank_service_local_profile_update_test; flutter analyze clean. Both DERIVED tests negative-controlled independently: removing the RankService clear from unbindSessionIdentity fails ONLY 'DERIVED COMPLETENESS' with 'RankService declares a static onStateChanged but sign-out never clears it'; removing it from app.dart dispose fails ONLY 'DERIVED SYMMETRY' with 'app.dart installs RankService.onStateChanged but never clears it'." }
  - { tier: 2_hive, status: verified, evidence: "no Hive key participates — signOut's existing clearAllData + deleteAllFilesForCurrentUser steps are untouched and still run BEFORE the new unbind" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no table read or written" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "client-only change; no Edge Function touched by this fix" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: verified, evidence: "OneSignal external_id and Firebase Crashlytics userIdentifier are the two external bindings; both are released by the same SDK calls that set them, under the identical platform guards. Live confirmation that a signed-out device stops receiving pushes needs APK +37 on a handset and is recorded as OWED below — it is not claimed here." }
  - { tier: 12_client_server_contract, status: verified, evidence: "sign-in still binds: the REGRESSION case asserts OneSignal.login( and setUserIdentifier( both remain, so push targeting for the next user is preserved" }
impact_analysis: >-
  Account-tier, self-contained, no redeploy. The exposure is the SIGNED-OUT
  WINDOW, and stating it precisely matters because the OI overstates it: this is
  NOT "user B's crashes get attributed to user A". When B signs in,
  _ensureLocalUser overwrites both bindings, so B is attributed correctly. The
  real leak is the gap between A signing out and anyone signing in — the device
  stays external_id = A indefinitely, so A's notifications keep landing on a
  handset A no longer controls. That is a privacy leak of fitness data to
  whoever now holds the phone, and it is the reason this shipped as a fix rather
  than hygiene.

  The static-callback half is smaller but real: each closure captures the
  previous session's Riverpod container, so a write after sign-out invalidates
  providers in a scope that no longer corresponds to the signed-in user.
  Subscription and Nutrition were released on app.dart dispose() — widget
  teardown, which a sign-out-and-navigate never triggers. RankService was
  released NOWHERE: installed at app.dart:76 next to the other two, absent from
  dispose(), and absent from every other site (grep over lib/ and test/ returns
  exactly one assignment). It leaked past both sign-out and teardown.

  OWED, not claimed: the two SDK calls are platform channels and are pinned by
  comment-stripped source-grep plus the wiring assertion, not by driving the
  real plugin. Confirming on a live handset that a signed-out device stops
  receiving A's pushes requires APK +37 installed and is tracked as OI-55's
  sibling verification. The behavioural half of the test — the three static
  callbacks — IS a real state transition and is asserted as one.
---

# `signOut` released Hive and Supabase but nothing the device held outside them

## What was actually wrong

`_ensureLocalUser` binds the device to a user at sign-in in two places:

| Binding | Site | Guard |
|---|---|---|
| Crashlytics `setUserIdentifier(user.id[0:8])` | `auth_provider.dart:655` | `!kDebugMode` |
| `OneSignal.login(user.id)` | `auth_provider.dart:675` | `!kIsWeb` |

`signOut` cleared `UserRepository`, the Hive user session, and the Supabase
session — and touched neither. A repo-wide grep for `OneSignal.logout()` or
`setUserIdentifier('')` returned nothing before this batch.

## The correction to how this was filed

OI-51 describes it as cross-user attribution. It is not. `_ensureLocalUser`
overwrites both bindings when the next user signs in, so B is never mistaken for
A. The window that matters is **after A signs out and before anyone signs in**,
which on a sold or handed-on device is unbounded. During it the handset is still
`external_id = A` and every `morning-alert`, streak nudge and coach push
addressed to A arrives — with A's numbers in the body.

Two of the OI's four sub-findings were already closed before this batch, and the
diagnose-doc records that rather than claiming credit for them: Razorpay
callbacks are nulled by `razorpay_service._onUserChanged()` via
`SingletonLifecycleRegistry` (2026-05-20 audit), and `SubscriptionService.onStateChanged`
was already reset — but at `app.dart:90`, inside `dispose()`.

## The third callback, and why the first draft missed it

The first draft of this fix cleared the two callbacks the OI named. Enumerating
the declaration site instead of the ticket found a third:

```
$ grep -rn "static void Function()? onStateChanged" lib/
lib/core/services/nutrition_write_service.dart:755
lib/core/services/rank_service.dart:53
lib/core/services/subscription_service.dart:238
```

`RankService.onStateChanged` is installed at `app.dart:76`, immediately below
the other two. `dispose()` at `:90-91` clears only the first two. Nothing else
in `lib/` or `test/` assigns it. So it was the worst of the three — it survived
sign-out *and* widget teardown — and it was invisible to a fix that trusted the
ticket's list.

## Why the tests are derived rather than listed

A hand-written list of three would have passed on the day this bug was
introduced. Both new assertions compute their own required set:

- **DERIVED COMPLETENESS** walks `lib/`, finds every `static void Function()? onStateChanged`
  declaration, resolves its owning class, and requires a matching
  `X.onStateChanged = null` inside `unbindSessionIdentity`. A fourth callback
  added tomorrow fails this test until it is cleared. It also asserts the
  enumerator found ≥3, so a broken enumerator cannot pass vacuously.
- **DERIVED SYMMETRY** extracts every `X.onStateChanged = () {` install in
  `app.dart` and requires a matching clear in the same file — pinning the
  teardown half independently, so either regression fails on its own.

This is the structural answer a3d7b1 reached for the same class of miss: derive
the set from the source of truth, never restate it.

## Guards

Both SDK calls mirror their bind sites exactly — `!kIsWeb` for OneSignal,
`!kDebugMode` for Crashlytics. An unbind running where the bind never did would
be a new failure mode, not a fix. Each step keeps `signOut`'s per-step
`try`/`catch` shape so a throwing third-party SDK cannot abort sign-out
partway through.
