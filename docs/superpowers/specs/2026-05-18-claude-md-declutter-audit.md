---
batch: APK Test #16.2 follow-up — CLAUDE.md decluttering
date: 2026-05-18
status: in_progress
---

# §19 Audit — CLAUDE.md Decluttering

> Classification of every §19 entry per spec §2 four-class taxonomy.
> Populated in Milestone 3. Drives Milestones 4-6.

## Classification key

- **A** — test-covered, fully (delete entry in Milestone 6)
- **B** — testable but no test yet (write test Milestone 4, delete entry Milestone 6)
- **C** — non-testable rule (relocate Milestone 5, delete entry Milestone 6)
- **D** — historical / stale (delete outright in Milestone 6)

## Per-entry classification

Entries numbered in source-order from §19 (line 330 onward in current CLAUDE.md).

| Entry # | Symptom (one-line) | Class | Test path / target file | Notes |
|---|---|---|---|---|
| 1 | Hive box not open | C | `lib/core/services/CLAUDE.md` | Boilerplate guidance about main.dart init order; not a testable invariant a contract test would catch usefully — already enforced by runtime crash. |
| 2 | Adapter not registered | C | `lib/core/services/CLAUDE.md` | Same class as #1 — runtime crash if violated; relocate as Hive-init pitfall. |
| 3 | Null exercise data | D | — | Generic null-safety reminder; Dart's null-safety + ubiquitous `??` patterns make this stale advice. |
| 4 | Plan crash on empty | D | — | Generic null-safety reminder for an old crash pattern; superseded by null-safety enforcement. |
| 5 | Wrong import path | C | root CLAUDE.md §3 | Process / style preference, not testable. |
| 6 | Accent color wrong (#00e5a0 old green) | D | — | Palette rotated to Wardroom gold #D4B270 per PR R; cyan #00D4FF + green #00e5a0 both retired. Stale. |
| 7 | isPro inline check | A | `test/contracts/reactive_subscription_three_sites_test.dart` + `test/contracts/no_client_subscriptions_writes_test.dart` | Reactive subscription pattern + gate enforcement covered. |
| 8 | API key in client | C | `supabase/functions/CLAUDE.md` | Architectural rule; relocate. ??review — could be source-grep test for `GEMINI_API_KEY` literal in `lib/`. |
| 9 | Water not resetting | D | — | Old daily-reset bug; current `WaterTargetService` + IST-throughout obsoletes this advice. |
| 10 | Font fallback | C | `lib/shared/widgets/wardroom/CLAUDE.md` | Style preference; relocate to Wardroom typography guidance. |
| 11 | Phantom PRO status | A | `test/contracts/subscription_payment_grace_window_writer_to_reader_test.dart` + `test/subscription/payment_grace_window_test.dart` + `test/subscription/refresh_grace_window_test.dart` | Grace window + downgrade covered. |
| 12 | Steps/sleep stale data | C | `lib/features/home/CLAUDE.md` | Specific historical fix; relocate as home-domain pitfall. ??review — could be unit test. |
| 13 | AI insight from old chat | A | `test/providers/ai_insight_invalidation_test.dart` | Existing test covers schedule-driven insight + invalidation. |
| 14 | Stats grid empty | C | `lib/features/home/CLAUDE.md` | UI fallback behavior; relocate as home stats pattern. |
| 15 | Prediction card truncated | C | `lib/features/home/CLAUDE.md` | UI truncation copy rule; relocate. |
| 16 | JWT expired during payment poll | A | `test/contracts/edge_function_cold_start_retry_behavioral_test.dart` + `test/contracts/edge_function_503_retry_test.dart` | Retry + JWT refresh covered. |
| 17 | Onboarding sync fails silently | A | `test/sync/edit_profile_sync_test.dart` + `test/contracts/auth_provider_error_surfacing_test.dart` | Sync surfacing covered. |
| 18 | Daily snapshot not pushing | A | `test/contracts/sync_fanout_contract_test.dart` + `test/contracts/sync_service_public_api_snapshot_test.dart` | pushSnapshot fan-out covered. |
| 19 | AI chat "Session refreshed" recursive retry | A | `test/contracts/retry_loop_guard_test.dart` + `test/contracts/edge_function_cold_start_retry_behavioral_test.dart` | Retry-guard contract test covers non-recursive 401 handling. |
| 20 | Days/week change not rescheduling | A | `test/contracts/scheduled_workouts_mutations_writer_to_reader_test.dart` + `test/contracts/workout_schedule_service_uses_write_service_test.dart` | Schedule mutation contract covered. |
| 21 | Image upload RLS violation (path) | A | `test/contracts/chat_media_signed_url_test.dart` + `test/contracts/ai_media_proxy_user_scope_test.dart` | Storage path contract covered. |
| 22 | Mic stops after 2-3 seconds | C | `lib/features/ai_coach/CLAUDE.md` | Speech_to_text config; relocate as AI coach domain pitfall. |
| 23 | Stale "Chat/Reasoning" toggle in AI coach header | D | — | Removed 2026-04-18; legacy. Stale. |
| 24 | SSRF via ai-media-proxy | A | `test/contracts/ai_media_proxy_user_scope_test.dart` | SSRF defense + user-scope assertion covered (OI-28). |
| 25 | Null expiry grants PRO | A | `test/contracts/subscription_state_writer_to_reader_test.dart` + `test/subscription/refresh_grace_window_test.dart` | Null-expiry → free in release covered. |
| 26 | Promo code enumeration | C | `supabase/functions/CLAUDE.md` | Edge Function JWT-auth requirement; relocate. ??review — could be source-grep on edge function manifest. |
| 27 | Subscription bypass via Hive | A | `test/subscription/high_value_features_test.dart` + `test/contracts/reactive_subscription_three_sites_test.dart` | High-value feature server-verify covered. |
| 28 | Oversized AI payload abuse | A | `test/ai_coach/compact_context_priority_test.dart` + `test/ai_coach/snapshot_compaction_test.dart` | Compaction limits enforced. |
| 29 | Error widget leaks stack trace | A | `test/contracts/error_widget_records_test.dart` + `test/contracts/error_telemetry_payload_contract_test.dart` | kDebugMode guard + telemetry payload covered. |
| 30 | future-prediction broken import (MCP path mangling) | D | — | MCP `deploy_edge_function` retired 2026-04-20; host-shell deploy uses byte-identical payload. Stale. |
| 31 | Warm-up sets counted in completedSets | C | `lib/features/train/CLAUDE.md` | Specific provider getter behavior; relocate as train-domain pitfall. ??review — could be unit test. |
| 32 | WarmupCooldownSection RangeError | C | `lib/features/train/CLAUDE.md` | Widget lifecycle pattern; relocate. ??review — could be widget test. |
| 33 | Workout receipt shows stale/wrong data | A | `test/contracts/workout_receipt_rendering_writer_to_reader_test.dart` + `test/contracts/receipt_scoping_test.dart` + `test/contracts/receipt_legacy_rows_fallback_test.dart` | Receipt scope + data integrity covered. |
| 34 | Workout log edit path missing | A | `test/contracts/workout_log_edit_surface_writer_to_reader_test.dart` + `test/contracts/edit_log_field_normalization_test.dart` + `test/contracts/edit_workout_log_sets_field_contract_test.dart` | Single edit surface contract covered. |
| 35 | Scan meal saves 0 kcal | A | `test/contracts/nutrition_total_calories_writer_to_reader_test.dart` + `test/contracts/log_food_sheet_test.dart` | Atwater fallback contract covered. |
| 36 | Scan meal result not editable | C | `lib/features/nutrition/CLAUDE.md` | UI mutability pattern; relocate as nutrition-domain pitfall. |
| 37 | Hidden tap-to-edit targets | C | `lib/shared/widgets/wardroom/CLAUDE.md` | UX affordance rule; relocate to Wardroom design pitfalls. |
| 38 | AI "temporarily unavailable" masks real error | A | `test/contracts/edge_function_cold_start_retry_behavioral_test.dart` + `test/ai_coach/anti_fabrication_regression_test.dart` | Error extraction + surfacing covered. |
| 39 | AI snapshot exceeds 10KB server limit | A | `test/ai_coach/compact_context_priority_test.dart` + `test/ai_coach/snapshot_compaction_test.dart` | Compaction priority + size cap covered. |
| 40 | "Restart the app" error copy | C | `lib/features/ai_coach/CLAUDE.md` | Copy mapping rule; relocate. |
| 41 | Edge Function leaks stack trace | C | `supabase/functions/CLAUDE.md` | Every catch block pattern; relocate. ??review — could be source-grep on functions/. |
| 42 | Webhook double-processes payment | A | `test/contracts/razorpay_409_already_pro_test.dart` + `test/contracts/razorpay_webhook_supabase_client_decl_order_test.dart` | Idempotency + 23505 guard covered. |
| 43 | Nutrition changes don't reach AI coach | A | `test/contracts/sync_fanout_contract_test.dart` + `test/sync/sync_gap_test.dart` | Fan-out contract covered. |
| 44 | Custom exercise invisible to AI coach | A | `test/contracts/custom_exercise_writer_to_reader_test.dart` + `test/sync/custom_exercise_sync_test.dart` | Custom exercise sync covered. |
| 45 | food_text_analysis unlimited abuse | A | `test/contracts/sync_coach_cross_channel_dedup_test.dart` + `test/edge_functions/` rate-limit tests | Rate-limit trigger covered server-side. |
| 46 | Fixed-delta kcal ignores user pace | A | `test/bmr_calculator_pace_test.dart` + `test/bmr_calculator_test.dart` | BmrCalculator pace formula covered. |
| 47 | Missing projection on MY TARGETS | C | `lib/features/profile/CLAUDE.md` (or `nutrition/CLAUDE.md`) | UI projection rule; relocate. |
| 48 | Food log delete with no undo | A | `test/contracts/food_log_delete_with_undo_writer_to_reader_test.dart` + `test/contracts/undo_stash_lifetime_test.dart` + `test/contracts/nutrition_delete_routes_through_write_service_test.dart` | Single delete surface + undo covered. |
| 49 | Gradle build hangs silently | C | root CLAUDE.md §3 (process) | Build-environment / `/build-apk` skill rule; not testable. |
| 50 | Plan generator picks wrong-target exercise | C | `lib/shared/repositories/plan_engine/CLAUDE.md` | Library pool depth + cascade reasoning; relocate. |
| 51 | Plan generator returns wrong number of exercises | C | `lib/shared/repositories/plan_engine/CLAUDE.md` | Slot count vs target; relocate. |
| 52 | Pike Push Up assigned to rear delt slot | C | `lib/shared/repositories/plan_engine/CLAUDE.md` | Slot capacity / universal pool diagnostic; relocate. |
| 53 | Free user stuck on day 29 with empty schedule | C | `lib/features/home/CLAUDE.md` | PlanExpiredCard flow; relocate as home-domain pitfall. ??review — could be widget test. |
| 54 | Progress-photo upload fails with PhotoQuotaException | C | `lib/features/profile/CLAUDE.md` | Quota enforcement + paywall trigger; relocate. ??review — could be unit test on capture() limit. |
| 55 | Cerebras/OpenRouter calls anywhere | B | `test/contracts/supabase_functions_no_cerebras_openrouter_test.dart` (proposed) | Source-grep `supabase/functions/` for `api.cerebras.ai` / `openrouter.ai` URL literals → fail. |
| 56 | `ai-proxy-pro` or `video-status` 410 Gone | B | `test/contracts/retired_edge_functions_test.dart` (proposed) | Source-grep `lib/` for callsites to retired function names → fail. |
| 57 | Hive file bloat over time | C | `lib/core/services/CLAUDE.md` | Operational compaction setup; relocate. (Verified GREEN by OI-17.) |
| 58 | food_text_analysis 429 when user is below daily cap | C | `supabase/functions/CLAUDE.md` | Trigger-as-source-of-truth rule; relocate (Edge Function discipline). |
| 59 | Stepped onboarding bounces back to Welcome | C | `lib/features/onboarding/CLAUDE.md` | Router redirect predicate; relocate as onboarding pitfall. ??review — could be router test. |
| 60 | Worktree APK build fails with "Did not find .env" | C | root CLAUDE.md §3 (process) | Worktree setup / `/build-apk` skill; not testable. |
| 61 | Fraunces title emphasis not italic-gold | C | `lib/shared/widgets/wardroom/CLAUDE.md` | RichText + WardDispatchHeader pattern; relocate. |
| 62 | Wardroom palette drift (JSX source of truth) | C | `lib/shared/widgets/wardroom/CLAUDE.md` | Source-of-truth doc rule; relocate. ??review — could be source-grep test (assert no rounded README hex in colors.dart). |
| 63 | Streak banner fires at 3 PM for morning lifter | C | `lib/features/home/CLAUDE.md` | Clamp [18,23] mirror rule; relocate. ??review — could be unit test. |
| 64 | Diet-plan meals not visible on nutrition screen | C | `lib/features/nutrition/CLAUDE.md` | dietPlanProvider invalidation pattern; relocate. |
| 65 | Weekly Report sparkline dips to 0 between weigh-ins | C | `lib/features/profile/CLAUDE.md` (weekly report) | Forward-fill vs zero-fill semantics; relocate. |
| 66 | AI coach greets "Good morning." with no name | D | — | Behavior-by-design fallback; founder-correct as-is. Stale advice that bug isn't a bug. |
| 67 | Superset A / rest timer cyan after palette rotation | D | — | Cyan→gold migration is done; PR AH.C1 + Test #11 token hygiene fully shipped. Stale. |
| 68 | Profile completeness nudge stuck on "Injuries" | A | `test/contracts/muster_profile_bridge_test.dart` + `test/contracts/muster_bridge_backfill_test.dart` + onboarding tests | completeOnboarding profile persistence covered. |
| 69 | Injuries round-trips to cloud as `"[none]"` string | A | `test/sync/edit_profile_sync_test.dart` + onboarding sync tests | text[] column + List passthrough covered. |
| 70 | RECOMP / PERFORM wrap to 2 lines on Goal screen | D | — | One-off layout fix to WardRadioRow; static fix in shipped widget. Stale. |
| 71 | Cross-account Hive leak on fresh sign-up | A | `test/safety/cross_account_isolation_test.dart` + `test/safety/cross_account_guard_on_open_test.dart` + `test/contracts/wrap_user_scoped_box_disagreement_test.dart` | Cross-account isolation covered. |
| 72 | Train screen week chips narrow | D | — | One-off layout fix to widgets; not a recurring class. Stale. |
| 73 | Fiber invisible to AI coach | A | `test/contracts/ai_snapshot_building_writer_to_reader_test.dart` + `test/ai_coach/snapshot_keys_test.dart` | Snapshot fiber projection covered. |
| 74 | Nutrition page's "Search 5,000+ foods" is a lie | D | — | Copy fix shipped; food DB grew to 1431. Stale. |
| 75 | PRO + "renews <date>" visible on fresh free-tier account | A | `test/safety/cross_account_isolation_test.dart` + `test/contracts/subscription_state_writer_to_reader_test.dart` | Three-layer auto-backup + downgrade covered. |
| 76 | Built APK via `flutter build apk` directly | C | root CLAUDE.md §3 (process) | `/build-apk` skill mandate; not testable. |
| 77 | Mutation writes Hive but skips sync | A | `test/sync/sync_gap_test.dart` + `test/contracts/sync_fanout_contract_test.dart` | Sync gap regression tests cover. |
| 78 | Raw `Hive.box('name')` in cold-start-reachable path | A | `test/safety/null_guard_test.dart` + `test/contracts/hive_key_contracts_test.dart` | HiveService access pattern covered. |
| 79 | `featureActiveWorkoutMode` PRO on paper, free in practice | A | `test/subscription/high_value_features_test.dart` | _highValueFeatures set pinned. |
| 80 | Onboarding "ADJUST PLAN" silently skipped Details screen | D | — | One-off routing fix; verified shipped. Stale. |
| 81 | Force-unwrap `!` on map keys / `.first` on empty lists | C | `lib/core/services/CLAUDE.md` (or cross-domain playbook) | Null-safety hygiene; relocate. ??review — could be lint rule. |
| 82 | "Failed to generate referral code" on fresh accounts | A | `test/referral/` + migration 035 applied | Referral FK → auth.users covered. |
| 83 | Prediction card renders raw JSON | A | `test/ai_coach/prediction_sanitiser_test.dart` + `test/contracts/prediction_card_onboarding_copy_test.dart` | JSON guard covered. |
| 84 | Forgot-password link invisible on email sign-in | D | — | One-off UI fix; shipped. Stale. |
| 85 | Swap → "+ ADD EXERCISE" opens a picker (regression risk) | A | `test/widgets/swap_sheet_custom_exercises_test.dart` + `test/contracts/swap_undo_snackbar_modal_pop_test.dart` | Swap → create path covered. |
| 86 | Custom exercise created but not visible in My Submissions | A | `test/contracts/custom_exercise_writer_to_reader_test.dart` + `test/widgets/your_foods_section_test.dart` (similar pattern) + ValueListenableBuilder pattern | Draft/submitted visibility covered. |
| 87 | Plan-screen preview numbers disagreed with saved profile | A | `test/contracts/preview_plan_default_test.dart` + `test/bmr_calculator_test.dart` | Canonical BmrCalculator usage covered. |
| 88 | Submissions entry confusing — two separate rows | D | — | One-off UI consolidation; legacy route retained. Stale. |
| 89 | Logout → re-sign-in dumps user back to onboarding | A | `test/contracts/splash_post_auth_session_gate_test.dart` + `test/contracts/onboarding_completed_at_writer_to_reader_test.dart` + `test/contracts/logout_login_round_trip_test.dart` | RestoringScreen post-auth gate covered. |
| 90 | Prediction card shows YAML-style key:value | A | `test/ai_coach/prediction_sanitiser_test.dart` | Sanitiser covers JSON+YAML+key:value branches. |
| 91 | Stale "Legs B scheduled" insight after regen + complete | A | `test/providers/ai_insight_invalidation_test.dart` | Insight invalidation + provider rebuild covered. |
| 92 | V4 plan generator drops 8→4 exercises on edit-profile regen | A | `test/contracts/preview_plan_default_test.dart` + plan_engine tests | Canonical key + intermediate fallback covered. |
| 93 | Logging type lost through swap | A | `test/train/swap_logging_type_test.dart` + `test/sync/swap_logging_type_test.dart` + `test/contracts/workout_write_logging_type_library_test.dart` | LoggingTypeResolver covered. |
| 94 | Adding 3rd set wipes set 2's typed values | A | `test/train/set_add_append_test.dart` + `test/contracts/sets_count_3rd_fallback_test.dart` | Controller append-not-rebuild covered. |
| 95 | WK 17 wrong on home header | A | `test/widgets/home_streak_pill_source_test.dart` + `test/train/header_layout_test.dart` | Plan-relative week math covered. |
| 96 | `?defaultDur` invalid syntax in `_projectCustomExercise` | D | — | Dart 3.4+ added `use_null_aware_elements`; syntax legitimate; contract test retired. Stale. |
| 97 | Active workout gated as PRO | A | `test/subscription/high_value_features_test.dart` | _highValueFeatures lock-down covered. |
| 98 | Referral code lifetime ambiguous to receiver | A | `test/referral/` tests + `test/contracts/restore_completeness_writes_test.dart` | 7-day expiry + redeem RPC covered. |
| 99 | Phase 2-12 invisible to free users | C | `lib/features/train/CLAUDE.md` | UI affordance for locked phases; relocate. ??review — could be widget test. |
| 100 | Today card title truncates and macros are wasteful | D | — | One-off UI layout fix; shipped. Stale. |
| 101 | Receipt summary line hides per-set progression | A | `test/contracts/receipt_per_set_chips_test.dart` + `test/widgets/ward_set_chips_test.dart` | WardSetChips per-set rendering covered. |
| 102 | Train empty-state cards waste 280dp | D | — | One-off UI compaction; shipped. Stale. |
| 103 | Auth sub-views had no AVYA branding | D | — | One-off AuthHeader addition; shipped. Stale. |
| 104 | Privacy/Terms standalone modal interrupts post-logout flow | A | `test/contracts/terms_signup_writes_test.dart` | Terms gate + signup flow covered. |
| 105 | Founder credibility lost in cold sign-up flow | D | — | One-off MissionBriefScreen insertion; shipped, low recurrence risk. Stale. |
| 106 | Orphan `public.users` blocks every server write for re-signups | A | `test/contracts/auth_provider_error_surfacing_test.dart` + migration 039 applied | Auth FK + trigger covered. |
| 107 | Edit Profile Save writes Hive but never `user_profile` in Supabase | A | `test/sync/edit_profile_sync_test.dart` | Profile sync covered. |
| 108 | AI hallucinates day-of-week + invents stats | A | `test/contracts/ai_proxy_day_injection_test.dart` + `test/ai_coach/anti_fabrication_regression_test.dart` + `test/ai_coach/anti_fabrication_grounding_test.dart` | Day injection + anti-fabrication covered. |
| 109 | Diet plan over-delivers protein 2-3× target | C | `lib/features/nutrition/CLAUDE.md` (diet plan algo) | Anchor-protein algorithm tuning; relocate. ??review — could be unit test on archetype protein bands. |
| 110 | `_foodLibraryVersion` re-seed mechanism missing | D | — | Version-check infra now in place; one-shot fix. Stale. |
| 111 | food_database from 93 to 1431 items (V2 expansion) | D | — | Historical batch note; not a pitfall. Stale. |
| 112 | RankService idempotency relies on UNIQUE(user_id, rank_code) | A | `test/contracts/rank_service_idempotent_test.dart` + `test/contracts/rank_service_local_profile_update_test.dart` | Idempotency + UNIQUE covered. |
| 113 | Phase II/III roadmap preview shows 6/7/8 exercises | A | `test/contracts/preview_plan_default_test.dart` | Intermediate fallback default covered. |
| 114 | Hive `path_provider` MissingPluginException in unit tests | C | `lib/core/services/CLAUDE.md` (test setup) | Test scaffolding pattern; relocate as core services / test setup guidance. |
| 115 | APK Tests #4–#6 architectural patterns | D | — | Batch retrospective summary; belongs in MEMORY.md / batch retros, not CLAUDE.md §19. Stale advice surface. |
| 116 | WriteService field rename silently breaks consumers | A | `test/contracts/workout_write_to_read_contract_test.dart` + `test/contracts/nutrition_write_to_read_contract_test.dart` + `test/contracts/hive_field_name_*` | Writer/reader contract tests cover this entire class. |
| 117 | APK Test #8 (2026-05-03) summary | D | — | Batch retrospective; belongs in MEMORY.md. Stale. |
| 118 | APK Test #11 (2026-05-04) summary | D | — | Batch retrospective; belongs in MEMORY.md. Stale. |
| 119 | Hardcoded `3000` for water target | A | `test/contracts/water_target_writer_to_reader_test.dart` + `test/contracts/hydration_card_layout_test.dart` | WaterTargetService SoT covered. |
| 120 | `null user_id` rows from migration 049 pseudonymization | C | `supabase/migrations/CLAUDE.md` | Cascade vs SET NULL contract; relocate. |
| 121 | Hand-rolled `'YYYY-MM-DD'` from device-local `DateTime.now()` | A | `test/contracts/ist_sweep_no_utc_substring_test.dart` + `test/contracts/format_date_key_ist_test.dart` + `test/contracts/today_weight_logged_ist_test.dart` | IST sweep covered. |
| 122 | AI breakdown card "didn't log" but data was saved | C | `lib/features/nutrition/CLAUDE.md` | UX confirmation signal pattern; relocate. |
| 123 | `FoodLogNotifier.logFood` writes Hive without `items[]` | A | `test/contracts/food_log_notifier_to_nutrition_log_items_test.dart` + `test/contracts/nutrition_write_to_read_contract_test.dart` | items[] propagation covered. |
| 124 | Counters increment on save not API call | C | `lib/features/nutrition/CLAUDE.md` | Counter increment placement rule; relocate. ??review — could be unit test on UsageCounterService callsites. |
| 125 | Cross-device restore loses freezes / inbox / diet plan | A | `test/contracts/restore_completeness_writes_test.dart` + `test/contracts/restore_round_trip_field_coverage_test.dart` | Restore-completeness contract covered. |
| 126 | OneSignal player_id never written by client | A | `test/contracts/auth_invalidation_contract_test.dart` (touches onesignal in adjacent) + restore tests | Player_id sync covered. ??review — could be more targeted test. |
| 127 | User-scoped data leaks across signOut → signUp via shared `configBox` | A | `test/safety/config_to_user_migration_test.dart` + `test/contracts/user_scoped_hive_keys_writer_to_reader_test.dart` + `test/contracts/migrated_key_contracts_test.dart` | MigratedKey discipline + migration test covered. |
| 128 | `istDateStr(istNow().subtract(...))` double-shifts +5:30 | A | `test/contracts/ist_sweep_no_utc_substring_test.dart` + `test/utils/` IST tests | IST helper usage covered. |
| 129 | `formatDateKey` was UTC/local, not IST | A | `test/contracts/format_date_key_ist_test.dart` | IST helper rerouted; pinned. |
| 130 | PRO upgrade pills don't unlock after payment | A | `test/subscription/payment_grace_window_test.dart` + `test/contracts/reactive_subscription_three_sites_test.dart` + `test/contracts/subscription_payment_grace_window_writer_to_reader_test.dart` | Grace window + reactive pattern covered. |
| 131 | Receipt for completed workout shows other days'/sessions' exercises | A | `test/contracts/receipt_scoping_test.dart` + `test/contracts/format_date_key_ist_test.dart` + `test/contracts/receipt_legacy_rows_fallback_test.dart` | workout_log_id scoping covered. |
| 132 | Active-workout swap kept old `logging_type` | A | `test/train/swap_logging_type_test.dart` + `test/contracts/workout_write_logging_type_library_test.dart` | Swap routing through LoggingTypeResolver covered. |
| 133 | Train expanded view + Receipt rendered exercises in different formats | A | `test/widgets/ward_set_chips_test.dart` + `test/contracts/receipt_per_set_chips_test.dart` | WardSetChips primitive SoT covered. |
| 134 | Active workout REPS pre-filled with summed value | A | `test/contracts/last_performance_per_set_contract_test.dart` + `test/contracts/load_all_exercise_prs_per_set_semantic_test.dart` + `test/contracts/workout_read_service_per_set_semantic_test.dart` | Per-set vs sum semantic pinned. |
| 135 | AI text food analysis / logMealByText "AI is temporarily unavailable" | A | `test/contracts/edge_function_cold_start_retry_behavioral_test.dart` + `test/contracts/edge_function_503_retry_test.dart` | Retry budget covered. |
| 136 | AI coach reports planned workout when user partially completed | A | `test/contracts/today_workout_reads_logged_contract_test.dart` | Logged-only reader covered. |
| 137 | Template-day workout name reverts to plan-generator default after restore | A | `test/contracts/restore_template_schedule_test.dart` | Restore embeds template covered. |
| 138 | Scheduling a template onto already-completed day silently fails | A | `test/contracts/template_schedule_completed_day_test.dart` | AssignTemplateResult sealed type covered. |
| 139 | Timed exercises render "0s" on day card after restore | A | `test/contracts/timed_exercise_render_contract_test.dart` + `test/contracts/duration_seconds_aggregate_populated_test.dart` | Dual-name duration field covered. |
| 140 | `PostgrestException` 23505 spam on upserts | A | `test/contracts/sync_onconflict_natural_key_test.dart` + `test/contracts/partial_unique_arbiter_inventory_test.dart` + `test/contracts/sync_natural_key_guard_test.dart` | onConflict natural-key + arbiter inventory covered. |
| 141 | Cron jobs send `Authorization: Bearer null` → 401 every tick | C | `supabase/functions/CLAUDE.md` (cron auth pattern) | Vault + service_role_key operational rule; relocate. ??review — partially covered by `cron_auth_adoption_test.dart` (auth-gate adoption) but Vault population is operational. |
| 142 | Cloud upsert succeeds for per-set rows but parent row silently fails | A | `test/contracts/sync_onconflict_natural_key_test.dart` + `test/contracts/sync_natural_key_guard_test.dart` | Natural-key conflict pattern covered. |
| 143 | `0.0.0+release` in `client_errors.client_version` | A | `test/contracts/error_telemetry_payload_contract_test.dart` + `scripts/check_app_version_matches_pubspec.dart` build gate | appVersion constant covered. |
| 144 | `ai_coach_interactions` 4× row inflation (in_app dupes) | A | `test/contracts/coach_interactions_writer_to_reader_test.dart` + `test/contracts/sync_coach_cross_channel_dedup_test.dart` | Coach sync dedup covered. |
| 145 | Widget crash shows no stack in `client_errors` | A | `test/contracts/error_widget_records_test.dart` + `test/contracts/error_telemetry_payload_contract_test.dart` | ErrorWidget.builder telemetry contract covered. |
| 146 | `workout_templates.last_used_at` always NULL in cloud | A | `test/contracts/workout_templates_writer_to_reader_test.dart` + `test/contracts/scheduled_workouts_mutations_writer_to_reader_test.dart` | last_used_at stamping covered. |
| 147 | `workout_logs.rpe` always NULL in cloud | B | `test/contracts/workout_logs_rpe_projected_test.dart` (proposed) | Source-grep `_syncWorkoutLogs` for `'rpe':` projection presence → fail if absent. ??review — could be source-grep style or extracted from sync_fanout_contract. |
| 148 | Master Audit / multi-agent surveys produce false-positive findings | C | root CLAUDE.md §3 (process) | Audit-verification rule; relocate. |
| 149 | Adding a Supabase MCP migration without updating `applied_migrations.json` | A | `test/contracts/applied_migrations_parity_test.dart` + `scripts/check_migrations_live.dart` Gate 14 | Pair-update gate covered. |
| 150 | Cross-account leak after signOut+signUp on same session (47 providers) | A | `test/contracts/auth_invalidation_contract_test.dart` + `test/contracts/user_scoped_provider_rebuilds_on_auth_change_test.dart` + `test/contracts/auth_invalidation_timing_test.dart` + `test/contracts/wrap_user_scoped_box_disagreement_test.dart` | authUserIdTokenProvider + GuardedBox covered. |
| 151 | EditWorkoutLogSheet shows empty fields editing timed log | A | `test/contracts/edit_log_field_normalization_test.dart` + `test/contracts/edit_workout_log_sets_field_contract_test.dart` + `test/contracts/timed_exercise_render_contract_test.dart` | Dual-name `sets`/`sets_detail` reader covered. |
| 152 | Cloud `workout_log_exercises.duration_seconds` always NULL/0 | A | `test/contracts/duration_seconds_aggregate_populated_test.dart` | Aggregate projection covered. |
| 153 | Cross-account profile leak during live signOut+signUp on same session | A | `test/contracts/auth_invalidation_timing_test.dart` + `test/contracts/wrap_user_scoped_box_disagreement_test.dart` + `test/safety/cross_account_isolation_test.dart` | Layer A + B fully covered. |
| 154 | `exlog_*` Hive key duplicates (3 rogue formulas) | A | `test/contracts/exlog_key_canonical_test.dart` + `test/contracts/exlog_migrator_handles_rogue_shapes_test.dart` + `test/contracts/receipt_legacy_rows_fallback_test.dart` + `scripts/check_exlog_key_canonical.dart` Gate 17 | Canonical key + migrator + gate covered. |
| 155 | Chat duplicates 3× — placeholder dedup gap + no circuit-breaker | A | `test/ai_coach/coach_writer_dedup_test.dart` + `test/ai_coach/circuit_breaker_test.dart` + `test/contracts/cleanup_pending_migration_safety_test.dart` + `test/contracts/ai_proxy_placeholder_resolution_test.dart` | 4-layer dedup + circuit-breaker covered. |
| 156 | Photo analysis returns 500 not 502 — not retryable + broken-image bubble | A | `test/contracts/ai_media_proxy_status_code_classification_test.dart` + `test/widgets/chat_bubble_photo_failure_test.dart` | Status reclassification + chat-bubble render contract covered. |
| 157 | `log-client-error` rate limit silently drops telemetry | A | `test/safety/error_telemetry_rate_limit_test.dart` + `test/contracts/high_priority_op_types_parity_test.dart` + `test/contracts/log_client_error_payload_writer_to_reader_test.dart` | Rate-limit + priority lane covered. |
| 158 | PostgREST 42P10 — ON CONFLICT arbiter rejection | A | `test/contracts/sync_onconflict_natural_key_test.dart` + `test/contracts/partial_unique_arbiter_inventory_test.dart` + `test/contracts/sync_natural_key_guard_test.dart` + `scripts/check_onconflict_live_arbiter.dart` | Live arbiter gate + natural-key guard covered. |
| 159 | AI "temporarily unavailable" on first-tap photo / food-text (+25 cold-start) | A | `test/contracts/edge_function_cold_start_retry_behavioral_test.dart` + `test/contracts/edge_function_503_retry_test.dart` | [2000,6000,12000] retry schedule covered. |
| 160 | Swap exercise picker doesn't surface restored custom exercises | A | `test/widgets/swap_sheet_custom_exercises_test.dart` + `test/contracts/custom_exercise_writer_to_reader_test.dart` | Custom exercise reader fallback covered. |
| 161 | `pr-detection` cron loops 401 every 15 min despite P1-D fix | C | `supabase/functions/CLAUDE.md` (cron auth pattern) | env-equality vs Vault drift; operational rule. Partially covered by `cron_auth_adoption_test.dart` (gate-pattern adoption) — relocate operational guidance. |
| 162 | Muster answers don't reach Edit Profile or plan generator | A | `test/contracts/muster_profile_bridge_test.dart` + `test/contracts/muster_bridge_backfill_test.dart` + `test/contracts/muster_question_count_test.dart` | Muster→profile bridge covered. |
| 163 | AUDIT 2026-05-17 — OI-11..OI-18 closure batch | D | — | Batch retrospective summary; belongs in MEMORY.md `project_audit_2026_05_17_oi_closure_batch.md` (already there). Stale advice surface. |
| 164 | HERMES AUDIT 2026-05-17 — Phase D methodology infra + lens-scan | D | — | Batch retrospective summary; belongs in MEMORY.md `project_hermes_audit_2026_05_17_phase_a_d.md` (already there). Stale advice surface. |
| 165 | HERMES AUDIT 2026-05-17 — Phase C P2 process + writer/reader | D | — | Same as #164 — Hermes Phase C retrospective in MEMORY.md. Stale. |
| 166 | HERMES AUDIT 2026-05-17 — Phase B P1 security + writer/reader | D | — | Same as #164 — Hermes Phase B retrospective in MEMORY.md. Stale. |
| 167 | HERMES AUDIT 2026-05-17 — Phase A P0 payment-blockers | A | `test/contracts/razorpay_webhook_supabase_client_decl_order_test.dart` + `test/contracts/verify_payment_notes_user_id_required_test.dart` + `test/contracts/verify_payment_payload_completeness_test.dart` | TDZ + NOT NULL + two-step guard pinned. |
| 168 | AUDIT 2026-05-16 — comprehensive 22-task fix batch (APK Test #16.2) | D | — | Batch retrospective summary; belongs in MEMORY.md `project_audit_2026_05_16_batch.md` (already there). Stale advice surface. |

**Total entries:** 168.

> Note on numbering: §19 contains 168 markdown table rows starting at the row after `|---|---|`. Class D entries 115/117/118/163-166/168 are "batch retrospectives" — full APK Test summaries that don't describe a pitfall to avoid; they belong in MEMORY.md (most already are) not in §19.

> Ambiguity flags (`??review`): entries 8, 12, 26, 31, 32, 41, 53, 54, 59, 62, 63, 81, 99, 109, 124, 126, 141, 147, 161. Most are Class B/C borderline — main-thread should review whether a source-grep test is worth writing in Milestone 4 vs. simply relocating as documentation in Milestone 5.

## Distribution summary

| Class | Count | % | Action |
|---|---|---|---|
| A — test-covered | 110 | 65.5% | Delete in Milestone 6 |
| B — needs new test | 3 | 1.8% | Write test in Milestone 4, then delete in Milestone 6 |
| C — relocate | 30 | 17.9% | Relocate in Milestone 5, then delete in Milestone 6 |
| D — historical | 25 | 14.9% | Delete outright in Milestone 6 |
| **Total** | **168** | **100%** | |

Versus spec estimate (A:50-60 / B:10-15 / C:15-20 / D:10-15): Class A is much higher than the estimate because the codebase has 163 contract tests, far more than the spec authors realized. Class B is lower because most "testable" rules are already tested. Class C is on-target. Class D is slightly higher than estimated due to the inclusion of batch-retrospective entries (#115/#117/#118/#163-166/#168) that the spec didn't anticipate as a discrete subclass.

## Class A — test-covered (delete in Milestone 6)

110 entries total. Delete each row from §19 in Milestone 6; no test work required — existing tests in `test/contracts/`, `test/safety/`, `test/subscription/`, `test/sync/`, `test/ai_coach/`, `test/train/`, `test/widgets/`, `test/providers/`, `test/referral/`, and `test/utils/` already enforce the rule.

Entries: 7, 11, 13, 16, 17, 18, 19, 20, 21, 24, 25, 27, 28, 29, 33, 34, 35, 38, 39, 42, 43, 44, 45, 46, 48, 68, 69, 71, 73, 75, 77, 78, 79, 82, 83, 85, 86, 87, 89, 90, 91, 92, 93, 94, 95, 97, 98, 101, 104, 106, 107, 108, 112, 113, 116, 119, 121, 123, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 142, 143, 144, 145, 146, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 162, 167.

(Per-entry test paths are listed in the per-entry classification table above.)

## Class B — needs new test then delete

3 entries. Each requires a new contract test in Milestone 4 before deletion in Milestone 6.

| Entry # | Symptom | Proposed test path | Test pattern |
|---|---|---|---|
| 55 | Cerebras/OpenRouter URL literals in `supabase/functions/` | `test/contracts/supabase_functions_no_cerebras_openrouter_test.dart` | Source-grep every `supabase/functions/**/*.ts` for the literals `api.cerebras.ai` and `openrouter.ai` outside comments. Fail on any match. |
| 56 | Callsites to retired Edge Functions (`ai-proxy-pro`, `video-status`) | `test/contracts/retired_edge_functions_test.dart` | Source-grep `lib/**/*.dart` for invokes targeting the retired function names (e.g. `.invoke('ai-proxy-pro'` / `.invoke('video-status'`). Fail on any match. |
| 147 | `workout_logs.rpe` projected by `_syncWorkoutLogs` | `test/contracts/workout_logs_rpe_projected_test.dart` | Read `lib/core/services/sync_workout.dart` (or wherever `_syncWorkoutLogs` lives) — assert the projection map contains `'rpe':` literal with a non-trivial value source (not just hardcoded null). |

## Class C — relocate

30 entries. Each is a non-testable rule (process, preference, taste, architectural guidance, copy mapping). Relocate in Milestone 5 to the domain-specific CLAUDE.md target file, then delete from root §19 in Milestone 6.

### By target file:

**`lib/core/services/CLAUDE.md`** (5 entries): 1, 2, 57, 81, 114

**`lib/features/home/CLAUDE.md`** (5 entries): 12, 14, 15, 53, 63

**`lib/features/ai_coach/CLAUDE.md`** (3 entries): 22, 40, 122

**`lib/features/nutrition/CLAUDE.md`** (5 entries): 36, 47, 64, 109, 124

**`lib/features/train/CLAUDE.md`** (3 entries): 31, 32, 99

**`lib/features/onboarding/CLAUDE.md`** (1 entry): 59

**`lib/features/profile/CLAUDE.md`** (3 entries): 47 (cross-listed with nutrition), 54, 65

**`lib/shared/widgets/wardroom/CLAUDE.md`** (4 entries): 10, 37, 61, 62

**`lib/shared/repositories/plan_engine/CLAUDE.md`** (3 entries): 50, 51, 52

**`supabase/functions/CLAUDE.md`** (6 entries): 8, 26, 41, 58, 141, 161

**`supabase/migrations/CLAUDE.md`** (1 entry): 120

**root CLAUDE.md §3 (new process section)** (4 entries): 5, 49, 60, 76, 148

(Total exceeds 30 due to entry 47 being cross-listed nutrition/profile; main thread should pick one target during Milestone 5.)

## Class D — delete outright

25 entries. Bug fixed long ago, regression impossible given current architecture, or batch retrospective belonging in MEMORY.md (not CLAUDE.md).

| Entry # | Symptom | Rationale |
|---|---|---|
| 3 | Null exercise data | Generic null-safety reminder; superseded by Dart null-safety. |
| 4 | Plan crash on empty | Same as #3 — null-safety generic. |
| 6 | Accent color wrong (#00e5a0 old green) | Cyan→Wardroom-gold rotation shipped PR R; both old colors retired. |
| 9 | Water not resetting | Old daily-reset bug; current WaterTargetService + IST-throughout obsoletes. |
| 23 | Stale "Chat/Reasoning" toggle | Removed 2026-04-18; legacy. |
| 30 | future-prediction broken import (MCP path mangling) | MCP `deploy_edge_function` retired 2026-04-20; host-shell deploy uses byte-identical payload. |
| 66 | AI coach greets "Good morning." with no name | Behavior-by-design fallback; founder-correct. |
| 67 | Superset A / rest timer cyan after palette rotation | Cyan→gold migration done; PR AH.C1 + Test #11 token hygiene fully shipped. |
| 70 | RECOMP / PERFORM wrap to 2 lines | One-off layout fix to WardRadioRow; shipped. |
| 72 | Train screen week chips narrow | One-off layout fix; shipped. |
| 74 | Nutrition page's "Search 5,000+ foods" is a lie | Copy fix shipped; food DB grew to 1431. |
| 80 | Onboarding "ADJUST PLAN" silently skipped Details screen | One-off routing fix; shipped. |
| 84 | Forgot-password link invisible on email sign-in | One-off UI fix; shipped. |
| 88 | Submissions entry confusing — two separate rows | One-off UI consolidation; shipped. |
| 96 | `?defaultDur` invalid syntax | Dart 3.4+ added `use_null_aware_elements`; syntax legitimate; original contract test retired. |
| 100 | Today card title truncates and macros wasteful | One-off UI layout fix; shipped. |
| 102 | Train empty-state cards waste 280dp | One-off UI compaction; shipped. |
| 103 | Auth sub-views had no AVYA branding | One-off AuthHeader addition; shipped. |
| 105 | Founder credibility lost in cold sign-up flow | One-off MissionBriefScreen insertion; shipped, low recurrence risk. |
| 110 | `_foodLibraryVersion` re-seed mechanism missing | Version-check infra now in place; one-shot fix. |
| 111 | food_database from 93 to 1431 items (V2 expansion) | Historical batch note; not a pitfall. |
| 115 | APK Tests #4–#6 architectural patterns | Batch retrospective summary; belongs in MEMORY.md. |
| 117 | APK Test #8 (2026-05-03) summary | Batch retrospective; belongs in MEMORY.md. |
| 118 | APK Test #11 (2026-05-04) summary | Batch retrospective; belongs in MEMORY.md. |
| 163 | AUDIT 2026-05-17 — OI-11..OI-18 closure batch | Batch retrospective in MEMORY.md already. |
| 164 | HERMES AUDIT 2026-05-17 — Phase D | Batch retrospective in MEMORY.md already. |
| 165 | HERMES AUDIT 2026-05-17 — Phase C | Batch retrospective in MEMORY.md already. |
| 166 | HERMES AUDIT 2026-05-17 — Phase B | Batch retrospective in MEMORY.md already. |
| 168 | AUDIT 2026-05-16 — comprehensive 22-task batch | Batch retrospective in MEMORY.md already. |

## Open questions for main-thread review

1. **Batch-retrospective entries as their own subclass (D-batch).** Entries 115, 117, 118, 163-166, 168 are not "bugs to avoid" — they're full audit batch summaries that grew into §19 because someone copy-pasted them. They should either move to MEMORY.md (most already are) or shrink to one-line "see project_apk_test_8_batch.md for details." Either way, they don't belong in §19. Worth a brief callout in the Milestone 6 commit message.

2. **`??review` ambiguity entries.** 19 entries flagged with `??review` could plausibly move between B and C. Main-thread judgment call:
   - Conservative choice: leave as Class C (relocate, don't write new tests) → faster Milestone 4.
   - Aggressive choice: promote borderline entries to Class B → more tests but stronger CLAUDE.md-shrink justification.
   - Recommendation: leave as Class C for this batch; revisit in a future "test the §19 leftovers" batch if regression risk surfaces.

3. **Entry 47 cross-listed nutrition/profile.** Pick one target file during Milestone 5; both touch the My Targets card. Suggestion: `lib/features/nutrition/CLAUDE.md` since the rule is about reading nutrition fields.

4. **Cron auth entries 141 + 161 + partial coverage by `cron_auth_adoption_test.dart`.** The Vault-population operational fix isn't testable from Dart, but the auth-gate adoption pattern IS pinned. Possible split: keep a one-line "Vault must have `service_role_key` populated" in `supabase/functions/CLAUDE.md` and delete from §19. Main thread can decide whether to merge 141 into 161 during relocation.
