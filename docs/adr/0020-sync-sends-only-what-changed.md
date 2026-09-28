---
adr_id: 0020
title: Sync sends only what changed; the server keeps completed days and drops no-op updates; sync_epoch is the repair lever
status: accepted
date: 2026-09-28
deciders: Upendra
---

# ADR-0020: Sync sends only what changed; the server keeps completed days and drops no-op updates; `sync_epoch` is the repair lever

## Context

OI-237 measured the day-swapper + sync-load batch's own sync-load audit (spec
§1.5, 2026-09-26): a coalesced, fire-and-forget sync entry re-walked a user's
**entire** historical Hive log on every call, not just what changed since the
last successful push, then `await`ed a network upsert per row sequentially.
Measured live: `workout_schedule_completions` ~29 rewrites/row,
`scheduled_workouts` 1,377 updates vs 84 inserts, `template_exercises` ~33
rewrites/row on 23 live rows. A single sync pass routinely took 14–40s on a
heavy user's history, tripping `SyncService.restoreOpTimeout` (45s) — a
ceiling meant to catch a genuinely wedged call, not bound normal-case
latency. The existing OI-204 fix (three hand-rolled per-domain fingerprint
indexes for `sched`/`exlog`/`nlog`) proved the pattern worked but did not
generalize: 14 more domains needed the same skip, each with its own
swallowing-catch bookkeeping to get wrong.

A second, related defect (spec §1.6, recurrence of `5a36ad`): a sync payload
falling back to `DateTime.now()` for a timestamp describing the past
(completion time, template `created_at`, etc.) silently corrupted the cloud
value on every re-sync, 14 instances across the sync layer.

## Decision

1. **One shared helper, `SyncSkipIndex.pushIfChanged`** (`lib/core/services/sync/sync_skip_index.dart`),
   replaces the three OI-204 hand-rolled indexes and adds 14 more domains
   (17 total). It owns the push try/catch itself, so a domain loop can never
   record a row as sent after a swallowed failure; it fails open on a
   fingerprint-computation exception (push anyway, record nothing); it drops
   any stored fingerprint on a failed or unconfirmed push; and it stops
   entirely (`aborted`) the moment the live account changes mid-pass. Gate G1
   (`scripts/check_sync_hash_skip_atomicity.dart`) statically enforces that
   every history-loop upsert sits inside this one helper and that no other
   code writes a `*_payload_hash_index` key.
2. **The server drops no-op updates and never demotes a completed day**
   (migration `147_sync_noop_suppress_completed_guard_sync_epoch.sql`): a
   generic `suppress_redundant_updates_trigger()` (Postgres built-in) on 19
   tables makes an identical re-sent row create no new row version at all —
   a backstop for app versions already installed, and the only protection
   for the two tables (`water_logs`, `daily_steps`) whose writer stamps a
   fresh sent-at column on every push and so can never fingerprint-match
   client-side. `scheduled_workouts` gets a dedicated guard instead
   (`RETURN NULL`, never `RAISE`, when a completed row's status would
   change) so a stale device's resync can never silently un-complete a day
   another device already finished, and a raised error would make that
   device retry the same refused write forever.
3. **`sync_epoch` is the repair lever**, not a daily safety net. A daily
   unconditional 7-day re-send was considered and rejected (see below); the
   accepted mechanism is an operator-bumped `user_progress.sync_epoch`
   integer that clears every device's local skip index and forces exactly
   one full re-send, only when an operator has reason to believe cloud data
   was lost, wiped, or restored from a backup. See
   `docs/operations/SYNC_EPOCH_RESYNC.md`.
4. **Never send `DateTime.now()` for a past timestamp.** Resolution order:
   the recorded value → derived from a `*_ms` sibling or a timestamp
   embedded in the Hive key → omit the field entirely (never fabricate
   "now"). Gate G2 (`scripts/check_sync_no_now_fallback.dart`) fails a
   comment-stripped `?? DateTime.now()` literal anywhere in sync payload
   code.

**Rejected: a daily unconditional re-send as the safety net for missed
writes.** A blind resend of every planned/rest schedule row once a day would
undo another device's day-swap that landed between resends — the swap's
`arranged_at_ms` stamp exists precisely so a genuinely newer arrangement can
be told apart from a stale resend (restore-merge L3, `docs/architecture/sync.md`),
and a periodic full resend has no such signal for itself. `sync_epoch`, fired
only by an operator who has a specific reason, avoids that hazard entirely.

## Consequences

Good:
- Sync load drops from a full historical re-walk to "what actually changed",
  closing the OI-237 measured amplification without changing what data
  ultimately reaches the cloud.
- A completed day can never be silently un-completed by any stale device's
  resync, at the server layer — independent of whatever the client is doing.
- Past-timestamp corruption (recurrence of `5a36ad`) is closed with a
  mechanical gate (G2), not just a one-time fix.

Bad / accepted trade-offs:
- The 17 kill switches are all local `configBox` flags — there is no remote
  config for any of them, so a fleet-wide rollback of any one domain's skip
  needs a new release, not a dashboard flip.
- A `sync_epoch` bump costs one full re-send pass per device on that user's
  next launch — cheap for a single operator-driven repair, not something to
  reach for routinely.
- Two tables (`water_logs`, `daily_steps`) cannot be protected by the
  server-side no-op trigger at all, because their writer stamps a genuinely
  fresh sent-at column on every push; the client-side skip index is their
  only protection, and a client-side bug in that specific domain has no
  server backstop.
- M1 (unchanged): two overlapping sync passes for the same domain can both
  read the old stored fingerprint before either writes the new one — the
  per-key WriteService mutex is the actual serialization point; `SyncSkipIndex`
  is an optimization on top of it, not a replacement.

## See also

- `docs/superpowers/specs/2026-09-26-day-swapper-design.md` §1.5, §5.9, §5.10, §5.12
- `docs/architecture/sync.md` — full domain table, restore-merge L1–L3, kill-switch list
- `docs/operations/SYNC_EPOCH_RESYNC.md`
- `docs/diagnoses/2026-09-19-full-rescan-sync-timeout-d3f8a6.md` (the OI-204 predecessor this batch generalizes)
- Diagnose `a9d3f6` (OI-237)
