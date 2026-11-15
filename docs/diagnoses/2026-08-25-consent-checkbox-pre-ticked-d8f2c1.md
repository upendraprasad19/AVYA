---
bug_id: d8f2c1
date: 2026-08-25
batch: launch-blockers-1a
status: fixed
blast_radius: account
symptom: >
  The sign-up consent checkbox for Privacy Policy and Terms was PRE-TICKED. A user could create an
  account having made no affirmative gesture toward the policies at all — the box arrived already
  agreeing on their behalf. This app processes health data and is going through Play review with a
  Data Safety declaration, where that is the weakest defensible posture.
concept: terms_acceptance
sot_registry_entry: >
  None added. `terms_acceptance` is already registered (migration 032 + 118, writers and readers
  intact) and this change alters neither writer nor reader — only the INITIAL VALUE of the widget
  state that gates the button. Stated explicitly rather than left implied, because the neighbouring
  fields in that flow do have registry entries and the absence here is deliberate, not an omission.
writers:
  - { file: lib/features/auth/screens/sign_in_screen.dart, method: "_privacyAccepted field initialiser — the value changed from true to false", line: 111 }
  - { file: lib/features/auth/screens/sign_in_screen.dart, method: "_PrivacyCheckboxRow onChanged — the user's tick, now the only way the flag becomes true", line: 1015 }
readers:
  - { file: lib/features/auth/screens/sign_in_screen.dart, method: "CREATE ACCOUNT enabled: gate — the sole consumer", line: 1023 }
hive_key_prefix: not_applicable — widget state only; the consent TIMESTAMP write is unchanged by this fix.
hive_key_formula: not_applicable — see hive_key_prefix.
sync_methods: not_applicable — no sync path changed.
restore_methods: not_applicable — no restore path changed.
cloud_table: users
cloud_columns: [terms_accepted_at, terms_version]
contract_test_path: test/auth/terms_skip_test.dart
ist_handling: not_applicable — no date key or counter reset is touched. The consent timestamp write is unchanged.
provider_invalidations: none — local widget state.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no user-scoped Hive access added. The pre-existing write-ordering guard from b3f9e7 is untouched.
forbidden_patterns_checked: >
  Checked and clean. No Container color+decoration, no inline isPro, no raw Hive write at the
  pre-session point (the b3f9e7 dead-write class is NOT reintroduced — the consent capture still
  travels through `_ensureLocalUser`, not a direct box write at tap time).
proposed_fix: >
  Initialise `_privacyAccepted` to false so the user's tick is the affirmative action, and pin the
  default with a regex-matched assertion so a reformat cannot silently un-pin it.
regression_test_planned: [test/auth/terms_skip_test.dart]
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean. test/auth/terms_skip_test.dart 10/10; mutation (false→true) reddens the new regex assertion." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "No Hive write added or moved. The consent timestamp still flows through _ensureLocalUser as b3f9e7 established." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL; users.terms_accepted_at already exists (migration 032)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No backfill; migration 118 already handled historical NULLs." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function involved." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads consent state." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Razorpay/OneSignal untouched." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "The values written to users.terms_accepted_at / terms_version are unchanged; only WHEN the button unlocks differs." }
impact_analysis: >
  Severity: no data risk, no crash. It is a compliance posture change with a real product cost,
  and both halves should be said plainly.

  The gain: DPDP §6(1) requires consent by a "clear affirmative action". A pre-ticked box is the
  textbook example of what does not qualify — the GDPR equivalent was settled in Planet49. For an
  app shipping health data through Play review, the button-press argument the previous design
  rested on ("tapping CREATE ACCOUNT with the box checked is the affirmative action") is arguable
  rather than clean, and not worth defending to a reviewer.

  The cost, stated rather than buried: CREATE ACCOUNT is now disabled until the user ticks, which
  will cost some signup conversion. That is a product trade-off. Reverting is a one-word change,
  and the test names it so the revert is a conscious act rather than a drift.

  This REVERSES a documented earlier decision (the Q2 pre-check, citing the common Indian fintech
  pattern — CRED, Zerodha, Razorpay). That decision was not wrong on its own terms; the Play-review
  context is what changed.

  ⚠ KNOWN RESIDUAL — GOOGLE OAUTH IS NOT GATED BY THIS CHECKBOX, and this fix makes the asymmetry
  sharper rather than creating it. `_privacyAccepted` has exactly one consumer, the email
  CREATE ACCOUNT button (`sign_in_screen.dart:1023`). `signInWithGoogle()` (`:365`) is a separate
  affordance with no consent gate, and Google users converge instead on the PRE-EXISTING
  `ensureTermsConsentFallback` (from b3f9e7, untouched here), which auto-stamps
  `terms_accepted_at` from `created_at` with no user gesture at all. So after this change the app
  runs two consent regimes at once: an explicit tick for email, a backdated timestamp for Google —
  which is the PRIMARY CTA. Before this change the asymmetry existed too but was invisible, since
  neither path required a gesture.

  Deliberately NOT fixed here, and the reason matters: gating the Google button is a UX change to
  the app's primary sign-in affordance, needing its own design (where the checkbox sits relative
  to the OAuth card, what happens on the post-redirect return). Bolting it onto a copy fix would
  be the worse call. It is recorded as an explicit pre-launch risk in
  `docs/operations/GO_LIVE_CHECKLIST.md` §3 — which is the artifact whose entire job is carrying
  launch blockers — so a Play submission cannot happen without someone reading it. Found by the
  B-pass on this batch (Finding 1, P1).
---

# d8f2c1 — the consent checkbox agreed on the user's behalf

## What the user saw

The sign-up form's Privacy Policy / Terms checkbox arrived **already ticked**. Creating an account
required no affirmative gesture toward the policies.

## The fix

```dart
bool _privacyAccepted = false;   // was: true
```

`CREATE ACCOUNT` already gated on this flag (`:1023`), so the button is simply disabled until the
user ticks. The default is pinned by a regex-matched assertion in `test/auth/terms_skip_test.dart`
— matched by regex rather than a literal line so a reformat cannot un-pin it, and mutation-proven
(flipping it back to `true` reddens).

## What this does not fix

Google OAuth — the primary CTA — has no consent gate and never did. Those users get
`terms_accepted_at` auto-stamped from `created_at` by a pre-existing fallback. This change makes
that gap more visible by fixing the email path around it. It is carried as a pre-launch risk in
`docs/operations/GO_LIVE_CHECKLIST.md` §3 rather than silently patched, because gating the primary
sign-in affordance is a UX design decision, not a copy fix.
