---
bug_id: 7ad0d8
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 11 invariants documented in CLAUDE.md / audit findings / prior bug retros had no automated guardrail. Future code changes could silently remove them. Examples — delete-account skips confirmation_token check, razorpay-webhook drops the 5-min replay window, ai-proxy stops catching the food-text rate-limit trigger error, `isPro()` accidentally returns `true` on null expiry in release, `gate()` stops calling `verifyFromServer` for high-value features, exercise_selector cascade drops the universalPool fallback, etc.
concept: phase6_contract_tests
sot_registry_entry: audit_invariant_guardrails
writers: []
readers: []
hive_key_prefix: "n/a — guardrail tests"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: test/contracts/audit_2026_05_11_t1_t11_contracts_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["delete_account_skipping_jwt_or_confirmation", "webhook_dropping_replay_window", "promo_double_burn_on_replay", "ai_media_proxy_dropping_SSRF_allowlist", "isPro_returns_true_on_null_expiry_in_release", "gate_skipping_verifyFromServer_for_high_value", "onesignal_player_id_never_written", "food_text_cap_silenced", "ai_snapshot_no_9500_compaction_ceiling", "plan_generator_targetCount_or_cascade_removed", "client_side_subscriptions_write"]
proposed_fix: Single contract file at `test/contracts/audit_2026_05_11_t1_t11_contracts_test.dart` with 11 groups, one per T-N invariant. Each test is a source-grep / file-scan check that fails loudly if the named invariant is removed. Tests are file-I/O only — they run on every pre-commit at ~milliseconds per test.
regression_test_planned:
  - test/contracts/audit_2026_05_11_t1_t11_contracts_test.dart (18 individual tests across 11 groups)
---
# Audit Phase 6: 11 missing contract tests (T-1..T-11)

## Why

11 invariants documented across CLAUDE.md / audit findings / prior
bug retros had no automated guardrail. A future refactor could
silently remove them, and we'd only find out from a production
incident.

## What's pinned

| Row | Invariant |
|---|---|
| T-1 | `delete-account` Edge Function safety — JWT re-validation, confirmation_token check, Razorpay cancel succeeds before deletion, account_deletion_log audit row |
| T-2 | `razorpay-webhook` rejects events older than 5 minutes (replay window) |
| T-3 | `increment_promo_used_count` gated by `!alreadyProcessed` (no double-burn on replay) |
| T-4 | `ai-media-proxy` SSRF allowlist — only `/storage/v1/object/` prefix accepted |
| T-5 | `isPro()` consults `kDebugMode` for null-expiry path (rooted-device tamper defence) |
| T-6 | `gate()` calls `verifyFromServer` for high-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`) |
| T-7 | `auth_provider` writes `OneSignal.User.pushSubscription.id` to `user_progress.onesignal_player_id` |
| T-8 | `ai-proxy` catches the `food_text_daily_limit_reached` P0001 trigger and returns 429 |
| T-9 | `AiService._compactContext` enforces the 9500-byte target |
| T-10 | `VolumeFilter.targetCount` + 5-attempt cascade with `universalPool` fallback |
| T-11 | migration 052 drops permissive INSERT/UPDATE/DELETE on subscriptions + no client-side `.from("subscriptions").insert/update/upsert/delete` |

## How

Single file `test/contracts/audit_2026_05_11_t1_t11_contracts_test.dart`
with 11 `group(...)` blocks, one per T-N. Each test reads the
production source file via `dart:io` + applies a precise
source-grep. Failure mode = test goes red the moment someone
removes the invariant in a PR. Tests run on every pre-commit
(file I/O only, milliseconds each).

The 18 individual `test()` calls (some groups have 2-3) all pass
on the current source. Future code that silently regresses any
of these invariants fails CI immediately.

## Related

- T-12 (WriteService bypass detector) — shipped earlier in Phase 2 commit `14fef3f`
- `feedback_audit_methodology_lenses.md` — the audit methodology
  that surfaced these 11 missing guardrails
- CLAUDE.md §10 (subscription gate pattern) — pinned by T-5/T-6
- CLAUDE.md §11 (AI input validation) — pinned by T-8/T-9
- CLAUDE.md §12 (plan generator V4 pipeline) — pinned by T-10
- CLAUDE.md §16 (payment flow) — pinned by T-1/T-2/T-3
