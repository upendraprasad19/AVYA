---
bug_id: b95d61
date: 2026-10-21
batch: oi341-piece-b2-door (OI-341 Piece B2a)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: catastrophic
symptom: >-
  `create-razorpay-order`'s double-payment guard (APK Test #12.2 / Task #6, added after the founder paid four times in
  24 h on 2026-05-06) read the caller's latest active unexpired `subscriptions` row as `const { data: existing } = ...`
  and never looked at `error`. A failed read (a PostgREST error, a transport failure, a timeout) leaves `data` null, so
  the guard read as "no active row" and the function went on to create a Razorpay order. A PRO user could therefore be
  sold a second plan whenever the read failed: the guard failed OPEN in the one direction it exists to prevent. Found
  while planning OI-341 Piece B2a (plan docs/plans/oi341-piece-b2-door.md, section 1 facts, round 1 review).
concept: trial_purchase_door — an order is created only when the subscription read SUCCEEDED and the door's rule allows it.
sot_registry_entry: trial_purchase_door
writers:
  - { file: supabase/functions/create-razorpay-order/index.ts, method_or_widget: "handler: the guard block (one read of active unexpired rows; a read error answers 500 subscription_check_unavailable)", line: 146 }
readers:
  - { file: supabase/functions/create-razorpay-order/index.ts, method_or_widget: "handler: the Razorpay POST /v1/orders call, reached only after the guard allows it", line: 243 }
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: "openCheckout: callFunction('create-razorpay-order'); a non-2xx throws FunctionException and checkout does not open", line: 149 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [user_id, status, end_date, plan]
contract_test_path: supabase/functions/create-razorpay-order/index_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["none new: a created order is unchanged"]
  failure: ["console.error '[create-razorpay-order] request_id=<8hex> subscription guard read failed code=<sqlstate or no_rows_array>' (the code only, never the message); the response carries the same request_id"]
cross_account_guard: "the read is scoped by the JWT-verified user id (`supabase.auth.getUser(token)`), never by a client-supplied id; the test 'another user's paid row (order created)' pins that another user's row never blocks the caller."
forbidden_patterns_checked:
  - "answering 503 for the read failure — REJECTED (plan review round 1 P2-3): the client's retryColdStart repeats 502/503/504 up to 3 times, and supabase/functions/CLAUDE.md reads a 503 as boot-broken in the deploy smoke. 500 with error_code subscription_check_unavailable is not retried and not confused with a boot failure."
  - "keeping `.order().limit(1).maybeSingle()` — REJECTED: the B2a door needs every active row (a paid row must win over a later trial row), and `.maybeSingle()` without the limit fails on two rows (PGRST116, f2b9d4). One unlimited array read, decided in code."
  - "falling back to 'no row' on error (today's behaviour) — that is the bug: bug class 2.49, an error fallback that picks the destructive default (here: take the money)."
proposed_fix: >-
  `create-razorpay-order` reads `select plan, end_date where user_id = me and status = 'active' and end_date > now` with
  no limit, and checks `error` and that `data` is an array. On a failure it logs the code and answers 500
  `{error: "Could not verify your subscription. Please try again.", error_code: "subscription_check_unavailable",
  request_id}` without calling Razorpay, in BOTH switch states. On success the shut door answers today's 409
  `already_pro` from the latest-ending row (byte-identical to origin/main, golden-pinned) and the open door applies the
  B2a rule (plan 2.2). The env is read inside an exported `handler` and `serve()` runs only as the entrypoint, so the
  function is testable without binding a port.
regression_test_planned:
  - "supabase/functions/create-razorpay-order/index_test.ts: 'guard read ERROR (door shut)' and '(door open)': 500 subscription_check_unavailable, an 8-hex request_id, NO Razorpay order call; 'guard read ERROR: origin/main created the order' runs the SAME scenario against the unmodified origin/main door (fixture) and shows it answered 200 and created the order, i.e. the test fails without the fix."
  - "the same file's door-SHUT golden: 9 scenarios x 6 shut switch states against origin/main (status, body, the order body, the guard read's table and filters), so the fix changes nothing but the error case."
mutation_proof: >-
  D1 (the error check replaced by `if (false)`) reddens 2 tests (both guard-read-error tests: the handler then crashes
  on `null.filter` and answers the generic 500 'Internal server error', not subscription_check_unavailable). It is one
  of 53 B2a mutants run by `mutate_b2a.py` (scratchpad; 43 by the author, 10 proposed by the B-pass), each applied by an
  exact-one-match replace computed before any write, restored in a finally, and byte-compared after the run; 53 of 53
  red after two survivors (W4b, a log-line mutant, and SA1, a timer leak; neither is this fix) were closed. SA5 (the
  failure log without its code) is red through a test added by the B-pass. Self-attested.
impact_analysis: >-
  Behaviour change, deliberate and stated in the plan (2.2.2): a failed guard read used to create the order and now
  refuses it with a retryable message. The client treats any non-2xx from this function as a failed checkout open
  (FunctionException), so the user sees the existing checkout-failure path and can retry; no payment is taken. No real
  users exist yet (testing phase).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "lib/core/services/razorpay_service.dart:145-226 calls the function through SupabaseService.callFunction; a 500 throws FunctionException and the catch path aborts checkout (onFailure). No client change in B2a (B2b owns the client)." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "subscriptions.plan is NOT NULL (migration 006:9); status and end_date are the columns the guard always filtered on; no migration in B2a" }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "the live create-razorpay-order is the origin/main code (the fixture is a byte copy of b8385b6c); the B2a deploy is plan section 4 step 1, its own founder go, NOT done" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "the function reads with the service-role client, scoped by the JWT-verified user id" }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET hold the live pair (founder, 2026-10-21); B2a changes no secret value; SECRET_INVENTORY's RAZORPAY_KEY_SECRET row now lists this function" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the 409 already_pro body is unchanged on the shut door (golden); the new 500 carries error/error_code/request_id like the function's other errors" }
recurrence: "Same class as bug class 2.49 (an error fallback picks the destructive default) and f0b6d8 (clean-orphan-media read only `data` and treated an unreadable read as 'free', 2026-10-11) and f2b9d4 (ai-proxy checkPro, .maybeSingle() without a limit). Searched INDEX for the token (`create-razorpay-order`, `already_pro`) and the concept (double payment, duplicate active subscription): the only hit is 519075 (2026-05-06, the client's dead 409 detection), a different defect. The guard itself (2026-05-06) never had a diagnose-doc; this is its first."
related_bugs:
  - f0b6d8
  - f2b9d4
  - 519075
---

# `create-razorpay-order`'s double-payment guard failed open on an unreadable read

## What was wrong

The guard exists because the founder paid four times in 24 hours on 2026-05-06 while the phone's local PRO read was
false. It read the latest active unexpired row and answered 409 `already_pro` when it found one. It kept only `data`,
so a failed read looked exactly like "no row", and the function created the Razorpay order. The guard therefore
protected the case where nothing went wrong and did nothing in the case where the database could not answer.

## Writer and reader

Writer of the decision: the guard block in `handler` (`create-razorpay-order/index.ts:146-178`). Reader of the
decision: the Razorpay `POST /v1/orders` call in the same handler, and the client's `openCheckout`
(`razorpay_service.dart:145-226`), which opens checkout only on a 200.

## The fix

See `proposed_fix`. Plan: `docs/plans/oi341-piece-b2-door.md` (v4.2, section 2.2 item 2). Registry: concept
`trial_purchase_door`. Ledger: `docs/audit/oi341-piece-b2-door.closure.yaml`.
