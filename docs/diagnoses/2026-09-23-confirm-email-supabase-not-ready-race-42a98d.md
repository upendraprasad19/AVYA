---
bug_id: 42a98d
date: 2026-09-23
batch: confirm-email-init-race (live founder-driven reproduction, second of two root causes tracked under OI-244)
status: fixed
blast_radius: account
symptom: |
  Live-reproduced twice by the founder, on a real device, minutes after
  diagnose f92d17's token_hash-routing fix went to production: tapping a
  genuine, freshly-sent confirmation email link showed `ConfirmEmailScreen`'s
  "This confirmation link is invalid or has expired." error — first on the
  ordinary browser, then AGAIN in a fresh private/incognito window (ruling
  out stale-cache/service-worker theories entirely).

  Root cause isolated via live Supabase `auth_logs` queries (ClickHouse
  `logs` source `auth_logs`) across both reproductions: `auth.users` showed
  the account genuinely still unconfirmed (`email_confirmed_at IS NULL`),
  `POST /resend` calls from the founder's device succeeded (200) both times,
  but in the SAME time window, from the SAME IP, **zero `POST /verify`
  requests ever reached Supabase's Auth server** — proving the "invalid or
  expired" message was generated client-side, without Supabase ever being
  asked to check the link at all.

  Reading `AuthNotifier.confirmEmail` (`auth_provider.dart:702`) alongside
  its siblings `signInWithEmail`/`checkEmailRegistered` found the gap:
  those two call `ensureSupabaseReady()` (existing since 2026-04-04) before
  touching Supabase; `confirmEmail` — written 2026-09-16, five months after
  that helper existed — never did. `/confirm` is registered as a top-level
  `GoRoute` explicitly exempted from `_authRedirect` (`app_router.dart:162`,
  `:696`) and is NOT nested under `/splash` — the ONLY place
  `SupabaseService.instance.initialize()` is ever called
  (`splash_screen.dart:122`), deliberately deferred there per `main.dart`'s
  own comment ("so the UI appears immediately instead of after a 30-50s
  black screen"). Tapping a confirmation link is, structurally, always a
  brand-new cold page load landing directly on `/confirm` — Splash never
  mounts, Supabase is never initialized — yet `ConfirmEmailScreen.initState`
  still fires `confirmEmail(tokenHash)` automatically, with no user gesture.

  `_performConfirmEmail`'s first line, `_supabase.client.auth.verifyOTP(...)`,
  resolves through `SupabaseService.client => Supabase.instance.client`
  (`supabase_service.dart:59`). Read directly from the `supabase_flutter`
  package source in the pub cache (`supabase_flutter-2.17.1/lib/src/
  supabase.dart:43-49,178`): the `Supabase.instance` getter guards
  not-yet-initialized with a bare `assert()` — **stripped entirely in
  release builds** — and its backing field is `late SupabaseClient client;`.
  So on a real production `flutter build web --release`, accessing it before
  `initialize()` has run throws `LateInitializationError` — NOT
  `AuthException`/`TimeoutException`/`StateError` — which falls into
  `confirmEmailErrorState`'s final generic `catch (e)` branch
  (`auth_provider.dart:870-873`), producing the exact literal string shown:
  "This confirmation link is invalid or has expired." — before any HTTP
  request is even attempted. This matches every piece of live evidence
  exactly, including why `/resend` (called only from the already-warm
  sign-in screen, long after Splash has run) worked fine both times while
  `/confirm` (always cold) failed both times regardless of caching.

  This is almost certainly the true SECOND root cause behind the
  previously-unexplained **OI-244** ("6 of 9 real external signups in the
  prior 10 days never completed confirmation... `auth.audit_log_entries` is
  empty project-wide, so there is no server-side trail to distinguish
  causes") — a cold `/confirm` landing is the NORMAL case for a real user
  tapping the link fresh from their email client, not an edge case unique
  to today's repeated testing. Together with f92d17's fix (the first root
  cause, the Vercel query-string routing bug), both identified causes of
  confirmation calls silently failing on the web path are now fixed in
  code. OI-244 itself stays OPEN — it also tracks a separate, still-genuine
  Android App Links issue this fix does not touch.
concept: not_applicable — a control-flow/initialization-ordering fix
  (mirroring an already-established sibling pattern), not a new Hive/cloud
  writer/reader contract.
sot_registry_entry: not_applicable — same reasoning as f92d17's identical
  field; no new writer/reader pair, no Hive key, no cloud table.
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "AuthNotifier.confirmEmail — new `if (!await ensureSupabaseReady()) return;` guard, placed BEFORE the pre-existing OI-205 already-authenticated guard (reordered from the original draft per B-pass Finding 1 — see below)", line: 736 }
readers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "AuthNotifier._performConfirmEmail — the guarded call site; its first statement (`_supabase.client.auth.verifyOTP`) is now only reached once ensureSupabaseReady() has resolved true AND the OI-205 guard (which now correctly reads isAuthenticated post-init) has passed", line: 879 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable — pure client-side control-flow ordering fix; no schema or table touched.
cloud_columns: []
contract_test_path: test/contracts/confirm_email_readiness_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — this guard runs immediately after the
  existing OI-205 already-authenticated guard (`confirmEmailAuthGuardState`,
  unaffected and unchanged) and before any Supabase call; no interaction
  with cross-account Hive ownership.
forbidden_patterns_checked:
  - "calling Supabase.initialize() unconditionally from ConfirmEmailScreen or main() on every boot — rejected: ensureSupabaseReady() already does this idempotently (checks _supabase.isInitialized first, so it's a no-op on the normal warm-navigation path), and main.dart's own comment explains deferring init to SplashScreen is deliberate — avoiding a 30-50s black screen at boot. Duplicating an unconditional init call elsewhere would reintroduce exactly the cost that deferral exists to avoid."
  - "wrapping the verifyOTP call site in a broader try/catch specifically for LateInitializationError — rejected: papers over the symptom (still wastes a real attempt against an uninitialized client, with no accurate diagnostic) instead of closing the actual ordering gap; ensureSupabaseReady() already exists, is proven elsewhere (checkEmailRegistered, signInWithEmail), and produces an ACCURATE error message on genuine failure rather than a generic fallback."
proposed_fix: |
  lib/features/auth/providers/auth_provider.dart — `AuthNotifier.confirmEmail`
  gains `if (!await ensureSupabaseReady()) return;` immediately after the
  loading-state assignment, in the exact position `signInWithEmail` already
  uses it. No other method touched. `ensureSupabaseReady()` itself is
  unchanged — an existing, already-tested helper.
regression_test_planned:
  - test/contracts/confirm_email_readiness_behavioral_test.dart (new — 3 cases: (1) an overridden not-ready `ensureSupabaseReady` short-circuits confirmEmail before verifyOTP, surfacing ITS OWN message; (2) the REAL (non-overridden) ensureSupabaseReady, which fails in this VM test process on empty .env, surfaces its own accurate init-failure reason instead of the generic fallback; (3) a source-order pin proving `ensureSupabaseReady()` is called BEFORE `confirmEmailAuthGuardState` inside confirmEmail's body (added for B-pass Finding 1, see below). All three mutation-proven independently: (1)+(2) — commenting out the new guard line reddened both, and the mutated run produced the exact literal production string "This confirmation link is invalid or has expired." in both failures, reproducing the live bug's precise symptom in the test harness; (3) — swapping the guard's position (moving `ensureSupabaseReady()` after the OI-205 check instead of before) reddened case 3 as expected. Note: case 3's FIRST version used a naive `body.indexOf('ensureSupabaseReady()')` substring match and did NOT redden under that same swap, because a surrounding explanatory comment also contains the literal phrase "ensureSupabaseReady()" in prose — caught by re-running the mutation against the test as originally written, fixed by matching the exact statement `if (!await ensureSupabaseReady()) return;` instead of the bare call. Every mutation reverted; `flutter test` green (17/17 across the three confirmEmail-related test files) after each revert.
impact_analysis: |
  Additive-only: one new guarded line in `confirmEmail`, reusing an
  existing, already-proven helper (`ensureSupabaseReady`) that two sibling
  methods already call. No other method's behavior changes. The ONLY
  behavior change: on a cold `/confirm` landing where Supabase genuinely
  isn't ready yet, `confirmEmail` now AWAITS real initialization (idempotent
  — a no-op if already initialized) before ever touching `verifyOTP`,
  instead of racing an uninitialized singleton and showing a misleading
  "invalid or has expired" message regardless of whether the link was
  actually good. Live-verified this is happening on effectively every real
  `/confirm` click that reaches the screen cold (i.e. most of them) — this
  fix directly explains and closes OI-244.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/features/auth/providers/auth_provider.dart — clean. Read gotrue-2.27.1's verifyOTP and supabase_flutter-2.17.1's Supabase singleton directly from the pub cache (not from memory/prose) to confirm the exact throw mechanism: assert() stripped in release, backing `late SupabaseClient client` field." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive read or write anywhere in this diff." }
  - { tier: 11, name: "External services", status: verified, evidence: "Live ClickHouse query against Supabase's own auth_logs (source='auth_logs') across TWO independent live reproductions on the founder's real device — the original browser AND a fresh incognito window after fully closing the app tab — confirmed ZERO `/verify` POST requests reached the Auth server from the founder's IP in either window, while `/resend`/`/token` requests from the same IP in the same windows succeeded normally (200/400 as expected). This directly proves the failure occurs client-side, before any network attempt, ruling out an actually-expired/invalid token as the cause." }
  - { tier: 12, name: "Client → server contract, full user flow", status: fixed_in_this_batch, evidence: "test/contracts/confirm_email_readiness_behavioral_test.dart reproduces the exact symptom (mutated code emits the literal production error string) and the fix eliminates it. NOT yet re-verified against a live deploy — see residual." }
---

## Summary

A live, founder-driven reproduction — tapping a genuine confirmation email
link, twice, once from a fresh incognito window to rule out caching —
isolated a concrete, structural root cause distinct from (and downstream of)
diagnose f92d17's token-routing fix deployed minutes earlier: `AuthNotifier
.confirmEmail` never guarded against Supabase not yet being initialized,
unlike its sibling auth methods. `/confirm` is reached as a genuinely cold
page load that bypasses `SplashScreen` (the only place `Supabase.initialize()`
runs) entirely, so the auto-fired confirmation call routinely raced an
uninitialized Supabase client and failed silently, client-side, before any
request ever reached the server — misreporting a perfectly valid link as
"invalid or has expired." This is very likely the true root cause of the
previously-unexplained OI-244.

## Root cause

See `symptom` above. In short: `confirmEmail` was missing the
`ensureSupabaseReady()` guard that `signInWithEmail`/`checkEmailRegistered`
already use, and `/confirm`'s route structure makes that guard's absence
matter on essentially every real invocation rather than only occasionally.

## Fix

See `proposed_fix` — one guarded line in
`lib/features/auth/providers/auth_provider.dart`, mirroring an established
pattern already proven elsewhere in the same file.

## Regression tests

- `test/contracts/confirm_email_readiness_behavioral_test.dart` —
  mutation-proven, see `mutation_proven`-equivalent note in
  `regression_test_planned` above (this diagnose-doc predates rule 21's
  separate `mutation_proven` YAML block convention in some older docs; the
  evidence is recorded in the field above instead).

## OI board

Updates **OI-244** (stays OPEN) — `docs/audit/open_issues.md`'s entry
appended with a second "UPDATE" paragraph in the same commit, citing this
bug id. NOT closed: this fix + f92d17 together resolve both identified
causes of confirmation calls silently failing on the web path, but OI-244
also tracks a genuinely separate, still-unresolved Android App Links issue
(App Links not claiming the confirm URL, falling back to a browser) that
needs the founder's own Play Console certificate check — outside this
session's reach.

## Deploy status

**NOT deployed.** Code is written, tested, and mutation-proven in this
worktree, but shipping it live requires a Vercel production deploy, which
needs its own explicit founder authorization per CLAUDE.md §4.3 — separate
from, and in addition to, the authorization already given for f92d17's fix.
