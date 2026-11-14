---
hermes_pass_id: 2026-07-13-hermes-admin-dashboard
ran_at: 2026-07-13T07:40:00+05:30
batch_scope: working-tree-vs-main (branch admin-dashboard; pre-apply)
lens_set: [L1, L14, L21, L22, L23, L31, L37, L40]
agents_dispatched: 8
findings_total: 14
findings_by_severity: { P0: 0, P1: 3, P2: 6, false_alarm: 5 }
verdict: accepted
---

# Hermes Pass (E-pass) — admin-dashboard batch

8 fresh, context-blind Opus lenses, one per charter. Catastrophic-tier
(the `admin-*` Edge Function glob), so Hermes is mandatory.

## Summary
- **The two P0-critical lenses for a cross-user admin gate — L23 (authorization
  defense-in-depth) and L40 (PII) — returned CLEAN.** L23 produced a full
  caller→verdict truth-table with no fail-open on any path, and independently
  confirmed the SQL layer is locked (`REVOKE FROM PUBLIC` + `GRANT service_role`,
  and `grep` proved no `ALTER DEFAULT PRIVILEGES` silently re-grants `authenticated`).
  L40 confirmed no PII in any durable sink except the admin-gated response body
  (intended), flagging the `ADMIN_USER_IDS` config as the sole P0 hinge.
- **L14 (onConflict) + L22 (schema-payload parity): CLEAN** — the `snapshot_date`
  arbiter is a non-partial `UNIQUE NOT NULL`, and the sole NOT-NULL-no-default
  column is supplied.
- 3 P1 + 6 P2 actionable findings, all fixed in-batch (no deferrals). No P0.
- **Ship-blockers: none.**

## Findings by lens

### L1 — writer/reader drift
- **P1 (F1) — engagement/ops "today" tiles read the up-to-24h-stale snapshot, not live.** Growth's tiles were live (`founder_metrics_for_admin_api`), but the read EF never called `founder_metrics_engagement()`/`_ops()` live, so those tabs' tiles read `trend.last` (yesterday's completed snapshot, or 0 before the first nightly run). **FIXED:** the read EF now calls all three functions live and merges them into `current`; the snapshot table backs only the `trend` series. `AdminCurrentMetrics` extended +8 fields; tiles rebind to `current.*`.
- **P2 (F2) — `client_errors_7d` stored + parsed but rendered by no tile (dead field).** **FIXED:** surfaced as an "Errors 7d" ops tile.
- **P2 (F3) — open-alerts tile used the 20-capped list length; trend uses an uncapped count.** **FIXED:** tile + card chip now use the live uncapped `current.openAlertsCount`; the feed shows "showing latest N of M" when truncated.
- **P2 (F4) — expiry list not scoped (all-of-history).** **FIXED** by the L21/L37/L40 shared bound (below) — the 30-day floor makes "expired" = recent lapses.
- Clean: all 30+ growth/revenue/expiry/alert field chains traced name+semantic-identical end-to-end. Positional `select * from private.founder_metrics()` wrapper verified column-order-identical to migration 093.

### L14 — onConflict natural-key live arbiter — CLEAN
`snapshot_date` is a column-level (non-partial) `UNIQUE NOT NULL` (migration 102:24); the upsert payload always supplies it; `id` (identity) + `computed_at` (`default now()`) self-populate. No 42P10, no 23502, no duplicate-row corruption. (Cosmetic nit noted, not actioned: `computed_at` isn't refreshed on the DO-UPDATE retry path.)

### L21 — Edge Function semantic correctness
- **P1 — `getUser` was outside the try** → a transient GoTrue/network reject bubbled out of `serve` as a bare CORS-less 500 (opaque error on the web dashboard). **FIXED:** identity resolution wrapped in a fail-CLOSED try returning sanitized `serverError` (still can't fail open — an exception can't reach the admin check).
- **P2 — expiry query unbounded** (dup of L1-F4 / L37 / L40). **FIXED** (shared bound).
- Clean: no TDZ, all awaits present, `firstError` catches all Promise.all legs, `.single()` is correct (all founder_metrics_* are single-row no-FROM SELECTs), no raw-error leak, correct status codes.

### L22 — schema-vs-payload parity — CLEAN
Full per-column nullability table: only `snapshot_date` is NOT-NULL-no-default and it's supplied; every payload key maps to a real column; every `.select()`/filter column exists in the verified live set.

### L23 — authorization defense-in-depth (service-role) — CLEAN (no fail-open)
Full truth-table: anon-key/expired/invalid/non-admin/empty-allowlist/`getUser`-throw all resolve to 401/403/500 fail-closed; service-role short-circuits correctly. Privileged reads are all after the gate. SQL layer independently locked (no `ALTER DEFAULT PRIVILEGES` undermining the REVOKE). More robust than the `promote-community-item` precedent, not weaker. **Sole P0 hinge: `ADMIN_USER_IDS` must contain only the founder's UUID (config, not code).**

### L31 — cron efficiency — 2 fixed, rest false-alarm/low
- **P2 (F2/F3) — `ai_coach_interactions.created_at` + `client_errors.created_at` had no leading index** (all existing indexes are user_id-leading → seq scan on a bare `created_at` filter). Elevated because the live tiles now run these per page-load. **Verified live via `pg_indexes` + FIXED:** added `idx_client_errors_created` + `idx_ai_coach_interactions_created` (migration 102, `IF NOT EXISTS`).
- **FALSE_ALARM (F1) — streaks DISTINCT ON:** the agent claimed no composite index, but live `pg_indexes` shows `uq_streaks_user_week (user_id, week_start)` — the DISTINCT ON scans it backward. No index needed. (Verified, not trusted.)
- **Low, not actioned (F4) — `alerts WHERE resolved_at IS NULL` seq scan:** `alerts` is tiny + slow-growing; a partial index is a genuinely-negligible micro-opt with no growth curve. Noted.

### L37 — empty/null-shape readers
- **P2 — `DateTime.parse` on a non-null string** could throw `FormatException` (unreachable today — all sources are Postgres timestamptz / server ISO — but a latent crash class). **FIXED:** all three sites → `DateTime.tryParse(raw) ?? sentinel`.
- **Not actioned (FALSE_ALARM) — `_int`/`_double` throw on a JSON *string* value:** unreachable — every field is `bigint` (JSON number). Would only bite if a future migration makes a column `numeric`/`decimal` (PostgREST returns those as strings). Documented latent; revisit if a numeric column is added. Not a live bug — no fix (defending every accessor against a can't-happen type is over-engineering).
- Clean: every `.last`/`.first` guarded by `isNotEmpty`; `WardSpark` guards `length < 2` + divide-by-zero; all empty maps/lists render `EmptyState`; `current:null` double-defended (`.single()` 500s on 0 rows + `?? const {}`).

### L40 — PII / privacy — substantially CLEAN
- Response `subscriptions_expiring` carries user emails — the feature's purpose, admin-gated (L23 verified holds). The 30-day bound (L1-F4 fix) also minimizes the exposed set.
- `console.warn` logs a rejected caller's UUID (pseudonymous, not email) — acceptable per charter.
- No PII in `cron_call_log`, the snapshot table (counts only), or any client log sink. No `ProviderObserver`, no `toString()` override → no accidental stringify leak.

## Founder triage
Self-triaged in auto mode (catastrophic-tier discipline). 0 P0. The two
security-critical lenses (L23/L40) clean. All 3 P1 + all actionable P2 fixed
in-batch; the 3 not-actioned items are verified FALSE_ALARM (streaks index),
unreachable-latent (numeric-column parse), or negligible-micro-opt on a tiny
table (alerts index) — none is a deferred bug. Re-analyze + parsing test green
after fixes. Successive reviews surfaced refinements, not fundamental defects
(core auth/schema/writer-reader were sound) → converged, not "split it". Verdict: accepted.

## Addendum — post-apply P0 that L23's static grep missed (diagnose a9d3f1)

L23 rated the SQL authorization layer CLEAN, having grepped all migrations for
`ALTER DEFAULT PRIVILEGES` (none) and confirmed `REVOKE FROM PUBLIC` + `GRANT
service_role`. **The live post-apply privilege check (§6 tier 8) then found the
three functions were still anon/authenticated-EXECUTE-able** — Supabase's
platform-level default privileges grant EXECUTE on new public functions DIRECTLY
to those roles (not via PUBLIC, and not in any migration file, so invisible to a
source grep). Since they are SECURITY DEFINER, that was an anon-readable
business-metrics leak. Fixed in-batch by migration 103 (`REVOKE EXECUTE ... FROM
anon, authenticated`); live-verified proacl now `{postgres, service_role}`.
This is the lesson that a static review CANNOT substitute for the live
privilege check on a service-role-only public SECURITY DEFINER function — the
verdict stands (converged: P0 caught + fixed before go-live, real-world exposure
none), but L23's "SQL layer independently locked" claim was over-confident.
See `docs/diagnoses/2026-07-13-admin-metrics-anon-executable-a9d3f1.md`.

## Action items
- [x] L1-F1 live current (EF + model + tabs + test + SoT)
- [x] L1-F2 surface client_errors_7d
- [x] L1-F3 uncapped open-alerts count + truncation note
- [x] L1-F4 / L21 / L37 / L40 expiry window bounded [now-30d, now+30d]
- [x] L21 getUser inside fail-closed try
- [x] L31 two created_at indexes (verified live-missing)
- [x] L37 DateTime.tryParse hardening
- [ ] (operational, at deploy) confirm `ADMIN_USER_IDS` = founder UUID only — the L23/L40 P0 hinge
