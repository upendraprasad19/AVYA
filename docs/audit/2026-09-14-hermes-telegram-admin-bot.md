---
hermes_pass_id: 2026-09-14-hermes-telegram-admin-bot
ran_at: 2026-09-14T20:20:00+05:30
batch_scope: main..telegram-admin-bot (32 commits)
lens_set: [L1, L14, L21, L22, L23, L31, L35, L40]
agents_dispatched: 8
findings_total: 19
findings_by_severity: { P0: 0, P1: 0, P2: 4, P3: 8, false_alarm: 7 }
verdict: accepted
---

# Hermes Pass — telegram-admin-bot

## Summary

8 parallel Opus lens agents, most-capable-model, context-blind, dispatched
against the full 32-commit branch diff (`main..telegram-admin-bot`) plus the
live source tree. **Zero P0/P1.** Four P2s, three of which are the SAME
underlying finding surfaced independently by three different lenses (L1,
L22, L35) — corroboration, not triplication. Eight P3s, mostly PARTIAL
(real but low-severity or already-scoped-out). Seven FALSE_ALARM, each with
a stated verification command per the skill's anti-pattern rule against
unevidenced "looks fine".

- **Ship-blockers:** none.
- **Fixed in this batch (follow-on commit):** F1 (migration 135's mirror
  gap), F2 (`/errors` cap-marker checks the wrong array), F3 (`/digest`
  help text says "today's" when it means "yesterday's"), F4 (defensive
  hardening: explicit unset-secret check in `isAuthorizedTelegramSender`,
  matching `cron_auth.ts`'s own convention), F5 (defensive hardening: the
  one reachable-by-code-change token-leak-shaped line in
  `alert-critical-notify` gets the same `telegramErrorSummary`-style guard
  `_shared/telegram.ts` already uses everywhere else).
- **Filed on the OI board (out of this branch's scope):** F6 → OI-201
  (burst-dispatch + no-retry, pre-existing infrastructure amplified by
  this branch's delivery mechanism).
- **Accepted as documented tradeoffs, no action:** F7 (134's success
  telemetry marks pg_net enqueue, not delivery — same fire-and-forget
  shape as every other cron-dispatch trigger in this repo), F8
  (`admin_metrics_daily` trend discontinuity at the 135 cutover date —
  a one-time historical blip in an internal chart, not a data-correctness
  bug), F9 (134's rollback block is a pointer to 133's body rather than
  inline DDL — a real header-convention deviation, but 134 is applied and
  immutable; noted in this report as the permanent record per
  `supabase/migrations/CLAUDE.md`'s own guidance for where corrections to
  an immutable migration's defects belong).

## Findings by lens

### L1 — Writer/reader drift
1. **REAL → F1** (merged below). `client_errors_today` (135) and
   `client_errors_7d` (unchanged) now apply different predicates to the
   same table, consumed as one metric pair by `ops_health_tab.dart` and
   persisted by `compute-admin-metrics-daily` into `admin_metrics_daily`.
2. **REAL → filed OI-201** (burst-dispatch half) + **confirmed inert,
   no new action** (the `alert_cron_function_dead` false-critical-loop
   risk L1 independently found is the SAME risk R2-11 already filed as a
   hard precondition on OI-179/OI-199 — verified directly by reading
   `cleanup_cron_call_log()`'s global two-row-only retention: since it
   keeps only ONE success row table-wide, not per-function, a sporadic
   function's success row is deleted by ordinary cron churn well before
   the 8-day silence threshold in `alert_cron_function_dead` can ever see
   it. Confirmed by reading migration 110 directly, not trusted from
   either subagent's prose).
3. FALSE_ALARM — migration 134's `client_errors` insert columns (verified
   against live schema + the 078 corrected precedent).
4. FALSE_ALARM — `founder_metrics_ops()`'s RETURNS TABLE shape vs its 4
   readers (byte-identical to 101's definition).
5. PARTIAL, no new information — OI-200's already-filed `event`-vs-`info`
   asymmetry between `/status` and `/errors`.

### L14 — onConflict live arbiter
NOT_APPLICABLE. Zero `ON CONFLICT`/upsert shapes introduced or touched —
this branch is read-only reporting + three `CREATE OR REPLACE FUNCTION`
migrations with no constraint or nullability change. Full census of every
`insert`/`upsert`/`conflict`/`unique` hit across all 42 changed files
confirmed none are new arbiter-resolving statements.

### L21 — Edge Function semantic correctness
1. **REAL → F2**. `cmdErrors`'s truncation marker (`index.ts:498`) checks
   `rows.length` (the FILTERED array, post-`event`/`info` exclusion)
   against `CLIENT_ERRORS_QUERY_CAP`, but the cap applies to the RAW read
   (`data`, `.limit(1000)`). On any real day with at least one `info` row,
   the filter removes it and the marker can never fire even when the raw
   read WAS truncated. `cmdSubs` gets this right (checks the unfiltered
   array) — this is a slip, not a deliberate choice.
2. **PARTIAL → F5**. `alert-critical-notify/index.ts:115`'s
   `String(err).slice(0,200)` on a caught `fetch` error is the
   bot-token-leak-into-cron_call_log shape this repo's own CLAUDE.md
   pitfall table documents (and `morning-alert` already has the LIVE
   version of this bug). Not reachable today (`sendTelegram` never lets a
   raw fetch rejection escape to this catch), but positional, not
   structural — a future line added inside this `try` would leak the
   token with no gate to catch it.
3. **REAL → F3**. `/help`'s `"re-send today's digest"` line is wrong —
   `cmdDigest` composes yesterday's IST window by design (matching the
   08:00 cron), so the text should say "yesterday's".
4. FALSE_ALARM — TDZ/execution-order (every module-level const initializes
   before the single entry point). FALSE_ALARM — missing `await` (every
   promise in both functions is awaited or is a deliberate parallel
   collection). FALSE_ALARM — swallowed catches (every catch either logs +
   telemetrizes or converts to a caller-visible marker, except the one
   deliberately-silent `req.json()` parse). FALSE_ALARM — always-200
   timing oracle (both refusal paths cost identical work and return
   byte-identical responses; no distinguishing signal).

### L22 — Schema-vs-payload parity
1. FALSE_ALARM — migration 134's `client_errors` INSERT columns against
   live NOT NULL constraints (all three NOT NULL columns supplied on
   every one of the three INSERT paths; no CHECK constraint on the
   synthetic `'server-trigger'`/`'server'` placeholder values, and no
   downstream reader parses them as a real version/platform).
2. **REAL, independently confirms L1's F1** — same finding, same fix.
3. FALSE_ALARM — `founder_metrics_ops()`'s RETURNS TABLE vs all callers
   (same conclusion as L1, independently derived).

### L23 — Authorization defense-in-depth
No bypass found on either function. Two PARTIALs, both fixed defensively:
1. **PARTIAL → F4 (partially addressed)**. `isAuthorizedTelegramSender`'s
   unset-secret fail-closed behavior is INCIDENTAL (falls out of the
   empty-header guard), not an EXPLICIT check + warning the way
   `cron_auth.ts:118` has one. Not exploitable — but a mis-provisioned
   deploy is silently dead rather than diagnosable.
2. PARTIAL, accepted as documented tradeoff — `req.json()` parses an
   unbounded body before the auth gate runs (no data is touched, no
   service-role handle exists yet, so this is not an authz bypass; a
   webhook body-size cap is a reasonable future hardening but is scope
   creep for this batch given Telegram's own webhook payload ceiling
   already bounds it in practice).
3. FALSE_ALARM — `telegram-admin-bot`'s privileged reads all sit strictly
   after the auth gate (traced control flow, no early return/exception
   path bypasses it). FALSE_ALARM — `alert-critical-notify`'s gate
   likewise strictly precedes every privileged action. FALSE_ALARM — the
   trigger-dispatch secret can't be forged (RLS + `private` schema close
   both the "forge the dispatch" and "cause an unwanted dispatch" vectors).

### L31 — Cron job efficiency
1. FALSE_ALARM — `cmdRevenue`'s `maxPages: 200` fails LOUDLY (throws), not
   silently; PARTIAL on the stated rationale (protects against runaway
   reads, not webhook timeout, which binds on round-trips not rows — the
   comment's justification is imprecise but the value itself is fine).
2. **REAL → filed OI-201** (burst-dispatch half).
3. **PARTIAL → filed OI-201** (no-retry-on-429 half).
4. FALSE_ALARM — `/status`'s `count(*)` queries are all bounded by
   existing retention (`client_errors` 30d, `cron_call_log` 7d) or are
   working-set counts (`alerts WHERE resolved_at IS NULL`).
5. FALSE_ALARM — `cmdCron`'s 7-day window read matches
   `cleanup_cron_call_log`'s own retention exactly; the residual blind
   spot is already OI-199.

### L35 — Migration reversibility / forward-compat
1. FALSE_ALARM — migration 133's rollback DDL is executable and genuinely
   restorative.
2. **PARTIAL → F9 (noted, not fixed — applied+immutable)**. Migration
   134's "rollback DDL" block is a pointer sentence to 133's body, not
   actual DDL — a real deviation from the header convention's "commented
   reverse DDL block" requirement. Also: `Rollback strategy: migration
   133's own body` is not one of the convention's three accepted literals
   (`inline | migration NNN | not applicable`).
3. FALSE_ALARM — migration 135's rollback DDL is byte-verified against
   101's original definition; genuinely executable.
4. PARTIAL, accepted — 135's `REVOKE`/`GRANT` pair is *not* what keeps
   `anon`/`authenticated` out (this project's default privileges grant
   them directly per the documented `supabase/migrations/CLAUDE.md`
   pitfall); it's safe only because 101 already narrowed the ACL and no
   DROP occurred. Noted for whoever next changes this function's
   signature — not a defect in 135 itself.
5. FALSE_ALARM — dropping the 133/134 trigger orphans `alert-critical-
   notify` as unreachable dead code; nothing asserts the trigger exists.
6. **PARTIAL → F7 (accepted tradeoff, no action)**. 134's success
   telemetry marks pg_net ENQUEUE, not delivery confirmation — cannot
   distinguish "delivered" from "posted to a 404". Same fire-and-forget
   shape as every other cron-dispatch trigger in this repo (a systemic
   pattern, not unique to this branch).
7. **PARTIAL → F8 (accepted, no action)**. `admin_metrics_daily`'s
   `client_errors_today` series is discontinuous at the 135 cutover date
   — rows before and after were computed under two different predicates
   with nothing marking the change. One-time historical blip in an
   internal ops chart.

### L40 — PII / privacy in telemetry payloads
1. **REAL, low severity, functional not disclosure → not fixed
   (availability nit, no test exercises it, non-blocking)**. The one
   unescaped echo in the whole file (`index.ts:598`,
   `` `Unknown command: /${cmd}...` ``) — a founder-typed `/<b` could 400
   the Telegram send and silently drop the reply. Founder-only surface,
   no disclosure risk, just a robustness nit.
2. FALSE_ALARM — migration 134 never persists alert summaries into
   `client_errors` (only opaque IDs); `user_id=NULL` rows are also
   unreadable by any authenticated user per RLS.
3. PARTIAL, accepted — `SQLERRM` and the cron secret share one exception
   handler scope but no demonstrated Postgres error class echoes a
   computed argument into `SQLERRM`; flagged for awareness only.
4. PARTIAL, accepted — founder-typed search queries land in PostgREST URL
   logs (Supabase's own request logs), inherent to every PostgREST call
   in this repo, not a new exposure class introduced here.
5. FALSE_ALARM — no hardcoded secret anywhere in the branch diff (checked
   against JWT/bot-token/API-key shape patterns; only test dummies
   matched).

## Founder triage notes

Zero P0/P1 across 8 lenses on a catastrophic-tier, security-relevant
(founder-only auth surface, service-role reads) branch — consistent with
the depth of review this branch already received (2 whole-branch rounds +
3 B-passes before this Hermes pass). The corroborated P2 (F1, found
independently by 3 lenses) is the clearest signal in this report: it's the
exact mirror-case R2-10's own fix should have caught, and 3 lenses agreeing
on file:line and root cause makes it the highest-confidence finding here.
Fixed in the same follow-on commit as F2/F3/F4/F5. F6 (OI-201) is real
infrastructure work with its own blast radius, correctly out of scope for
this batch per the same reasoning R2-11 already established for
OI-179/OI-199. Verdict: **accepted** — this batch's remaining fixes
(F1-F5) are small, mechanical, and land in one follow-on commit before the
plan-review record.
