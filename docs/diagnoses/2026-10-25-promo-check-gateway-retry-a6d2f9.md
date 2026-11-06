---
bug_id: a6d2f9
date: 2026-10-25
batch: oi414-promo-no-gateway-retry
status: fixed
blast_radius: platform
symptom: >-
  One tap on the paywall's APPLY button can invoke validate-promo up to four
  times. validate-promo spends one check unit before it reads the body, and the
  shared client wrapper SupabaseService.callFunction sends a call again, after
  2 s, 6 s and 12 s, whenever the gateway answers 502, 503 or 504. If the
  gateway answers after the handler already ran, every send spends another unit.
  At 7 units per fixed UTC-hour bucket (PR #168), two such taps lock the user out
  of promo checks until the bucket ends (up to 60 minutes). The same shape exists
  for the PRO day swap (consume-day-swap, 3 per IST week: one swap can leave the
  week at 3 of 3). NOT observed live: a 30-day read of client_errors (7,142 rows)
  holds no edge_function_cold_start_retry event for either function.
concept: gateway_error_resend_spends_quota
sot_registry_entry: promo_validate_rate_limit
writers:
  - { file: supabase/functions/validate-promo/index.ts, method: handler (consume_quota before the body is read), line: 88 }
  - { file: supabase/functions/consume-day-swap/index.ts, method: handler (consume_quota, no refund), line: 106 }
  - { file: lib/core/services/supabase_service.dart, method: SupabaseService.retryColdStart (the loop that sends the call again; isColdStart predicate unchanged), line: 534 }
  - { file: lib/core/services/supabase_service.dart, method: retryColdStart early gate for a flagged call (the fix), line: 551 }
readers:
  - { file: lib/core/services/supabase_service.dart, method_or_widget: callFunction (now forwards spendsQuotaPerCall), line: 445 }
  - { file: lib/shared/widgets/paywall_sheet.dart, method_or_widget: _validatePromoCode (the only validate-promo caller; passes the flag), line: 220 }
  - { file: lib/core/services/day_swap/day_swap_allowance.dart, method_or_widget: DaySwapAllowance._callServer (the only consume-day-swap caller; passes the flag), line: 120 }
hive_key_prefix: "day_swap_allowance (userBox, phone copy of the weekly swap count); the promo half has no Hive state"
hive_key_formula: "DaySwapAllowance.hiveKey -> {weekStart(IST Monday): {used, limit?, pro?, server_seen_at_ms?}}"
sync_methods: []
restore_methods: []
cloud_table: usage_counters
cloud_columns: [user_id, quota_key, window_start, used, updated_at]
contract_test_path: test/contracts/edge_function_cold_start_retry_behavioral_test.dart
ist_handling: []  # no date key is written or read; the promo bucket is a fixed UTC hour by founder decision, the swap window is the server's IST week
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [edge_function_no_retry_quota_call, day_swap_allowance_consume]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "client\\.functions\\.invoke\\(", absent: false }  # exactly one occurrence in supabase_service.dart, unchanged
  - { pattern: "e\\.status == 500 not preceded by retryOn500 &&", absent: true }
  - { pattern: "retry|401 inside the /// doc above callFunction", absent: true }
  - { pattern: "callFunction\\(\\s*['\"]validate-promo['\"] without spendsQuotaPerCall: true", absent: true }
  - { pattern: "callFunction\\(\\s*['\"]consume-day-swap['\"] without spendsQuotaPerCall: true", absent: true }
proposed_fix: >-
  A named argument spendsQuotaPerCall (default false) on callFunction and
  retryColdStart. A separate early gate inside the FunctionException catch, before
  the isColdStart branch, throws a 502, 503 or 504 on the first answer for a
  flagged call and logs edge_function_no_retry_quota_call (fn and status; LOW
  priority, no server change). retryOn500 stays independent; every other status
  and a transport failure (status 0) are unchanged. isColdStart stays byte-identical.
  paywall_sheet.dart and day_swap_allowance.dart pass true. Default false is the old
  behaviour verbatim for every other caller.
regression_test_planned:
  - test/contracts/edge_function_cold_start_retry_behavioral_test.dart
  - test/contracts/call_function_spends_quota_per_call_behavioral_test.dart
  - test/contracts/spends_quota_per_call_source_pins_test.dart
related_bugs:
  - c7e3b1  # H1: the order endpoint answered 502 on a refused order; callFunction sent it again, each send a unit. Same class, fixed there on the server (answer 500).
  - c01d57  # origin of the 502/503/504 re-send set (ai-proxy cold starts); this change narrows it per call, not globally
  - f2c9a8  # OI-366: the promo limit the amplification now bites
recurrence: |
  Recurrence of c7e3b1 H1 (2026-10-25): a function that spends a quota unit per
  call is re-sent by the shared client wrapper after a gateway error. H1 fixed the
  order endpoint on the SERVER by making its own refusals answer 500; that cannot
  help a status only the gateway produces, and it left every other metered call
  exposed. This fix is on the client and per call. A second instance of the same
  drift: day_swap_allowance.dart's header says "nothing retries - a retry after an
  ambiguous failure could double-count", yet callFunction sent the call again; the
  writer's stated contract and the wrapper's behaviour had drifted apart.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "supabase_service.dart (flag, forward, early gate, status set); paywall_sheet.dart and day_swap_allowance.dart pass the flag. flutter analyze whole project: no new finding." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "day_swap_allowance keeps its phone +1 on a thrown call (_consume catch records day_swap_allowance_consume); the next server reply overwrites it. The server runs behind the phone by one per failed call that did not reach the handler (accepted property A7)." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Read-only: client_errors spans 2026-09-25..2026-10-25 (7,142 rows); edge_function_cold_start_retry events: ai-proxy 502 x9, log-client-error 503 x4, none for validate-promo or consume-day-swap; rows mentioning BOOT_ERROR: 0." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function source changed; validate-promo v23 and consume-day-swap are untouched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No Razorpay, OneSignal or Firebase interaction changed." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "call_function_spends_quota_per_call_behavioral_test.dart drives the real SupabaseService.callFunction over real HTTP against a loopback server answering 502: a flagged call produces ONE request and one stop event; the unflagged control is sent again after 2 s (two requests by 2.6 s)." }
impact_analysis: >-
  Every caller of callFunction except the two flagged ones is unchanged (default
  false; short-circuit before anything new is read). validate-promo: a gateway
  502/503/504 on APPLY now shows the existing "Network error. Try again." after one
  attempt instead of up to four; a cold-start 5xx no longer recovers by itself, the
  user taps again. consume-day-swap: a gateway error keeps the phone copy and the
  server runs behind the phone by one per such failed call (accepted property A7). Pre-launch every account is a testing account (CLAUDE.md
  section 1); no existing-user path is affected.
---

# A gateway error must not make a metered call spend a second unit

Plan: `docs/plans/2026-10-25-oi414-promo-no-gateway-retry.md` (version 3, two context-blind review rounds). Board: OI-414. Founder scope call (2026-10-25): "Promo + day-swap (Recommended)". Closure ledger: `docs/audit/oi414-promo-no-gateway-retry.closure.yaml`.

## Writers and readers (named before the fix, CLAUDE.md 4.1)

- **Spend:** `validate-promo/index.ts:88` and `consume-day-swap/index.ts:106` call `consume_quota` before doing their work; `128_usage_counters.sql:95-100` counts every call that gets in below the limit. Neither function answers 502, 503 or 504 itself, so those statuses come from the platform and can arrive after the handler ran.
- **Send again:** `supabase_service.dart` `retryColdStart` (`isColdStart` at :534: 502, 503, 504, and 500 only with `retryOn500`), schedule `[2000, 6000, 12000]` ms, so up to four invocations per tap.
- **Callers:** exactly one each (`git grep` over lib/): `paywall_sheet.dart:219-220` and `day_swap_allowance.dart:120-123`.

## What is and is not claimed

- A gateway error costs 0 or 1 unit per tap and **the user cannot tell which**. The guarantee is "at most one unit per tap". This document and the OI closure never say "the handler did not run" or "a failed check costs nothing".
- **Deviation from OI-414's wording** ("the 503 boot-failure retry is unchanged"): a flagged call is not sent again on a 503 either. A BOOT_ERROR 503 means the handler never ran, but the repo has never observed that body (0 rows in client_errors mention BOOT_ERROR; only prose in 0a7b9f), so a carve-out keyed on `details['code']` would be an unverified helper that fails silently into "never send again". If a real body is ever captured, a carve-out can be added with that fixture.
- **Duplicate telemetry on the day swap is intended:** a gateway error produces `edge_function_no_retry_quota_call` (from the wrapper) and `day_swap_allowance_consume` (non-fatal from `_consume`).
- With the server kill switch `DISABLE_ORDER_ABUSE_GUARDS` on, validate-promo spends nothing but still loses the re-send. Harmless.
- **Accepted property A7 (day swap, under-count direction):** every swap whose call fails without reaching the handler leaves the server one more behind the phone (one per failed call, not one in total). Only another swap's reply overwrites the phone copy, downward, so a PRO user can reach limit+N swaps in the week (N = failed calls that did not reach the handler) and a second device can swap past a free limit. It is the recoverable direction, small and rare, and the same choice `weekly-report` makes.
- **Not flagged on purpose:** `create-razorpay-order` (30 per fixed hour; a re-send yields at worst a second unpaid order and the re-send recovers a cold start at the moment of payment). The flagged set today is `validate-promo` and `consume-day-swap`; the classification of every other call that reaches `callFunction` is in the closure ledger, and `docs/naming_conventions.md` and `docs/architecture/payment.md` say so instead of stating a general rule.
- **CLAUDE.md 4.6 (feature-flag protocol), stated openly:** payment is on the 4.6 list. The gate here is the compile-time call-site argument (default false = the old path verbatim for every other caller; rollback = revert the PR or drop the argument; a new build is needed). It is not a runtime flag. The direction is the safe one (less re-sending), the fault mode is a second tap, and no real user exists yet (CLAUDE.md section 1). The fallback if the B-pass or the founder rejects this reading is a lazily read Hive key `disable_no_gateway_resend`, which would then owe a removal OI (4.6 step 4). The plan-review record and the B-pass review file record the acceptance.
- Related registry concepts: `promo_validate_rate_limit` (primary) and `day_swap_allowance` (the second call site).
- OI-414's "done when" (a behavioural test that the promo call is not re-sent) is met by composition: the loop is behavioural (11 tests in the group, T1-T9), forwarding through `callFunction` is behavioural over real HTTP (1 test + a control), and the two call-site ARGUMENTS are source pins (presence only; a widget-level run needs the paywall provider tree, and the day-swap behavioural file's `debugConsumeForTests` bypasses `_callServer`).

## Mutation proof (CLAUDE.md 4.4 rule 21)

A compile error before the fix is NOT proof (the new tests name the new argument). The proof is the mutant run, repeated against the FINAL tests after the B-pass fixes. The mutation script is **session-local and not retained** (it lived in the session scratchpad; this table is the record). It computed every mutant before it wrote, asserted each anchor matched exactly once, restored in `finally` and on signals, and compared sha256 afterwards: **equal**. It ran over 7 test files (69 tests, baseline all green): the three new/extended ones, the three source pins that read the wrapper (`edge_function_503_retry_test.dart`, `retry_loop_guard_test.dart`, `food_ai_telemetry_retry_test.dart`) and `edge_function_storage_race_retry_test.dart` (included because it drives the same loop; the gate fires only on 502/503/504, so it is expected to stay green and does). 21 mutants plus M11 (run apart, behavioural files only), **all red, none survived, none a compile error**:

| # | Mutant | Red | Caught by |
|---|---|---|---|
| M1 | gate disabled | 7 | T1, T2, T3, T8, T9, end-to-end, gate-order pin |
| M2 / M3 / M4 | set drops 504 / 502 / 503 | 3 / 5 / 3 | the set pin plus the status's own tests (T2, T8 / T1, T8, T9, end-to-end / T3, T8) |
| M5 | `callFunction` default true | 2 | end-to-end control, declaration pin |
| M6 | `retryColdStart` default true | 14 | every test that expects a send-again |
| M7 | `callFunction` does not forward | 2 | end-to-end, forwarding pin |
| M8 | forward swapped with `retryOn500` | 3 | end-to-end, the new forwarding pin, and the EXISTING `food_ai_telemetry_retry_test.dart` pin on the `retryOn500` forward |
| M9 / M10 | paywall / day swap drops the argument | 1 / 1 | call-site pin (presence only, by design) |
| M11 | gate placed after the wait | 6 | T1, T2, T3 (the 60 s wait times out), end-to-end; T8 and T9 too, because the late copy logs no event (behavioural files only) |
| M12 | set also holds 500 | 4 | T6, T7, T8, set pin |
| M13 | stop event removed | 7 | T1, T2, T3, T8, T9, end-to-end, event pin |
| M14 | event message loses `fn=` | 6 | T1, T2, T3, T8, T9, end-to-end (full-string assertions) |
| M15 | `unawaited` becomes `await` | 1 | pin only (invisible to a synchronous test hook) |
| M16 | gate `&&` becomes `||` | 20 | |
| M17 | flag ignored | 15 | |
| M18 | flag only inside a `/* comment */` at the paywall | 1 | call-site pin (comment stripping) |
| M19 | telemetry lane carries the flag | 1 | anonymous-lane pin |
| M20 | a status (520) added to the `isColdStart` predicate only | 1 | T8 (the sweep; a list of three statuses would have missed it) |
| M21 | gate also requires `!retryOn500` | 2 | T9 (behavioural) and the gate-order pin (which can no longer find the gate text) |

Not claimed: `rethrow` to `throw e` is behaviourally equivalent (it only loses the stack trace). The three pins on the unchanged predicate stay green unchanged; the status set is a separate constant so the gate text never duplicates the predicate text a pin reads. The M11 and M15 caveat stands: M15 is killed by a source pin only, because the event hook is synchronous.
