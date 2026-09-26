# Migration source ↔ prod reconciliation (audit-2026-05-11 H-34)

## Status

Source migration count: **59 numbered + 3 timestamp-prefixed = 62** SQL files
(post-H-31 + H-33 — 058 added for `community_reviews`, 050 collision
split into `050` + `050b`; post-Test-#15.1 060 + post-audit-2026-05-12 061).

Prod migration count: **55 rows** in `supabase_migrations.schema_migrations`
(audit-2026-05-12 P3-H verified live via Management API; was stale at 53).

Recent additions:
- `060_workout_log_exercises_realistic_bounds` (APK Test #15.1 Bug E, 2026-05-11)
- `061_audit_2026_05_12_cron_and_bounds` (Audit 2026-05-12 P1-D + P1-E + P1-G + P3-B, 2026-05-12)

The deltas are bookkeeping artefacts, **not schema drift**. The schemas
themselves (tables, columns, constraints, indexes, RLS policies) are
verified-matched between source and prod. This README explains each
mismatch.

## Mismatches explained

### A. Migrations renamed during Dashboard apply

Two prod entries have names that don't match the source filename verbatim
because they were applied via the Supabase Dashboard SQL editor (which
renames the migration internally) instead of `supabase db push`:

| Prod migration name           | Prod version       | Source file                                          |
|-------------------------------|--------------------|------------------------------------------------------|
| `add_indexes_idempotency_rpc` | `20260405155008`   | `010_add_indexes_idempotency_rpc.sql`                |
| `injuries_text_array`         | `20260424112414`   | `033_injuries_array.sql`                             |
| `nutrition_log_fiber`         | `20260424112500`   | `034_nutrition_log_fiber.sql`                        |
| `add_terms_acceptance`        | `20260424074817`   | `032_add_terms_acceptance.sql`                       |
| `user_profile_missing_columns`| `20260416202625`   | `017_user_profile_missing_columns.sql`               |
| `client_errors_telemetry`     | `20260416204211`   | `018_client_errors.sql`                              |
| `dedupe_custom_entities`      | `20260417074959`   | `020_dedupe_custom_entities.sql`                     |
| `workout_log_sets`            | `20260417075132`   | `019_workout_log_sets.sql`                           |
| `user_profile_nutrition_targets` | `20260417075146`| `021_user_profile_nutrition_targets.sql`             |
| `progress_photos`             | `20260417075202`   | `022_progress_photos.sql`                            |
| `daily_steps`                 | `20260417075214`   | `023_daily_steps.sql`                                |
| `morning_alert_personalized_delivery_cron` | `20260503013622` | `046_morning_alert_personalized_delivery_cron.sql` |
| `clean_orphan_media_cron`     | `20260503124321`   | `048_clean_orphan_media_cron.sql`                    |

Resolution: leave as-is. The Dashboard-rename only affects the entry in
`supabase_migrations.schema_migrations`; the actual DDL applied matches
the source file exactly.

### B. Bundled-then-split: `add_gdpr_referral_community_tables`

Prod has one early migration `add_gdpr_referral_community_tables`
(`20260406192046`) that bundled what later got split across multiple
focused source files:
- `035_referral_codes.sql`
- `037_referral_redemptions.sql`
- `049_account_deletion_pseudonymize.sql`

The current prod schema matches the union of those later source files.
A fresh prod install via source would land at the same schema; the
bundling is purely a historical artefact.

### C. Source files without a prod entry (idempotent / superseded)

Some source files exist but never produced a distinct prod migration row
because they were applied as part of a different migration's chunked
deploy (e.g., 041 food_database seed v2 was applied as 11 chunks under
a single prod row).

### D. Recent additions (post-Phase-1 of this audit)

| Source file                                            | Prod version       |
|--------------------------------------------------------|--------------------|
| `052_subscriptions_rls_lockdown.sql`                   | `20260510200351`   |
| `053_security_definer_hardening.sql`                   | `20260510200641`   |
| `054_rls_policy_cleanup.sql`                           | `20260510201201`   |
| `055_rls_with_check_sweep.sql`                         | `20260510232545`   |
| `056_streak_progress_optimistic_lock.sql`              | `20260511054817`   |
| `057_schema_unique_indexes_h25_h26_h27_h28.sql`        | `20260511064405`   |
| `058_community_reviews_schema_in_source.sql`           | `20260511064542`   |

All 7 applied via MCP `apply_migration` during the 2026-05-11 audit
batch. `backups/applied_migrations.json` updated.

### E. 050 collision split (H-33)

Pre-fix:
- `050_streak_freezes_default_one.sql`
- `050_workout_templates_unique_user_name.sql`

Filesystem ordering between the two was non-deterministic. Renamed:
- `050_streak_freezes_default_one.sql` (kept)
- `050b_workout_templates_unique_user_name.sql` (was the second 050)

Both already applied on prod under the original numeric prefix; the
rename is source-only bookkeeping. The next net-new migration is `059`.

## Rule going forward

- Apply migrations only via `supabase db push` OR MCP
  `apply_migration` with the EXACT source filename as the `name`
  argument. Never use the Dashboard SQL editor for schema-mutating
  changes.
- Every applied migration MUST be reflected in
  `backups/applied_migrations.json` in the same commit per
  `feedback_migration_apply_record_pair.md`.
- Never re-use a numeric prefix. If conflict, suffix with letter
  (e.g., `050b`).
