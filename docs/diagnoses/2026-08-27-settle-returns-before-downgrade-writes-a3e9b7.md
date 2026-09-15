---
bug_id: a3e9b7
date: 2026-08-27
batch: apk-39-build
status: fixed
blast_radius: feature
symptom: >
  The pre-push full suite failed one assertion in
  `test/contracts/subscription_cqrs_behavioral_test.dart:286` —
  `Expected: null, Actual: '2026-08-26T14:22:04.764643'`, reason "the decision path must still
  wipe expiresAt". The value is a `_pastIso()` string, i.e. the failing test's OWN seed. The
  preceding assertion on `isPro` PASSED, so the run observed entitlement state MID-downgrade:
  after the first awaited write, before the second. The push was correctly aborted and nothing
  landed. Third occurrence of a failure in this file from the same class (2026-08-10,
  2026-08-25 as f3c7d2, now).
concept: >
  A stability sampler cannot distinguish "this write has not been scheduled yet" from "this write
  has finished" — both look like no change. f3c7d2 stated exactly that about the one
  fire-and-forget write at subscription_service.dart:458, then fixed only the setUp contamination
  it caused, leaving the sampler itself as the synchronisation mechanism for the five writes that
  follow. But isPro() calls _downgradeLocally() WITHOUT awaiting it (:464), so at the instant
  _settle() begins, none of those five writes need have started. Three stable 10 ms rounds can
  elapse entirely inside the gap between two of them. The fix stops sampling for a proxy and
  waits for the signal the production code already emits — _downgradeLocally fires onStateChanged
  only AFTER awaiting all five writes.
sot_registry_entry: >
  None added. No production file is modified — subscription_state already registers this
  writer/reader set and the contract is unchanged. The change is confined to the test harness
  synchronisation primitive.
writers:
  - { file: lib/core/services/subscription_service.dart, method: "isPro() genuine-expiry branch — calls _downgradeLocally() with NO await, which is what leaves the five writes unstarted at settle time. This is the line the two previous fixes did not name", line: 464 }
  - { file: lib/core/services/subscription_service.dart, method: "_downgradeLocally — awaits isPro/expiresAt/plan/localActivationAt/lastVerifiedAt in sequence, THEN fires onStateChanged", line: 1152 }
  - { file: lib/core/services/subscription_service.dart, method: "onStateChanged call — the completion signal, fired after the fifth write; the only observable meaning all five landed", line: 1175 }
readers:
  - { file: test/contracts/subscription_cqrs_behavioral_test.dart, method: "_settle — was a pure quiescence sampler; now chains onStateChanged and restarts the stability count once it fires", line: 76 }
  - { file: test/contracts/subscription_cqrs_behavioral_test.dart, method: "group B genuine-expiry test — expect(read(expiresAt), isNull); the assertion that observed the half-applied downgrade", line: 286 }
hive_key_prefix: expiresAt
hive_key_formula: "userBox['expiresAt'] via MigratedKey — user-scoped; deleted by _downgradeLocally as the second of its five writes."
sync_methods: not_applicable — expiresAt is written locally by _downgradeLocally and is never pushed by this path.
restore_methods: not_applicable — re-derived from the subscription row on refreshFromSupabase, not restored as a key.
cloud_table: none — expiresAt is the local mirror; the authoritative row is subscriptions.current_period_end.
cloud_columns: none — see cloud_table.
contract_test_path: test/contracts/subscription_cqrs_behavioral_test.dart
recurrence: >
  Third instance in this one file. 2026-08-10 replaced a fixed 20 ms sleep with the quiescence
  sampler. 2026-08-25 (f3c7d2) added a converging drain loop to setUp and marked itself
  status fixed; its own docstring was corrected during Hermes review to admit it closes the
  setUp-contamination window while the unawaited write remains. Each fix was a wider guess at the
  same heuristic. This one replaces the heuristic with the production completion signal.
ist_handling: not_applicable — no date KEY is derived here. The timestamps involved are absolute
  instants (expiry comparison via DateTime.now().isAfter), not IST day-boundary keys, so the
  IST rule does not bind. The seed helpers use relative offsets (now -1d / now +30d) for the same
  reason.
cross_account_guard: >
  Unchanged and still intact. The :458 marker write stays gated on
  HiveUserSession.currentOwnerFullId != null, and _downgradeLocally's streak clamp keeps the same
  guard — the 2026-06-06 cross-account banner-leak protection is untouched by this fix.
provider_invalidations: >
  None changed. _settle now CHAINS onStateChanged rather than replacing it, so every consumer the
  hook invalidates still receives its call in the same order; the test that counts fires still
  counts them. The handler is restored in a finally block so a throwing test cannot leak it.
telemetry_op_types: none — no telemetry event is emitted or altered by this change.
forbidden_patterns_checked: >
  No inline isPro gate added, no setState, no direct Hive/Supabase call from a widget, no
  Container(color:+decoration:). The change adds no production code at all.
impact_analysis: >
  Test-harness only. Blast radius feature — one file under test/contracts/. The risk of the fix
  is that it could WAIT LONGER and slow the suite: bounded by the same 5 s deadline as before,
  and measured at 00:03-00:04 for the file versus 00:02 previously, i.e. ~1 s across 16 tests.
  The opposite risk — waiting too little — is what it removes. No production behaviour changes.
proposed_fix: >
  Replace the pure quiescence sampler in _settle with one that chains SubscriptionService
  .onStateChanged and restarts the stability count the first time it fires, then restores the
  previous handler in a finally block. Rejected alternative: widening the heuristic (more rounds
  or a longer interval), which moves the failure rate without closing the window and is what the
  two previous fixes each did.
regression_test_planned: >
  The fixed file IS the regression test: test/contracts/subscription_cqrs_behavioral_test.dart,
  16/16. Because the defect is a race, presence of the fix was proven by instrumenting the
  restart branch and observing it fire 7 times in one run (the downgrade call sites) and not fire
  for the 5 healthy-row calls. A probabilistic load repro was attempted and was UNINFORMATIVE in
  both arms — see the body; it is recorded so it is not repeated.
related_bugs: [f3c7d2]
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "No lib/ file changed — git diff --stat shows one file, the test. Production downgrade behaviour is byte-identical; :464 stays deliberately unawaited because isPro() is a synchronous bool read." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "16/16 pass. Mechanism proven IN EFFECT by instrumenting the restart branch: the probe fired 7 times in one run across the file's 12 _settle() call sites — the downgrade paths — and did not fire for the 5 healthy-row calls, confirming the no-downgrade fallback is preserved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL; these are Hive keys." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function involved." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads these keys." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Local-only keys; no policy." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Razorpay/OneSignal untouched." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request shape changed." }
---

# _settle() returned mid-downgrade because it sampled a proxy instead of waiting for the signal

## What the failure actually said

```
test\contracts\subscription_cqrs_behavioral_test.dart 286:7
  Expected: null
    Actual: '2026-08-26T14:22:04.764643'
  the decision path must still wipe expiresAt
```

`_pastIso()` is `DateTime.now().subtract(const Duration(days: 1))`. The suite ran on 2026-08-27,
so `2026-08-26T14:22:04` is this test's own seed, written seconds earlier — **not** a stale value
from a previous test, which is what f3c7d2 diagnosed. The assertion on `isPro` immediately above
it PASSED. One of `_downgradeLocally`'s five writes had landed and the next had not.

## Why the previous two fixes did not hold

Both hardened the same heuristic.

| Date | Fix | What it left |
|---|---|---|
| 2026-08-10 | fixed 20 ms sleep → quiescence sampler | sampler still cannot see an unstarted write |
| 2026-08-25 (f3c7d2) | converging drain loop in `setUp` | closes setUp contamination only; its own docstring says so |
| 2026-08-27 (this) | wait for `onStateChanged` | replaces the heuristic with the signal |

The load-bearing line neither earlier fix named is `subscription_service.dart:464`:

```dart
_downgradeLocally();   // Future<void>, called WITHOUT await
```

`isPro()` is a synchronous `bool` read — by design, post-CQRS-split, so it can be called from a
`build()`. It therefore *cannot* await the downgrade, and that is correct production behaviour.
The consequence is that when `_settle()` starts, the five writes may not have been scheduled at
all. Three stable 10 ms rounds inside that window is a false positive, and under load the window
is easily wide enough to contain them.

## The fix

`_downgradeLocally` fires `onStateChanged` **after** awaiting all five writes
(`subscription_service.dart:1175`). That hook is the only observable meaning "every write has
landed". `_settle()` now chains it — preserving any handler the caller installed, so the test
that counts hook fires still counts them — and restarts the stability count once, the first time
it fires. Quiescence observed before the hook is treated as the false positive it is.

The hook is a **floor, not a replacement**: a healthy active row never downgrades and never fires
it, so with no downgrade the behaviour is exactly as before. Restarting the count rather than
returning on the hook also keeps the trailing fire-and-forget `:458` marker covered by real
quiescence.

## What was proven, and what was not

**Proven — the mechanism executes.** Instrumenting the restart branch showed the probe firing
**7 times** in one run, across the file's 12 `_settle()` call sites: the downgrade paths. It did
not fire for the 5 healthy-row calls. The fix is not inert, and the fallback is intact.

**NOT proven — a load reproduction.** An attempt to reproduce probabilistically (8 CPU
busy-loops against the single test file) gave PASS 5/5 with the fix **and** PASS 6/6 with the fix
deliberately neutered. Recorded plainly because it is a negative result about the *method*, not
evidence for the fix: that load model does not reproduce the original condition, which arose in a
690-file suite at ~4-way isolate parallelism with concurrent `dart run` calls contending on the
Dart SDK lock. Both arms passing means the experiment was uninformative in both directions. It is
written down so nobody re-runs it expecting signal.

The real gate is the pre-push full suite — the input set the failure actually appeared in.

## Contributing condition worth recording

The failing run was made materially more likely by six concurrent `dart run` invocations issued
*while* the full suite was executing. CLAUDE.md §0 documents that `flutter/bin/dart` is a wrapper
which takes the SDK update lock and **serializes** concurrent callers. Incidental "quick checks"
during a running suite are not free — they are load, and this class of test is load-sensitive by
construction.
