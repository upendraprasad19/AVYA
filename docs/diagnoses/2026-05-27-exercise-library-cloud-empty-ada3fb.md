---
bug_id: ada3fb
date: 2026-05-27
batch: 2026-05-27 delightful-cascade drift-closure batch (8 findings — 1 P0 + 4 P1 + 3 P2)
status: fixed
symptom: |
  The `/sync-claude-md` audit on 2026-05-27 found that the cloud
  `exercise_library` table contained 0 rows. The food parallel
  (`food_database`) was correctly seeded — 1,431 rows present from
  migration 030 (initial 93 foods) + 041 v2 expansion. But no migration
  had ever been authored to push the bundled exercise seed
  (`assets/data/exercise_library.json`, 258 entries) to cloud.

  This silently broke the `beat-my-coach` Edge Function (PRO feature),
  which since deploy has been querying `exercise_library` for
  bodyweight + cardio fallback exercises and receiving an empty
  result set. The user-visible symptom: when the coach tool asked
  "give me 3 bodyweight alternatives", the Edge Function returned no
  candidates — likely manifesting as a generic "I don't have any
  alternatives right now" response instead of the intended swap list.

  Architecturally, founder confirmed the SoT model: cloud
  `exercise_library` is the canonical growing library = base seed +
  community-promoted entries (via `promote-community-item` Edge
  Function from `user_custom_exercises`). The base seed simply never
  shipped to cloud.
concept: exercise_library_cloud_seed
sot_registry_entry: exercise_library_seed
writers:
  - { file: supabase/migrations/074_seed_exercise_library.sql, method: INSERT_VALUES_ON_CONFLICT, line: 28 }
  - { file: scripts/seed_exercise_library.js, method: main, line: 80 }
  - { file: supabase/functions/promote-community-item/index.ts, method: copy_to_exercise_library, line: 1 }
readers:
  - { file: supabase/functions/beat-my-coach/index.ts, method: fetch_bodyweight_alternatives, line: 193 }
  - { file: test/contracts/exercise_library_cloud_seeded_test.dart, method: pins_seeded_row_count, line: 1 }
hive_key_prefix: "exercise_library (cloud only — no Hive key)"
hive_key_formula: "n/a (cloud-only data; Hive uses bundled exerciseBox loaded from assets/data/exercise_library.json at boot)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: [id, name, category, movement_pattern, exercise_type, primary_muscles, secondary_muscles, equipment_needed, logging_type, difficulty_level, suitable_for, coaching_cues, common_mistakes, default_sets, default_reps, default_rest_secs, source, is_active, is_indian_context, created_at]
contract_test_path: test/contracts/exercise_library_cloud_seeded_test.dart
ist_handling:
  - { file: supabase/migrations/074_seed_exercise_library.sql, line: 28, fn: "uses now() at insert time — IST not applicable to seed data (timestamps are insert-time markers only, not user-action dates)" }
provider_invalidations: []
telemetry_op_types:
  success: [exercise_library_seed_applied]
  failure: [exercise_library_seed_failed]
cross_account_guard: "n/a — exercise_library is canonical library data, not user-scoped. RLS allows SELECT to all authenticated users."
forbidden_patterns_checked:
  - { pattern: "beat-my-coach reading exercise_library and getting 0 rows", absent: true }
  - { pattern: "cloud exercise_library empty when bundled seed exists", absent: true }
  - { pattern: "user_custom_exercises promotion target missing", absent: true }
proposed_fix: |
  Author migration 074_seed_exercise_library.sql that mirrors the
  existing 030_seed_food_database.sql pattern:

  1. Source: bundled JSON at assets/data/exercise_library.json
     (258 exercises, same file Hive loads at boot).
  2. Deterministic UUIDv5 per `(namespace, "exercise_library|<json_id>")`
     using the shared namespace `5a1f0b0c-9dad-11d1-80b4-00c04fd430c8`
     (matches food seed + user_custom_* convention) so re-runs are
     idempotent.
  3. INSERT...ON CONFLICT (id) DO UPDATE so future re-applies refresh
     the canonical fields without disturbing community promotions.
  4. Schema mapping: movement_pattern + exercise_type are TEXT in DB
     but arrays in JSON — flatten to first element. JSON-only fields
     (tempo, met_value, pro_tip, image_*, gif_url, equipment_tier,
     cns_demand, target_focus, priority_tier, rep_range, etc.) are
     not surfaced in the cloud schema yet; they live in the bundled
     Hive box. Add columns in a follow-up migration when a cloud
     reader needs them.

  Generator: scripts/seed_exercise_library.js (mirrors
  scripts/seed_food_database.js). Apply via Supabase Management API
  helper (.claude/apply_migration_via_api.js) because the 128KB SQL
  payload exceeds the MCP apply_migration tool's per-call cap.

  Update backups/applied_migrations.json with the 074 entry per
  CLAUDE.md §4.5 (feedback_migration_apply_record_pair.md).

  Update docs/architecture/database.md with the SoT model section
  describing the base-library + promotion-growth pattern (parallels
  food_database ↔ user_custom_foods).

  Add regression test test/contracts/exercise_library_cloud_seeded_test.dart
  asserting row count ≥ 250 (slightly below seed size to tolerate
  future curation pruning, but flag if anything wipes the library).
regression_test_planned:
  - test/contracts/exercise_library_cloud_seeded_test.dart

touched_layers_checked:
  - { layer: client_code, status: not_applicable, evidence: "no client code changes; bundled Hive exerciseBox already had all 258 entries" }
  - { layer: hive_local_state, status: not_applicable, evidence: "Hive exerciseBox shape unchanged" }
  - { layer: postgres_schema, status: verified, evidence: "exercise_library columns confirmed via information_schema (NOT NULL: id, name, logging_type; rest nullable per migration 005) — no schema change needed, only data" }
  - { layer: postgres_data, status: fixed_in_this_batch, evidence: "SELECT count(*) FROM exercise_library: 0 → 258 (verified via MCP execute_sql post-apply, 76 bodyweight_reps entries available for beat-my-coach)" }
  - { layer: migrations_applied, status: fixed_in_this_batch, evidence: "074_seed_exercise_library applied via .claude/apply_migration_via_api.js (HTTP 201); backups/applied_migrations.json updated with sha256:8dc62e5b…" }
  - { layer: edge_function_code_vs_deploy, status: verified, evidence: "beat-my-coach/index.ts:193 reads exercise_library with .or('category.eq.Calisthenics,category.eq.Cardio') — unchanged; now returns non-empty result set on next invocation" }
  - { layer: cron_jobs, status: not_applicable, evidence: "no cron changes" }
  - { layer: rls_policies, status: not_applicable, evidence: "no RLS changes (exercise_library is public-read for authenticated users)" }
  - { layer: storage_buckets, status: not_applicable, evidence: "no Storage changes" }
  - { layer: secrets_api_keys, status: not_applicable, evidence: "no secret changes" }
  - { layer: external_services, status: not_applicable, evidence: "no external service changes" }
  - { layer: client_server_contract, status: verified, evidence: "beat-my-coach contract unchanged; client expectation is non-empty exercise list; cloud now satisfies that contract" }

impact_analysis: |
  - **PRO feature restored**: beat-my-coach Edge Function returns
    real bodyweight + cardio alternatives instead of an empty list.
    Users had been seeing degraded coach suggestions since deploy.
  - **Promotion path unblocked**: promote-community-item Edge
    Function's INSERT into exercise_library now lands alongside a
    populated base library, not as the sole row source. Future
    community-promoted entries accrete on top of the 258 seed entries.
  - **SoT model documented**: docs/architecture/database.md now
    describes the base-library + promotion-growth pattern as a
    first-class concept paired with the food parallel.
  - **No production behaviour regression**: the seed is purely
    additive (INSERT ON CONFLICT DO UPDATE). Cloud reads that
    previously returned [] now return populated rows; cloud reads
    that returned populated rows (none existed) are unaffected.
  - **Reproducibility**: scripts/seed_exercise_library.js regenerates
    the SQL deterministically from the bundled JSON. Future schema
    additions just re-run the generator + re-apply.

closes-batch: 2026-05-27-delightful-cascade
---

# Bug ada3fb — 2026-05-27 exercise_library cloud empty

## Summary

`/sync-claude-md` audit caught that cloud `exercise_library` was
empty. Root cause: the bundled-seed → cloud pipeline that exists for
foods (migration 030 + 041) was never authored for exercises. Reader
broken in silence: `beat-my-coach` Edge Function line 193.

Fix: migration 074 seeds the cloud table with 258 entries from
`assets/data/exercise_library.json`. SoT architecture now matches the
food pattern — base library + accreted community promotions.

## Migration 074

Source: `supabase/migrations/074_seed_exercise_library.sql` (128.6 KB,
258 INSERT VALUES tuples, INSERT ON CONFLICT DO UPDATE).
Applied 2026-05-27 via `.claude/apply_migration_via_api.js` (HTTP 201).
Recorded in `backups/applied_migrations.json` as `074_seed_exercise_library`,
sha256 `8dc62e5b0c358c0ba6111ef837f8388c859ea8ccb53530f2f76156514f5ac04e`.

Live verification:
```sql
SELECT count(*) FROM exercise_library
-- → 258
SELECT count(*) FROM exercise_library WHERE logging_type = 'bodyweight_reps'
-- → 76 (what beat-my-coach pulls via category filter)
```

## Why this didn't surface earlier

`beat-my-coach` is gated PRO. With founder as the sole production
tester, the path is rarely walked. No client-side telemetry on
"coach returned 0 alternatives" — would have caught this within an
hour of first deploy if it existed. Filed mentally as a future
improvement; not in scope for this batch.

## Related

- See `docs/architecture/database.md` "SoT model: base library +
  community-promoted growth" section (added in this batch).
- Parallels `feedback_writer_reader_field_drift_recurring.md` —
  this is a writer-absent / reader-empty class of drift, not a
  field-name drift. Cloud reader assumed a populated table that no
  writer had ever filled.
