---
hermes_pass_id: 2026-11-05-hermes-oi179-cron-dead-alert
ran_at: 2026-11-05T14:40:00+05:30
batch_scope: 0d16beb1 (branch oi179-cron-dead-alert, one commit over origin/main a94d0257 + 17)
lens_set: [L1, L14, L22, L31, L35]
agents_dispatched: 2
findings_total: 9
findings_by_severity: { P0: 0, P1: 0, P2: 1, P3: 8, false_alarm: 1 }
verdict: accepted
verdict_note: every finding has one terminal state below; no P0 or P1; the migration itself drew no defect
---

# Hermes Pass - OI-179 (migration 169, cron_call_log retention 7 -> 10 days), catastrophic tier by content

Lens set: the migration set (L1, L14, L22, L35) plus L31 (alert coverage and false-fire), 5 lenses in 2 Sonnet
seats, one wave, no database access, read-only command list (founder's Sonnet-only rule overrides the skill's Opus
default). Ran AFTER the B-pass fixes, on the committed tree (docs/reviews/b466a59cc4f1-review.md). Seat A: L1, L14,
L22. Seat B: L31, L35.

## Summary
- 0 P0, 0 P1, 1 P2, 8 P3 records (9 distinct after dedup of two seats naming the `/cron` window), 1 false_alarm.
- Ship-blockers: none.
- Both seats independently confirmed: migration 169 is the 110 body except the interval, grants complete, ledger sha256
  equals the file, no later migration redefines the function, no other pruner is scheduled in the repo, the slowest
  scheduled cadence is weekly (6.68 d silent at 06:47 UTC on Sunday, 7.68 d on Monday, both under 8), and the earliest
  possible first page is 2026-11-06 (the table held about 7.5 days at apply).

## Findings by lens

### L1 - writer_reader_drift
- **A-F1 (P2, PARTIAL):** `telegram-admin-bot` `/cron` keeps a 7-day `.gte()` window, so a function silent for 7-10
  days is invisible there while the alert can now page for it (`index.ts` `sevenDaysAgoIso`). Seat B's F4 is the same
  finding. Disclosed in the code comment this batch added. **Terminal: filed** on OI-199 (the OI that owns
  retention vs per-function silence): its note now says the `/cron` window is aligned when that OI is fixed, an Edge
  Function change with its own deploy go.
- **A-F4 (P3, FALSE_ALARM on the premise):** silence past 10 days leaves no rows so the alert cannot fire; stated in
  migration 169's header, CRON_REGISTRY and OI-199. **Terminal: verified_clean** (an accepted, documented limit).

### L14 - DB constraints
- Clean: empty table removes nothing; the keep-set cannot contain NULL (`id` is a BIGSERIAL primary key); a tie on the
  newest `started_at` keeps one arbitrary tied row (negligible, only when both are older than the cut); no FK,
  trigger or RLS on the table; indexes exist; about 760 rows held.

### L22 - live state vs repo
- **A-F2 (P3, REAL):** old 7-day prose survives above the new update note in `telegram-admin-bot/index.ts` and in
  CRON_REGISTRY row 80 ("7-day retention (10 days from migration 169...)"). **Terminal: verified_clean** by design:
  the old text is dated history and each is annotated directly with the 2026-11-05 update; migration 068's "7 days"
  is an immutable applied file.
- **A-F3 (P3, REAL):** the comment-only edits to `telegram-admin-bot` and `_shared/cron_telemetry.ts` leave the
  bundled payload copies under `backups/edge_function_payloads/` and the deployed functions textually behind.
  **Terminal: verified_clean:** no behaviour differs (comment-only, platform tier, deno check clean); the
  diagnose-doc states "not redeployed". Redeploying every cron function for a comment would add risk for no gain.
- Repo-checkable claims true: ledger hash equals `sha256sum` of the file; ledger time 2026-11-05T12:28:57+05:30
  equals 06:58:57 UTC equals Supabase version 20261105065857. Live-database claims are repo-unverifiable by design
  (no DB access for seats); they were measured by the coordinator (function body, ACLs, row counts, jobs).

### L31 - cron/alert false-fire analysis
- **B-F1 (P3, REAL):** no per-run cap and no fleet-wide guard: in an 8-10 day outage up to 17 CRITICAL rows, each
  dispatching `alert-critical-notify`; on the first recovery morning functions scheduled after 06:47 UTC would page
  before their own first run. **Terminal: filed as OI-473** (suppress while `alert_cron_silence` is open, or cap).
- **B-F2 (P3, PARTIAL):** the dedup (`acknowledged = false` and 24 h) lets an acknowledged alert re-fire and is
  jitter-sensitive, so 2-3 alerts per dead function (3 worst case with 10-day retention), noise not a false fire.
  **Terminal: filed as OI-473** (dedup per function with a longer window).
- **B-F3 (P3, REAL, process gap):** the exclusion is a hard-coded name inside the cron body; retiring or renaming a
  cron function within 10 days pages CRITICAL for 2-3 days and nothing ties retirement to the list. **Terminal: filed
  as OI-473** (roster test: every `logCronStart` caller is scheduled or excluded). `weekly-recalc` stays OI-472.
- **B-F4 (P3, PARTIAL):** same `/cron` 7-day window as A-F1. **Terminal: filed** on OI-199 (see A-F1).

### L35 - ordering / live-change-then-merge
- **B-F5 (P3, REAL, transient):** until this branch merges, `main` still defines 7 days (migration 110) while live is
  10 days, so a `supabase db reset` or replay from `main`, or a branch cut from `main`, restores the unsatisfiable
  state. It self-heals when 169 lands. **Terminal: fixed by landing:** the PR is merged through
  `scripts/land_pr.sh` in the same session; recorded here so a replay before then is not a surprise.
- Clean: `cleanup_cron_call_log` is defined only in 068/109/110/169; nothing after 169 redefines it; `mig/169` is
  reserved on the remote so no parallel branch can mint it; `origin/main` has no `169_` file yet (expected).
- Cosmetic: the ledger entry for 169 was indented two extra spaces. **Terminal: fixed** (re-indented; Gate 39 hashes
  the migration file, not the ledger, so it still passes).

## Founder triage
All findings given a terminal state in this batch; the founder's explicit go to apply, commit, push and open the PR
was given in chat 2026-11-05. No P0 or P1, so no `block_ship`.

## Action items
- [x] A-F1 / B-F4 `/cron` window: filed on OI-199 with the instruction to align it - owner: OI-199.
- [x] A-F2, A-F3, A-F4: verified_clean with the reasons above - owner: n/a.
- [x] B-F1, B-F2, B-F3: filed as OI-473 with acceptance criteria - owner: OI-473.
- [x] B-F5: resolved by the merge of this PR; ledger indentation fixed in this commit.

## Self-evolution
2 Sonnet seats, one wave, about 2 minutes wall-clock each. Signal per lens: L31 4 real of 4 (the only seat that
found anything new, all P3); L1 2 of 2 (one false_alarm on the premise); L22 2 of 2 (wording and comment drift);
L14 0 of 0; L35 2 of 2. Lesson: for a batch that turns a dead alert on, give a seat the alert's FIRST-FIRE behaviour
(who pages, how many times, in what order) as its subject; the three real design edges came only from that seat.
