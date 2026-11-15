---
branch: telegram-admin-bot
date: 2026-09-14
blast_radius: catastrophic
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/57b11b5c90cb-review.md
hermes: accepted
hermes_report: docs/audit/2026-09-14-hermes-telegram-admin-bot.md
---

# Plan-review record — Telegram admin bot (read-only, catastrophic)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `catastrophic`, computed from the staged apply set.** Migrations 133-136 all
`CREATE OR REPLACE FUNCTION ... SECURITY DEFINER`, which
`scripts/blast_radius_content_rules_lib.dart` forces to `catastrophic` regardless of path
tier — confirmed live via `git diff --cached --name-only | dart run
scripts/blast_radius_from_diff.dart -` at the time each migration was staged. Catastrophic
requires `hermes: accepted` (`check_plan_review_record_exists.dart`), satisfied below.

## Rounds

**Round 1 — whole-branch review of the initial 12-task implementation, dispatched on the
most capable available model.** 13 findings requiring action (F1 a process finding — an
earlier "resolved" claim in the diagnose-doc that was itself false and had to be
corrected twice — plus F2-F13 code findings: `cmdErrors` blind to failure-shaped
`'event'`-coded rows mirroring migration 087's regex; `sanitizeFindQuery` stripping `.`
and breaking email search; the auth gate untestable without an injectable `sendFn`;
`isAuthorizedTelegramSender` silent on an unset secret/chat-id; the errors cap marker
checking the filtered array's length instead of the raw read's; `/help`'s digest
description misdescribing "today's" digest as "yesterday's"; `cmdRevenue`'s
`fetchAllPages` unbounded). All fixed in commit `bfc1bc11`. B-pass:
`docs/reviews/014866ecac87-review.md` — 2 findings, both fixed, 0 false alarms.

**Round 2 — fresh, context-blind review of the Round-1-hardened branch (most capable
model), per §4.12's requirement that review #2 run on the corrected plan, not the
original.** 16 findings (R2-01 a process finding, fixed directly; R2-02 through R2-16
code/doc findings): the injectable-`sendFn` fix from Round 1 needed
`alert-critical-notify` to gain the same seam (a live network call in its own tests);
both cron-adoption-gate test rosters (`cron_auth_adoption_test.dart`,
`cron_telemetry_adoption_test.dart`) missing `alert-critical-notify`;
`founder_digest_content.ts`'s log lines misattributing the caller across
`founder-digest` and `telegram-admin-bot`; `CRON_REGISTRY.md` and
`SECRET_INVENTORY.md` both stale on this bot's real consumers; and migration 135
(founder_metrics_ops()'s `client_errors_today` inflated by migration 134's own
success-path telemetry writing an `'info'`-coded row on every successful alert dispatch)
— written and tested but held out of the fix commit pending live-apply authorization
per CLAUDE.md §4.3 (plan approval != deploy approval). 14 of the 15 code findings landed
in `46bd3d3f`; migration 135 landed separately in `667ca3ba` after explicit founder
authorization via AskUserQuestion, with live pre/post-apply verification (function-body
diff, privilege checks, a rolled-back-transaction behavioral probe:
`test/sql/founder_metrics_ops_excludes_info_client_errors_live_verify.sql`, executed
result baseline_today=4 → after_info_row=4 (unchanged) → after_real_error_row=5).

**Convergence.** 13 → 15 material findings; Round 2's own corrections (the
`alert-critical-notify` seam, the registry rows) were new material introduced by
Round 1's fixes, not defects surviving from before Round 1 — the expected shape per
§4.12 point 1. No round surfaced a genuinely new mechanism class after Round 2; the
unit did not need splitting.

## Ground truth (verified live, project `dedsavbjuwgarrhphgnl`)

Both migrations 135 and 136 applied live 2026-09-14 after separate explicit founder
authorizations (AskUserQuestion, "Apply now"), each with pre-apply function-body read,
post-apply `has_function_privilege` checks (anon/authenticated → false, service_role →
true) and a `BEGIN...ROLLBACK` behavioral probe against the real table. `founder_metrics_ops()`
live definition confirmed via `pg_get_functiondef` to match the applied file exactly, both
times. `backups/applied_migrations.json` carries both entries with cloud versions
`20260914141301` (135) and `20260914154130` (136).

## B-pass (platform → required)

Three separate B-pass invocations, one per distinct staged apply set, each landed in the
commit it reviews:

- **`docs/reviews/014866ecac87-review.md`** — Round 1's fix diff. 2 findings, 0 false
  alarms, both fixed.
- **`docs/reviews/c0ea56c3d0e5-review.md`** — migration 135. 2 findings (1 P2 accepted as
  a documented tradeoff and filed as OI-200 — the migration file itself is applied and
  immutable per `supabase/migrations/CLAUDE.md`, so the correction lives on the OI board
  and in the diagnose-doc rather than in the file; 1 P3 fixed), 0 false alarms. Carries an
  honest preamble narrating a hash-fixed-point mis-navigation this session hit and
  permanently fixed in `.claude/skills/code-review/SKILL.md` §3 (the gate excludes
  `.claude/skills/code-review/SKILL.md` from the staging hash in addition to
  `docs/reviews/`, since OI-162 slice 4 — the skill's own doc had never been updated to
  say so).
- **`docs/reviews/57b11b5c90cb-review.md`** — migration 136, the FINAL commit on this
  branch (`daee18f8`). **0 findings across all 8 lenses.** The hash was stable on the
  first computation, confirming the SKILL.md fix above held. `bpass_review:` above points
  here — the final diff, per the same "check the live/final state, not a promise" rule
  `docs/plan-reviews/oi153-pro-media-caps.md` records for the same reason.

## Hermes pass (catastrophic → required)

`docs/audit/2026-09-14-hermes-telegram-admin-bot.md` — 8 context-blind Opus lens agents
(L1 writer/reader drift, L14 onConflict live arbiter, L21 Edge Function semantic
correctness, L22 schema-vs-payload parity, L23 auth defense-in-depth on service-role
paths, L31 cron job efficiency, L35 migration reversibility/forward-compat, L40
PII/privacy in telemetry) over the whole hardened branch (32 commits at dispatch time).
**19 findings (0 P0, 0 P1, 4 P2, 8 P3), 7 false_alarm, verdict accepted.** The
highest-severity real findings: F1 (corroborated independently by L1/L22/L35) — migration
135 fixed `client_errors_today`'s inflation from migration 134's own success-path
telemetry but missed the identical bug in the sibling `client_errors_7d` subquery on the
same table — fixed live as migration 136 with founder authorization, verified via
`test/sql/founder_metrics_ops_excludes_info_from_7d_too_live_verify.sql` (baseline_7d=140
→ after_info_row=140 unchanged → after_real_error_row=141, and
today_after_both_rows=5 confirming 135's earlier fix stayed unregressed). F2-F4 (Edge
Function hardening: `alert-critical-notify`'s one remaining raw-error catch replaced with
`telegramErrorSummary()` closing a positional bot-token-leak shape; two smaller
correctness gaps) fixed in `7adb991f`. F5 was a Deno test-file ES-module
import-hoisting trap (a statically-imported `handler` closing over module-scope env-var
consts evaluated before the test's own `Deno.env.set()` calls) worked around via a
cache-busted dynamic `import()`, same class as the existing `ai-media-proxy`
`STORAGE_PREFIX` pitfall documented in `supabase/functions/CLAUDE.md`. The remaining P3s
either landed alongside F1-F5 in `7adb991f`/`daee18f8` or were filed as OI-201
(`alert_cron_function_dead`'s burst-dispatch + Telegram send-failure no-retry gap,
L31-sourced, corroborated against OI-179/OI-199's own precondition notes — confirmed
currently inert by reading `cleanup_cron_call_log()`'s live retention SQL directly rather
than trusting subagent prose: it keeps only the newest `success` row table-wide UNION the
newest row of any status table-wide, two rows total, which is why a sporadic
trigger-dispatched function's success row is pruned by ordinary cron churn long before an
8-day silence threshold could ever observe it).

## What this record does NOT claim

- The deploy state of `telegram-admin-bot`, `alert-critical-notify`, and `founder-digest`
  as Edge Functions: verified live during Task 13 Steps 1-7 (secrets, deploys, webhook
  registration, smoke tests), recorded in the diagnose-doc's `touched_layers_checked`
  field and `backups/edge_function_payloads/`, not restated here.
- Runtime behaviour beyond what the Deno tests, the live SQL probes cited above, and the
  Task 13 smoke tests cover.
- Migration 135's and 136's rollback bodies are inline (commented DDL at file end) per
  the header convention; neither has been exercised, consistent with every other
  migration on this branch.
