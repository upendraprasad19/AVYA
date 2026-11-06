---
bug_id: 7ad0d3
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 7 Edge Function date-key sites used UTC midnight (`new Date().toISOString().split("T")[0]`, `setUTCHours(0,0,0,0)`, etc.) for rate-limit windows, snapshot keys, and look-back cutoffs. For Indian users (UTC+5:30), the UTC date doesn't roll over until 05:30 IST — so the daily 10-msg cap reset at dawn, vision cap reset at 05:30, weekly recalcs covered the wrong 7-day window, and monthly prediction re-trigger cutoffs were off by 5h30m.
concept: edge_function_ist_sweep
sot_registry_entry: ist_date_helpers
writers:
  - { file: supabase/functions/_shared/ist_date.ts, method_or_widget: istDayStartIso, line: 25 }
readers:
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: vision cap + free msg cap + memory_embeddings.metadata.date, line: 280 }
  - { file: supabase/functions/beat-my-coach/index.ts, method_or_widget: re-challenge cutoff + snapshot date, line: 159 }
  - { file: supabase/functions/future-prediction/index.ts, method_or_widget: 30-day re-trigger cutoff + snapshot date, line: 241 }
  - { file: supabase/functions/weekly-recalc/index.ts, method_or_widget: 4-week window cutoff, line: 172 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: 7-day window, line: 105 }
hive_key_prefix: "n/a — Edge Function date math"
hive_key_formula: "istDateStr(d) for date keys; istDayStartIso(d) for `created_at >= <timestamp>` filters"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [created_at, channel, user_id]
contract_test_path: "n/a — TS Edge Function sweep; verification is via the existing morning-alert + daily-snapshot reads that already use istNow()"
ist_handling: ["istDateStr() for date strings", "istDayStartIso() for timestamptz comparison"]
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["edge_function_new_date_toISOString_split_T_zero_for_date_key", "edge_function_setUTCHours_for_today_midnight"]
proposed_fix: Add `istDayStartIso(d)` helper to `supabase/functions/_shared/ist_date.ts` returning `<istDate>T00:00:00+05:30` for timestamptz comparisons. Sweep 7 sites — ai-proxy (vision cap, free-msg cap, embedded memories metadata.date), beat-my-coach (re-challenge cutoff + snapshot date), future-prediction (30d cutoff + snapshot date), weekly-recalc (4-week window), weekly-report (7-day window). All now route through istDateStr() or istDayStartIso() so the "today" window aligns with the user's IST day.
regression_test_planned:
  - "n/a — TS Edge Function changes; verified by deploy + production query inspection"
---
# Audit H-4..H-10: Edge Function UTC midnight sweep

## Bug

7 sites across 5 Edge Functions built date keys / midnight cutoffs
against UTC instead of IST. For Indian users (UTC+5:30):

- **ai-proxy / free-tier 10-msg/day cap** (H-4): `setUTCHours(0,0,0,0)`
  resets the cap at 05:30 IST every morning. User who hits 10 at
  23:00 IST sees the cap stay until dawn instead of midnight.
- **ai-proxy / vision 15/day cap** (H-10): same — UTC midnight reset.
- **ai-proxy / memory_embeddings.metadata.date** (H-7): UTC date
  stored on every conversation embedding → cross-day retrievals
  silently skipped around the IST midnight boundary.
- **beat-my-coach / re-challenge cutoff** (H-5): UTC-based 14-day
  window for the next challenge — 5h30m drift vs the user's
  perceived weeks.
- **beat-my-coach / snapshot_date** (H-5): same daily-snapshot row
  used by ai-proxy reader — IST-keyed. UTC write here meant the
  challenge metadata sometimes landed on the previous IST day's
  snapshot row.
- **future-prediction / 30-day re-trigger cutoff** (H-6): UTC.
- **future-prediction / snapshot_date** (H-6): same class as
  beat-my-coach.
- **weekly-recalc / 4-week window** (H-8): UTC date subtraction →
  the recalc covered IST mon-sun weeks misaligned by 5h30m at the
  endpoints.
- **weekly-report / 7-day window** (H-9): UTC. Sunday's weekly
  report potentially missed Saturday's last workout if the user
  trained between 18:30-23:59 IST.

## Cause

The `_shared/ist_date.ts` helper existed (`istDateStr`, `istNow`)
but wasn't used consistently. Migration / cleanup sweeps (Test #11
B1+B2+M3, Test #11 cleanup, Test #12 follow-ups) each closed a
subset; none covered the Edge Function surface in full.

## Fix

1. **New helper** `istDayStartIso(d)` in `_shared/ist_date.ts`
   returns `<istDate>T00:00:00+05:30` — directly comparable against
   `timestamptz` columns via `.gte("created_at", istDayStartIso())`.
   Postgres handles the offset; the query covers `[ist_midnight,
   now)`.
2. **Sweep** 7 sites listed above. Replace `new Date().toISOString().split("T")[0]` with `istDateStr()`; replace
   `setUTCHours(0,0,0,0) + toISOString()` with `istDayStartIso()`.
3. **Import** `istDateStr` and/or `istDayStartIso` per file.

## Deploys

Edge Functions touched (require redeploy):

- `ai-proxy` (large multi-file — host-shell deploy required)
- `beat-my-coach`
- `future-prediction`
- `weekly-recalc`
- `weekly-report`

## Regression check

The TS Edge Function source-grep guardrail is implicit — any new
`new Date().toISOString().split("T")[0]` usage will be visible in
PR diffs. Phase 8 cleanup adds a contract test if drift recurs.

Suite: 1569 pass / 0 fail / 2 skip (Dart client tests unaffected).

## Related

- Test #11 B1+B2+M3 (initial IST sweep), Test #11 cleanup,
  Test #12 follow-ups (closed other subsets)
- CLAUDE.md "Hand-rolled 'YYYY-MM-DD' from device-local DateTime.now()" bug class
- `feedback_use_ist_throughout.md` (project memory)
- `feedback_ist_sweep_gap.md` (recurrence pattern — first pass always misses sites)
