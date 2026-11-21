# Phase A · Coverage Matrix & Gap Analysis — 2026-05-16

## Existing audit infrastructure inventory

| Asset | Count | Notes |
|---|---:|---|
| `docs/sot_registry.yaml` concepts | **36** | Plan estimate said 33; registry has grown 3 since CLAUDE.md was written. |
| `test/contracts/*.dart` | **114** | Plan estimate said 25; massively larger. Many writer/reader pairs already pinned. |
| `scripts/check_*.dart` | **12** | Plan estimate said 17; remaining 5 build gates use other mechanisms. |
| `docs/audit/` historical reports | 13 markdown files across 4 dated dirs (2026-05-04, 2026-05-11, 2026-05-12, AUDIT_PLAYBOOK.md, 2026-05-16/) | |
| `docs/diagnoses/` files | (sample later in Phase B) | |

### Existing 12 gate scripts (do NOT duplicate in Phase E)
1. `check_apk_size_within_bounds.dart`
2. `check_bugfix_commits_have_diagnose.dart`
3. `check_edge_function_payloads.dart`
4. `check_exlog_key_canonical.dart`
5. `check_generic_error_telemetry.dart`
6. `check_id_injection_on_get.dart`
7. `check_migrations_applied.dart`
8. `check_naming_audit.dart` — **cluster 1 already partially covered**
9. `check_onconflict_live_arbiter.dart` — **cluster 4 partly covered**
10. `check_sot_registry_completeness.dart` — **cluster 2 partly covered**
11. `check_sync_fanout.dart` — **cluster 5 partly covered**
12. `check_writeservice_contracts.dart` — **cluster 3 partly covered**

### Coverage gaps (NEW deliverables needed in Phase E)

| Cluster | Existing | Gap |
|---|---|---|
| 1 Naming | `check_naming_audit.dart` + `naming_audit_test.dart` | Verify breadth — does it cover directory-structure drift + reserved-domain glossary collisions? |
| 2 SoT parity | `check_sot_registry_completeness.dart` + `sot_registry_completeness_test.dart` | Inverse check: writer/reader pairs NOT in registry that should be |
| 3 Hive contracts | `check_writeservice_contracts.dart` + 25+ `*_writer_to_reader_test.dart` files | Per-prefix card doc (`hive-prefixes.md`) does not exist yet |
| 4 DB columns | `check_onconflict_live_arbiter.dart` | **Column-population matrix doesn't exist**. NEW: `db-coverage.csv` |
| 5 Sync fan-out | `check_sync_fanout.dart` + `sync_fanout_contract_test.dart` + `restore_completeness_writes_test.dart` | **`applied_migrations_parity_test.dart` does not exist** |
| 6 AI architecture | `ai_proxy_day_injection_test.dart` + `edge_function_*` tests + tool registry | **`check_ai_tool_dispatcher_coverage.dart` does not exist**; tool-routing audit doc does not exist |
| 7 Cross-screen flow | Implicit in contract tests | **Data-flow-trace doc does not exist**. Single biggest documentation gap. |
| 8 Subscription gates | `reactive_subscription_three_sites_test.dart` + `subscription_*` tests | **`gate_coverage_test.dart` does not exist** |
| 9 Cron + Edge Fn ops | `check_edge_function_payloads.dart` + scattered Edge Fn tests | **Cron-health SQL monitoring doc does not exist** |
| 10 Telemetry | `check_generic_error_telemetry.dart` + `error_telemetry_*` tests | Coverage breadth audit; cron telemetry path |
| 11 Concurrency | `auth_invalidation_*` + `streak_progress_service_concurrency_test.dart` | **`check_writeservice_only.dart` does not exist** |
| 12 Provider invalidation | Implicit in `*_writer_to_reader_test.dart` | **`check_mutation_invalidation_set.dart` does not exist** |
| 13 Type consistency | Implicit in field-name contracts | **`type_consistency_test.dart` does not exist** |
| 14 Dead schema | None | **All work is new** |
| 15 Discipline gate | `check_bugfix_commits_have_diagnose.dart` + `check_migrations_applied.dart` | **`audit_discipline_history.dart` does not exist** |

## A.4 — GEMINI_API_KEY validity

✅ **WORKING.** Live evidence from `ai_coach_interactions`:
- Channel `app` (chat): 6 successful Gemini calls in last 14 days, 98,901 tokens consumed.
- Models used: `Gemini 2.5 Flash` + `Gemini 2.5 Flash Lite`.
- Most recent: 2026-05-15 04:11 UTC.

⚠️ **Two latent issues discovered during the probe (record as Phase A findings, route to Phase B):**

### Finding A-1: `model_used='pending'` rows never updated after success (CONFIRMED BUG)
8 rows across 2026-05-11 → 2026-05-15 have `ai_response IS NOT NULL` (Gemini answered) but `model_used` stayed at `pending`. The ai-proxy placeholder reservation logic from Test #16.1 / Bug B inserts `model_used='pending'`, then UPDATEs after Gemini responds — but UPDATE pattern is leaving `model_used` stale on the `food_text_analysis` channel. Verify in Phase B Agent 5.

### Finding A-2: Duplicate `(food_text_analysis, in_app_orphan)` row pairs still accumulating
Pairs of rows with identical `user_message` + `created_at` within seconds of each other:
- 2026-05-15 04:13: orphan @ 25.58s + food_text @ 06.17s (~19s apart)
- 2026-05-12 17:24-17:25 (~8s apart)
- 2026-05-12 05:07-05:08 (~10s apart)
- 2026-05-11 05:22 (~identical timestamps)

Test #16.1 / Bug B added 60s dedup window for the ai-proxy placeholder. But the in_app_orphan write happens client-side BEFORE Edge Function returns (Hive write fires sync to cloud as `in_app_orphan` before Edge Function ai_coach_interactions row materializes). 60s server-side dedup doesn't catch the cross-channel pair. Recurrence of the same class as Test #16.1.

These are not strictly part of cluster 6 (AI architecture) — they are about **writer drift between client and server within the same conceptual write**. Add to Agent 5's scope.

## Live cloud snapshot summary

See `phase-a-snapshot.md` for full table list + row counts. **Key data point: 14 of 46 tables have 0 rows**. 8 of those 14 are RED FLAGS:

1. `body_measurements` (0) — Hive writer exists, sync probably missing or silently failing
2. `promo_code_uses` (0) — 3 codes exist, redemption write missing
3. `referral_codes` (0) — founder generated codes in Test #2; sync broken?
4. `referral_redemptions` (0) — paired
5. `saved_diet_plans` (0) — `_syncSavedDietPlan` exists per §15; gap?
6. `sleep_logs` (0) — core feature; sync gap
7. `user_custom_foods` (0) — Hive has them; sync broken
8. `user_saved_meals` (0) — Hive has them; sync broken

This is **a single class of bug** — possibly the same root cause across all 8 tables. Route to Agent 4 (sync fan-out + restore completeness) with this prioritization.

## Phase A wrap-up

- A.1 ✅ Snapshot complete (`phase-a-snapshot.md` + `db-columns-raw.json`)
- A.2 ✅ Inventory complete (36 SoT concepts, 114 contract tests, 12 gate scripts, 13 historical audit docs)
- A.3 ✅ Coverage matrix complete (this doc) — 11 of 15 clusters have NEW deliverables
- A.4 ✅ GEMINI_API_KEY working + 2 latent findings (A-1, A-2) recorded

**Estimated false-positive rate adjustment:** Phase A already surfaced 2 confirmed bugs + 8 RED FLAGS via live SQL alone, with zero subagent involvement. Existing infrastructure is much larger than my plan estimated (114 contract tests, not 25). Phase B agent prompts should incorporate this: many surfaces are already audited; agents should focus on **deltas and gaps**, not re-derive what's already covered.
