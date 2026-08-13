---
bug_id: a7e3c1
date: 2026-08-12
batch: supabase-test-http
status: fixed
blast_radius: feature
symptom: >-
  Every test in test/supabase/ fails at setUpAll with
  `AuthUnknownException(message: Received an empty response with status code 400)`.
  The message reads exactly like Supabase rejecting the anon key, so the natural
  response is to go re-verify the credentials — which are correct. No HTTP request
  ever leaves the process. Surfaced as a RED main on 2026-08-12, the first time the
  `Supabase Integration Tests` CI job ran with real Actions secrets configured
  (OI-105); it had been green-because-skipped for its entire prior existence.
concept: test_binding_http_mock_masks_real_network
sot_registry_entry: not_applicable
writers:
  - "test/supabase/supabase_test_helper.dart:47 (pre-fix) —
     `TestWidgetsFlutterBinding.ensureInitialized()`. This is the WRITER of the
     process-wide `HttpOverrides.global`: the binding installs a `_MockHttpOverrides`
     whose HttpClient answers EVERY request with 400 and performs no network I/O.
     It is called for an unrelated reason (Supabase.initialize() needs the
     shared_preferences platform channel), so the HTTP side effect is invisible at
     the call site."
readers:
  - "test/supabase/supabase_test_helper.dart:100 — `_client.auth.signInWithPassword`,
     via package:gotrue. Reads the ambient HttpClient and receives the fabricated
     400."
  - "test/supabase/auth_restore_test.dart:28 + test/supabase/sync_service_test.dart
     (setUpAll) — both call signIn() and die there, so ZERO assertions in either file
     have ever executed."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/supabase_test_helper_http_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >-
  Grepped the whole repo for `TestWidgetsFlutterBinding.ensureInitialized` paired
  with real network use. test/supabase/ is the only suite that intends to make live
  HTTP calls; every other use of the binding is in widget/unit tests that must NOT
  hit the network, where the mock is correct and must stay. Fix is therefore scoped
  to this one helper rather than applied globally. Stated as known-exposure, not a
  census.
proposed_fix: >-
  Set `HttpOverrides.global = null` immediately after
  `TestWidgetsFlutterBinding.ensureInitialized()` in the Supabase helper, restoring
  the real HttpClient while keeping the binding needed for platform channels.
  Extracted into `debugRemoveHttpMock()` (@visibleForTesting) rather than inlined,
  so a test can assert it actually happened instead of trusting a comment.
regression_test_planned: >-
  test/scripts/supabase_test_helper_http_test.dart — asserts HttpOverrides.current
  is non-null immediately after ensureInitialized() (a PRECONDITION check, so the
  test cannot pass vacuously if a future Flutter stops installing the mock), then
  null after debugRemoveHttpMock(). Behavioral, not a source grep.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "test/scripts/supabase_test_helper_http_test.dart green; `flutter analyze` clean for both touched files." }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "Ruled the credentials OUT as the cause, which is the whole point of this fix. `gh api repos/upendraprasad19/AVYA/actions/secrets` → SUPABASE_URL + SUPABASE_ANON_KEY both present (created 2026-08-12T15:44Z). The 400 was fabricated by Flutter, never sent by Supabase." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "MUTATION-PROVEN: removing the `HttpOverrides.global = null` line reddens the new test with `Expected: null / Actual: <Instance of '_MockHttpOverrides'>` — the failure names Flutter's own mock class. LIVE-PROVEN: before the fix `flutter test --dart-define-from-file=.env test/supabase/auth_restore_test.dart` gives AuthUnknownException(empty response, 400); after it, AuthApiException(message: Invalid login credentials, code: invalid_credentials) — a genuine reply from the Supabase auth API, i.e. the request now leaves the process and reaches the server." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "REMAINING BLOCKER, deliberately not hidden: `select ... from auth.users where email = 'qa@icanbefitter.com'` on dedsavbjuwgarrhphgnl returns ZERO rows. The QA fixture account this suite signs in as does not exist, so the suite still cannot pass. Creating an account is a user-only action (agent is prohibited from account creation), so it is filed as OI-115 rather than worked around." }
impact_analysis: >-
  Two separate things were broken and the first one hid the second. The HTTP mock
  meant these tests could never have passed on any machine, with any credentials,
  since they were written — the suite was structurally incapable of integrating
  with anything, while presenting as a credentials problem. That is the more
  dangerous half: OI-105 was filed on the belief that adding secrets would make
  this job start verifying things, and the job would instead have kept failing with
  a message pointing at the secrets that had just been fixed.
  This fix does not turn the job green. It converts a misleading failure into an
  accurate one (`invalid_credentials` naming a fixture account that genuinely does
  not exist), which is the prerequisite for anyone diagnosing the rest. Stated
  plainly rather than claimed as a full repair.
related_bugs:
  - "d4f9b2 (2026-08-11) — same family in spirit: a fabricated/ambiguous signal read
     as a real verdict about a remote system. There, an empty ls-remote meant both
     'ref absent' and 'probe unreachable'; here, a 400 from a local mock is
     indistinguishable at the call site from a 400 from Supabase."
recurrence: >-
  Not a recurrence of any indexed bug — grepped docs/diagnoses/INDEX.md for
  HttpOverrides / TestWidgetsFlutterBinding / 'status code 400' / http mock: zero
  matches. Noted explicitly so a future audit can verify this was checked rather
  than assumed. It IS the second instance in two days of the broader
  bad-news-vs-no-news class (see related_bugs).
---

# `test/supabase/` could never reach the network — the 400 was Flutter's, not Supabase's

## What happened

The `Supabase Integration Tests` CI job had been passing for its entire existence by
**skipping** — the repo had zero Actions secrets, so `if: env.SUPABASE_URL != ''` was
always false (OI-105). Secrets were added 2026-08-12 15:44 UTC. The next two pushes to
`main` — `888a3fcd` at 17:29 and `4894539f` at 19:05 — both went red.

The failure looked like a rejected key:

```
AuthUnknownException(message: Received an empty response with status code 400, ...)
```

It is not. Buried in the same log:

```
Warning: At least one test in this suite creates an HttpClient. When running a test suite
that uses TestWidgetsFlutterBinding, all HTTP requests will return status code 400, and no
network request will actually be made.
```

## The mechanism

`supabase_test_helper.dart` calls `TestWidgetsFlutterBinding.ensureInitialized()` because
`Supabase.initialize()` needs the `shared_preferences` platform channel. That binding also
installs a process-wide `HttpOverrides` whose `HttpClient` returns 400 for everything and
sends nothing. The helper needed one effect of the binding and silently inherited the other.

So the suite was structurally incapable of integrating with anything, on any machine, with
any credentials, from the day it was written — while failing in a way that points at the
credentials.

## The fix, and what it does not fix

`HttpOverrides.global = null` after the binding, extracted as `debugRemoveHttpMock()` so a
test can assert it rather than trust a comment.

After it, the same run gives:

```
AuthApiException(message: Invalid login credentials, statusCode: 400, code: invalid_credentials)
```

That is a real reply from Supabase's auth API — the request now leaves the process. **The
job is still red**, because `qa@icanbefitter.com` does not exist in `auth.users` (verified by
direct query, zero rows). Creating it is a user-only action; filed as **OI-115**.

> **Numbering note.** This was filed as OI-109 and renumbered to OI-115 when the branch caught up
> with `main`. Another session had concurrently landed OI-109…114, and I had picked "next free"
> against my own branch's copy of the board rather than against `origin/main` — the same
> stale-input-set error the board's own `babea1a4` ("six OI ids named two issues each") had just
> fixed six instances of. The duplicate-id detector added in that commit is what would have caught
> it; here the merge conflict did. The commit message of `1568ba42` still says OI-109 — immutable
> history, corrected here rather than by rewriting it.

This fix is therefore a prerequisite, not a repair. Saying otherwise would repeat the exact
error the bug itself embodies — reporting a state you have not actually reached.
