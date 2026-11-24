---
hermes_pass_id: 2026-11-24-hermes-oi519-play-billing
ran_at: 2026-11-24T16:10:00+05:30
batch_scope: origin/main...ad057818 (branch oi519-revenuecat-plan, 96 files), plus the plan's live sequence
lens_set: [L1, L2, L21, L22, L23, L29, L40]
agents_dispatched: 4
model_deviation: "Sonnet, one wave of 4, not the skill's Opus default: the founder's standing rule (2026-09-26, 2026-10-07) overrides it."
findings_total: 18
findings_by_severity: { P0: 0, P1: 0, P2: 3, P3: 15, false_alarm: 0 }
verdict: accepted
---

# Hermes Pass — OI-519 Android PRO through Google Play Billing (RevenueCat), +51

Seven lenses in four fresh, context-blind **Sonnet** seats, one wave, after the B-pass fixes (`ad057818`). Sonnet,
not this skill's Opus default, under the founder's standing Sonnet-only rule (the same recorded deviation as the
2026-09-28, 2026-10-20 and 2026-10-21 passes). Seats: (1) L1 + L22, (2) L21 + L29, (3) L2 + L23 as the abuse seat, with
the local docker PostgREST allowed, (4) L40 plus the plan's LIVE SEQUENCE as its subject (the 2026-10-21 lesson). Each
seat read whole functions, not only the diff (the 2026-09-13 lesson), and was told which earlier rounds' findings were
already closed (plan sections 14-27).

## Summary
- 0 P0, 0 P1, 3 P2, 15 P3. 0 false alarms; 2 P3 verified clean (H3-2, H3-3).
- Ship-blockers: none.
- Every finding below is terminal: 16 fixed in this batch, 2 verified clean. One fix (H1-3) changes a live function: it
  ships as a draft SQL file proven locally and is applied at live step L2 with its own founder go (the cron draft's
  precedent); until then the defect stays as live today (minutes-wide, referral-conversion only).

## Findings by lens

### L1 / L22 — writer/reader drift, payload parity (seat 1)
- **H1-1 P3** — `_shared/revenuecat_mirror.ts`: a good customer read with NO avya_pro Play entry leaves an existing
  Play row granting PRO until its end_date (nothing writes it). Fix: critical alert `revenuecat_entry_missing` when a
  Play row is active (`MirrorDb.hasActivePlayRow`); the mirror never revokes on an absence (a wrong revoke takes PRO
  from a payer). Test: `revenuecat_mirror_test.ts` (entry missing / present, active / not).
- **H1-2 P3** — readers the batch had not changed: the admin "expiring" list, the digest expiring counts and the bot's
  `/expiring` listed every auto-renewing Play subscriber each period; the bot's `/subs` counted Play rows as
  monthly/yearly; the digest's "Cancelled (manual)" counted Play refunds. Fix: `_shared/subscription.ts`
  `withoutRenewingPlay` used by all three expiring readers (with `fetchRenewingPlayUserIds`, null = fail); `/subs`
  buckets Play as `google_play`; the manual count excludes Play rows and a separate "Google Play refunds" line reads
  them. Tests: admin, bot, digest and founder-digest suites.
- **H1-3 P3** — migration 182 `upsert_play_subscription`: the start_date rule keyed on `status = 'active'` alone, so a
  row not re-read since it ended kept the OLD chain's start_date on a resubscribe in that gap
  (`process_referral_conversions` keys on start_date). Fix (final form after the B-pass, see the addendum): keep the
  start only when the new period begins by the old end, `excluded.start_date <= s.end_date`, as
  `docs/plans/2026-11-24-revenuecat-upsert-start-date.migration-draft.sql` (CREATE OR REPLACE, same signature, ACL
  self-check), applied at L2 with its own go. Proof: `test/sql/play_upsert_start_date_local.sh` (182 alone keeps the
  stale start, the defect; 182 + draft does not; a really running renewal keeps its start on both; C4-C6 add a late
  renewal and the exact-end boundary).
- **H1-4 P3** — `ai_snapshot_builder.dart`: `expires_at` / `plan` read from the raw configBox next to a MigratedKey
  `auto_renew`, so with a session open they came back null. Fix: all three through `SubscriptionService` getters.
  Test: `test/ai_coach/snapshot_keys_test.dart` (values in the per-user box).

### L21 / L29 — function semantics, rate limits (seat 2)
- **H2-1 P2** — RESTORE during a `revenuecat-sync` 429 or 503 (verify false) told a payer "No active PRO found".
  Fix: `PlaySyncAnswer.unavailable` (408, 5xx, network) and `PlayConfirmResult {pro, notPro, couldNotCheck}`; a failed
  or refused LAST check is couldNotCheck -> "Couldn't check your PRO right now" (after a purchase: the slow line).
  Tests: `paywall_play_body_behavioral_test.dart` (pure loop table + two widget cases).
- **H2-2 P3** — no log line when the sync quota is exhausted. Fix: `console.warn` with the request id only.
- **H2-3 P3** — a reconcile run with 199 of 200 failed reads recorded `success`. Fix: failed when `failed > mirrored`.
- **H2-4 P3** — the cron draft's `net.http_post` had pg_net's 5 s default timeout. Fix: `timeout_milliseconds :=
  120000` (signature checked on the local supabase/postgres image, pg_net 0.20.0).
- **H2-5 P3** — the webhook read the whole body before its 64 KB check; a TRANSFER's uid list was uncapped. Fix:
  `readBounded` (stops at 64 KB + 1) and `MAX_UIDS_PER_EVENT = 5` with an alert when cut.
- **H2-6 P3** — the mirror retried a RevenueCat 429 at once. Fix: wait `Retry-After` (bounded 2 s; default 500 ms).

### L2 / L23 — RLS, grants, service-role authz; abuse (seat 3)
- **H3-1 P3** — SANDBOX (license tester) Play rows counted as Play subscribers in the admin dashboard; the same in
  the digest and the bot (twins). Fix: PRODUCTION only; testers shown apart as "not paid" (`play_sandbox_active`,
  admin tile "Play testers", digest and bot lines).
- **H3-2 P3** — the webhook body names uids to re-read. verified_clean: the mirror never writes body fields, re-GETs
  the customer, and the event needs the shared secret; worst case is extra reads (now capped, H2-5).
- **H3-3 P3** — 182's ACL self-check does not re-run on a later CREATE OR REPLACE. verified_clean: Postgres keeps a
  function's ACL across CREATE OR REPLACE; the H1-3 draft carries its own self-check.
- No cross-user path found: sync's uid is the JWT's only; delete-account's uid is the JWT's; reconcile reads uids from
  the database; SECURITY DEFINER functions are service_role-only with search_path pinned.

### L40 + the live sequence (seat 4)
- **H4-1 P2** — a webhook answered while the switch was OFF (200, ledger `switch_off`) was never mirrored after ON:
  the reconcile re-read only users who already had a Play row. Fix: the reconcile adds every user whose latest
  `switch_off` event in 7 days is newer than their last Play read (`switchOffCatchUpUids`, newest first). Tests:
  reconcile unit table + the real-PostgREST harness (`revenuecat_reconcile_postgrest_local.sh`, user d007).
- **H4-2 P2** — a later deploy of delete-account / verify-subscription / expiry-reminder from a tree before this merge
  silently drops the Play handling (delete-account would stop cancelling Play, with no alert). Fix: plan section 10
  deploy precondition (all 10 functions only from merged `main`, `git diff HEAD origin/main -- supabase/functions`
  empty, version and payload checks after each deploy; the same for every later deploy).
- **H4-3 P3** — the test event proves the webhook auth only, not `REVENUECAT_SECRET_KEY`. Fix: plan section 10 says
  so; the sandbox `revenuecat-sync` GET is the only gate for the secret.
- **H4-4 P3** — an unknown product id from RevenueCat's body went unbounded into `alerts.context_json`. Fix:
  `plainBounded(productId, 64)` (B-pass A4: no JSON quotes). The deleted user's id kept in the delete alert is documented as the handle for the
  hand cancel (payment.md).
- **H4-5 P3** — a cancel's CANCELLATION webhook, landing between the delete leg and the auth delete, re-GETs the
  customer and RevenueCat re-creates it after the DPDP delete. Fix: the leg is split; cancels run before the auth
  delete, the customer DELETE after it (`deletePlayCustomer`, section 6b), when the mirror already refuses the uid.
  Tests: `revenuecat_leg_test.ts` (step 1 never DELETEs; the order pin in index.ts).

## Verification
- Deno (final tree, after the addendum's fixes): webhook 18, sync 11, reconcile 23, delete-account 17, admin 26,
  bot 54, verify-subscription 3, redeem-referral 12, founder-digest 69, `_shared` 1013 (2 need `--allow-run`, green
  with `-A`).
- Local docker: the PostgREST harness ALL PASSED (with the catch-up cases); the start_date proof ALL PASSED.
- Flutter: whole-project analyze with no warning; targeted tests green (the log-safety contract classifies the new
  `pgErrorCode(e)` line).
- Mutants on the fixes: see the plan's section 28 (each applied, run, restored).

## Founder triage
Accepted by the coordinator under the standing instruction (fix every finding in the batch, no deferrals). Founder
decisions still pending are live steps only (L2 deploy, the two draft SQL applies, switch ON, the +51 build).

## Action items
- [x] H1-1 .. H1-4, H2-1 .. H2-6, H3-1, H4-1 .. H4-5 — fixed in this batch (H1-3 as a locally proven draft, applied
  at L2 with its own go).
- [x] H3-2, H3-3 — verified_clean (reasons above).

## Self-evolution
- Lens signal: L1 4/4, L21/L29 6/6, L2/L23 1/3 (2 verified clean, 0 exploitable), L40 + live 5/5.
- The live-sequence seat again found the two process P2s (switch-OFF catch-up, deploy from an old tree): give a seat the
  runbook whenever a batch ends in live steps (third instance after 2026-10-21 and 2026-10-25).
- A "gone" or "already owned" answer from a store is a guard with a mirror (paused / held subscription, own purchase
  still confirming): read only the documented code as terminal, and check this account first.

## Addendum — B-pass rounds on the hermes fixes (2026-11-24)
Full tables: plan section 28. Round 1, two fresh Sonnet seats: seat A (server) 5 P3, seat B (client + SQL draft) 3 P2
+ 1 P3; 8 fixed, 1 accepted (A5, the failed-run rule is noisier by design). The P2s: "already owned" read a failed check
as another account (B1), store PRO + a failed verify read as "no PRO found" (B2), and the draft's
`status + end_date > now()` rule restarted a chain whose renewal was read late (B3, now
`excluded.start_date <= s.end_date`). One more found by the coordinator while fixing B2: with the mirror switch OFF,
`revenuecat-sync` now answers `store_checked: false`, read as "could not check". Mutants R1-R11, all red.

Round 2, one fresh Sonnet seat on the fix diff: 1 conditional P2 (the paged catch-up read could fail the whole run;
now best effort, falls back to the regular candidates), 2 P3 (the exact-end boundary, now `<=` with harness case C6;
catch-up starvation, accepted: 7 days, 50 a run, RESTORE heals). Both fixes mutated red. Converged: no P0/P1 in either
round.
