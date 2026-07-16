---
scope: admin
parent: ../../../CLAUDE.md
created: 2026-07-13
updated: 2026-07-13
status: active
---

# Admin Dashboard — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/admin/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/features/admin/` is the **founder-only business-metrics dashboard** — a
web-only screen reachable at `/admin` on `app.icanbefitter.com`. It is NOT one
of the 5 tab screens; there is no bottom-nav entry and no in-app link anywhere.
The founder navigates to the URL directly after signing in.

Files:

- `screens/admin_dashboard_screen.dart` — `DefaultTabController(length: 4)` with
  a `WardLetterhead` header + a `TabBar` over 4 tabs. `dataAsync.when(...)`
  renders the standard loading (skeleton) / error / empty contract.
- `widgets/growth_tab.dart` — total users, signups today/7d/30d, PRO/free split,
  30-day sparkline trends.
- `widgets/engagement_tab.dart` — workouts / food logs / AI-coach messages / streak
  trends.
- `widgets/revenue_tab.dart` — active-sub split, derived MRR (see caveat below),
  and the founder-requested **expired / expiring-7d / expiring-30d** subscription
  buckets.
- `widgets/ops_health_tab.dart` — `client_errors` trend, the existing `alerts`
  feed (reused as-is), cron-failure trend.
- `models/admin_dashboard_data.dart` — defensively-parsed response model for the
  `admin-dashboard-data` Edge Function (every field null-safe; the trend array is
  empty/near-empty for the first ~30 days after ship).
- `repositories/admin_dashboard_repository.dart` — thin wrapper around
  `SupabaseService.callFunction('admin-dashboard-data')`; throws
  `AdminNotAuthorizedException` on a 403 so the screen can tell "not the founder"
  apart from a transient network error.
- `providers/admin_dashboard_provider.dart` — `FutureProvider<AdminDashboardData>`
  watching `authUserIdTokenProvider` for auth-change rebuilds.

## The Hive-first exception (the reason this file exists)

Root CLAUDE.md §4.4 rule 1 mandates **Hive-first for ALL reads/writes** — every
feature reads local Hive first, never blocks UI on Supabase. **This one feature
is a deliberate, documented exception.** There is no meaningful per-device copy
of cross-user aggregate business data (total users across ALL accounts, MRR,
every subscription's expiry) — Hive on the founder's device only ever holds the
founder's OWN rows, which is the wrong dataset entirely. So `adminDashboardProvider`
is the single provider in the app that talks directly to a Supabase Edge Function
instead of reading Hive. It still uses the Repository pattern (rule 4) and the
standard loading/error/empty screen contract (rule 13) — only the Hive-first half
of rule 1 is waived, and only here. A future audit or gate should find THIS
record, not just the plan file, when it asks "why does an admin provider skip
Hive?". SoT registry concept: `admin_dashboard_metrics_snapshot`.

## Security is server-side — the client guards are UX only

- **Real gate:** `admin-dashboard-data`'s `ADMIN_USER_IDS` allowlist (same pattern
  as `promote-community-item`, diagnose `7ad0c5`). A caller whose authenticated
  `user.id` is not in the allowlist gets a 403 with no data. Unset env var →
  fail-secure, reject everyone.
- **Platform guard (UX):** `app_router.dart`'s `_authRedirect` bounces `/admin` to
  `/home` on any non-`kIsWeb` platform. This is defense-in-depth, not the boundary
  — the `/admin` route is registered unconditionally (unlike `/dev`, which is
  `kDebugMode`-gated and compiled out of release) because it must be live in the
  production web build.
- Never add an inline `isPro` / client-side identity check as the *gate*. The
  server 403 is the gate; the screen just renders `AdminNotAuthorizedException`
  as a clean "not authorized" `EmptyState`.

## Rollback & kill-switch (catastrophic-tier requirement)

- **Kill-switch (instant, no deploy):** unset the `ADMIN_USER_IDS` Edge Function
  secret → `admin-dashboard-data` fail-secure 403s **every** caller → the
  dashboard is dark for everyone. This is the fastest way to pull the feature if
  the gate is ever suspect. `cron.unschedule('compute_admin_metrics_daily')`
  separately stops the nightly snapshot writes.
- **Migration rollback:** both migrations carry inline reverse DDL (commented at
  file end). 102 → `cron.unschedule` + drop the two `created_at` indexes + drop
  `compute_admin_metrics_function_url()` + drop `admin_metrics_daily`. 101 → drop
  the three `public.founder_metrics_*()` functions (leave `private.founder_metrics()`
  untouched — it predates this batch).
- **Edge Function rollback:** both functions are NEW (not replacing an existing
  one), so a bad deploy can't break existing behavior; roll back via the
  `/edge-function-deploy-rollback` skill (SHA-pinned) or simply leave them
  undeployed. The client degrades to an `ErrorState` if the function is absent.

## Caveats baked into the UI

- **Derived MRR is computed, not stored** — active-plan counts × current list price.
  Accurate only while `promo_code_uses` has 0 rows; the Revenue tab labels it as
  derived. If discounting ships, this number drifts and must move server-side.
- **Current price is read-only.** Editable pricing was explicitly scoped OUT of
  this batch (price is hardcoded in 5 places incl. `_shared/captain_manual.ts`,
  feeding the payment-security `derivePlanFromAmount` path). See the plan's
  "explicitly out of scope" section before touching it.
- **Trends need history.** One snapshot row accrues per day (cron
  `compute_admin_metrics_daily`, 23:45 IST). Every trend card degrades to a
  "not enough history yet" line when `< 2` points exist — do not assume a full
  30-day series on day one.

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Adding a bottom-nav entry or in-app link to `/admin` | The dashboard is intentionally URL-only + web-only + server-gated. A visible entry would invite non-founder taps that then 403. | this file + plan |
| Registering `/admin` inside `if (kDebugMode)` | It must be reachable in the PRODUCTION web build. `/dev` is debug-only; `/admin` is not. Access control is the server allowlist, not the build mode. | `lib/core/router/app_router.dart` |
| Treating a 403 as a crash / generic error | `AdminNotAuthorizedException` renders a clean "Not authorized" `EmptyState`; only non-auth errors get the retry `ErrorState`. | `admin_dashboard_screen.dart` |
| Reading a snapshot `*_today` field as a live current value | The snapshot is up to 1 day stale. Current-state stat tiles (e.g. open-alerts count) read the LIVE list length, not the trend's snapshot field, so the tile and the list below it never disagree. | `ops_health_tab.dart` |
| Expecting the bare `/admin` *path* to reach the dashboard | The app uses Flutter's default **HashUrlStrategy** (no `setUrlStrategy` anywhere), so the `/admin` GoRoute is reachable only via the fragment `#/admin`. `app.icanbefitter.com/admin` works because `vercel.json` redirects `/admin` (+ `/admin/`) → `/#/admin`. Don't remove that redirect, and don't assume path routing. Diagnose `b3f9a1`. | `vercel.json` redirects + `app_router.dart` |
| Cold-tab `/admin` bounces to `/home` | FIXED (diagnose `b3f9a1`, was B-pass Finding 4). `_authRedirect` now returns `/restoring?next=%2Fadmin` for a cold `/admin`, and `RestoringScreen.resolveRestoreDestination` (allowlist `{'/admin'}`, default `/home`) honors it at the three `context.go` sites. The `next` param is allowlisted so it can't be a general open-redirect. Only `/admin` is threaded — every other gated route still lands on `/home`. | `app_router.dart` `_authRedirect` + `restoring_screen.dart` |
| Using `warning`/`high`/`medium` as an `alerts.severity` value | The live vocabulary is `info`/`warn`/`critical` (migration 076 CHECK). `warn` (not `warning`) is what every alert cron writes — map it explicitly or warnings render as neutral (B-pass Finding 2). | `ops_health_tab.dart` `_severityTone` |

## Tests pinning the rules here

- `test/contracts/admin_dashboard_data_parsing_test.dart` — defensive parse of the
  Edge Function response (complete / empty-trend / missing-keys / null-field cases).
- `supabase/functions/admin-dashboard-data/index_test.ts` — `isAuthorizedAdminCaller`
  fail-secure truth table, `bucketSubscriptionsByExpiry`, `computeDerivedMrr` (Deno).
- `supabase/functions/compute-admin-metrics-daily/index_test.ts` — `buildSnapshotRow`
  merge/purity (Deno).
- `test/contracts/restoring_next_destination_test.dart` — `RestoringScreen.resolveRestoreDestination`
  allowlist (`/admin`→`/admin`; every other/external value → `/home`). Pins the cold-load
  `/admin`-reachability fix (diagnose `b3f9a1`).

## See also

- `docs/sot_registry.yaml` — concept `admin_dashboard_metrics_snapshot`.
- `docs/operations/CRON_REGISTRY.md` — `compute_admin_metrics_daily` row.
- `docs/operations/SECRET_INVENTORY.md` — `ADMIN_USER_IDS` row.
- `supabase/functions/CLAUDE.md` — Edge Function deploy + auth pattern.
- `lib/shared/widgets/wardroom/CLAUDE.md` — palette + primitives used by the tabs.
