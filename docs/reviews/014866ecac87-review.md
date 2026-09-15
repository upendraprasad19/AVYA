---
reviewed_at: 2026-09-14T00:00:00+05:30
staged_against: 014866ecac87
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 2
verdict: accepted
---

# Code Review — 014866ecac87

Staged diff: `supabase/functions/telegram-admin-bot/{index.ts,index_test.ts}`,
`supabase/functions/alert-critical-notify/{index.ts,index_test.ts}`,
`supabase/functions/_shared/telegram.ts` (header only),
`supabase/functions/_shared/cron_auth.ts` (exports a previously-private
`timingSafeEqual`, catastrophic by path per `docs/blast_radius.yaml`).
This is the fix-response commit for whole-branch review round 1's findings
F2-F13 (F1 is a process finding, tracked separately).

## Finding 1 — P2 — asserted_fixture_value / guard_without_its_mirror
- **file:line:** `supabase/functions/telegram-admin-bot/index.ts:446-451` (comment above `cmdCron`)
- **claim:** the comment justifying the F4 fix (`.limit(200)` → `.gte()` 7-day
  window) asserted `cleanup_cron_call_log()` (migration 109) "ALWAYS SPARES
  each function's most recent row regardless of age." Live read of the
  function body (`supabase/migrations/109_cron_silence_alert_and_log_cleanup.sql:62-76`)
  shows it spares exactly ONE row globally (the single most-recent
  `status='success'` row table-wide), not one per function. A function
  silent >7 days has ALL its rows purged and becomes invisible to
  `/cron`/`/status` — the same blind-spot class F4 fixed, re-manifesting
  past 7 days instead of past 200 rows.
- **verification:** `select pg_get_functiondef('public.cleanup_cron_call_log'::regproc)` (or read the migration source directly, since no later migration redefines it).
- **status:** accepted, fixed in this commit — comment corrected in both
  the source and its mirroring test comment; deeper fix (per-function
  retention exemption) filed as OI-199, separate pre-existing
  infrastructure out of this diff's scope.

## Finding 2 — P3 — missing_input
- **file:line:** `supabase/functions/telegram-admin-bot/index.ts:213` (`cmdSubs`)
- **claim:** `cmdSubs`'s subscription read carried no `.limit()` at all,
  unlike `cmdErrors`'s already-explicit `CLIENT_ERRORS_QUERY_CAP` +
  "capped" marker pattern established in this same diff. Inconsistent, and
  a silent undercount on a high-signup day.
- **verification:** read `cmdSubs`'s query chain; compared against
  `cmdErrors`'s pattern in the same file.
- **status:** accepted, fixed in this commit — added `SUBS_QUERY_CAP`
  (1000, PostgREST's real max) + the same honest marker, with a dedicated
  mutation-proven test.

## Founder triage notes

Both findings accepted and fixed in the same commit as this review.
Finding 1's comment-accuracy defect is fully fixed here; the separate,
pre-existing `cleanup_cron_call_log()` per-function retention gap it
uncovered is filed on the OI board as OI-199 (terminal state:
upstream_blocked — real infrastructure work, not part of this diff).
Zero P0/P1s; reviewer's
explicit verdict was "Accept with one non-blocking follow-up recommended
... Neither blocks merge." Re-verified post-fix: `deno check` clean,
`deno test` 375/375, both new fixes mutation-proven.
