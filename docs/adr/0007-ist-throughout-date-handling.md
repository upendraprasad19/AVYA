---
adr_id: 0007
title: IST throughout for all date keys, cloud date columns, counter resets
status: accepted
date: 2026-05-05
deciders: Upendra
---

# ADR-0007: IST (UTC+5:30) throughout for all date handling

## Context

ICANBEFITTER serves Indian users exclusively at launch. A "day" in
the app — the unit of streaks, daily nutrition targets, "today's
workout," daily AI message quotas — must mean **the user's local
day**, not UTC.

A user logs a workout at 10pm IST on Monday. In UTC that's 4:30pm
Monday. If a downstream system uses UTC date-keys, the workout gets
filed under "Monday" anyway — fine. But a user logs a workout at
1am IST on Tuesday. In UTC that's 7:30pm Monday. UTC-keyed systems
would file Tuesday's workout under Monday. **Streak math, daily
quota math, "yesterday's intake" — all break.**

Originally a few code paths used UTC; a few used `DateTime.now()`
(local but device-time-dependent — broken when user travels);
a few used IST. Mixed regime caused bugs:
- Streak miscounts after late-night logging.
- Daily AI quotas resetting at midnight UTC = 5:30am IST.
- "Yesterday's macros" showing today's data near IST midnight.

## Decision

**IST (UTC+5:30) is the canonical timezone for ALL date semantics in
the app and cloud.** Specifically:

- Date keys in Hive (`yyyy-MM-dd` strings) are IST-derived.
- Cloud `date` columns (Postgres `date` type) store IST date.
- Counter resets (AI quota, streak window, daily targets) fire on
  IST midnight.
- Timestamps remain UTC at the storage layer (Postgres `timestamptz`),
  but every UI render and bucket-key computation goes through the
  IST helpers.

Helpers (mandatory; do not roll your own):
- `lib/core/utils/ist_date.dart` — Dart: `istDateStr()`,
  `istMidnight()`, etc.
- `supabase/functions/_shared/ist_date.ts` — Deno/TS counterparts for
  Edge Functions.

Encoded in CLAUDE.md §4.5.

## Alternatives considered

1. **UTC everywhere.** Rejected.
   - The standard "always use UTC at the boundary" rule assumes a
     global user base where local-day semantics is a per-user concern.
     We have one timezone; pinning the bucket boundary to UTC
     introduces a 5:30am rollover that confuses users.
   - Streak math becomes counterintuitive ("I worked out at 11pm
     last night — why does my streak say 0 today?").

2. **Per-user timezone (`users.timezone` column).** Rejected at this
   time.
   - Adds correctness surface area we don't need at India-only
     launch.
   - Edge Functions would have to fetch the user's TZ before doing
     ANY date math — performance hit.
   - Revisit only if we expand outside India.

3. **Device local timezone.** Rejected.
   - User flies Mumbai → London → back. Local timezone changes.
     Streaks would break mid-trip.
   - Server-side cron jobs (weekly recalc, evaluate-rank-promotions)
     have no "user device" — they must use a fixed TZ.

4. **Asia/Kolkata via IANA TZ DB.** Considered. Equivalent semantics
   to UTC+5:30 since India has no DST. The fixed offset is simpler
   in code; if India ever adopts DST (it won't), we'd revisit. The
   `_shared/ist_date.ts` helper does the offset arithmetic by hand;
   no TZ database lookup.

## Consequences

Good:
- **Streak math is intuitive.** Bucket boundary aligns with how users
  experience days.
- **Daily quota resets are predictable.** Free-trial AI quota resets
  at IST midnight, not 5:30am.
- **Cloud cron jobs use the same clock as clients.** Weekly recalc
  fires at IST Monday 4am. No "did my Monday workout get counted in
  this week's report or last week's" ambiguity.
- **Helpers prevent drift.** Two files (`ist_date.dart` +
  `_shared/ist_date.ts`) are the only places that do the arithmetic.

Bad:
- **IST sweep gaps are recurring.** First-pass IST conversions
  always miss 2-3 sites (`feedback_ist_sweep_gap.md`). Test #11.1
  found 4 missed sites months after the initial sweep. Mitigation:
  exhaustive grep + second-pass audit; gate
  (`check_ist_helper_usage.dart`).
- **`istDateStr` double-shift bug** (Test #11.1) — a caller passed
  an already-IST DateTime and the helper shifted it again. Helper
  contract documented; tests added.
- **Counter-reset bugs** when cron schedules cross IST midnight
  in unexpected ways. The cron telemetry helper
  (`_shared/cron_telemetry.ts`) helps; bugs still happen.
- **If we expand outside India, this becomes load-bearing tech
  debt.** Mitigated by: helper centralization (two files to change),
  per-user TZ column already idea-ready.

## Status

Active. Locked across client + cloud + crons. Reverting requires
per-user TZ infrastructure and migration of all date-keyed data.
Not on the roadmap.

## See also

- CLAUDE.md §4.5
- `lib/core/utils/ist_date.dart`
- `supabase/functions/_shared/ist_date.ts`
- `feedback_ist_sweep_gap.md`
- `feedback_use_ist_throughout.md`
- Test #11.1 retro (`project_apk_test_11_1_full_config_migration.md`)
