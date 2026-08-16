---
bug_id: c8f4a2
date: 2026-08-16
batch: rr1-referral-401
status: fixed
blast_radius: feature
symptom: >-
  `main` is RED. The CI job `Supabase Integration Tests` fails on its `Run Edge
  Function tests` step, on a SINGLE assertion:
  `test/edge_functions/redeem_referral_test.dart:46`, RR-1 "Missing auth returns
  401" — `Expected: false / Actual: <null>`. The statusCode==401 assertion two
  lines above PASSES, so the 401 itself is correct; only the body assertion
  fails. Stable across runs (`+18 -1` identical on 083b5ac2 and 1c5458f3).
concept: edge_function_gateway_vs_function_error_contract
sot_registry_entry: not_applicable
writers:
  - "SUPABASE GATEWAY (verify_jwt: true on the deployed function, v14 ACTIVE) —
     the ACTUAL author of RR-1's response. Emits
     {\"code\":\"UNAUTHORIZED_NO_AUTH_HEADER\",\"message\":\"Missing
     authorization header\"}. Verified by reproducing RR-1's exact request with
     curl against the live endpoint."
  - "supabase/functions/redeem-referral/index.ts:57-60 — the function's OWN 401,
     emitting {error, request_id}. UNREACHABLE for RR-1: verify_jwt rejects
     before the body runs."
  - "supabase/functions/redeem-referral/index.ts:156-164 (jsonError) — every
     other error path, also {error, request_id}. No error path has ever emitted
     `success`."
  - "supabase/functions/redeem-referral/index.ts:127, :148 — the ONLY writers of
     `success`, and both are 200 success paths."
readers:
  - "test/edge_functions/redeem_referral_test.dart:46 — asserted
     `body['success'] isFalse`. THE DEFECT: a field no error path emits, on a
     response the function does not even author."
  - "lib/features/profile/screens/invite_friends_sheet.dart:106 — the only real
     client reading the flag: `body['success'] == true`. Absent key -> false.
     CORRECT."
  - "lib/features/profile/repositories/referral_repository.dart:96-105 — reads
     `body['error']`, never `success`. CORRECT."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/edge_functions/redeem_referral_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: >-
  Untouched. `verify_jwt: true` is deliberately LEFT ON. Turning it off would
  make the function's own 401 reachable and "fix" the assertion, and is exactly
  the 7ad0c4 / b3f0d9 regression class (gateway auth removed, handler-level gate
  the only thing left). Not done.
forbidden_patterns_checked: >-
  Enumerated the real consumers rather than assuming: `grep -rn "\['success'\]"
  lib/` returns exactly ONE reader (invite_friends_sheet.dart:106), and it uses
  `== true`. `grep -n "test('RR-"` returns only RR-1/RR-2/RR-5 plus RR-local-*,
  refuting the file header's claim of an RR-3 and RR-4.
proposed_fix: >-
  RR-1 asserts the property that holds regardless of WHO answers — status 401
  and `body['success'] isNot(true)` — instead of a function-shaped key the
  gateway never emits. Deliberately NOT pinning the gateway's `code`/`message`
  strings: those are Supabase platform copy we do not control, and pinning them
  buys nothing while risking a false red on any platform change. Three adjacent
  defects fixed in the same batch (§4.2): the file header documented RR-3 and
  RR-4 which have never existed; each test opened with `if (!hasKey) return;`,
  making a credential-less run render as a PASS (OI-105 silent-green class), now
  a REPORTED group-level skip; and RR-2 asserted `anyOf(401, 200)`, which
  accepted both outcomes, now `equals(401)`. Plus a stale comment in
  referral_repository.dart:96 naming a `{ok:true}` field the EF never emits.
regression_test_planned: >-
  The test file IS the regression artifact. Its discrimination was PROVEN by
  three mutations actually run against the live endpoint, restored from a FILE
  BACKUP (never `git checkout`, which restores to HEAD and destroys unrelated
  edits): (A) restoring the old `isFalse` reddens RR-1 alone (+7 -1) — proving
  the test evaluates a live response and the old assertion failed for exactly
  the diagnosed reason; (B) `isNot(true)` -> `isNot(null)` reddens RR-1 (+7 -1)
  — proving the new matcher is evaluated against the real body and is not
  vacuous; (C) RR-2 `equals(401)` -> `equals(200)` reddens RR-2 — proving the
  tightened assertion can fail. Skip-gate control: a define-less run now reports
  `+5 ~3` (three SKIPPED) where it previously reported `+8`.
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "One comment corrected in referral_repository.dart; no logic changed. `flutter analyze` on both touched directories reports only 2 pre-existing deprecation infos, both in OTHER files (ai_proxy_test.dart:62, pgvector_test.dart:74)." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "No Hive box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No migration; no table touched." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "The fixed tests write nothing — they assert on rejected requests." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_deploy, status: verified, evidence: "GET /v1/projects/dedsavbjuwgarrhphgnl/functions/redeem-referral -> version 14, status ACTIVE, verify_jwt TRUE. This is the fact the whole diagnosis turns on, and it was read from the deploy API, not inferred from repo source. The function is NOT redeployed by this batch." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "Not a cron function." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy changed; the requests never reach Postgres." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret changed. The test needs only SUPABASE_ANON_KEY, which is why — unlike the sibling sync suite — it could be run and mutation-proven locally." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Reproduced RR-1's exact request against the live endpoint: HTTP 401 with {code, message}. Both real client readers enumerated and confirmed correct. 8/8 green live; 5 pass + 3 reported-skipped define-less." }
impact_analysis: >-
  NO PRODUCT BUG. The user-facing path was always correct: the one client that
  reads the flag uses `body['success'] == true`, so an absent key evaluates
  false, and the repository reads `error` instead. The defect was entirely in
  the test, which asserted a contract that nothing produces — and it blocked
  `main`, which under rule 20 is a P0.
  .
  THE NEAR-MISS WORTH RECORDING. Reading the Edge Function source suggested the
  fix "assert body['error'] instead", because the function's own error paths all
  emit {error, request_id}. That fix would ALSO have failed: the gateway body
  carries `message`, not `error`. The source described code that never runs for
  this request. Only reproducing the request with curl surfaced it. This is the
  verify-one-hop-and-claim-the-chain class again — the same shape as reading
  `Box get workoutBox => workoutBoxGuarded.rawBox` and stopping before
  `wrapUserScopedBox` (b6e1d4, the immediately preceding batch). The rule that
  would have caught it earlier: when a test asserts on a RESPONSE, establish WHO
  AUTHORS the response before reading any source that might author it.
  .
  WHY IT SURFACED NOW. It is not new. The `Run Edge Function tests` step had
  NEVER RUN: the `Run Supabase tests` step above it failed first, and GitHub
  Actions halts a job at its first failed step. `gh run view <prior> --log-failed
  | grep -c edge_functions` returns 0. Fixing the Supabase step (b6e1d4) let the
  job reach this step for the first time. Third consecutive layer in this line
  of work, each hidden by the one above it: HTTP stub (3b7e1c) -> missing QA
  account (f7a2c4) -> stale sync payloads (b6e1d4) -> this.
  .
  WHAT IS NOT CLOSED. The function's own `getUser(token)` 401 path
  (index.ts:57-60) is now near-unreachable from outside, because the gateway
  rejects anything the function would reject. It is not fully dead — a
  correctly-signed but expired token could pass the gateway and fail getUser —
  but no test covers it and this batch does not add one, because doing so needs
  a real minted-then-expired token. Stated rather than implied.
related_bugs:
  - "b6e1d4 (2026-08-15) — the immediately preceding batch, whose fix unmasked
     this. Same verify-one-hop class."
  - "3b7e1c — TestWidgetsFlutterBinding's HttpOverrides 400 stub; the first layer
     of this stack."
  - "f7a2c4 (2026-08-15) — the missing QA account; the second layer."
  - "e8a1c3 (2026-06-12) — delete-account 401 on every valid token. The EF auth
     contract that redeem-referral's getUser(token) pattern was modelled on."
  - "d2b9e6 (2026-06-13) — redeem-referral RLS-context bug; same function,
     different layer."
  - "7ad0c4 / b3f0d9 — verify_jwt:false + no handler gate. The regression this
     fix deliberately does NOT commit by leaving verify_jwt ON."
  - "OI-105 — the silent-green class the `if (!hasKey) return;` pattern belongs
     to."
recurrence: >-
  Yes, twice over. (1) Writer/reader drift — the repo's most recurrent class
  (§4.1, >=15) — with the twist that the READER is a test and the WRITER turned
  out to be infrastructure rather than our code. (2) The
  verify-one-hop-and-claim-the-chain error, committed again during THIS
  investigation and caught only by reproducing the request. The generalisable
  rule is in impact_analysis: identify the author of a response before reading
  any source that might be it.
---

# RR-1 asserted the wrong author's contract

## What was wrong

```dart
expect(response.statusCode, equals(401));          // passes
final body = jsonDecode(response.body) as Map<String, dynamic>;
expect(body['success'], isFalse);                  // Actual: <null>
```

The deployed function runs with `verify_jwt: true`, so the **Supabase gateway**
answers an unauthenticated request and the function body never executes:

```
gateway  → {"code":"UNAUTHORIZED_NO_AUTH_HEADER","message":"..."}
function → {"error":"...","request_id":"..."}      (never reached here)
```

`success` appears only on the function's 200 paths. The test asserted a field
that no error path emits, on a response our code does not author.

## The fix

Assert what is true regardless of who answers:

```dart
expect(response.statusCode, equals(401));
expect(body['success'], isNot(true),
    reason: 'an unauthenticated request must never report success');
```

Not pinning the gateway's `code`/`message` — platform copy we don't control.

## The trap this batch nearly fell into

Reading `index.ts` suggests "assert `body['error']` instead." That fails too —
the gateway sends `message`, not `error`. The source describes code that does
not run for this request. **Establish who authors a response before reading any
source that might.**

## Proven, not asserted

Three mutations run live: restoring `isFalse` reds RR-1; `isNot(true)` →
`isNot(null)` reds RR-1; RR-2 `equals(401)` → `equals(200)` reds RR-2. Plus the
skip-gate control — a define-less run went from `+8` (three tests silently
passing while doing nothing) to `+5 ~3`.
