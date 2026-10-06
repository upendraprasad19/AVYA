---
bug_id: d4a8f6
date: 2026-09-16
batch: email-confirm-ux
status: fixed
blast_radius: account
symptom: >-
  The email-confirm-ux batch's new "already signed in" guard state
  (`ConfirmEmailScreen._buildAlreadySignedInState`, OI-205's interim guard)
  ships a SIGN OUT button whose `onTap` called
  `ref.read(authNotifierProvider.notifier).signOut()` directly, with no
  try/catch — the bare-await shape every other DIRECT `AuthNotifier.signOut()`
  call site in the app had before this exact class of gap was closed at each
  of them. CORRECTED (B-pass Finding 1 on this exact fix): every step
  inside `_teardown()` already swallows its own throw in its own
  try/catch (`auth_provider.dart:891-905`), and `_performSignOut`'s own
  try/catch around `_teardown().timeout(...)` (`:871-884`) also does not
  rethrow — so an internal teardown step throwing, or the whole call timing
  out, cannot surface as a thrown exception from `signOut()`. The narrower,
  genuinely-reachable throw this guard protects against is the unguarded
  `state = ...` assignment after teardown (`:886`, e.g. notifier disposed
  mid-call) or `ref.read(authNotifierProvider.notifier)` itself throwing at
  the call site. (The timeout case — which this guard structurally cannot
  catch, because nothing throws — is tracked separately as OI-208.)
  Regardless of the exact mechanism, this file lacked the same defensive
  shape its two precedents already carry for the identical call pattern,
  which is the gap that actually needed closing here. Caught not by a review
  round but by `pre-push.sh`'s full
  `flutter test` run: `test/contracts/signout_unbinds_sdk_identity_test.dart`'s
  DERIVED per-call-site enumerator (`.auth.signOut(`-shaped lines, resolved
  per-file) found this new file lacked a matching
  `await releaseDeviceSessionIdentity()` anywhere in it, and failed the actual
  `git push` to `main` before this landed.
concept: device_session_identity_binding
recurrence: >-
  Third instance of the OI-51 class, not a new one. e7b3c5 (2026-07-27)
  closed the original gap (signOut() released nothing outside Hive/Supabase).
  A later, undocumented "round 2" of the same DERIVED gate widened the
  enumerator from two hard-coded paths to a tree-wide grep and found
  `settings_screen.dart`'s `_SignOutButton` had the identical bare-await
  shape — its own in-code comment records this ("OI-51 round 2: the DERIVED
  gate found this site — no reviewer did, and neither did I") and fixed it
  with the exact try/catch + defensive `releaseDeviceSessionIdentity()` shape
  this doc's fix mirrors. `perform_sign_out.dart` independently carries the
  same defensive pattern for its own notifier-then-fallback shape. This
  instance is the same gap recurring in NEW code (a screen that did not exist
  before this batch), not a regression of either prior fix — both of those
  remain intact and still pass.
related_bugs: e7b3c5
sot_registry_entry: device_session_identity_binding
writers:
  - { file: lib/features/auth/screens/confirm_email_screen.dart, method: _buildAlreadySignedInState_onTap, line: 211 }
  - { file: lib/features/auth/screens/confirm_email_screen.dart, method: _buildAlreadySignedInState_onTap_catch, line: 220 }
readers:
  - { file: lib/features/auth/providers/auth_provider.dart, method: releaseDeviceSessionIdentity, line: 49 }
hive_key_prefix: n/a — the bound identities live in the OneSignal + Crashlytics SDKs and in Dart static fields, never in Hive
hive_key_formula: n/a — no Hive key participates in this contract
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/signout_unbinds_sdk_identity_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: "a `.auth.signOut(`-shaped call site under lib/ with no `await releaseDeviceSessionIdentity()` anywhere in its own file", absent_after_fix: true }
proposed_fix: >-
  Wrap the SIGN OUT button's `AuthNotifier.signOut()` call in try/catch,
  mirroring settings_screen.dart's `_SignOutButton` byte-for-byte in shape:
  on any throw, log it and call `await releaseDeviceSessionIdentity()`
  defensively before falling through to the existing unconditional
  `context.go('/sign-in')`. No new import needed — both symbols were already
  reachable via this file's existing `auth_provider.dart` import.
regression_test_planned:
  - test/contracts/signout_unbinds_sdk_identity_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter test test/contracts/signout_unbinds_sdk_identity_test.dart test/auth/confirm_email_screen_test.dart test/contracts/confirm_email_error_mapping_test.dart -> 22/22 passed (independently reproduced by the B-pass via --reporter=json). Mutation-proven: reverting the try/catch to the original bare await -- which shifts the signOut() call from line 211 to line 210, since removing the 'try {' line moves everything below it up by one -- reddens exactly the 'DERIVED: every .auth.signOut( call site in lib/ reaches releaseDeviceSessionIdentity()' assertion (Expected: empty, Actual: [this file, line 210]) with the other 9 assertions in this 10-test file staying green; re-applying the fix restores 10/10. (Corrected post-B-pass, Findings 3-4: this evidence string originally cited line 211 for the MUTATED state -- correct only for the fixed state -- and 8 siblings where 10 total minus 1 failing is 9.)" }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive key participates — this concept lives entirely in the OneSignal/Crashlytics SDKs and Dart static fields" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no table read or written" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "client-only change" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: verified, evidence: "the defensive call reuses the SAME releaseDeviceSessionIdentity() function already exercised by e7b3c5's own OWED live-handset verification — this fix adds a new CALLER, not new SDK-facing behavior, so no new live check is owed" }
  - { tier: 12_client_server_contract, status: not_applicable, evidence: "no client-server contract change; this is a client-only defensive completeness fix" }
impact_analysis: >-
  Account-tier, self-contained, no redeploy. Narrow blast radius: this is the
  ONLY call site the DERIVED enumerator found missing (verified by re-running
  the full assertion after the fix — 0 remaining in the `missing` list), and
  the guard state it belongs to (OI-205's interim already-signed-in block)
  did not exist before this same batch, so no user has hit the unfixed shape
  in production. Caught before the push that would have landed it on `main`,
  by the exact gate this class of bug has a standing, derived (not
  hand-listed) test for — the gate worked as designed. The two established
  precedents (settings_screen.dart, perform_sign_out.dart) were independently
  re-verified to still pass unchanged; this fix does not touch either.
---

# The new OI-205 "already signed in" SIGN OUT button skipped the OI-51 device-identity release on a `signOut()` failure

## What was actually wrong

The email-confirm-ux batch's round-2 fix added `ConfirmEmailScreen._buildAlreadySignedInState`
with a SIGN OUT button calling `ref.read(authNotifierProvider.notifier).signOut()`
directly, with no try/catch:

```dart
onTap: () async {
  await ref.read(authNotifierProvider.notifier).signOut();
  if (context.mounted) context.go('/sign-in');
},
```

This is exactly the bare-await shape `test/contracts/signout_unbinds_sdk_identity_test.dart`'s
DERIVED enumerator exists to catch: it walks every `.dart` file under `lib/`,
finds every line shaped like a sign-out call, and — per file — requires that
file to independently contain `await releaseDeviceSessionIdentity()`
somewhere. `AuthNotifier.signOut()` itself DOES reach the release on its
normal path (`_performSignOut` → `_teardown` → `unbindSessionIdentity`).
**Corrected** (the B-pass on this exact fix, Finding 1): the framing
originally here was "any step inside `_teardown()` throws before reaching
that point" — but every
step in `_teardown()` (`auth_provider.dart:891-905`) already swallows its own
throw internally, and `_performSignOut`'s own try/catch around the whole
call (`:871-884`) also does not rethrow, so an internal step throwing cannot
actually escape `signOut()`. The guard this fix adds is genuinely needed —
it matches an established, already-shipped precedent for the identical call
shape — but the specific mechanism it protects against is narrower: the
unguarded `state = ...` assignment after teardown (`:886`) or
`ref.read(authNotifierProvider.notifier)` itself throwing at the call site.
A related but distinct gap — a `_teardown()` TIMEOUT, rather than a throw,
also leaves the device bound with no exception for any of the three call
sites to catch — is real, pre-existing across all three sites, and is
tracked separately as OI-208 rather than folded into this fix.

## Why this wasn't a false positive

Two other call sites in the app make the identical
`ref.read(authNotifierProvider.notifier).signOut()` call, and neither trips
the enumerator, because both already carry the defensive fallback:

- `lib/features/profile/screens/settings_screen.dart:355-374`
  (`_SignOutButton`) — its own comment: *"OI-51 round 2: the DERIVED gate
  found this site — no reviewer did, and neither did I."*
- `lib/features/profile/screens/profile/perform_sign_out.dart:19-42` —
  catches the notifier's throw, falls back to a raw
  `SupabaseService.instance.client.auth.signOut(scope: SignOutScope.local)`,
  then explicitly releases: *"this fallback runs precisely BECAUSE the
  notifier path failed — possibly before it reached the unbind."*

Both establish the same fix shape this doc applies a third time. Bypassing
`AuthNotifier.signOut()` entirely in favor of a raw Supabase-only call (to
avoid tripping the enumerator a different way) was considered and rejected —
that would reintroduce the class of stale-Hive-data bug the notifier's full
teardown exists to prevent, trading one OI-51-shaped gap for a worse one.

## The fix

```dart
onTap: () async {
  try {
    await ref.read(authNotifierProvider.notifier).signOut();
  } catch (e) {
    debugPrint('[ConfirmEmailScreen] signOut error: $e');
    await releaseDeviceSessionIdentity();
  }
  if (context.mounted) context.go('/sign-in');
},
```

Structurally identical to `settings_screen.dart`'s `_SignOutButton` (same
try → await signOut() → catch(e) → debugPrint → comment →
releaseDeviceSessionIdentity() → [snackbar] → unconditional context.go
shape), minus its screen-specific snackbar (a UX nicety, not part of the
OI-51 contract). NOT byte-for-byte (B-pass Finding 5): the debugPrint tag
string and the explanatory comment text both differ between the two files,
which the original wording of this doc overstated. Navigation to
`/sign-in` remains unconditional, reached whether or not the catch fires —
matching the established precedent exactly.

## Residual gap — not fixed here (OI-208)

The B-pass on this fix (Finding 2) surfaced a related, deeper gap: `_performSignOut`'s try/catch around
`_teardown().timeout(signOutTimeout)` does not rethrow a genuine TIMEOUT any
more than it rethrows an internal step's throw (both are swallowed
identically). So if teardown actually HANGS and times out before reaching
`unbindSessionIdentity()`, `signOut()` still returns normally to every
caller — meaning none of the three try/catch guards (this one,
`settings_screen.dart`, `perform_sign_out.dart`) ever fire, because nothing
throws for them to catch. This is pre-existing and identical across all
three sites, not introduced or worsened by this fix; closing it needs
`_teardown()` itself to signal whether it genuinely completed, which is a
change to the shared sign-out contract every caller relies on — filed as
OI-208 rather than attempted inline.

## How this was caught

Not by either plan-review round (round 1 focused on the OI-205
risk-documentation asymmetry; round 2 focused on the sign-in-CTA no-op that
motivated this exact button's existence) and not by the B-pass that ran
alongside those rounds on the whole batch — none of the three had reason to
re-derive OI-51's own tree-wide enumerator against a brand-new file. It was
caught by `pre-push.sh`'s full `flutter test` run, which failed the actual
push to `main`. This is the gate working exactly as designed: a DERIVED,
tree-wide check that automatically covers new code, rather than a
hand-maintained list that would need remembering to update.

A second, dedicated B-pass was then self-triggered on this fix itself before
committing it (per §4.3 — this diagnose-doc's own blast radius is `account`).
It found no code defect, but did find three precision errors in this doc's
own narrative, all corrected above: the originally-stated failure mechanism
("any step in `_teardown()` throws") does not match what the code can
actually do; the mutation-proof evidence string cited the fixed state's line
number (211) for the mutated state, which is actually line 210 (removing the
`try {` line shifts everything below it up by one); and it undercounted the
passing sibling assertions (10 total − 1 failing = 9, not 8). None of these
affected whether the fix itself is correct — only whether this document's
account of it was.
