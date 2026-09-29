---
bug_id: c7e3b9
date: 2026-09-29
batch: oi-182-202-subscription-state
status: fixed
blast_radius: catastrophic
symptom: |
  OI-202. users.subscription_status never reconciles back to 'free' after a
  subscription expires, and users.subscription_expires_at is only ever written
  forward. Live (2026-09-29, project dedsavbjuwgarrhphgnl): 38 users, 8 carry
  subscription_status='pro', but only 5 have a live active subscription; 2 are
  lapsed rows that still read 'pro', and 1 (4d27a40b, expiry 2026-06-22) has ZERO
  subscription rows -- an orphan the mirror alone remembers. The stale value fed
  founder_metrics() (and through it the admin dashboard, the daily admin metrics
  cron, the founder digest and the Telegram admin bot) and, historically,
  morning-alert's PRO copy (a7d2e9). Two canonical answers to "is this user PRO"
  disagreed by up to 6 users.
concept: subscription_expiry_derived
sot_registry_entry: subscription_expiry_derived
writers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: "users.update mirror write REMOVED; the subscriptions insert is the only entitlement write", line: 555 }
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: "users.update mirror write REMOVED; response reports the canonical row's end_date", line: 620 }
  - { file: supabase/functions/_shared/subscription.ts, method_or_widget: "fetchLatestActiveEndByUser + reduceLatestEndByUser + usersWithLatestEndIn -- the derived replacement", line: 236 }
readers:
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: "gatherDigestInput expiringSoon / lapsedYesterday -- one shared latest-end read, two sections", line: 920 }
  - { file: supabase/functions/telegram-admin-bot/index.ts, method_or_widget: "cmdExpiring -- throws on a failed read instead of printing zero", line: 283 }
  - { file: supabase/functions/admin-dashboard-data/index.ts, method_or_widget: "loadExpiryRows -- latest end in [now-30d, now+30d] plus users.email", line: 103 }
hive_key_prefix: n/a
hive_key_formula: "n/a -- server-only; the Flutter client never read the mirror columns (git grep lib/ finds only the admin response key subscription_expires_at)"
sync_methods: []
restore_methods: []
cloud_table: "users (two columns dropped), subscriptions (the source, unchanged)"
cloud_columns:
  - subscription_status
  - subscription_expires_at
  - end_date
  - status
contract_test_path: test/contracts/subscription_columns_dropped_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a -- service-role Edge Functions and one SECURITY DEFINER SQL function; no per-user client state."
forbidden_patterns_checked:
  - { pattern: "any shipped file naming users.subscription_status / users.subscription_expires_at (comments stripped; two exact-snippet allowances for the admin RESPONSE key)", absent: true }
  - { pattern: "a failed subscriptions read rendered as an empty map / zero count", absent: true }
proposed_fix: |
  Founder-approved 2026-09-29: derive-and-drop, rejecting the smaller
  reconciler-cron alternative. The single PRO definition stays in
  _shared/subscription.ts (status='active' AND end_date > now()); no new DB
  object. Steps, in live order:
  1. Code: fetchLatestActiveEndByUser (paged, pinned floor, null on failure) and
     two pure reducers; founder digest, telegram-admin-bot and
     admin-dashboard-data migrate to it; razorpay-webhook and verify-payment stop
     writing the mirror; telegram-bot/bot.py is_pro() queries subscriptions;
     seed_qa.sql and the e2e doc stop naming the columns.
  2. Migration 152 (one transaction, lock_timeout 5 s, all statements
     idempotent): CREATE OR REPLACE private.founder_metrics() first (byte-for-byte
     RETURNS TABLE, explicit search_path, REVOKE/GRANT re-issued) so DROP COLUMN
     cannot silently break it; then DROP TRIGGER trg_subscription_update_user,
     DROP FUNCTION update_user_subscription_status() and extend_subscription(uuid,
     integer) (zero callers, service_role only), DROP COLUMN x2, NOTIFY pgrst.
     Inline rollback block at file end.
  3. Order matters: the razorpay-webhook returns 500 when its users.update fails,
     so the six Edge Functions (razorpay-webhook, verify-payment, founder-digest,
     telegram-admin-bot, admin-dashboard-data, expiry-reminder) deploy BEFORE the
     column drop.
  founder_metrics() after the rewrite (predicted from live data, to be confirmed
  post-apply): 38 total / pro_active 5 / pro_expired 2 / free 31, with
  total = pro_active + pro_expired + free preserved. pro_active does not move.
  Definitions (B-pass finding 1 made the draft match the plan): pro_active = a
  live active row; pro_expired = at least one subscriptions row of ANY status
  and NO live active row (cancelled/expired rows are the win-back population);
  free_users = total - pro_active - pro_expired = never subscribed. The live
  numbers are identical under a status='active'-only reading, so neither the
  dry-run nor the smoke test could tell the two apart until the first
  cancellation -- the migration-text test therefore pins the status set.
regression_test_planned: |
  Deno: supabase/functions/_shared/subscription_test.ts (11, filter-evaluating
  fake with a server row cap; multi-active-user reducer fixtures; null-not-empty
  on error), founder-digest/index_test.ts (+3), telegram-admin-bot/index_test.ts
  (+2, one message-pinned), admin-dashboard-data/index_test.ts (+5).
  Dart: test/contracts/subscription_columns_dropped_test.dart (source scan with
  an exact-snippet allowance and positive controls), flipped
  pro_predicate_adoption_test.dart (exemption removed; each read pattern now has
  its OWN positive control), repointed audit_2026_06_07_batch6_server_test.dart,
  referral_trial_subscription_grant_test.dart and the live SQL scripts
  (onconflict_live_arbiter case 28, security_definer_anon_revoke guarded with
  to_regprocedure).

  Mutation-proven 2026-09-29 (Part B, applied by single-match replace, none a
  compile error): B1 reducer keeps first-seen: 4 reds. B2 string compare: 1.
  B3 no status filter: 1. B4 no floor: 1. B5 empty map on error: 2. B6 closed
  range: 1. B7 digest 7d uses 30d: 1. B8 digest floor tStart: 1. B9 digest null
  becomes zero: 1. B10 bot null guard removed: ZERO reds at first -- the
  TypeError from iterating null throws anyway, so a bare assertRejects could not
  tell the guard from an accident; the assertion now pins the message and the
  mutation reddens 1. B10b bot null coalesced to zero: 1. B11 admin null -> []: 1.
  B12 admin drops emails: 1. B13 bot selects the dropped column: 1. B14/B15
  webhook and verify-payment re-add a mirror write: 1 and 2. B16 bot.py reads the
  mirror: 1. B17 seed writes the mirror: 1. B18 a broken .eq read pattern in
  pro_predicate_adoption_test: ZERO reds at first (the positive control was
  satisfied by the === pattern alone); fixed with per-pattern controls, then 1 red.
  B-pass finding 3 (the per-consumer boundary flags were unpinned: five
  mutations survived) closed with boundary fixtures; re-proven: D1 digest lapsed
  made inclusive: 1 red. D2 digest 7d exclusive: 1. D3 bot 7d exclusive: 1.
  D4 admin window exclusive: 1. (Two survivors were judged equivalent, not
  covered: cmdExpiring's floor -> epoch is harmless because of the final >= now
  filter, and admin's null-guard is backed by the outer try/catch returning 500.)
hermes_findings_closed: |
  Hermes pass 2026-09-29 (report docs/audit/2026-09-29-hermes-oi-182-202-subscription-state.md).
  L21 razorpay-webhook: a 23505 on the subscriptions insert fell through to
  redeemPromo and could double-redeem; now `alreadyProcessed = true` on 23505
  (pinned, presence-only, in razorpay_webhook_promo_double_burn_guard_test.dart).
  L23/L1 founder_metrics + reducers: fetchLatestActiveEndByUser got maxPages 200
  and a >=5000-row console.warn canary; expiry-reminder (a sixth reader of the
  dropped-column era logic, missed by the first inventory) now uses the latest-end
  reduction with a null-throws guard (test/contracts/expiry_reminder_latest_end_test.dart);
  /user in telegram-admin-bot renders `free (<plan> lapsed <date>)` for an
  active-status row whose end_date has passed. L29 rate-limit matrix: see the OI-182
  diagnose f2a6d1 "Server quota budget". L22 schema-vs-payload parity: clean in the
  repo (954 refs, RETURNS TABLE parity proven in a throwaway local Postgres);
  one PARTIAL below.
hermes_l35_closed: |
  F1 (P1): the plan now requires Commit 1 to be merged to origin/main with CI green
  BEFORE the dry-run, the EF deploys and the apply, and the git-grep precheck on
  origin/main before the apply (plan step 1b). F3: lock bound is SET/RESET
  lock_timeout, pinned in the Commit-2 migration-text test. F4: rollback now restores
  the orphan from the snapshot and carries no BEGIN/COMMIT. F2 is the deployed-bot
  item below.
blocked_on_user_items: |
  1. The deployed Telegram coach bot: NOT DEPLOYED as of 2026-09-29 (founder: the feature is
     hidden; OI-227 records the connect entry points removed 2026-09-21). Nothing reaches a VPS
     bot, so the drop cannot break it. The in-repo telegram-bot/bot.py is patched anyway
     (is_pro queries subscriptions, fail-safe False) so a future deploy starts correct. Terminal:
     verified by the founder's statement plus OI-227; not independently checkable from this host.
  2. Pre-existing and out of this batch's scope: bot.py receive_email links a chat to any account
     from an unverified typed email (P2, dormant while the bot is off). Recorded on OI-227 as a
     phase-2 constraint (the linking-token handshake replaces the email prompt); no new OI.
  3. The pre-152 admin_metrics_daily history keeps the old pro_expired/free
     definition, so the trend has a one-day step at the apply.
impact_analysis: |
  Who is affected: the founder-facing surfaces (admin dashboard expiry tab, daily
  admin metrics snapshot, founder digest, Telegram /expiring and /user) and the
  Telegram AI-coach bot's PRO check. No end-user surface reads the columns (the
  Flutter client derives from subscriptions), so no client release is needed.
  Behaviour change: expiring / lapsed counts now follow each user's LATEST active
  row, so a renewed user no longer appears as lapsed. Orphan data: user 4d27a40b
  (mirror 'pro', expiry 2026-06-22, zero subscription rows) loses that value on
  drop; it is preserved in backups/subscription_mirror_columns_snapshot_2026-09-29.json
  along with the other seven rows.
  Blast radius is catastrophic by path glob (razorpay-webhook, verify-payment,
  admin-*) and by content (SECURITY DEFINER rewrite), so a Hermes pass is
  mandatory. Live steps (dry-run, six EF deploys, the apply) each need the
  founder's explicit go and are recorded below as they happen.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "git grep over lib/ finds no read or write of either column; the only hit is the admin RESPONSE key subscription_expires_at in admin_dashboard_data.dart, kept so no client release is needed. Whole-tree flutter analyze clean." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Server-only concern." }
  - { tier: 3, name: "Postgres schema", status: blocked_on_user, evidence: "Migration 152 drafted (kept outside the repo tree until applied, so Gate 14 and the applied-migrations parity test never see an unapplied file). Requires the founder's explicit go for the dry-run and for the apply; to be re-marked fixed_in_this_batch with information_schema evidence after the apply." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Live 2026-09-29 read-only: 8 users with a non-default mirror, 5 with a live active subscription, 2 lapsed with rows, 1 orphan with zero rows. Snapshot of all 8 written to backups/subscription_mirror_columns_snapshot_2026-09-29.json before any DDL." }
  - { tier: 5, name: "Migrations applied", status: blocked_on_user, evidence: "backups/applied_migrations.json gets the 152 entry (real cloud_version, sha256) in the SAME commit as the SQL file, after the live apply. Not yet applied." }
  - { tier: 6, name: "Edge Function code vs deploy", status: blocked_on_user, evidence: "Six deploys pending the founder's go, before the column drop: razorpay-webhook v25 (verify_jwt false), verify-payment v21 (true), founder-digest v8 (false), telegram-admin-bot v5 (false), admin-dashboard-data v6 (true), expiry-reminder (verify_jwt and live version to be read live immediately before the deploy). deno check of the whole functions tree is clean; the full deno test run is 743 passed with 2 failures that are the known VPS :8000 AddrInUse bind in two untouched files (future-prediction, re-engagement)." }
  - { tier: 7, name: "Cron jobs", status: verified, evidence: "compute-admin-metrics-daily (cron 30) and the founder digest (cron 38) read founder_metrics_for_admin_api() -> private.founder_metrics(); both are covered by the rewrite and by the post-apply smoke test." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "An all-schema pg_proc scan found exactly three functions referencing the columns (update_user_subscription_status, extend_subscription, private.founder_metrics); no policy, view, index, cron command or publication references them." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Traced checkout -> razorpay-webhook / verify-payment -> subscriptions insert -> derived readers; the webhook's 500-on-failed-users-update is the reason EF deploy precedes the drop." }
recurrence: a7d2e9 (2026-07-26, docs/diagnoses/2026-07-26-morning-alert-pro-from-stale-column-a7d2e9.md -- the same stale-mirror class, fixed at the consumption layer only)
related_bugs: [a7d2e9, 9c4f2e, 7ad0c1, a1c9f4, e3b9d7]
---

# A denormalized entitlement mirror that nothing reconciled, dropped instead of patched

## Summary

`users.subscription_status` and `users.subscription_expires_at` were written by
three paths (the `trg_subscription_update_user` trigger, razorpay-webhook,
verify-payment) and unset by none. The 2026-07-26 fix moved PRO decisions onto
the `subscriptions` predicate but left the mirror in place "as a cache for the
admin dashboard", and left `private.founder_metrics()` reading it. A cache whose
only remaining readers are the founder's own dashboards is exactly the surface
where a wrong number is believed, so the durable fix is to remove it rather than
reconcile it.

## What the plan reviews caught

A schema-scoped dependency query (schema `public` only) missed
`private.founder_metrics()`, which is why the migration rewrites that function
first: `DROP COLUMN` succeeds silently on a function body and only breaks at
call time. Two later corrections each introduced a defect the next round caught
(a no-op last retry in the OI-182 half, and a `BEGIN ... ROLLBACK` dry-run that
would hold a lock). The dry-run is therefore a single `DO` block that always
raises. Three rounds ran; no fourth.
