---
bug_id: 3b7e1c
date: 2026-08-12
batch: supabase-ci-http-mock
status: fixed
blast_radius: feature
symptom: >-
  Every file in test/supabase/ dies in setUpAll with
  `AuthUnknownException(message: Received an empty response with status code 400,
  originalError: Instance of 'Response', statusCode: 400)` the moment real
  credentials are supplied. The CI job "Supabase Integration Tests" went from
  green-but-vacuous to failing on 2026-08-12 when SUPABASE_URL /
  SUPABASE_ANON_KEY were first added as Actions secrets (created 15:44Z; first
  failing run 31622882040 on merge 888a3fcd). No test in the suite reaches its
  first assertion.
concept: test_binding_stubs_http_for_integration_tests
sot_registry_entry: not_applicable
writers:
  - "test/supabase/supabase_test_helper.dart:47 — `TestWidgetsFlutterBinding.ensureInitialized()`
     inside `_mockSharedPreferences()`. This is the WRITER of `HttpOverrides.global`:
     the binding installs a `_MockHttpOverrides` that answers every request with
     status 400 and an empty body WITHOUT opening a socket. Confirmed by name in the
     mutation run: `Expected: null / Actual: <Instance of '_MockHttpOverrides'>`."
readers:
  - "test/supabase/supabase_test_helper.dart:76 — `signIn()` -> `_client.auth.signInWithPassword`,
     the first reader. gotrue constructs an HttpClient, which resolves
     `HttpOverrides.current` AT CONSTRUCTION TIME, gets the stub, and receives the
     synthetic 400. Surfaces as AuthUnknownException from
     package:gotrue/src/fetch.dart:60 GotrueFetch._handleError."
  - "test/supabase/auth_restore_test.dart:24-30 and test/supabase/sync_service_test.dart —
     both call SupabaseTestHelper.init() + signIn() in setUpAll, so the throw aborts
     the whole file before any assertion runs."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/supabase/http_override_restored_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >-
  ⚠ CORRECTED 2026-08-13. The first version of this field claimed "test/supabase/ is
  the only integration surface in the repo that needs a live socket". That was FALSE
  and round-2 review disproved it behaviourally: `test/edge_functions/ai_proxy_test.dart`
  and `pgvector_test.dart` call `TestWidgetsFlutterBinding.ensureInitialized()` inline
  in their own setUpAll, never call SupabaseTestHelper.init(), and were still returning
  the identical `AuthUnknownException(... status code 400)` this diagnose is about —
  in the same CI job, one step later. The fix reached 2 of the 4 affected files while
  the doc asserted a clean census.
  THE REAL CENSUS, run per-file rather than asserted: ~150 files under test/ call
  `ensureInitialized()`. Exactly THREE need the stub undone —
  `test/supabase/supabase_test_helper.dart` (via `prepareBinding()`, used by
  auth_restore + sync_service), `test/edge_functions/ai_proxy_test.dart` and
  `test/edge_functions/pgvector_test.dart` (both now call `restoreRealHttp()`
  directly). `test/edge_functions/webhook_test.dart` never installs the binding at all
  and needs nothing. Every other call site is a unit or widget test whose HTTP is
  mocked DELIBERATELY — clearing the override there would be the bug, not the fix.
  Verified by listing every `ensureInitialized()` file and checking each for a
  restoration call, not by a single grep whose result was generalised.
proposed_fix: >-
  Keep the binding, drop only its HTTP interception. The binding cannot be removed —
  `Supabase.initialize()` needs the mocked `shared_preferences` MethodChannel that
  `_mockSharedPreferences()` registers, and that requires an initialized binding. So
  `SupabaseTestHelper.restoreRealHttp()` sets `HttpOverrides.global = null`
  immediately after `_mockSharedPreferences()` in `init()`, before any Supabase call.
  Ordering is load-bearing and stated in the doc comment: the binding installs the
  stub, so clearing it must happen AFTER ensureInitialized(), not before.
  Note the asymmetric dart:io API — `HttpOverrides.global` is a setter only; the
  readable side is `HttpOverrides.current`. Reading `.global` is a compile error,
  which is how the first draft of the regression test failed to build.
regression_test_planned: >-
  TWO files, both BEHAVIOURAL (bind a real socket, count hits) rather than
  source-greps, and both hermetic — loopback only, no credentials, no Supabase
  project — so they run in the ordinary unit-test job. Deliberate: this bug hid
  BECAUSE the credential-gated suite never ran, so a credential-gated test would
  inherit the same blind spot.
  (1) test/supabase/http_override_restored_test.dart — asserts the stub answers 400
  with ZERO server hits, that restoreRealHttp() yields 200 with EXACTLY ONE hit, and
  that prepareBinding() leaves no override. Order-independent: each test re-installs
  the captured stub in setUp, verified across 3 randomize-ordering seeds.
  (2) test/supabase/prepare_binding_order_test.dart — ONE test in its OWN FILE so it
  gets a VIRGIN isolate. `ensureInitialized()` is idempotent, so once anything has
  touched the binding both orderings behave identically: the ordering assertion is
  only observable before the first touch. Measured — with this test inside file (1),
  inverting the two lines stayed GREEN; in its own file the same mutation is RED.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "2/2 green in test/supabase/http_override_restored_test.dart; the helper is test-only code, no lib/ surface touched." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Hive is initialized into a systemTemp dir by the helper; unchanged by this fix." }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "gh api repos/upendraprasad19/AVYA/actions/secrets -> total_count 2 (SUPABASE_URL, SUPABASE_ANON_KEY, both created 2026-08-12T15:44Z). Their arrival is what un-skipped the suite; the fix does not read or alter them." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "MUTATION-PROVEN four ways, none contacting the production project. (1) Bogus-host A/B: pre-fix gives `AuthUnknownException ... status code 400` — byte-identical to the CI failure — post-fix gives `SocketException: Failed host lookup`, i.e. a real socket was attempted. Re-run per file, this is ALSO what proved ai_proxy/pgvector were still broken after the first fix. (2) Gutting restoreRealHttp()'s body reddens the behavioural test. (3) Deleting the restoreRealHttp() call from prepareBinding() reddens it. (4) INVERTING the two lines reddens prepare_binding_order_test.dart — and only there: inside the main file the same mutation stayed GREEN, because ensureInitialized() is idempotent and that file's setUpAll had already installed the binding. The virgin-isolate file exists solely to make (4) observable." }
  - { tier: 11, name: external_services, status: verified, evidence: "No workflow change in this piece. `.github/workflows/test.yml` runs test/supabase/ then test/edge_functions/ in the same `supabase-tests` job, which is why the two files left unfixed by the first attempt would have failed one step after the ones that were fixed." }
impact_analysis: >-
  Blocked 100% of the repo's Supabase integration coverage — 6 files that have never
  once executed in CI (test/supabase/auth_restore_test.dart, sync_service_test.dart,
  and the 4 under test/edge_functions/), covering the surface with the worst P0 history
  in this repo per OI-105 (the Razorpay webhook TDZ P0, referral redemption, ai-proxy,
  pgvector). Severity is bounded by the fact that it broke TESTS, not production: no
  lib/ code path is affected. But it is the reason a job could sit green for its entire
  life while verifying nothing, and it would have re-broken the moment anyone added the
  secrets — which is exactly what happened.
  NOT YET ESTABLISHED, and deliberately not claimed: whether the 6 files PASS against
  real Supabase once the harness works. This fix removes the harness blocker only.
  OI-105 predicted in advance that the first real run should be expected to go red and
  budgeted for triage; that triage is a live-prod question because
  SupabaseTestHelper.cleanup() issues DELETEs across 12 tables for the QA user on every
  setUp(), so it needs its own explicit authorization per CLAUDE.md §4.3.
related_bugs:
  - "OI-105 (docs/audit/open_issues.md) — 'the Supabase Integration Tests CI job has
     verified NOTHING since it was written: the repo has zero Actions secrets'. This
     diagnose is the other half of that item: OI-105 explains why the job was green,
     3b7e1c explains why it goes red the instant it stops being vacuous. OI-105 stays
     OPEN until the job actually verifies something."
  - "OI-104 — hook staleness goes unchecked. Same family: a check that reports success
     without having examined the thing it names."
recurrence: >-
  First instance of this specific bug (binding-stubbed HTTP defeating an integration
  suite). It IS the Nth instance of the repo's dominant meta-class — a green check
  whose input set is narrower than the thing it certifies
  (feedback_green_check_input_set_width, 14+ instances). Here the input set was
  literally empty: with no credentials every file took its `SKIPPED` branch, so the job
  reported success having executed zero assertions, for its entire life. The lesson
  already on file applies verbatim: say the input set out loud before citing any check.
  The regression test is deliberately credential-FREE so that it cannot itself be
  disabled by the same absent-input condition.
---

# 3b7e1c — Supabase integration tests: the test binding stubs all HTTP

## What happened

`SUPABASE_URL` / `SUPABASE_ANON_KEY` were added as GitHub Actions secrets at 15:44Z on
2026-08-12. Every file in `test/supabase/` is gated on
`SupabaseTestHelper.hasCredentials`; without secrets each emits a single
`SKIPPED: ...` placeholder test and returns. So the "Supabase Integration Tests" job
had been green since it was written while executing nothing (OI-105).

With the secrets present the suite ran for the first time — and immediately failed in
`setUpAll`, before any assertion, on the first real network call.

## Root cause

`Supabase.initialize()` needs a mocked `shared_preferences` MethodChannel, which
requires an initialized binding, so `_mockSharedPreferences()` calls
`TestWidgetsFlutterBinding.ensureInitialized()`. That binding also installs an
`HttpOverrides.global` which answers **every** request with status 400 and an empty
body, without opening a socket. Flutter prints this itself in the run log:

> When running a test suite that uses TestWidgetsFlutterBinding, all HTTP requests
> will return status code 400, and no network request will actually be made.

`signIn()` therefore receives a synthetic 400 and throws
`AuthUnknownException(... status code 400)`.

The binding is required and the network is required, and the binding breaks the
network. That is the whole bug.

## Fix

Keep the binding; clear only its HTTP interception, after initialization and before
any Supabase call:

```dart
_mockSharedPreferences();
restoreRealHttp();   // HttpOverrides.global = null
```

## What this fix does NOT do

It does not make the 6 integration files pass. It makes them *able to run*. Whether
they pass against the live project is unknown — they have never executed — and finding
out requires running DELETEs against production for the QA user, which is a separate,
explicitly-authorized step. OI-105 stays OPEN until the job verifies something real.
