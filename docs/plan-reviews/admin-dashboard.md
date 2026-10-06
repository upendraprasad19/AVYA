---
branch: admin-dashboard
blast_radius: catastrophic
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/052a3098df6c-review.md
hermes: accepted
hermes_report: docs/audit/2026-07-13-hermes-admin-dashboard.md
recorded_at: 2026-07-13T07:50:00+05:30
---

# Plan-review record — admin-dashboard (founder-only business-metrics dashboard)

Keystone record for CLAUDE.md §4.12. Blast-radius **catastrophic** — the
`supabase/functions/admin-*/**` glob classifies `admin-dashboard-data` as
catastrophic because a fail-open in its `ADMIN_USER_IDS` gate would leak every
user's subscription data (emails, expiry) to a non-admin. Catastrophic requires
`bpass: accepted` + `hermes: accepted`, both satisfied below.

## Review rounds (3 independent, context-blind, ground-truth-verified)

1. **Pre-execution independent adversarial plan review** — dispatched during
   Plan Mode. Caught the single most important design error: the new SQL
   functions were planned for the `private` schema (mirroring
   `private.founder_metrics()`), which PostgREST does NOT expose to `.rpc()`
   (`supabase/config.toml` `[api] schemas = ["public","graphql_public"]`). I
   personally verified the finding against source (read config.toml, migration
   028, grepped every `.rpc(` in the repo — none targets `private.*`) before
   accepting it, then rewrote the plan + migration 101 to use `public`. Also
   caught a 5th hardcoded-price location (`_shared/captain_manual.ts`) for the
   deferred pricing project. Wrong design corrected BEFORE a line of code.

2. **B-pass (`/code-review`)** — a fresh context-blind Sonnet reviewer over the
   full implementation diff, 6 lenses incl. the catastrophic admin-gate.
   **Admin-gate lens returned CLEAN (full path trace).** 5 findings; 4 actionable
   fixed in-batch (engagement tile mislabel, `_severityTone` `'warn'` vocabulary,
   cold-tab `/admin` limitation documented, stale SoT line-range), 1 terminal
   apply-time sequencing item (`live_schema_columns.json` regen). Record:
   `docs/reviews/052a3098df6c-review.md` (verdict: accepted).

3. **Hermes E-pass (`/hermes-pass`)** — 8 fresh context-blind Opus lenses
   (L1/L14/L21/L22/L23/L31/L37/L40), mandatory for catastrophic tier. **The two
   P0-critical lenses — L23 (authorization defense-in-depth) and L40 (PII) —
   returned CLEAN** (full caller→verdict truth-table, no fail-open; SQL layer
   independently locked with no `ALTER DEFAULT PRIVILEGES` undermining the
   REVOKE; no PII in durable sinks). 3 P1 + 6 P2, all actionable fixed in-batch
   (live-current tiles, bounded expiry window, `getUser` fail-closed, 2 verified-
   missing indexes, `DateTime.tryParse` hardening). 0 P0. Record:
   `docs/audit/2026-07-13-hermes-admin-dashboard.md` (verdict: accepted).

## Ground-truth verification (verified against LIVE state, not prose)

- Every column referenced by migration 101's SQL bodies + the read EF's
  `.from()/.select()` calls verified present in live `information_schema`
  (`workout_logs.date`, `nutrition_logs.date`, `ai_coach_interactions.created_at`,
  `streaks.{user_id,week_start,is_streak_maintained}`, `client_errors.created_at`,
  `alerts.{resolved_at,suggested_action,...}`, `cron_call_log.{started_at,status}`,
  `subscriptions.{plan,status}`, `users.{id,email,subscription_expires_at}`).
- **Live-data verification caught a real bug the reviews would have shipped:**
  `subscriptions.plan` distinct values are `{monthly, referral_trial}` (not the
  assumed `monthly/yearly`) — 6 of 7 active subs are `referral_trial`, which the
  original code counted nowhere → the Revenue tab would have shown "1 monthly, 0
  yearly" against 7 active subs with 6 unexplained. Fixed by `bucketActivePlans`
  (monthly/yearly/trial/other, reconciles to active).
- Dry-ran migration 101's exact function bodies against live data — all execute,
  values plausible (`client_errors_7d: 323`, `open_alerts: 28` matching the live
  alert feed, `on_streak: 1`).
- Verified L31's index claims via live `pg_indexes` — corrected the Hermes agent
  (streaks composite `uq_streaks_user_week` DOES exist; agent claimed it didn't).
- Verified the bounded expiry window `[now-30d, now+30d]` loses no current data
  (all 6 expired subs lapsed within 30d).

## Convergence

Successive reviews surfaced REFINEMENTS (staleness, bounds, hardening, indexes),
not fundamental defects — the core auth/schema/writer-reader design was sound
across L23/L40/L14/L22. This is convergence, not a "split it" signal (§4.12.1).
`flutter analyze` + the parsing contract test are green after all fixes. Deno
tests are hand-verified + hand-traced (no local Deno binary); CI's Deno job is
the executable backstop.

## Verdict: converged

Gated next (NOT part of this record): explicit founder go for the live migration
apply + Edge Function deploy (§4.3 — plan approval ≠ deploy approval), then the
apply-time `applied_migrations.json` + `live_schema_columns.json` regen, then
`--no-ff` merge to main.
