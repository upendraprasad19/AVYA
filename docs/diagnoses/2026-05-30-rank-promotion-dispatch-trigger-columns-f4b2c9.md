---
bug_id: f4b2c9
date: 2026-05-30
batch: web-e2e-2026-05-30
status: fixed
symptom: >
  Surfaced during live web E2E. After onboarding, amar@gmail.com had ZERO
  rank_promotions rows (not even the SD2 floor) and the browser console showed
  "[RankService.evaluateAndPromote] PostgrestException(column \"message\" of
  relation \"client_errors\" does not exist, 42703)". Every rank_promotions
  INSERT aborts → no user can be promoted → user_profile.current_rank_code
  never advances. The core "Become a Lt" rank ladder is broken.
concept: rank_monotonic_current_code
sot_registry_entry: rank_monotonic_current_code
blast_radius: catastrophic
writers:
  - { file: supabase/migrations/078_fix_dispatch_proactive_coach_promotion_columns.sql, line: 46 }
  - { file: lib/core/services/rank_service.dart, method: evaluateAndPromote_upsert, line: 121 }
readers:
  - { file: lib/core/services/rank_service.dart, method: evaluateAndPromote_denorm_update, line: 157 }
hive_key_prefix: "userBox['profile']['current_rank_code']"
hive_key_formula: "user_profile.current_rank_code denormalizes MAX(rank_promotions.rank_code by ladder ordinal)"
sync_methods: [syncProfileNow]
restore_methods: [restoreFromCloudForUser]
cloud_table: rank_promotions
cloud_columns: [user_id, rank_code, achieved_at, trigger_type, trigger_metadata]
contract_test_path: test/contracts/dispatch_proactive_coach_promotion_columns_test.dart
ist_handling: []
provider_invalidations: [userProfileProvider]
telemetry_op_types:
  success: [proactive_coach_promotion_dispatched]
  failure: [proactive_coach_promotion_dispatch_failed, rank_service_evaluate_and_promote]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "client_errors(... message, severity ...) in dispatch trigger", absent: true }
  - { pattern: "NEW.created_at in dispatch_proactive_coach_promotion", absent: true }
proposed_fix: >
  Rewrite private.dispatch_proactive_coach_promotion() (AFTER INSERT trigger on
  rank_promotions) via migration 078. Three defects: (1) it referenced
  NEW.created_at — rank_promotions has no created_at column (real timestamp is
  achieved_at, NOT NULL) → resolution failed → jumped to WHEN OTHERS; (2) all
  three client_errors inserts used columns message + severity which do not
  exist (real: error_message, error_code) and omitted NOT NULL client_version +
  platform; (3) the WHEN OTHERS handler re-raised the same bad insert, so the
  exception escaped the trigger and rolled back the rank_promotions row. Fix:
  use NEW.achieved_at directly; all client_errors inserts use error_code /
  error_message / client_version ('server-trigger') / platform ('server'); wrap
  the handler's telemetry insert in a nested BEGIN/EXCEPTION ... NULL so a
  telemetry failure can NEVER again abort the promotion. Recording the
  promotion must always win over dispatching its celebration.
regression_test_planned:
  - test/contracts/dispatch_proactive_coach_promotion_columns_test.dart
touched_layers_checked:
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "information_schema 2026-05-30: rank_promotions has no created_at (cols id/user_id/rank_code/achieved_at/trigger_type/trigger_metadata); client_errors has no message/severity (real: error_code NOT NULL, error_message, op_type, client_version NOT NULL, platform NOT NULL)" }
  - { tier: 7, layer: cron_trigger, status: fixed_in_this_batch, evidence: "trg_dispatch_proactive_coach_promotion is AFTER INSERT FOR EACH ROW on rank_promotions; function rewritten via migration 078 (apply_migration success)" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live rollback-txn: INSERT rank_promotions under OLD fn -> 42703 (handler line 50); under NEW fn (applied) -> succeeds + 1 proactive_coach_promotion_dispatched client_errors row; both rolled back. amar had 0 rank_promotions pre-fix." }
  - { tier: 5, layer: migrations_applied, status: fixed_in_this_batch, evidence: "078 applied via MCP apply_migration; backups/applied_migrations.json updated (sha256:f997449a...)" }
impact_analysis: >
  AFTER INSERT trigger on rank_promotions raised on every insert and, because
  its exception handler re-raised, aborted the originating INSERT. So no rank
  promotion could persist and evaluateAndPromote aborted before updating the
  user_profile.current_rank_code denorm. Currently low absolute impact — the DB
  is pre-launch with 5 historical rank_promotions across 4 test users (those
  rows predate the breakage) and only 1 profile above the SD2 floor — but the
  bug would break promotions for every real user post-launch, i.e. the core
  "Become a Lt" wedge. 3rd instance of the client_errors wrong-column class:
  diagnose 9e1d4c (2026-05-29) fixed the Edge Function logTelemetry TypeScript
  but missed this Postgres trigger function; this is also a cross-table column
  drift (§2.20, NEW.created_at). The client shouldPromote logic + rank year-sim
  tests stayed green because they never exercise the live trigger. Fix is a
  CREATE OR REPLACE (no schema/data change, no lock) — instantly reversible to
  the prior body archived here.
---

# f4b2c9 — rank-promotion dispatch trigger wrote non-existent columns, aborting every rank_promotions insert

## What happened
`private.dispatch_proactive_coach_promotion()` (AFTER INSERT FOR EACH ROW on
`rank_promotions`) referenced columns that do not exist. On every insert:
`NEW.created_at` (no such column on rank_promotions) failed → the `WHEN OTHERS`
handler ran `INSERT INTO public.client_errors(user_id, op_type, message,
severity)` → `message`/`severity` do not exist (42703) → the handler's own
exception escaped → the `rank_promotions` INSERT rolled back. Result: no
promotion ever persisted. Live proof: amar onboarded with **zero**
`rank_promotions` rows and the console logged the 42703 from
`RankService.evaluateAndPromote`.

## Root cause
Two overlapping wrong-reference classes in one function:
- **§2.20 cross-table column drift:** `NEW.created_at` (column lives nowhere on
  rank_promotions; the timestamp is `achieved_at`).
- **client_errors wrong-column class (3rd instance):** `message`/`severity`
  instead of `error_message`/`error_code`, plus the omitted NOT NULL
  `client_version`/`platform`. Diagnose 9e1d4c fixed the *Edge Function*
  telemetry but never touched this *Postgres trigger*.

The fatal amplifier: the `WHEN OTHERS` handler re-ran the same broken insert, so
a telemetry failure became a promotion-data failure.

## Fix (migration 078)
- `NEW.achieved_at::text` (NOT NULL) replaces `COALESCE(NEW.achieved_at,
  NEW.created_at)`.
- All `client_errors` inserts use real columns: `error_code`, `error_message`,
  `client_version='server-trigger'`, `platform='server'`.
- The handler's telemetry insert is wrapped in a nested `BEGIN/EXCEPTION ...
  NULL` so it can never again abort the promotion.

## Verification
Live rollback-transaction (2026-05-30): under the OLD function an
`INSERT INTO rank_promotions` raised 42703 (from handler line 50); after
applying migration 078 the same insert **succeeds** and writes one
`proactive_coach_promotion_dispatched` `client_errors` row — both rolled back,
zero pollution. Post-apply rollback-txn against the live deployed function:
insert succeeds.
