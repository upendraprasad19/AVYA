---
bug_id: 060837
date: 2026-10-26
batch: oi410-verify-nonactive-row (OI-410)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: catastrophic
symptom: >-
  verify-payment answered HTTP 200 `{verified: true, plan, end_date, source: "razorpay_api"}` for a payment whose
  subscriptions row was NOT `active` (cancelled, expired, any other value). The early read filters `status = active`
  in SQL, but three later arms read the same row (user id + payment id) without that filter and fell through to the
  same success answer: the idempotency pre-select's `else` arm, the OFF-branch 23505 re-read, and the stacking-ON
  `record_paid_subscription` answer with `inserted = false` (migration 161 returns the stored row whatever its
  status). Two of the three were reachable only because a transient read ERROR on the pre-select left the row "not
  found" and sent the request into the insert branch. The caller must own the payment (notes.user_id equals the JWT
  caller) and Razorpay must still say `captured`, so no stranger gains anything; the owner of an operator-cancelled
  paid row got `verified: true` and the client wrote optimistic local PRO with that row's date. Found by the
  payment-hardening hermes pass (docs/audit/2026-10-25-hermes-payment-hardening.md, H5, P3), filed as OI-410. LATENT
  when found: 14 live subscriptions rows, 4 non-active (3 cancelled, 1 expired), all with an end date in the past.
concept: verify_payment_verified_means_active_row - for a row this request did not insert, verify-payment answers verified:true only after reading that row as active in the same request.
sot_registry_entry: verify_payment_verified_means_active_row
writers:
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "handler: the stacking-ON door - after record_paid_subscription answers inserted=false, one status read keyed on payment id AND user id, gated by replayGate", line: 689 }
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "handler: the OFF-branch 23505 door - the winner row's re-read now selects status and is gated by replayGate", line: 766 }
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "handler: the idempotency pre-select's else arm - gated by replayGate before the row's end_date is read", line: 779 }
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "replayVerdict / replayGate: the ONE decision (ok only for a row read as exactly active) and its two HTTP 200 soft failures", line: 849 }
readers:
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: "_pollAndActivate Phase 2: writes PRO with the row's end_date only on status 200 && verified == true; anything else falls to Phase 3", line: 915 }
  - { file: lib/core/services/payment_retry_attempt.dart, method_or_widget: "runVerificationRetryAttempt: only verified == true writes PRO and clears the grace window", line: 82 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [status, razorpay_payment_id, user_id, end_date]
contract_test_path: supabase/functions/verify-payment/index_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["none new"]
  failure: ["none new: two code-only console lines, `[verify-payment] replay refused, row not active payment_id= status=` and `[verify-payment] replay unconfirmed payment_id= code=` (allowlisted in payment_log_safety_writer_to_reader_test.dart)"]
cross_account_guard: "unchanged and still first: notes.user_id must equal the JWT caller before any read of the stored row (diagnose b5e8d2). The three reads are keyed on payment id AND user id. A foreign-owned row with the same payment id (impossible by the notes check and the unique index, but unguarded in the OFF 23505 arm before this fix) now answers unconfirmed instead of the seeded verified:true."
forbidden_patterns_checked:
  - "a runtime kill switch for the change - REJECTED by the founder (plan Q1, 2026-10-26, 'No switch; rollback = redeploy'): a switch OFF would restore the very defect this OI closes, the changed answers happen only when a pre-existing row is non-active or unreadable, and flipping a secret needs a redeploy anyway, so rollback is a forward-deploy of the saved previous bundle."
  - "fixing only the pre-select arm (design A) - REJECTED in plan review round 1: the 23505 arm and the ON path are reachable without any race whenever the pre-select ERRORS while a non-active row exists, so a one-door fix is the guard-without-its-mirror class."
  - "refusing only on PROOF of a non-active row and keeping d6b736 F2's seeded verified:true when the row cannot be read (design B3) - REJECTED by the founder (plan Q3, 'Accept B2'): it leaves a reachable verified:true after a non-active row under two read failures and contradicts the stated invariant. B2 costs one client retry interval in a three-failure case; no money or entitlement is lost."
  - "answering a 500 on an unreadable row - REJECTED: the client retries 500s and the soft failure (HTTP 200 verified:false) already means 'not yet' to both readers; no new 500 path in a catastrophic handler."
  - "an inline per-door status check - REJECTED: ONE pure function (replayVerdict) decides at every door so a future arm cannot diverge; strict equality (null, empty string, ACTIVE-cased and any future value fail closed)."
proposed_fix: >-
  Add `replayVerdict(row, readFailed)` (ok only for a row read as exactly "active"; not_active for any other status;
  unconfirmed for an absent row or a failed read) and `replayGate(row, readError, paymentId)` (null for ok, else one
  code-only log line and an HTTP 200 `verified:false` soft failure with CORS headers) after the handler. Door 1: the
  pre-select selects `id, end_date, status` and its else arm calls the gate before reading end_date. Door 2: the 23505
  re-read selects `end_date, status`, keeps its error and calls the gate before reading the winner's end date (the
  d6b736 F2 seed still serves the successful-insert path). Door 3: when the rpc answers inserted=false, one extra read
  `select status` keyed on payment id and user id goes through the gate (no extra read when inserted=true). Messages:
  "Subscription for this payment is not active" and "Could not confirm this payment yet; please retry". The stale
  header contract (a never-implemented `{verified:false, status:"pending"}` and a never-implemented 409
  `already_pro`) is replaced by the real outputs. No migration, no client change.
regression_test_planned:
  - "supabase/functions/verify-payment/index_test.ts (real supabase-js client on a fetch-level fake): T0 replayVerdict table (dynamic-import namespace, because index.ts reads its env at module load); T1 door 1 over ten non-active statuses (cancelled, expired, refunded, pending, empty, null, absent key, ACTIVE-cased, a hostile newline value, a 40-character value) for switch OFF and ON, plus a cancelled row with end_date null: HTTP 200 deep-equal soft failure, CORS and content-type headers, nothing written, one code-only log line; T1b door 2 (pre-select ERROR, 23505, re-read non-active); T1c door 3 (ON, out_inserted=false) with a second same-user active row so a user-id-only read would answer unconfirmed; T2 positive controls (an ACTIVE row still verifies at every door); T2d absent and unreadable rows at doors 2 and 3 answer unconfirmed with code=no_code / code=XX000, and T2d' a fetch that THROWS answers the same soft failure (supabase-js returns it in `error`, so no 500); T1b' and T1c' the NO-pre-select-error routes into doors 2 and 3 (a gate nested under a pre-select error would miss them); T2f a FOREIGN-OWNED row for the payment id answers unconfirmed; T2e negative (ON, inserted=true: zero subscriptions reads after the rpc); T3 and T3b the frozen pre-Piece-A handler reproduces the defect at door 1 and door 2; T4 the request shapes. Every soft failure also asserts no console.error line. Thirteen existing tests were affected (ten went red, three went vacuous) and all were repaired, as listed in the plan."
  - "test/contracts/verify_payment_verified_means_active_row_writer_to_reader_test.dart (Gate 9 name = the SoT concept): replayVerdict is the one decision with a single strict === \"active\"; exactly three `const refused = replayGate(` doors; the three reads are keyed on payment id AND user id; the early read stays active-only; exactly two `verified: true` literals; the two soft-failure bodies. Presence only; behaviour is the Deno file."
  - "test/contracts/payment_log_safety_writer_to_reader_test.dart: two new exact-text allowlist entries, `codeToken(rowStatus)` and `pgErrorCode(readError)`."
mutation_proof: >-
  Scratchpad v4/mutate.py (each mutant computed from the file before any write, applied, run against the whole
  verify-payment Deno directory and the two Dart oracles, then restored in `finally` with an equal-sha256 check; the
  script asserted every mutant APPLIED and that the files equal their originals at the end). 31 mutants (24 from the first run, 7 added after the B-pass), 31 killed,
  none by a compile error (every kill had failed > 0 in a run that produced a result line). M0, the handler reverted to
  origin/main, is the red-without-fix proof: 36 Deno tests red (T0 on the missing function; T1/T1b/T1c/T2d on
  behaviour) plus the Dart pin. Per mutant, Deno reds: M1 door 1 removed 23; M2 condition inverted 37; M3 compares to
  cancelled only 21; M4 pre-select without status 27; M5 null treated as active 4; M6 refusal keeps verified:true 27;
  M7 refusal 409 27; M8 refusal carries end_date 26; M9 unconfirmed mapped to ok 5; M10 log carries the raw status 11;
  M11 verdict check on the early read 1 (it reddens only because that select has no status); M12 case-insensitive
  compare 4; M13 refusal nested under end_date 2 (the end_date:null row); M14 door 2 removed 5; M15 door 3 removed 3;
  M16 door 3 keyed on user id only 1 (the second same-user row); M17 door 2 treats an absent row as ok 1; M18 the
  normaliser strips every select 7 (the goldens); M19 CORS and content-type dropped from the refusal 31; M20 door 3
  passes null as the read error 1 (killed only by the code=XX000 assertion, because a null row already yields
  unconfirmed); M21 door 3 read also when inserted 4; M22a door 1 select drops the payment-id filter 17; M22b door 2
  re-read drops it 1 (T4). Added after the B-pass: M23 door 2 gate nested under a pre-select error 2 (T1b', T2f); M24 door 3 gate nested the same way 1 (T1c'); M25 refused log swapped to console.error 29; M26 unconfirmed log swapped to console.error 6; M27 door 2 re-read drops the user_id filter 2 (T2f, T4) plus the Dart pin; M28 a fourth arm added to the answer chain: 0 Deno reds (runtime unchanged), killed by the Dart chain pin only; M29 door 3 ignores a read error 2 (T2d, T2d'). Note (B-pass seat 1): for a real client `data` is null whenever `error` is set, so `readFailed` is redundant with `row == null`; the mutants that only change the error argument (M20, M29) are killed through the code=XX000 log assertion and T0, not through a different HTTP answer. Self-attested.
impact_analysis: >-
  A request whose stored row reads back `active` takes the same requests and gets the same body as before (T2, T2b,
  T2c, the unchanged 23505 race test, the OFF goldens through a normaliser that touches only the pre-select's select).
  Changed answers: (1) a pre-existing non-active row for the payment: HTTP 200 verified:false instead of verified:true;
  (2) a replay whose row cannot be read at doors 2 and 3 (needs a pre-select error AND a second failed or empty read):
  HTTP 200 verified:false "Could not confirm this payment yet; please retry" instead of the seeded verified:true. The
  client treats any answer other than status 200 && verified == true as a soft failure (Phase 2 falls to Phase 3, the
  retry helper returns false), so neither answer writes PRO. EFFECT ON THE USER, stated plainly: the optimistic local
  PRO the payment wrote stays and the in-flight marker stays open for the grace window (about 21m45s,
  payment_timing.dart), during which refreshFromSupabase and verifyFromServer suppress a downgrade; the fix therefore
  DELAYS an honest demotion by up to about 20 minutes for the rare class (an operator-cancelled, still-captured paid
  row inside the confirmation window). It is not a user-visible improvement; its value is the server's verified:true
  contract. No existing user is affected today: the 4 live non-active rows are all in the past.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "index.ts replayVerdict/replayGate and the three doors; the client readers (razorpay_service.dart:915, payment_retry_attempt.dart:82) already gate on verified == true and need no change; analyze whole project 0 errors, 0 warnings" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "subscriptions has pkey, user_id FK and unique_razorpay_payment_id; NO CHECK constraint on status (free text), so the strict === active compare fails closed for any future value (read-only information_schema/pg_constraint read, 2026-10-26)" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "read-only count 2026-10-26: 14 subscriptions rows, active 10 (6 with a payment id), cancelled 3, expired 1, all four non-active rows have a payment id and an end_date in the past, so the defect was latent with no live victim" }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "live verify-payment is v31, verify_jwt true (read-only list_edge_functions on 2026-10-26; docs/audit/payment-hardening.closure.yaml:66 records the same version); the deploy of this fix is a separate per-action founder go after the merge" }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "no live trace: handler-level tests only (fake fetch under the real supabase-js client); the live proof of the refusal is waived by the founder (plan Q2, 2026-10-26)" }
recurrence: >-
  Recurrence of two recorded classes. (a) Guard-without-its-mirror (see the references in classes 2.49, 2.51 and
  2.133 of .claude/skills/debugging/bug-classes.md): the SQL `status = active` guard sat on the early read only; its three sibling arms were added later for
  idempotency and a race (F31/F33 b3f0d9, review d6b736 F1/F2) and copied "return the canonical row's date", not "only
  if it still entitles"; plan review round 1 found the 23505 and ON doors were reachable through a read ERROR, which a
  happy-path census missed. (b) Class 2.49 / diagnose f0b6d8 (a helper's fail-safe direction belongs to the CALLER):
  d6b736 F2's seeded verified:true when the winner row cannot be re-read is a fail-OPEN direction chosen for replay
  convenience, wrong in front of an entitlement answer; the new unconfirmed outcome fails safe. New class 2.135 records
  the replay-door census.
related_bugs:
  - b3f0d9
  - c8f229
  - b5e8d2
  - d1a4f6
  - f5d8c3
  - f0b6d8
---

# verify-payment answered verified:true for a payment whose subscription row was not active

## What was wrong

`verify-payment` has one early read that asks Postgres for the caller's row for this payment with `status = active`
and answers `source: "existing"`. When that misses, three later arms read the SAME row (payment id and user id) with no
status filter and fall to the same final answer, `verified: true, source: "razorpay_api"`: the idempotency pre-select's
`else` arm, the OFF-branch 23505 re-read and the stacking-ON `record_paid_subscription` answer with `inserted = false`.
A cancelled or expired row therefore verified. The 23505 and ON arms needed no race: any transient error on the
pre-select leaves `paymentSubRow` null while a row exists, and the request continues to the insert branch.

## Writer and reader

Writer: the three doors and the helper, now at `verify-payment/index.ts:689`, `:766`, `:779` and `:849`. Readers: the
client's Phase 2 (`razorpay_service.dart:915`) and the retry helper (`payment_retry_attempt.dart:82`), which write PRO
only on `verified == true`. The client's own stated invariant (`razorpay_service.dart:1012-1016`, "a verified:true
reply always means an active subscriptions row exists") was false before this fix.

## The fix

See `proposed_fix`. Plan: `docs/plans/2026-10-26-oi410-verify-payment-non-active-row.md` (its plan-review record, docs/plan-reviews/oi410-verify-nonactive-row.md, lands in the third commit of this branch).

Founder decisions, 2026-10-26, pasted from the plan: Q1 "OI-410 changes the verify-payment function (payment,
catastrophic tier). CLAUDE.md 4.6 asks for a feature flag on payment changes. The plan proposes NO runtime switch ...
Do you ratify no switch?" answered **"No switch; rollback = redeploy (Recommended)"**. Q2 "After the fix is deployed,
how should OI-410 be closed? ..." answered **"Waive the live proof (Recommended)"**. Q3 "Design B2: when verify-payment
cannot read the payment's row at the replay points (the read fails or finds nothing), should it answer a soft failure
('Could not confirm this payment yet; please retry', HTTP 200, verified:false) instead of the old seeded
'verified:true'? ..." answered **"Accept B2 (Recommended)"**. Q4 "How far may I go on OI-410 now? A deploy is never
included ..." answered **"Implement through merge (Recommended)"**.

Rollback: forward-deploy the saved previous bundle (plan, Verification, rollout); no client build is needed. The live
deploy is a separate go and is NOT part of this commit.
