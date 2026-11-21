---
adr_id: 0002
title: Supabase as backup cloud + AI + community substrate
status: accepted
date: 2026-03-23
deciders: Upendra
---

# ADR-0002: Supabase as backup cloud + AI + community substrate

## Context

ADR-0001 locked Hive as primary storage. We still need a cloud:
- Backup so users can restore on a new device or after uninstall.
- Authentication (email + Google OAuth + phone OTP).
- Edge Functions for AI inference (we can't ship API keys client-side).
- Postgres for community surfaces (`community_reviews`, promotion-aware
  surfaces) and analytics queries.
- Storage for progress photos (PRO feature) and exercise media.

Solo founder, mobile + offline-first, sub-100-user phase. Cost and
operational complexity matter as much as features.

## Decision

**Supabase Postgres + Auth + Edge Functions + Storage.** Single cloud
provider for backup, auth, AI proxy, community data, and Storage. The
fitness-app Supabase project lives at
`dedsavbjuwgarrhphgnl.supabase.co` in `ap-southeast-1`.

Encoded in CLAUDE.md §2 + §2a.

## Alternatives considered

1. **Firebase (Auth + Firestore + Cloud Functions + Storage).** Rejected.
   Three reasons:
   - Firestore is non-relational; community queries (`promote-community-item`,
     ranked-user lookups, referral graphs) want SQL. NoSQL would force
     denormalization + read fan-out that costs more than Postgres at
     this scale.
   - Cloud Functions cold-starts are inconsistent vs Supabase Edge
     Functions (Deno isolates).
   - Vendor lock-in to Google Cloud — harder to move later if needed.

2. **Custom backend (Node/Postgres on Render / Fly.io).** Rejected. Solo
   founder cannot operate Auth, payments-webhook idempotency,
   rate-limiting, and DB migrations all by hand. Supabase bundles these
   plus a usable Studio UI that has saved hours during incidents.

3. **AWS (Cognito + RDS + Lambda).** Rejected. Higher operational
   overhead for the same set of services; Cognito UX is brittle for
   phone OTP; cost at small scale is competitive but DEV TIME is the
   binding constraint, not cents per request.

4. **Hasura / GraphQL Engine.** Rejected. Adds a layer for queries that
   Postgres handles directly; would couple us to a specific GraphQL
   client (and Flutter GraphQL clients are less mature than the
   Supabase Dart client).

5. **Multiple clouds (Auth at A, DB at B, EFs at C).** Rejected. Too
   much glue code; sync points multiply; auditing the trust boundary
   becomes a full-time job. Single-cloud trades vendor lock-in for
   operational simplicity — acceptable at solo founder scale.

## Consequences

Good:
- **Single auth surface.** Email + Google + phone OTP all in one
  Supabase Auth integration.
- **Edge Functions own the AI keys.** Client never sees Gemini /
  Cerebras tokens. AI proxy pattern (ADR-0004) is straightforward.
- **Postgres for analytics.** Ad-hoc queries during audits + incidents
  (the `client_errors` spike analysis, the food_database row count
  audit) are trivial. Hard to overstate this value vs Firestore.
- **Migrations are versioned SQL files.** Reviewable, replayable,
  ledger-tracked (`backups/applied_migrations.json`).
- **Storage bucket policies via RLS.** Same auth/auth model as DB,
  not a separate ACL system.

Bad:
- **Vendor lock-in.** If Supabase pricing changes dramatically or
  reliability regresses, we're stuck. Mitigation: every schema change
  is in `supabase/migrations/`, replayable elsewhere. Edge Functions
  are Deno-portable. Storage paths are simple. ~2-week migration cost
  to leave; not zero, not catastrophic.
- **Two Supabase accounts coexist** (myfitnessjourney1988 = fitness
  app; Upendra-personal = website). Easy to misroute MCP / CLI calls.
  Codified in CLAUDE.md §2a — verify project ID before any operation.
- **Vault / pg_cron quirks.** We've hit `service_role_key` Vault drift
  + cron auth issues (memory `project_audit_2026_05_17_oi_closure_batch`).
  `_shared/cron_auth.ts` helper exists to canonicalize the pattern.

## Status

Active. No serious alternative emerging.

## See also

- CLAUDE.md §2 (Tech Stack), §2a (project identity)
- `docs/architecture/database.md` — 47-table schema
- `supabase/migrations/CLAUDE.md` — migration discipline
- ADR-0001 (Hive primary)
- ADR-0004 (single AI endpoint)
