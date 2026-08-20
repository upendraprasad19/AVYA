---
reviewed_at: 2026-08-20T00:00:00+05:30
staged_against: de874b85c95c
blast_radius: catastrophic
reviewer: inline-adversarial-pass (see "Reviewer provenance" — NOT a fresh-context dispatch)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, metric_semantics, security_definer_acl, guard_subject_moved]
findings_count: 6
verdict: accepted
---

# Code Review (B-pass) — FOB-5 hold telemetry + engagement-metric channel filter

Batch: FOB-5 of OI-60. Branch `claude/oi-pending-hold-weeks-1od97o`.
Diagnose: `c7a3b9`. Migration: `120_engagement_metric_channel_filter_and_hold_telemetry.sql`.

## Reviewer provenance — read this before trusting the verdict

The skill's contract is a **fresh Sonnet subagent with no conversation context**
(`.claude/skills/code-review/SKILL.md:4`). This session is barred from dispatching
subagents, so this pass was run **inline, by the same context that wrote the code**.
That is a materially weaker instrument: an inline reviewer cannot be surprised by its
own assumptions, and the single most valuable property of the B-pass — context-blindness —
is absent.

It is recorded as `accepted` because every claim below is backed by a **live query or a
direct file read**, not by recall. Where a claim rests only on reasoning it is labelled as
such. Treat this record as "verified against ground truth by an interested party", not as
the independent pass the skill describes. The merge-to-main commit still owes the ×2
plan-review per §4.12.

## Verdict summary

- 2 findings fixed inside this commit (F4, F6).
- 1 finding needed a founder authorization (F1) — since **granted and applied**; see the
  correction appended to that finding.
- 3 findings assessed and accepted as-is with rationale (F2, F3, F5).
- Both fixes are mutation-proven (control green → mutant red → restored green, with the
  restored file confirmed byte-identical by `git diff`).
- 8 properties verified clean (below).

---

## Finding 1 — P2 — metric_semantics — `admin_metrics_daily.ai_messages_today` is now a mixed-definition series

- **file:line:** `supabase/functions/compute-admin-metrics-daily/index.ts:106` (writer) ← `supabase/migrations/120_…sql` (the redefined source)
- **claim:** Migration 120 changes what `ai_messages_today` MEANS. The nightly cron persists
  that value into `admin_metrics_daily`, which already holds **25 rows spanning 2026-07-26 →
  2026-08-19** computed under the *pre-120* definition. From the first post-120 nightly run the
  same column carries the new definition, with nothing in the row marking the change. A founder
  charting the series sees a cliff and reads it as an engagement collapse.
- **verification (live, `dedsavbjuwgarrhphgnl`):** recomputing all 25 historical dates under the
  new predicate → **15 of 25 rows change**; series total **58 → 8**. So the break is not
  hypothetical and not small.
- **why this is not the migration's bug:** the migration is *correct*; the persisted history is
  what is stale. Fixing it forward would mean leaving 25 wrong rows in place.
- **suggested-fix (needs founder go — this is a live UPDATE on founder metrics, §4.3).**
  ⚠ **The statement below is WRONG. It is kept as written so the correction is legible;
  the applied statement follows it.**
  ```sql
  with recomputed as (
    select (created_at at time zone 'Asia/Kolkata')::date as d, count(*) as c
    from public.ai_coach_interactions
    where channel in ('app','chat','in_app_orphan')
      and coalesce(user_message,'') <> '' and coalesce(ai_response,'') <> ''
    group by 1
  )
  update public.admin_metrics_daily m
     set ai_messages_today = coalesce(r.c, 0)
    from (select * from recomputed) r
   where r.d = m.snapshot_date
     and m.ai_messages_today is distinct from coalesce(r.c, 0);
  ```
  That last sentence is the error. Rows with no matching interaction day are **not** already
  correct — 13 of the 15 divergent rows needed to become `0` *because* those days had no
  qualifying interactions, which is exactly why `recomputed` has no row for them and the
  INNER join skips them. The preview query read correctly only because it used a LEFT join,
  which is not what the UPDATE did.

- **What was actually applied** (correlated subquery, so a zero-interaction day resolves to `0`):
  ```sql
  update public.admin_metrics_daily m
     set ai_messages_today = (
       select count(*) from public.ai_coach_interactions a
        where (a.created_at at time zone 'Asia/Kolkata')::date = m.snapshot_date
          and a.channel in ('app','chat','in_app_orphan')
          and coalesce(a.user_message,'') <> '' and coalesce(a.ai_response,'') <> ''
     )
   where m.ai_messages_today is distinct from ( /* same subquery */ );
  ```
  Caught only because the first attempt hit a connection timeout, which forced a state
  re-check before retrying. A clean first run would have reported "15 rows updated" and
  left 13 of them wrong — a silent partial fix that looks exactly like a complete one.
- **Also verified, not assumed:** `compute_admin_metrics_daily` runs `15 18 * * *` UTC =
  **23:45 IST**, so each snapshot already covered ~23h45m of its IST day. The delta is
  definitional, not partial-day-vs-full-day.
- **status:** `closed_in_commit` — authorized and applied 2026-08-20. Post-verification:
  `still_divergent = 0` across all 25 rows, series total `58 -> 8`, re-checked with a lateral
  recompute written independently of the UPDATE.

## Finding 2 — P3 — coverage — the three `hold_*` columns never reach the daily snapshot table

- **file:line:** `supabase/functions/compute-admin-metrics-daily/index.ts:87-113` (`buildSnapshotRow`)
- **claim:** The migration's own comment argues the new columns "reach the dashboard with NO Edge
  Function redeploy" because `admin-dashboard-data/index.ts:255` spreads the row wholesale. True —
  but there is a **second caller**, and it does not spread: `buildSnapshotRow` enumerates named
  fields, so `holds_started_today` / `holds_started_7d` / `holders_total` are silently dropped and
  never persist.
- **verification:** both call sites read directly (`grep -rn founder_metrics_engagement` → 2 callers);
  `EngagementRow` (`:43-49`) declares only the 5 original fields.
- **assessment — accepted, no change:** dropping unnamed fields is safe (no upsert break, which is
  why no redeploy is needed), and the history is not lost: all three columns are computed at read
  time from raw `ai_coach_interactions` rows, which persist indefinitely. A time series is
  reconstructible for any past window whenever it is wanted. Recorded so nobody later assumes
  `admin_metrics_daily` already carries hold history.
- **status:** accepted, documented.

## Finding 3 — P3 — convention — `today` and `7d` use different window semantics

- **file:line:** `supabase/migrations/120_…sql` (the `holds_started_today` vs `holds_started_7d` subqueries)
- **claim:** `holds_started_today` uses the IST-day boundary (`date_trunc('day', now() at time zone
  'Asia/Kolkata')`); `holds_started_7d` uses a rolling `now() - interval '7 days'`, i.e. the last
  168 hours, not the last 7 IST days. The two adjacent columns therefore answer subtly different
  questions.
- **assessment — accepted, no change:** it matches the shape of the existing `*_7d` columns and the
  name says `7d`, not `7 IST days`. Changing it would make this migration inconsistent with its own
  siblings for no gain. Recorded so a future reader does not assume day-aligned buckets.
- **status:** accepted, documented.

## Finding 4 — P2 — function_exception_swallow — telemetry could fail a committed hold — **FIXED IN THIS COMMIT**

- **file:line:** `lib/core/services/workout_schedule_write_service.dart` (the `hold_week_started` emit)
- **claim:** The emit was placed inside `holdWeek`'s `try`, whose `finally` only clears
  `_holdInFlight`. A **synchronous** throw from `AppEventsService.log` would propagate out of
  `holdWeek` *after* the hold was already committed to Hive — surfacing a materialized hold to the
  caller as a failure, and skipping the durability push that runs past the `finally`. The code
  comment asserted "log never throws", but that is a property of a **different file**
  (`app_events_service.dart`) that nothing pinned; the new `debugCapture` branch had just added a
  `capture.add(...)` call to that very method.
- **fix:** wrapped the emit in a local `try/catch`, so the invariant is enforced at the call site
  rather than assumed across a file boundary.
- **regression test:** `test/contracts/hold_week_mechanic_behavioral_test.dart` — *"a THROWING
  telemetry sink cannot fail or truncate a committed hold"*. Sets `debugCapture` to an
  **unmodifiable** list so `add` throws `UnsupportedError`, then asserts `holdWeek()` completes,
  the hold row still carries `hold_ordinal: 1`, and `plan_end` was still extended. Removing the
  `try/catch` reddens it on the `holdWeek()` await itself.
- **status:** `closed_in_commit`.

## Finding 5 — P3 — test seam in production code

- **file:line:** `lib/core/services/app_events_service.dart` (`static … debugCapture`)
- **claim:** A statically mutable field in production code that, when set, silently disables all
  telemetry. `@visibleForTesting` is analyzer-**info** only, so nothing blocks a production
  assignment.
- **verification:** `grep -rn debugCapture lib/ test/` → assigned in exactly one place, a test file;
  zero production assignments. Defaults `null`, and `log`'s production path is byte-identical when null.
- **assessment — accepted:** standard Flutter idiom, and the alternative (grepping the writer's
  source for the event name) is precisely the false-confidence pattern rule 21 warns about.
- **caveat recorded for future users of the seam:** the capture branch short-circuits **before**
  `_logAsync`'s `currentUser == null` early return, so a capture-based test cannot observe the
  signed-out drop. Irrelevant here (a holder is necessarily signed in) but it will matter to the
  next caller that adopts this seam.
- **status:** accepted, documented.

## Finding 6 — P1 — guard_without_its_mirror — the a9d3f1 regression test pins migration 103 by name and is blind to 120 — **FIXED IN THIS COMMIT**

- **file:line:** `test/contracts/admin_metrics_functions_role_revoke_test.dart:33-56`
- **claim:** This is the mirror of F5-E, not a repeat of it. E fixed the **live ACL** and hardened
  the `.sql`; this is about the **guard**. The existing test asserts that *migration 103* revokes
  EXECUTE from `anon` + `authenticated` on the three `founder_metrics_*` functions. But 103 is no
  longer the migration that owns the ACL for `founder_metrics_engagement` — **migration 120 DROPs
  and recreates it**, and 103's grants were revoked on the function object that 120 replaced. On any
  replay past 120 the protection comes solely from 120's own revoke lines. Delete them and the
  anon-readable-business-metrics leak reopens **while this test stays green**. A guard whose subject
  moved out from under it is worse than no guard: it reports safety it no longer checks.
- **verification:** enumerated every migration that creates or drops one of these functions —
  `101` (3 functions, **0** role-revoke lines: the historical bug) and `120` (1 function, 1 revoke
  line). Nothing else touches them, and nothing pinned 120.
- **fix:** a second test in the same file, written against the **migration set** rather than a named
  file — every migration numbered `>103` that creates or drops a `public.founder_metrics_*` function
  must re-assert the `anon, authenticated` revoke for each function it touches. The `>103` cutoff is
  explicit: 101 *is* the bug and 103 is its fix; neither may be rewritten. 121, 122 … are covered on
  arrival with no edit.
- **mutation proof:** control green (2/2) → delete migration 120's revoke line → **red** on the new
  test → restore → green, migration confirmed byte-identical via `git diff`. The scan also carries a
  `checked > 0` assertion so it cannot pass by matching nothing (the Gate-44 shape rule 24 bans).
- **status:** `closed_in_commit`.

---

## Verified clean (8 properties, each by live query or direct read)

1. **SECURITY DEFINER ACL** — `proacl` = `{postgres=X/postgres,service_role=X/postgres}`; `anon` and
   `authenticated` absent. This is the self-inflicted regression from the first apply, confirmed
   still closed after the revoke.
2. **No stale overload** — exactly **1** `founder_metrics_engagement` row in `pg_proc`; the
   `DROP`+`CREATE` left no second signature behind.
3. **`search_path` pinned** — `set search_path = public` on the SECURITY DEFINER function.
4. **Both RPC callers survive the widened return type** — `admin-dashboard-data` spreads (gains the
   columns), `compute-admin-metrics-daily` enumerates (ignores them). Neither breaks; no redeploy owed.
5. **No event-name substring collision** — all 11 `AppEventsService.instance.log` call sites
   enumerated; `hold_week_started` is the only event containing that token, so the SQL `LIKE` cannot
   match a different event.
6. **No injection into the `LIKE` predicate** — every `log` call site passes app-controlled literals
   (`{'week': 4}`, `{'ordinal': n}`); no user-authored text reaches an `app_event` `user_message`.
   A user typing `hold_week_started` into coach chat lands on `channel` `app`/`chat`/`in_app_orphan`,
   which the hold predicate excludes.
7. **The 500-char truncation cannot elide the match token** — `_logAsync` builds
   `{'event': event, ...metadata}` and Dart map literals preserve insertion order, so the event name
   is always at the head of the serialized string.
8. **Hold telemetry cannot inflate the metric it ships beside** — hold rows are `channel='app_event'`,
   which the new `ai_messages_today` predicate excludes on two independent legs (channel not in the
   SoT set, and `ai_response` is `''`).

## Cross-check against the batch's stated intent

FOB-5's own prescription (`where channel = 'app'`) was **refuted before apply** by live measurement
(7 of 116 rows → an ~89% undercount) and the repo's canonical `_coachChatChannels` set used instead.
The ledger entry for FOB-5 records that its own `how:` was wrong. Confirmed present in
`docs/ship_dark_pending_review.yaml`.
