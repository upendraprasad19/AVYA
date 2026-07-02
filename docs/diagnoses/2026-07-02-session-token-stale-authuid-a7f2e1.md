---
bug_id: a7f2e1
date: 2026-07-02
batch: fix-session-token-stale-authuid
status: fixed
blast_radius: account
symptom: >
  In-session account switch (sign-out userA → sign-in userB as a DIFFERENT user)
  leaves every mixin tab (Home/Train/Nutrition/Profile) stuck on the loading
  SKELETON forever, until a full page reload. Reproduced live on prod web
  2026-07-02 (test5 → test7): restore SUCCEEDED (restore_completed status=success
  path=singlecall) and the data was in Hive, yet Home never rendered it. A reload
  fixes it with NO re-restore.
concept: auth_hive_owner_agreement
sot_registry_entry: auth_hive_owner_agreement
symptom_class: stale-riverpod-cache / missed-liveness-edge (Layer B)
writers:
  - { file: lib/features/auth/providers/auth_invalidation_provider.dart, method: authUserIdTokenProvider, line: 48 }
readers:
  - { file: lib/shared/mixins/hive_tab_scaffold.dart, method: isSessionTearingDown, line: 96 }
hive_key_prefix: n/a (Riverpod provider token, not a Hive key)
hive_key_formula: n/a
sync_methods: n/a (client-only Riverpod liveness fix; no cloud round-trip)
restore_methods: n/a (upstream of restore — the skeleton gate short-circuits build() BEFORE any restored-data provider is read)
cloud_table: n/a
cloud_columns: n/a
contract_test_path: test/contracts/session_token_stale_authuid_recovery_test.dart
ist_handling: n/a (no date/time logic)
provider_invalidations:
  - authUserIdTokenProvider (re-emits on authStateProvider + hiveSessionOwnerProvider; consumed by every user-scoped provider + the isSessionTearingDown tab gate)
telemetry_op_types:
  - none (the stuck state reads through GuardedBox.empty which returns null silently — zero telemetry after the last restore event; this SILENCE is itself the diagnostic signal)
cross_account_guard: >
  PRESERVED. The token still returns '<anon>' unless authUid == hiveOwner; the fix
  only changes WHERE authUid is read (live SupabaseService.currentUser — the same
  source wrapUserScopedBox uses — instead of the cached currentUserProvider). A
  mismatch (or either side null) still yields '<anon>', so a stale/wrong uid can
  never serve another account's box. Regression test asserts isolation holds in
  BOTH kill-switch states.
forbidden_patterns_checked: >
  No raw Hive.box outside the guard path (the configBox read is the GLOBAL,
  non-user-scoped box, matching guarded_box.dart's sibling kill-switch — no
  recursion through wrapUserScopedBox). No new setState. No secret exposure.
  Kill-switch read is defensive (unopened box → fix stays ON).
proposed_fix: >
  OPT-1 (converged via ×2 context-blind plan review): authUserIdTokenProvider reads
  the LIVE auth uid — debugAuthUidResolverForTests?.call() ?? SupabaseService.instance.currentUser?.id
  (try/catch → null) — instead of ref.watch(currentUserProvider)?.id, keeping
  ref.watch(authStateProvider) + ref.watch(hiveSessionOwnerProvider) for reactivity.
  currentUserProvider is a plain non-reactive Provider that caches
  SupabaseService.currentUser on first read and is NEVER invalidated (its ONLY
  consumer was this token), so on an account switch it stayed cached as userA →
  authUid(A) != hiveOwner(B) → '<anon>' forever. Reading live makes the owner-edge
  rebuild recover. Kill-switch configBox['disable_live_auth_token_read'] (default
  OFF = fix ON) reverts to the verbatim cached-provider read (§4.6). OPT-2 (make
  currentUserProvider reactive) was REJECTED — it fires on authStateProvider BEFORE
  openForUser completes, re-introducing the ordering race.
regression_test_planned: >
  test/contracts/session_token_stale_authuid_recovery_test.dart — 4 cases: (1) FIX
  default: token recovers to the LIVE uid on account-switch even when the cached
  currentUserProvider is STALE (RED→GREEN — fails on pre-fix, passes on fix);
  (2) FIX isolation: live authUid != owner → '<anon>'; (3) kill-switch reverts to
  the cached-provider path verbatim; (4) isolation holds in the kill-switch state.
  Plus test/contracts/auth_invalidation_timing_test.dart migrated to the
  debugAuthUidResolverForTests seam (its currentUserProvider overrides went dead
  under OPT-1). All 16 (5 files) green + flutter analyze clean.
touched_layers_checked:
  - { tier: client_code, status: fixed_in_this_batch, evidence: "auth_invalidation_provider.dart live-authUid read + kill-switch; flutter analyze clean; 16 tests green across 5 contract files" }
  - { tier: hive_local_state, status: verified, evidence: "kill-switch reads GLOBAL configBox['disable_live_auth_token_read'] (Hive.box('configBox'), matches guarded_box sibling); regression test exercises both flag states via a temp Hive configBox" }
  - { tier: client_server_contract, status: verified, evidence: "live prod repro (test5→test7) + reload-fixes-with-no-restore + restore_completed success telemetry confirm the strand is upstream of data providers, not a data/restore fault" }
  - { tier: postgres_schema, status: not_applicable, evidence: "client-only Riverpod liveness fix" }
  - { tier: postgres_data, status: not_applicable, evidence: "no cloud writes" }
  - { tier: migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: edge_function, status: not_applicable, evidence: "no EF change" }
  - { tier: cron_jobs, status: not_applicable, evidence: "no cron" }
  - { tier: rls_policies, status: not_applicable, evidence: "no RLS change" }
  - { tier: storage, status: not_applicable, evidence: "no storage" }
  - { tier: secrets, status: not_applicable, evidence: "no secrets" }
  - { tier: external_services, status: not_applicable, evidence: "no external service" }
impact_analysis: >
  Affects any in-session account switch (sign-out A → sign-in B) OR an in-session
  sign-out→re-sign-in as the same user where a provider cached '<anon>' during the
  owner-null window — Home + all 4 mixin tabs stuck on skeleton until reload. Cold
  boot / first-login are UNAFFECTED (splash awaits openForUser before the
  ProviderContainer serves UI, so currentUserProvider first-builds with the correct
  user). No data corruption (reload renders the same Hive perfectly). Blast-radius
  account (lib/features/auth/** — the auth-invalidation liveness seam; the
  platform-tier primitives guarded_box.dart / hive_user_session.dart are NOT
  touched). If the fix were wrong it could (a) leave the gate stuck (status quo) or
  (b) — the risk the review scrutinized — serve one account's box to another; the
  authUid==hiveOwner equality guard (unchanged) prevents (b), verified by the
  isolation cases in both kill-switch states.
related_bugs:
  - b8e3f1 (OBS-6, 2026-06-21 — session-open race → blank Home)
recurrence: >
  Recurrence of b8e3f1 (OBS-6). That fix repaired the BOX read (guarded_box Layer A
  owner-null serve-empty + the /restoring router gate) and the blank-Home/error-card
  symptom, but did NOT touch the token SOURCE (currentUserProvider), so the residual
  neutral stuck-SKELETON symptom survived. Same family (auth-invalidation Layer B
  liveness), different actor (the token's authUid source vs the box read). Prior
  instance cited so a future audit can verify the seam is now fully closed.
---

# a7f2e1 — Account-switch stuck-Home: authUserIdTokenProvider read a stale cached authUid

## One-paragraph story

The Home (and Train/Nutrition/Profile) skeleton is gated by `isSessionTearingDown`
(`hive_tab_scaffold.dart:96` → `ref.watch(authUserIdTokenProvider) == '<anon>'`),
which sits **upstream of every data provider** (`home_screen.dart:250`
`if (isLoading || isSessionTearingDown) return ScreenLoadingSkeleton`). On an
in-session account switch, `authUserIdTokenProvider` rebuilds on the owner-edge
(`hiveSessionOwnerProvider` fires when `openForUser` stamps the new owner) but
re-read its `authUid` from **`currentUserProvider`** (`auth_provider.dart:41-47`)
— a plain, non-reactive `Provider` that caches `SupabaseService.currentUser` on
first read and is **never invalidated** (its only consumer was this token). So it
stayed cached as `userA` → `authUid(A) != hiveOwner(B)` → `'<anon>'` **forever** →
skeleton. `guarded_box` reads the **live** `Supabase.currentUser` (guarded_box.dart:238),
so the boxes *were* readable (userB's real restored data) — only the gate's uid
source was stale. Reload fixes it because a fresh `ProviderContainer` first-builds
the token after the owner is already `userB`. **Not a C3 restore bug** (restore
succeeded; reload needs no re-restore).

## The fix

Read the LIVE auth uid in `authUserIdTokenProvider` (the same source `guarded_box`
uses, so the gate and the box agree), keeping the `authStateProvider` +
`hiveSessionOwnerProvider` watches for reactivity. Kill-switched by
`configBox['disable_live_auth_token_read']` (default OFF = fix ON) reverting to the
verbatim cached-provider read.

## Verification

- `flutter analyze` clean on the changed files.
- `test/contracts/session_token_stale_authuid_recovery_test.dart` — RED→GREEN
  recovery + kill-switch revert + cross-account isolation (both states).
- `test/contracts/auth_invalidation_timing_test.dart` migrated to the
  `debugAuthUidResolverForTests` seam (the `currentUserProvider` overrides went
  dead under the fix).
- 16 tests green across the 5 affected auth/session contract files.
- Live prod: pending on-device / clean-browser re-walk of an account switch after
  the client ships (web redeploys from main on merge).
