---
bug_id: a7c3e9
date: 2026-09-07
batch: ci-t19-live-timeout
status: fixed
blast_radius: feature
symptom: >
  CI went red on `main` at 493d230b. The "Supabase Integration Tests" job failed
  with `TimeoutException after 0:00:30.000000: Test timed out after 30 seconds`
  on `ai_proxy_test.dart` T19 — a one-sentence live chat that normally answers
  in a few seconds. Every other job passed, including the Deno type-check and
  the full 5406-test unit suite. The job had succeeded on the three prior `main`
  runs, so this is live latency, not a regression: `ai_proxy_test.dart` makes
  LIVE calls to a deployed Edge Function and waits on a live Gemini generation,
  while running under Dart's DEFAULT 30-second per-test budget — a default meant
  for unit tests and never chosen for this workload. `callEdgeFunction`'s
  `http.post` carried NO timeout of its own, so a slow call consumed the test
  budget and reported a message naming no function, no URL and no elapsed time.
concept: edge_function_live_test_harness
sot_registry_entry: "none — test harness only; no writer/reader contract changed"
writers:
  - { file: test/edge_functions/ai_proxy_test.dart, method: "callEdgeFunction — the only caller of http.post in this file; now carries an explicit 90s budget" }
readers:
  - { file: test/edge_functions/ai_proxy_test.dart, method: "T15 / T18 / T19 and the auth tests, all of which await callEdgeFunction" }
hive_key_prefix: "n/a — test harness, no Hive surface"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/edge_functions/ai_proxy_test.dart
ist_handling: >
  Not applicable — no date key, no counter reset. Noted only because the same
  file's chat-cap helper IS IST-bound: the shared QA account's 10/day chat cap
  resets on the IST day boundary, which is what bounds how often this job can
  run at all.
provider_invalidations: "none — no client state, no providers touched"
telemetry_op_types: >
  No production telemetry. The behavioural change is diagnostic: a timed-out
  call now throws a TimeoutException naming the function, the budget and the
  elapsed wait, instead of the harness's generic "Test timed out after 30
  seconds". A timeout that reports nothing is NO NEWS, and no news is
  indistinguishable from every other hang.
cross_account_guard: >
  Unchanged. The file signs in as the single shared QA account; nothing here
  alters which account is used or what it can reach.
forbidden_patterns_checked: >
  No production code touched — the diff is one test file. No per-test timeout
  argument was added (CLAUDE.md 4.9's 5th-instance trap: a per-test override
  takes PRECEDENCE over a file-level @Timeout and would silently keep the old
  budget). No deferral euphemism. The warning comment is deliberately worded so
  it does NOT match the grep it prescribes — the self-matching shape the
  code-review skill's lens 8 names.
proposed_fix: >
  Two budgets, and their ORDER is the fix rather than either number alone.
  (1) `callEdgeFunction`'s http.post gets an explicit 90s `.timeout()` whose
  onTimeout THROWS a message naming the function, the budget and the elapsed
  wait. (2) The file gets `@Timeout(Duration(minutes: 3))`. The HTTP budget must
  stay BELOW the test budget so the HTTP one fires first; if the test budget won
  the race we would be back to a message that names nothing. onTimeout throws
  rather than synthesising a 5xx Response deliberately — a fake status code
  would make an `anyOf(200, 429)` assertion fail with a number the service never
  sent, which reads as a server bug.
regression_test_planned: >
  STATED PLAINLY BECAUSE IT IS A REAL LIMITATION: this file CANNOT run on the
  dev machine. It skips unless SUPABASE_TEST_EMAIL and SUPABASE_TEST_PASSWORD
  are set, and those are CI-only secrets — a local run reports "+1 All tests
  passed", which is the SKIPPED placeholder and not evidence of anything. So the
  fix's own wiring is exercised only in CI.
  What WAS proven locally, at zero quota cost: the timeout mechanism was
  reproduced verbatim against a black-hole address (10.255.255.1:9) in a
  throwaway probe. It fired at the budget, threw a TimeoutException naming the
  function and the wait, and did NOT produce the bare harness message.
  Mutation-proven: removing the onTimeout detail reddened 1 assertion. The probe
  was then DELETED rather than shipped — it duplicates the shape instead of
  exercising the real file, so keeping it would be a test that looks like
  protection it does not provide.
impact_analysis: >
  A slow live model call no longer fails the build at 30s, and when one does
  exceed 90s the failure says which function was slow and for how long. No
  production behaviour changes; no user-facing surface is touched. Cost note
  carried forward from the slice-2 diagnose: the three live chats here consume 3
  of the shared QA account's 10 daily messages, so CI can run about 3 times per
  IST day. This fix does not change that ceiling — a dedicated or PRO test
  account is the actual remedy and is not attempted here.
touched_layers_checked:
  - { tier: 1, name: client code, status: not_applicable, evidence: "no lib/ file changed; the diff is one file under test/ plus this doc" }
  - { tier: 2, name: hive, status: not_applicable, evidence: "no Hive surface in this file" }
  - { tier: 3, name: postgres schema, status: not_applicable, evidence: "no DDL" }
  - { tier: 4, name: postgres data, status: verified, evidence: "queried usage_counters live before running anything: test6@gmail.com chat_app used=3 of 10 for the current IST window, consumed by the failing CI run. No local run reached the live service, so this batch leaves the count unchanged." }
  - { tier: 5, name: migrations applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: edge function code vs deploy, status: not_applicable, evidence: "no Edge Function source changed; the deployed ai-proxy is untouched" }
  - { tier: 7, name: cron jobs, status: not_applicable, evidence: "no cron surface" }
  - { tier: 8, name: rls policies, status: not_applicable, evidence: "no policy changed" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: secrets, status: verified, evidence: "no secret read or added; confirmed SUPABASE_TEST_EMAIL/_PASSWORD are absent locally, which is exactly why the file skips here" }
  - { tier: 11, name: external services, status: verified, evidence: "the Gemini path is untouched; the failure was its LATENCY, and the fix only changes how long the harness waits and what it says when it stops" }
  - { tier: 12, name: client to server contract, status: not_applicable, evidence: "no contract changed; the assertions themselves are unmodified" }
related_bugs: [e7c4b2, f4a2d8]
recurrence: >
  Not a recurrence of a product bug. It IS a second instance of a harness class
  this repo already knows: CLAUDE.md 4.9 records that a test file whose work is
  bounded by an EXTERNAL process needs an explicit budget, and its 5th instance
  warns that a per-test timeout argument silently overrides a file-level
  @Timeout. That row was written about subprocess spawning; the same mechanism
  applies to a live network call, which is why the row's own framing — "the
  class is 'spawns a subprocess', NOT 'is named e2e'" — generalises here to
  "waits on something it does not control".
---

# A live-AI test ran on Dart's unit-test timeout

## What happened

`main` went red at `493d230b` on the `Supabase Integration Tests` job. One
test — T19, a one-sentence chat — exceeded 30 seconds and the run failed with

```
TimeoutException after 0:00:30.000000: Test timed out after 30 seconds.
```

Every other job passed: analyze, the 5406-test unit suite, the Deno
Edge-Function type-check, the APK build check, the audit gates and the
plan-review record gate.

## Why it is not the batch that pushed it

The batch that landed `493d230b` changed `weekly-report/index.ts` (not
deployed — live is still v26), test files and docs. It touched nothing
`ai-proxy` executes, and the same job passed on the three prior `main` runs.
What changed was live latency, which this file had no defence against.

## The actual defect

`callEdgeFunction` called `http.post` with **no timeout**, and the file declared
no `@Timeout`. So the effective budget for a live Gemini generation was Dart's
30-second default for unit tests — a number nobody chose for this workload — and
when it was exceeded the reported message named no function, no URL and no
elapsed time.

**Two budgets, ordered.** The HTTP budget (90s) must be smaller than the test
budget (3 min), or the test budget wins the race and the diagnostic is lost
again.

## What could not be verified here, stated plainly

This file **cannot run on the dev machine**. It skips unless
`SUPABASE_TEST_EMAIL` / `SUPABASE_TEST_PASSWORD` are set, and those are CI-only
secrets. A local run prints `+1 All tests passed` — that is the SKIPPED
placeholder, and reading it as a pass is exactly the empty-input-set trap.

The mechanism was proven separately, at zero quota cost, against a black-hole
address: it fired at the budget, named the function and the wait, and was not
the bare harness message. Removing the `onTimeout` detail reddened it. That
probe was deleted rather than shipped, because it duplicates the shape instead
of exercising the real file.
