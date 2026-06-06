# Alert baseline + Phase-2 threshold tuning — `client_errors_spike`

> **Scheduled:** 2026-06-03 (incident-playbook Phase 2). **Authored/landed:** 2026-06-06
> (the date in the filename is the scheduled cadence date per the MEMORY.md pointer).
> **Diagnose:** `f0b9d3`. **Migration:** `086_alert_client_errors_spike_tune.sql`.

## Why this doc exists
Phase 1 (migration 076, 2026-05-28) shipped the alert-detection crons with
**deliberately low placeholder thresholds** so they would fire during the
baseline week and prove the wiring. Phase 2 was scheduled to re-tune them from
observed data. It came due when **alert #24 paged critical** ("354 rows/hr") for
the founder's own reinstall/restore burst — exposing that the alert was not just
mis-thresholded but **counting the wrong thing**.

## Baseline data (live queries, project `dedsavbjuwgarrhphgnl`)

### 1. The sink is dominated by non-errors
`client_errors` is dual-purpose: it carries both genuine failures and
`error_code='event'`/`'info'` **telemetry breadcrumbs** (restore/sync progress).

| Window | Total rows | `event`/`info` breadcrumbs | Real errors |
|---|---|---|---|
| Last 10 days | 4,258 | 3,472 (**81.5%**) | 786 |
| Last 24 hours | 645 | 381 (59%) | 264 |

Distinct users in the 10-day window: **2** (essentially the founder's dogfooding
+ one secondary). There is no production fleet yet, so **every spike today is the
founder's own testing.**

### 2. Real-error hourly distribution (breadcrumbs excluded, 10 days)
Computed over hours that had ≥1 real error (27 such hours):

| p50 | p95 | p99 | max | mean |
|---|---|---|---|---|
| 8 | **127** | 161 | 161 | 29 |

### 3. What the real errors actually are
Overwhelmingly **transient infrastructure / already-fixed**, not novel app bugs:
- `PostgrestException 57014` — statement timeout on upserts (transient DB load).
- `PostgrestException PGRST002` — schema-cache warmup ("Retrying."), transient.
- `String / ClientException: Software caused connection abort` / `Failed to fetch`
  — client network drops during restore/sync bursts.
- `FunctionException 401 Invalid or expired token` on `push_snapshot` — auth churn.
- `PostgrestException … violates check constraint "wls_reps_realis…"` — **already
  fixed** by migration 085 (the wls per-set reps clamp).
- Genuinely novel client crashes (`_TypeError`, `StateError`, `minified:*`) are
  **< 6 rows each** over 10 days — the real signal is tiny.

## Decisions

### A. Exclude only the unambiguous breadcrumbs
The count now filters `error_code IS DISTINCT FROM 'event' AND … 'info'`. This is
unambiguous (events/info are not failures) and removes the 81.5% inflation.

### B. Rejected: stripping transient/retryable noise in SQL
Tempting (it dominates the real-error set), but **rejected as leaky + brittle**:
the *same logical error* appears under **different `error_code`s** — e.g. a
realtime channel error is logged as both `RealtimeSubscribeException` **and**
`String` (op_type `realtime_stream_weight_logs`). Any code/string denylist in the
cron SQL would miss half its targets and need constant maintenance. The robust
lever is **threshold magnitude**, not classification.

### C. Thresholds — "Tolerant" (founder-chosen 2026-06-06)
| Severity | Old (076) | New (086) |
|---|---|---|
| info (fire floor) | 20 | **100** |
| warn | 50 | **250** |
| critical | 100 | **500** |

Rationale: real-error baseline p95=127, max=161. A reinstall/restore burst
(~150 real errors, mostly transient connection-aborts during the offline-queue
replay) now lands at **info (silent)**; only a genuinely large spike pages
critical. For a pre-launch, solo-dogfooding app this minimizes false pages while
the event-exclusion already removes the bulk of the noise.

Window / cadence / dedup unchanged: 60 min / `*/15` / 1h.

## Verification
- Read-only before/after: old bare 24h count **645** → breadcrumb-excluded **264**.
- Post-apply `cron.job` body: exclusion present, thresholds 500/250/100, old
  20/50 gates gone.
- `test/contracts/alert_thresholds_sync_test.dart` pins yaml↔migration agreement
  + the exclusion.

## Follow-ups (flagged, not in this batch)
1. **Per-user normalization** once real DAU grows — a global hourly count will
   rise with users; revisit then (the alert is global-aggregate today).
2. **Client-side realtime noise** — the app logs `RealtimeSubscribeException`
   with WebSocket close code **1000** (a *normal* closure) as an error, churning
   the `weight_logs` channel. A cheap client fix (don't log code-1000) would cut
   it at the source.
3. **`edge_function_health` + `payment_flow_health`** remain Phase-1 placeholders
   — re-tune when each has its own baseline.
