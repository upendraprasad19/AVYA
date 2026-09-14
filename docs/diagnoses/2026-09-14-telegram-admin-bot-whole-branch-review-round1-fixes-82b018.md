---
bug_id: 82b018
date: 2026-09-14
batch: telegram-admin-bot whole-branch review round 1 fix response
status: fixed
blast_radius: catastrophic
symptom: |
  Whole-branch review round 1 (context-blind, most-capable-model, live-state
  verified) of the telegram-admin-bot branch found 13 findings (F1-F13). This
  doc covers the code-level fixes for F2-F13 (F1 is a process finding about
  the merge itself — no plan-review record existed — tracked separately, not
  a code defect). Three were real bugs already live in production:
  - F2: HELP_TEXT and two Usage strings contained raw "<text>"/"<email-or-id>"
    placeholders, sent with parse_mode:"HTML" — Telegram's HTML parser
    rejects unsupported tags with a 400, so /help (and /find, /user with no
    args) silently failed to send since first deploy.
  - F3: /user threw PGRST116 for any user with >1 active subscription row
    (a real live user has exactly this shape from a renewal overlap).
  - F4: /cron's `.limit(200)` on started_at desc silently dropped the
    STALEST (most important) jobs once they aged out of the recency window
    — live evidence showed 3 genuinely-silent functions missing entirely.
  The remaining findings (F5-F13) were robustness/correctness/security
  hardening found before wider use: alerts/find pagination hid a real
  total, /errors had a fake 2000-row bound (PostgREST caps at 1000
  silently), /find had a PostgREST filter-injection shape via commas, /subs
  silently dropped the "today" half of its own documented contract,
  _shared/telegram.ts's header falsely claimed founder-digest as a caller,
  /expiring's source-of-truth choice was undocumented, the webhook secret
  comparison was not constant-time, a dead variable, and a selected-but-
  never-rendered timestamp on critical alerts.
concept: telegram_admin_bot_command_correctness
sot_registry_entry: |
  Not applicable — this batch's Global Constraints explicitly state no new
  SoT registry entries are needed (read-only reporting over existing
  writer/reader contracts, not a new one).
writers:
  - { file: supabase/functions/telegram-admin-bot/index.ts, method_or_widget: cmdSubs/cmdAlerts/cmdFind/cmdCron/cmdErrors/cmdUser, line: various }
  - { file: supabase/functions/alert-critical-notify/index.ts, method_or_widget: formatCriticalAlertText, line: 27 }
readers:
  - { file: supabase/functions/_shared/telegram.ts, method_or_widget: sendTelegram, line: 34 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: subscriptions, alerts, client_errors, cron_call_log, users
cloud_columns:
  - subscriptions.end_date
  - subscriptions.status
  - alerts.detected_at
  - cron_call_log.started_at
  - cron_call_log.function_name
contract_test_path: supabase/functions/telegram-admin-bot/index_test.ts
ist_handling:
  - "cmdSubs buckets today/yesterday off istYesterdayWindow()'s tStart boundary, inclusive on the today side (>=)."
provider_invalidations: []
telemetry_op_types: {}
cross_account_guard: "Not applicable — founder-only, dual-authed (webhook secret + chat-id allowlist) admin surface, no per-user account context."
forbidden_patterns_checked:
  - { pattern: "raw HTML placeholder text sent with parse_mode:HTML", absent: true }
  - { pattern: "unbounded PostgREST read with no explicit cap or overflow signal", absent: true }
proposed_fix: |
  Twelve targeted fixes in supabase/functions/telegram-admin-bot/index.ts,
  supabase/functions/alert-critical-notify/index.ts, and
  supabase/functions/_shared/{telegram.ts,cron_auth.ts} — see the review
  findings (F2-F13) and this commit's body for the one-line summary of each.
regression_test_planned:
  - supabase/functions/telegram-admin-bot/index_test.ts
  - supabase/functions/alert-critical-notify/index_test.ts
impact_analysis: |
  Three real production bugs fixed (F2 /help silently broken since deploy,
  F3 /user throws for a real live user, F4 /cron hides genuinely-stale
  jobs). Remaining fixes are hardening found before wider use — no
  regression in existing correct behavior; every existing test either
  passed unchanged or was updated to match a corrected query-chain shape
  (documented per-fix in code comments). Requires a redeploy of both
  telegram-admin-bot and alert-critical-notify (already live at v1/v1 from
  the pre-review deploy) to take effect in prod.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "Server-side Edge Functions only; no Flutter client touched." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "cron_call_log 7-day retention (always spares each function's latest row) confirmed via migrations/109_cron_silence_alert_and_log_cleanup.sql before choosing the 7-day .gte() window for F4." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check clean on all touched files; deno test 374/374 across telegram-admin-bot, alert-critical-notify, founder-digest, _shared. Redeploy owed as part of Task 13's operational rollout (v2 of both functions)." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Telegram's HTML parse_mode tag allowlist confirmed against api.telegram.org docs; F2's fix (bracket placeholders instead of angle brackets) verified via a new exhaustive tag-sweep test (assertOnlySupportedTelegramTags) over HELP_TEXT and every static Usage string." }
---

## Summary

Whole-branch review round 1 of `telegram-admin-bot` (dispatched on the most
capable model, context-blind, live-state-verified — per the SDD skill's
final-review process) found 13 findings. This is the fix-response commit
for the 12 code-level ones (F2-F13); F1 (no plan-review record for the
branch, which is catastrophic tier) is a process finding tracked and
resolved separately via `docs/plan-reviews/telegram-admin-bot.md`.

## Root cause

No single root cause — this is a review-response batch. The three P1s
share a common shape: each assumed a simplifying invariant (a static help
string never needs escaping like DB-sourced fields; a user has at most one
active subscription; a recency-limited window is equivalent to "the latest
row per function") that held in the author's mental model but not against
either Telegram's real parser or live production data.

## Fix

Per finding, verified against live state before writing any code (not
trusted from the review's prose, per this repo's own
`feedback_pg_trigger_exception_column_drift.md` lesson from earlier in
this same batch):

- **F2**: `<text>`/`<email-or-id>` → `[text]`/`[email-or-id]` in HELP_TEXT
  and both Usage strings. New test sweeps every static string for any
  Telegram-unsupported HTML tag.
- **F3**: `/user`'s subscription lookup: `.maybeSingle()` →
  `.order("end_date", {ascending:false}).limit(1)`, reading `data?.[0]`.
- **F4**: `/cron`: `.limit(200)` (row-count, silently drops stale jobs) →
  `.gte("started_at", sevenDaysAgoIso)` (time-window, matches
  `cleanup_cron_call_log()`'s 7-day retention which always spares each
  function's latest row regardless of age).
- **F5**: `/alerts` and `/find` both gained `{count:"exact"}` + an
  "… +N more" overflow line, mirroring the digest's already-fixed pattern.
- **F6**: `/errors`'s fake `.limit(2000)` → real `.limit(1000)` (PostgREST's
  actual cap) + an explicit "capped at 1000" marker when hit.
- **F7**: new `sanitizeFindQuery()` strips PostgREST `or=` structural
  characters (`,.()`) and the function's own wildcard characters (`%*\`)
  from user input before interpolation.
- **F8**: `/subs` now buckets one `.gte(yStart)` read (no upper bound) into
  Today/Yesterday client-side, closing the gap between the spec/help-text/
  test-title (all said "today/yesterday") and the code (yesterday only).
- **F9**: `_shared/telegram.ts`'s header corrected — `founder-digest` does
  NOT import this module's sender (it keeps its own for a real reason: the
  shared truncator is a raw slice, and the digest needs line-boundary-aware
  truncation or Telegram 400s the whole message). Documented as a
  deliberate divergence, not an unfinished extraction, with an explicit
  warning against "finishing" it naively.
- **F10**: one-line comment on `/expiring` documenting its deliberate
  `users.subscription_expires_at` source-of-truth choice (mirrors the
  digest's own `expiringSoon`) and the drift risk against the Global
  Constraint that `subscriptions` is authoritative elsewhere.
- **F11**: webhook secret comparison now goes through
  `_shared/cron_auth.ts`'s constant-time `timingSafeEqual` (newly exported)
  instead of a bare `!==` — this is the only gate on a publicly-reachable
  endpoint, same threat model as the 16+ cron-secret-gated functions that
  helper was written for.
- **F12**: dead `todayStart` variable removed as part of F8's rewrite.
- **F13**: `alert-critical-notify`'s critical-alert message now renders
  `detected_at` as an IST clock time (was selected and typed but never
  rendered).

## Pre-commit gate follow-up (mechanical, same commit)

Attempting to commit surfaced a THIRD wave: `check_unbounded_cron_reads.dart`
failed with 5 violations. It scans any function importing
`_shared/cron_auth.ts` — F11's fix (exporting `timingSafeEqual` for the
webhook-secret comparison) pulled `telegram-admin-bot` into that scan
roster for the FIRST time, retroactively exposing pre-existing gaps the
gate had never been able to see:

- **4 false positives**: `cmdSubs`/`cmdFind`/`cmdAlerts`/`cmdErrors`'s
  `.limit()` calls already used named constants (`SUBS_QUERY_CAP` etc.) —
  functionally bounded, but the gate's regex requires a LITERAL digit
  (`founder_digest_content.ts` documents this convention explicitly: "only
  `.limit(<digits>)` so it can verify the bound is <= 1000"). Fixed by
  passing the literal digit directly to `.limit()`, with a comment tying it
  to the named constant used elsewhere in each function for readability.
- **1 real pre-existing gap**: `cmdRevenue`'s subscription read had NO
  bound at all — genuinely invisible until this same F11 fix widened the
  gate's roster. A hard cap would be the WRONG fix here (it would silently
  undercount MRR on a real business past the cap, unlike every other
  command's page+total shape which correctly caps a DISPLAY list). Routed
  through `fetchAllPages` (`_shared/paged_fetch.ts`), mirroring
  `_shared/subscription.ts`'s own `subscriptions` read pattern exactly
  (`orderBy: "id"`).

## B-pass follow-up (same commit, catastrophic tier — touches `_shared/cron_auth.ts`)

A required B-pass (`docs/reviews/8804b0235504-review.md`) on this staged
diff found one P2 and one P3, both accepted and fixed in this same commit:

- **P2**: `cmdCron`'s new comment claimed `cleanup_cron_call_log()`
  (migration 109) "always spares each function's most recent row" — false;
  it spares exactly ONE row globally (the single latest `status='success'`
  row table-wide), not one per function. Comment corrected in both the
  source and its mirroring test comment. The deeper fix (widening the
  retention function's exemption to per-`function_name`) is separate,
  pre-existing production infrastructure — filed as **OI-199**, not folded
  into this diff.
- **P3**: `cmdSubs` had no upper bound at all, unlike `cmdErrors`'s
  already-explicit cap+marker pattern — added `SUBS_QUERY_CAP` (1000,
  matching PostgREST's real `db-max-rows`) + the same honest marker.

## Verification

- `deno check --node-modules-dir=none` clean on every touched file.
- `deno test` 375/375 across `telegram-admin-bot`, `alert-critical-notify`,
  `founder-digest`, `_shared` (was 363 before this batch's new tests).
- `check_unbounded_cron_reads.dart` clean (44 files scanned, 0 violations,
  3 pre-existing unrelated waivers untouched).
- Mutation-proven (rule 21): F2, F3, F4, F5, F6, F7, F8, F13, the B-pass's
  `cmdSubs` cap marker, and `cmdRevenue`'s `fetchAllPages` routing each had
  their new/extended test's protection deliberately neutered once and
  confirmed to redden exactly the intended test(s), then reverted. F11 is not behaviorally
  mutation-observable by design (a constant-time compare must produce
  identical true/false outcomes to a naive one — only the timing
  side-channel differs, which no functional assertion can see); verified
  instead via `deno check` + the existing auth tests staying green. F9,
  F10, F12, and the B-pass's comment correction are
  documentation/dead-code changes with no new behavioral assertion to
  mutate.

## Related bugs

Same batch, same branch: `docs/diagnoses/2026-09-14-critical-alert-trigger-missing-telemetry-d70421.md`
(migration 134) — a different reviewer-found gap in the same feature,
fixed earlier in this session. `feedback_green_check_input_set_width.md`
is the general class F4 belongs to (a row-count window silently narrowing
what a check can see); this is a new instance of it, not yet added there
since the mechanism (recency window vs retention window) is specific
enough to warrant its own note if it recurs a third time.
