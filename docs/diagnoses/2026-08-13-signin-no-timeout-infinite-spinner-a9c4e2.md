---
bug_id: a9c4e2
date: 2026-08-13
batch: backend-cpu-starvation
status: fixed
blast_radius: account
symptom: |
  Founder signed in as test6@gmail.com on the prod web build
  (app.icanbefitter.com/#/sign-in) at 2026-08-13 23:03 IST. The SIGN IN WITH
  EMAIL button entered its spinner state and never left it — no error, no
  SnackBar, no navigation, no escape affordance. Screenshot shows the email
  step with the button rendering CircularProgressIndicator indefinitely.

  The sign-in itself SUCCEEDED. Supabase auth_logs, same instant:
    POST /token grant_type=password, actor_username test6@gmail.com,
    actor_id 039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4, status 200, duration 309ms.
  A session was issued. The credentials were never in question.

  What hung was everything after it. From 23:03:45 onward the same browser
  (remote_addr 106.222.236.110) logged:
    23:03:45 GET  /user   200 but 9.4s      (already degraded)
    23:03:48 POST /token  504  10.7s  "context deadline exceeded"
    23:04:09 POST /token  504  12.2s
    23:05:48 GET  /user   504  27.3s
    23:05:57 GET  /user   500  35.9s  "Unhandled server error: context canceled"
    23:08:13 GET  /user   504  17.5s
  The backend was CPU-throttled (see e4a7c9); Postgres logged continuous
  "canceling statement due to statement timeout" 23:05:47-23:10:41.

  The bug is not that the backend degraded. The bug is that a degraded backend
  produces an UNBOUNDED spinner with no error path and no user escape, because
  nothing on the sign-in path carries a deadline.
concept: auth_signin_completion
sot_registry_entry: auth_signin_completion
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "signInWithEmail — sets AuthStatus.loading, awaits signInWithPassword, then awaits _ensureLocalUser, and only then sets AuthStatus.success. No timeout on any step.", line: 189 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "signInWithEmail — the await that hung: _ensureLocalUser(response.user!)", line: 206 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "signInWithEmail — state = AuthStatus.success, never reached", line: 213 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "_ensureLocalUser — openForUser + 6 one-shot migrators + hydrateFromCloud, all network-touching, none bounded", line: 617 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "_ensureLocalUser — AuthSessionBootstrapper.hydrateFromCloud call, wrapped in try/catch but NOT in a timeout", line: 811 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "signOutTimeout = 20s — the PRECEDENT this fix mirrors; its doc comment names this exact wedge class", line: 463 }
readers:
  - { file: lib/features/auth/screens/sign_in_screen.dart, method_or_widget: "build — isLoading = authState.status == AuthStatus.loading; the spinner is a direct render of this", line: 202 }
  - { file: lib/features/auth/screens/sign_in_screen.dart, method_or_widget: "ref.listen — navigates to /restoring ONLY on AuthStatus.success; shows a SnackBar ONLY on AuthStatus.error. AuthStatus.loading forever renders nothing but the spinner.", line: 167 }
  - { file: lib/features/auth/screens/sign_in_screen.dart, method_or_widget: "_buildPrimaryButton — isLoading renders CircularProgressIndicator and nulls onTap", line: 1347 }
  - { file: lib/features/auth/screens/sign_in_screen.dart, method_or_widget: "SIGN IN WITH EMAIL button — the call site the founder tapped", line: 845 }
hive_key_prefix: "n/a — no new Hive key; _ensureLocalUser's existing writes are unchanged"
hive_key_formula: "unchanged; the fix bounds how long the caller waits, it does not alter what is written"
sync_methods: [hydrateFromCloud]
restore_methods: []
cloud_table: users
cloud_columns: [id, last_active_at]
contract_test_path: test/contracts/signin_bounded_completion_test.dart
ist_handling:
  - "Not applicable — the fix introduces a relative Duration ceiling measured with a stopwatch/timeout, never a wall-clock date key. No IST conversion is involved."
provider_invalidations: []
telemetry_op_types:
  success: [auth_signed_in, auth_user_ensured]
  failure: [auth_signin_ensure_local_user_timeout, auth_signin_partial_completion]
cross_account_guard: |
  MUST NOT BE WEAKENED, and this is the sharpest risk in the fix. _ensureLocalUser
  contains the cross-account clear-guard (auth_provider.dart:642-694): it detects
  a stale profile id, calls clearAllData(), re-reads to verify the clear landed,
  and force-signs-out + throws StateError if it did not. Wrapping the WHOLE method
  in a timeout would let a caller proceed while that guard is mid-clear — turning a
  transient network hang into a cross-account data leak, which is a far worse bug
  than the spinner.

  Therefore the ceiling MUST NOT span the guard. The proposed split below bounds
  only the segment AFTER the ownership work is complete: openForUser and the
  cross-account clear-and-verify stay unbounded and awaited exactly as today; the
  migrators and hydrateFromCloud — every one of which is already individually
  try/caught as non-fatal, retried next launch — are what the timeout covers.
  Any implementation that cannot preserve that boundary should not ship.
forbidden_patterns_checked:
  - { pattern: "an await on the sign-in path with no enclosing Duration ceiling", absent: true, after_fix: true }
  - { pattern: "a timeout wrapping HiveUserSession.openForUser or the cross-account clear-and-verify block", absent: false, after_fix: false }
  - { pattern: "AuthStatus.loading reachable as a terminal state (no success, no error, no timeout transition)", absent: true, after_fix: true }
proposed_fix: |
  MIRROR THE signOut PRECEDENT. auth_provider.dart:463 already carries
  `static const Duration signOutTimeout = Duration(seconds: 20)`, and its doc
  comment states the principle verbatim: "a `finally` only runs when control
  leaves the `try`, and a never-resolving `await` never does". RestoringScreen
  carries the same idea as UX (15s soft hint, 30s CONTINUE escape). Sign-in is
  the one auth path that got neither.

  1. Split _ensureLocalUser into two phases at the existing seam:
     - PHASE A (unbounded, unchanged): openForUser + the cross-account
       clear-and-verify guard. Correctness-critical, must complete. See
       cross_account_guard.
     - PHASE B (bounded): the 6 one-shot migrators + the terms-consent stamp +
       hydrateFromCloud + the Crashlytics/OneSignal binds. Every one of these is
       ALREADY individually try/caught as non-fatal with a "retries next launch"
       comment — so a timeout here changes the failure MODE (fast + visible)
       without changing the failure SEMANTICS.

  2. Add `static const Duration signInTimeout = Duration(seconds: 20)` and apply
     it to Phase B. Same value as signOutTimeout, same rationale — the user is
     staring at a button they just tapped.

  3. On timeout: do NOT set AuthStatus.error. The session is genuinely valid
     (the 200 at 23:03:28 proves the token was issued), so erroring out would
     strand a signed-in user on /sign-in. Set AuthStatus.success and let
     RestoringScreen take over — it already owns the degraded-backend UX
     (soft hint, CONTINUE escape) and already handles DestinationUnknown
     correctly (c2e9f4). Emit auth_signin_ensure_local_user_timeout.

  4. Kill-switch configBox['disable_signin_timeout'] restores verbatim
     pre-fix behaviour (§4.6).

  WHY NOT "just add a timeout to signInWithPassword": that call succeeded in
  309ms. Bounding it would have changed nothing. The hang is downstream, which
  is exactly why the fix has to be located by tracing the awaits rather than by
  guessing at the network call that looks most suspicious.
regression_test_planned: |
  test/contracts/signin_bounded_completion_test.dart — behavioral.

  Cases:
  1. Phase B hangs (injected never-completing future) → state reaches
     AuthStatus.success within signInTimeout + margin, and
     auth_signin_ensure_local_user_timeout is emitted. FAILS on main: pre-fix
     the state stays AuthStatus.loading forever and the test times out.
  2. Phase B completes normally → success, NO timeout telemetry. Pins that the
     happy path is untouched.
  3. Phase A (cross-account guard) hangs → state does NOT advance. This is the
     mirror test that pins the boundary: if a later refactor widens the ceiling
     to cover Phase A, this case goes green when it must stay red.
  4. Kill-switch ON + Phase B hangs → stays loading (verbatim pre-fix).

  Case 3 is the one that matters most and is the one a careless implementation
  would omit — per feedback_mistake_guard_without_its_mirror, the test suite
  written from the same mental model as the fix asserts what the fix DOES and
  not what its over-application would look like.

  MUTATION PROOF: widening the timeout to wrap all of _ensureLocalUser must
  redden case 3; deleting the timeout must redden case 1. Record both counts.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "auth_provider.dart:189-225 and :617-864 read in full; confirmed no timeout on any await between AuthStatus.loading and AuthStatus.success. signOutTimeout at :463 read directly and confirmed as the in-repo precedent." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Phase A/B split leaves every Hive write in place and in order. The terms-consent stamp (b3f9e7) stays after openForUser and after the clear-guard, preserving that fix's own precondition." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "auth_logs confirm POST /token 200 in 309ms for actor 039b8eb3 at 17:33:28 UTC — the sign-in succeeded, locating the hang strictly downstream of signInWithPassword." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Client-only." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involvement in the interactive sign-in path." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Unchanged." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage involvement." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret touched." }
  - { tier: 11, name: external_services, status: verified, evidence: "OneSignal.login and Crashlytics.setUserIdentifier sit in Phase B and are already !kIsWeb / !kDebugMode guarded and try/caught; bounding them changes nothing on web, where this was observed." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Full flow traced end-to-end from the button tap (sign_in_screen.dart:845) through the notifier to the live edge_logs/auth_logs for the same request ids and remote_addr." }
impact_analysis: |
  USER-VISIBLE SEVERITY. Total, silent, unrecoverable-without-reload failure of
  the single most important flow in the app, triggered by any backend
  degradation. No error message, no retry affordance, no escape. The user
  cannot distinguish "wrong password" from "backend down" from "app broken" —
  and the one thing that is definitely NOT wrong (their credentials) is the
  first thing they will assume and start re-typing.

  FREQUENCY. Bounded by backend health, not by user behaviour. On 2026-08-13 it
  fired on the first sign-in attempt during a 16-minute outage. Any future
  CPU-credit exhaustion (see e4a7c9) reproduces it exactly.

  WHY THIS IS OURS AND NOT SUPABASE'S. The backend recovering in 16 minutes is
  an infrastructure event. A client that hangs forever with no error rather
  than failing in 20 seconds with a retry is a defect we own, and the codebase
  demonstrably already knows this: signOut got a ceiling, restore got a ceiling
  AND an escape hatch, and both carry comments explaining why. Sign-in was
  simply missed. That is worth stating plainly rather than filing this under
  "Supabase was down".

  ASYMMETRY THAT SETS THE FIX'S DIRECTION. Two ways to be wrong on timeout:
  proceed too early (risking a half-initialised session) or wait forever
  (guaranteed dead-end). The cross_account_guard section is where "proceed too
  early" is genuinely dangerous, which is exactly why the ceiling is scoped to
  exclude it. Everything Phase B does is already declared non-fatal by its own
  existing try/catch blocks — so for that segment, waiting forever has no
  upside at all.

  INTERACTION. Independent of e4a7c9 and d7b1f8. This fix does not reduce
  outage frequency (e4a7c9 does) and does not reduce retry load (d7b1f8 does);
  it makes the outage survivable from the user's seat. All three are worth
  landing and none substitutes for another.
related_bugs: [2026-08-10-resolve-destination-failed-read-means-new-user-c2e9f4, 2026-05-22-restoring-timeout-threshold-4a3b08, 2026-08-01-password-reset-stuck-screen-c8f1d3]
self_review_findings: |
  PREMISE CHECKED BEFORE DIAGNOSING. The founder's framing was "stuck here,
  why?" with no claim about cause. Rather than assume bad credentials or a
  client bug, the auth log was queried first — and it showed a 200 in 309ms,
  which REFUTED the most natural hypothesis (auth failure) and relocated the
  entire investigation downstream. This is the §2.27 lesson (verify the framing
  with tools before fixing) applied pre-emptively.

  A WRONG FIX I ALMOST PROPOSED. The instinct is to wrap signInWithPassword in
  a timeout — it is the network call that "looks like" the risk. The logs show
  it completed in 309ms and bounding it would have fixed nothing. The hang was
  found by tracing which awaits sit between AuthStatus.loading and
  AuthStatus.success, not by pattern-matching on suspicious-looking calls.

  THE RISK THIS FIX INTRODUCES, NAMED. A naive implementation wraps
  _ensureLocalUser wholesale and thereby bounds the cross-account clear-guard —
  converting a spinner into a potential cross-account leak. That is a strictly
  worse trade and it is the most likely way this fix goes wrong. It is called
  out in cross_account_guard, encoded as forbidden pattern 2 (the only entry in
  this batch asserting absent:false — the timeout MUST NOT be there), and
  pinned by regression case 3.
---

# Sign-in has no timeout: a degraded backend produces an unbounded spinner

See frontmatter for the full analysis. One-line summary: `signInWithEmail`
awaits `_ensureLocalUser` — six migrators plus `hydrateFromCloud`, all network,
none bounded — before setting `AuthStatus.success`, so when the backend stops
answering the state never leaves `AuthStatus.loading` and the button spins
forever with no error and no escape. `signOut` has carried a 20s ceiling for
exactly this reason since 2026-07; sign-in never got one.

The ceiling is deliberately scoped to EXCLUDE the cross-account clear-guard.
Bounding that would trade a spinner for a data leak.
