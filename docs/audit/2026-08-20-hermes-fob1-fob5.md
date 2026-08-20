---
hermes_pass_id: 2026-08-20-hermes-fob1-fob5
ran_at: 2026-08-20T23:10:00+05:30
batch_scope: b7602ad..7cf6815 (branch claude/oi-pending-hold-weeks-1od97o)
lens_set: [L1, L2, L8, L9, L10, L13, L23, L40]
agents_dispatched: 5
findings_total: 24
findings_by_severity: { P0: 0, P1: 7, P2: 13, P3: 4, false_alarm: 9 }
verdict: pending
---

# Hermes Pass — FOB-1 (week identity) + FOB-5 (hold telemetry)

Blast radius `catastrophic` (SECURITY DEFINER content), so §4.12.3 requires `hermes: accepted`.
Five context-blind agents, each told to assume the author wrong. Live DB reached
(`dedsavbjuwgarrhphgnl` only) by three of them; two ran real mutation exercises.

## Summary

**Zero P0. Seven P1.** The centrepiece migration is correct, applied, correctly granted and
replay-faithful — every security claim the author made was independently verified TRUE,
including by role-assumption inside Postgres. The damage is elsewhere: **two of the batch's own
load-bearing claims are false**, and the test suite cannot see the defect class that actually
shipped.

## P1 findings

### P1-A — `4 + ordinal` DOES reach two user-facing labels (L1)
`workout_schedule_write_service.dart:285` stamps `copy['week'] = 4 + n`. Two readers render it:
`home_screen.dart:781,801` (`workoutMode: 'Week $week'`) and `day_detail_sheet.dart:102,127`
(`'WEEK $week'`). At flip-on a holder sees **"HOLDING · H1"** and **"Week 5"** on the same
screen — the contradiction FOB-1 exists to close, reintroduced inside one tab. Durable across
reinstall (`sync_workout.dart` pushes/restores `week`). `WeekIdentity`'s own doc-comment forbids
a `4 + ordinal` getter; these surfaces reach the value without one.
Missed because the sweep was scoped to `getCurrentWeekNumber()`/`getProgramWeek()` consumers;
these read the stamped row field. The evidence was in hand — `fob1-week-identity.closure.yaml:138`
says "hold rows sit at week 5+".
**Latent** (write path flag-gated) → blocks flip-on, not this merge.

### P1-B — the identity→label wiring seam is untested (L8)
Mutation 12 (`profile_provider` passes `holdOrdinal: null`) → **full suite 4757 green**.
Mutations 11+13b+14 together → **green**. The `surface wiring` group
(`hold_week_identity_behavioral_test.dart:291`) self-labels PRESENCE-ONLY, but understates it:
its grep tokens all survive the defect, because the defect is in the argument, not the call.
Fails rule 21's bar ("fails when the runtime path is broken even if the source text remains
intact"). This is the layer P1-A actually shipped in.

### P1-C — the a9d3f1 replay guard has three holes (L8 + L23)
`admin_metrics_functions_role_revoke_test.dart` verifies the revoke's PRESENCE only:
- **order-blind** — move the revoke above the `DROP`+`CREATE` and it stays green while the file
  replays anon-executable (L23 mutation C).
- **spelling-blind** — `drop function if exists public.fn;` (no parens) and
  `create or replace function fn()` (unqualified) both reset the ACL and both slip past
  (L8 variants A/B). `expect(checked, greaterThan(0))` does not help: migration 120 keeps the
  count above zero forever, so a future 121 written either way is silently unscanned.
- **role-order brittle** — `from authenticated, anon` (identical SQL) reddens it (L23 mutation D).

### P1-D — the three new columns reach the payload, not the dashboard (L40 + L8, independently)
`.single()` returns an object, the EF spreads it wholesale, deployed copy is byte-identical to
repo (no OI-93 drift), columns are live. But `AdminCurrentMetrics.fromJson`
(`admin_dashboard_data.dart:136`) is a named-key parser declaring 17 fields; the three new keys
appear nowhere in `lib/`, and `engagement_tab.dart` renders four hardcoded tiles. The founder
sees nothing. FOB-5 was filed because five events had zero consumers; it replaced them with an
event whose consumer chain terminates one hop earlier than claimed. This is OI-101's
"shipped but nothing calls it" reproduced one layer up from where the RPC choice avoided it.

### P1-E — a nightly cron deletes the rows the new metrics count (L40)
`rolling-context/index.ts:383-393` summarize-and-deletes from `ai_coach_interactions`.
`holders_total` is an all-time `count(distinct user_id)` over that table. Live:
`archived_event_rows 92 / deleted_from_source 91 / still_present 1`. The metric is a **floor,
not a count**, and fails silently. Compounded by L9-F3: `_logAsync` never sets `created_at` and
drops failures with no queue, so an **offline hold emits nothing, ever**.

### P1-F — analytics rows are already inside the LLM's retrievable memory (L40)
92 of 598 `memory_embeddings` rows (15.4%) are `app_event` rows embedded as
`source_type='conversation'`, sample `"User: {event: phase_1_cycle_repeat_started}\nCoach: "`.
`rolling-context:269` fetches with no channel filter; `ai-proxy:884` concatenates retrieval into
the SYSTEM prompt. **Predates this batch** — but this is the batch that derived the six-channel
taxonomy and applied it to exactly one consumer while five others kept reading unfiltered.

### P1-G — `log_table_retention` is live in prod with no file, and defeats Gate 31 (L9)
Live `schema_migrations` row `20260815155823`. Its own stored header: `Destructive?: yes —
deletes ~29,044 run records and ~10,654 client_errors rows … NOT recoverable`, cites diagnose
`c8e5b3` (does not exist) and "reverse block in the repo file" (does not exist). Two cron jobs
active now (`jrd_retention_daily`, `client_errors_retention_daily`); `CRON_REGISTRY.md` lists
neither. **Gate 31 scans `supabase/migrations/*.sql` for `cron.schedule(...)`** — a migration
with no file is invisible to the gate built to catch this. Applied 2026-08-15, five days before
this branch. Not caused by this batch.

## P2 findings (abridged)

- **L1-F2** `sync_profile.dart:287` writes the clamped `4` to cloud `user_progress.current_week`;
  `weekly-recap-ready:78` renders `"Week 4 debrief ready"` to a holder, `weekly-report:482`
  injects `- Current week: 4` into the Gemini prompt. An **undeclared third omission**, same
  class as the `ai_snapshot_builder` case that WAS declared. PRO-gated, so it bites on a
  free→PRO upgrade mid-hold.
- **L1-F6 / L8-P1-3 / L8-P1-4** no SoT concept for the hold-telemetry cross-language contract;
  `ai_messages_today`'s channel set unpinned against `_coachChatChannels` (the batch built the
  machinery and stopped one assertion short); `admin_dashboard_metrics_snapshot` declares
  `reader_manifest_complete: true` while migration 120 changed its reader's semantics.
- **L40-3 / L40-4 / L40-5** restore renders `app_event` rows as the user's own chat bubbles
  (replay path filters, render path does not); `daily-snapshot` feeds them into the
  profile-fact-extraction prompt its own comment calls the highest-consequence injection site;
  no consent gate, `metadata` unscrubbed.
- **L1-F5 / L23-F4 / L8-P2-2** the metric is forgeable — `channel` has no CHECK, RLS constrains
  only `user_id`; parity test's `firstMatch` binds to the wrong emit once a second is added
  (fails closed, but the repair path it suggests turns the suite green while unasserting the
  real seam).
- **L8-P2-3** the Remotion assertion is comment-satisfiable, and `remotion/` is outside
  `flutter test` and outside CI entirely — that grep is the only thing behind the composition.
- **L23-F3** OI-78 still live, still exactly 3, no 4th added. All three are SECURITY INVOKER, so
  a `prosecdef=true` filter misses them. The allowlist gate OI-78 prescribed exists in none of
  the 89 gate scripts.
- **L9-F2** hold schedule keys off by one day east of UTC+05:30 (pre-existing, systemic — the
  whole plan shifts together, so holds do not drift relative to it).

## Verified clean / false alarms

The ship-dark negative control is REAL (mutation 1 reddened) — §4.12.4 evidence sound.
Live ACL `{postgres=X,service_role=X}` matching both siblings, proven by role assumption
(`anon_DENIED / authenticated_DENIED / service_role_EXECUTED_ok`); file replays safe against
BOTH `pg_default_acl` grantor entries. `search_path` pinning sufficient (qualified refs + no `C`
on `public` for anon/authenticated). Every public table has RLS. The double `at time zone` is
exact — proven live, delta `00:00:00`, and it avoids the very bug shape suspected.
`holds_started_7d`'s rolling window matches the 093/101 house convention. `Map.toString()`
ordering, 500-char truncation, coach-message poisoning, all three quota triggers, the TSX
`holdOrdinal` seam and its loose `== null`, `week_selector.dart:341`, DPDP cascade, the 5.3x
arithmetic, migration-120 numbering, manifest pair-update, replay fidelity. 4 of 7 test files
hold up under mutation; the cross-language parity test and the pre-push parity test are good
work — mutations 5 and 7 both reddened, including the hard single-column case.

## Process finding

Two reviewers independently flagged that the mutation run and the read-only reviewers shared one
working tree. One watched migration 120 change under it twice mid-read and nearly filed a
phantom P0 against clean code. **A mutation run in the primary worktree while a reviewer reads
it is the §4.13 shared-index problem in a new costume.** Mutation proving needs its own worktree.
Recorded here because the dispatch was the author's, not the reviewers'.

## Founder triage

<pending>

## Action items

<pending — see triage>
