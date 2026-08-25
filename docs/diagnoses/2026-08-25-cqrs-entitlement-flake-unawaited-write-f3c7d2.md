---
bug_id: f3c7d2
date: 2026-08-25
batch: launch-blockers-1
status: fixed
blast_radius: feature
symptom: >
  `test/contracts/subscription_cqrs_behavioral_test.dart` fails intermittently with
  `Expected: null, Actual: '2026-08-24T01:39:16.286648'` on a `pro_lapsed_at` assertion. It is
  load-dependent: reproduced 1-in-3 while the machine was busy, 0-in-9 idle. Because it lands in
  the full suite it is indistinguishable from a real regression, and it blocks a push at random.
  Second occurrence of this shape in this same file (first: 2026-08-10).
concept: >
  A sampler cannot observe a write that has not started. The enforcement path stamps the lapse
  marker fire-and-forget, OUTSIDE the method whose writes the test's quiescence helper was built
  around. Quiescence closes the "write in flight" window but not the "write not yet scheduled"
  window — an unstarted write is byte-identical to a finished one from the sampler's point of
  view. Under load the write misses the stability window entirely, lands after the NEXT test's
  setUp has cleared the keys, and resurrects one with the previous test's value.
sot_registry_entry: >
  None added. `subscription_state` already registers the entitlement writer/reader set and this
  fix changes neither — the only production file involved is read, not modified. The change is
  confined to test-harness teardown/setup determinism.
writers:
  - { file: lib/core/services/subscription_service.dart, method: "genuine-expiry branch — unawaited(MigratedKey.write(_proLapsedAtKey, expiresAt.toIso8601String())); the ONLY fire-and-forget entitlement write, and the one outside _downgradeLocally", line: 458 }
  - { file: lib/core/services/subscription_service.dart, method: "_downgradeLocally — awaits ALL of its own writes (isPro/expiresAt/plan/localActivationAt/lastVerifiedAt), which is why the sampler works for those and not for :458. Corrected 2026-08-25: this cited :275, which is inside writeSubscriptionState (an ACTIVATION write) — opposite semantics, and exactly the mis-citation the naming rule exists to prevent", line: 1152 }
  - { file: test/contracts/subscription_cqrs_behavioral_test.dart, method: "setUp — cleared the six keys in a single pass, with nothing guaranteeing a late write could not land after it", line: 118 }
readers:
  - { file: test/contracts/subscription_cqrs_behavioral_test.dart, method: "group A test 1 — expect(MigratedKey.read('pro_lapsed_at'), isNull) after a PURE read; the assertion that observed the resurrected key", line: 177 }
  - { file: test/contracts/subscription_cqrs_behavioral_test.dart, method: "_settle — quiescence sampler; its key tuple DOES include pro_lapsed_at, which is why 'add the key to the tuple' was not the fix", line: 76 }
hive_key_prefix: pro_lapsed_at
hive_key_formula: "userBox['pro_lapsed_at'] via MigratedKey — user-scoped, which is itself the fix for the 2026-06-06 cross-account banner leak."
sync_methods: not_applicable — the lapse marker is local-only and is never pushed.
restore_methods: not_applicable — never restored; it is re-derived from expiry state.
cloud_table: none — pro_lapsed_at exists only in the per-user Hive box.
cloud_columns: none — see cloud_table.
contract_test_path: test/contracts/subscription_cqrs_behavioral_test.dart
ist_handling: >
  not_applicable, and worth stating because it was my first (wrong) hypothesis. The failing value
  looked date-shaped and the failures clustered after midnight IST, so this was initially
  diagnosed as an IST/UTC date-boundary bug. It is not. See impact_analysis — the refutation is
  recorded deliberately so nobody re-derives it.
provider_invalidations: none — no production behaviour changed.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  Untouched and verified still intact. The :458 stamp remains gated on
  `HiveUserSession.currentOwnerFullId != null`, which is what keeps the marker in the per-user
  userBox rather than the shared configBox (the 2026-06-06 P0). The fix adds no write path.
forbidden_patterns_checked: >
  Checked and clean. No production file modified. No fixed sleep introduced — the file's own
  docstring already records why a fixed sleep is not a synchronization primitive, and the new
  helper is a converging loop with an explicit deadline and a LOUD failure, not a longer wait.
proposed_fix: >
  Replace setUp's single-pass key deletion with `_drainAndClearEntitlementKeys()`: a converging
  loop that deletes any non-null entitlement key, samples, and only exits once a full pass sees
  every key null AND that holds for 3 consecutive rounds. A late write resurrects a key, the next
  pass deletes it, and the loop converges by construction. On failure to converge within 5s it
  THROWS with the offending key names, so a future unawaited writer surfaces as itself rather
  than as a bogus assertion failure against correct production code.
regression_test_planned: [test/contracts/subscription_cqrs_behavioral_test.dart]
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "No lib/ file changed — confirmed by git diff --stat: the only modified file is the test. Production expiry behaviour is byte-identical." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "The fix operates entirely on Hive entitlement keys in the test harness. 16/16 pass idle; 6/6 pass under the same CPU load that produced the failure." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL; pro_lapsed_at is Hive-only." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function involved." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads the lapse marker." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Local-only key; no policy." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Razorpay/OneSignal untouched." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request shape changed." }
impact_analysis: >
  Product impact: ZERO. This is a test-harness defect and no user is affected. That conclusion is
  load-bearing enough to justify how it was reached, because the obvious reading was the opposite.

  Why the unawaited write is NOT a production race. The concern would be the :458 stamp landing
  AFTER something deletes it, losing the Home expiry banner. It does not: `_downgradeLocally`
  (read in full) writes isPro=false and deletes expiresAt / plan / localActivationAt /
  lastVerifiedAt — it does NOT touch pro_lapsed_at. The only delete of the marker lives in
  `writeSubscriptionState`, which runs when a NEW subscription is written, where clearing it is
  correct. So the marker always survives the downgrade regardless of when the unawaited write
  lands, and the "stamp BEFORE the wipe" comment at :448 holds in effect even though the write is
  not awaited.

  ⚠ TWO WRONG HYPOTHESES, recorded so they are not re-derived. (1) "CI runs UTC, local runs IST."
  FALSE — `.github/workflows/test.yml:27-28` sets `TZ: Asia/Kolkata`, so CI runs IST too. (2)
  "Then it must be an IST/UTC date-boundary bug in expiry, firing in the 00:00-05:29 IST window
  where the IST and UTC dates differ." Also false, and it was seductive: the failures did cluster
  after midnight IST, the value WAS date-shaped, and the diagnoses index carries a genuine
  recurring IST/UTC class (7ad0d3, 26b360, bb3acc, 4c8788) that it pattern-matched perfectly.
  What killed it: running the full suite under TZ=UTC to "match CI" broke 19 unrelated tests
  (meals_today, today nlog_ rows, getTodayUserMessageCount) because the app is IST-throughout by
  design — so UTC is never a valid way to verify this suite. The real variable was machine LOAD,
  not the clock; the after-midnight clustering was confounding, not causal, because that is simply
  when the machine was busy running other suites. Proof: 1-in-3 failures under synthetic CPU load
  at 08:10 IST — hours outside the supposed window — and 0-in-9 idle.

  Blast-radius tradeoff, stated rather than left implied: the drain throws from `setUp`, so if a
  writer ever fails to converge inside 5s the WHOLE FILE fails at setup rather than one assertion
  failing mid-test. That is deliberate — a loud, attributable setup failure beats a silent
  misattribution — but it is a change in failure shape, not purely an improvement.

  Cost of the misdiagnosis: roughly an hour, plus two full-suite runs. It is exactly the failure
  mode the new loud StateError is designed to prevent — leftover test state presenting itself as a
  production defect.

  Why this recurred. The 2026-08-10 fix replaced a 20ms fixed sleep with the quiescence sampler
  and documented that history well. But it hardened the sampler and left the single genuinely
  unawaited write outside its reach — fixing the instance, not the mechanism
  (feedback_mistake_guard_without_its_mirror, now 16 instances across 8 sessions). The converging
  clear is mechanism-level: it does not need to know which writes exist, only that the keys end up
  and stay gone.
---

# f3c7d2 — the entitlement CQRS test flakes under load, and it is not a timezone bug

## The failure

```
Expected: null
  Actual: '2026-08-24T01:39:16.286648'
```

on `expect(MigratedKey.read('pro_lapsed_at'), isNull)`. The value is a `_pastIso()` output — the
`expiresAt` a *previous* test seeded.

## The mechanism

`subscription_service.dart:458` stamps the marker fire-and-forget:

```dart
unawaited(MigratedKey.write(_proLapsedAtKey, expiresAt.toIso8601String()));
```

It sits OUTSIDE `_downgradeLocally`, which awaits every one of its own writes. The test's
`_settle()` samples the key tuple for quiescence — and `pro_lapsed_at` **is** in that tuple, which
is why "add the key" was not the fix. The gap is subtler:

> a write that has not been scheduled yet is indistinguishable, to a sampler, from one that has
> finished.

Under load the write misses `_settle()`'s 3×10 ms stability window entirely, lands after the next
test's `setUp` cleared the keys, and resurrects one.

## The fix

`setUp` now calls `_drainAndClearEntitlementKeys()` — delete, sample, repeat until every key reads
null for 3 consecutive rounds; throw loudly with the key names if 5 s passes without converging.

## Verification

| Condition | Before | After |
|---|---|---|
| Idle | 0 failures / 9 runs | 16/16 pass |
| Under CPU load | **1 failure / 3 runs** | **0 failures / 6 runs** |
| Mutation (restore single-pass delete) | — | **1 failure / 3 runs** — reproduces |

Production code is unmodified; `git diff --stat` shows one changed file, the test.
