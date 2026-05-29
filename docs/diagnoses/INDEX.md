# Bug Directory (auto-generated)

Generated: 2026-05-29T20:25:54.657502.
Re-run: `dart run scripts/build_bug_index.dart`

## By recurrence class

## By concept

### workout_completion_status (7 bugs)
- 2026-05-29 7c2a8b — >
- 2026-05-12 a9f3d2 — Home today-card showed "BACK DAY A · DONE" (green DONE pill) for Sat May 9, but the calendar-strip's Sat May 9 cell showed only the gold today-border with NO checkmark, while earlier completed days (Mon May 4) correctly showed a checkmark.
- 2026-05-12 d4e9c1 — |
- 2026-05-10 a7c1e2 — Calendar checkmarks for May 5/6/7 vanished on the founder's account after restore, despite cloud workout_logs and scheduled_workouts.status='completed' being correct for those dates.
- 2026-05-10 e3f7a8 — A subset of users (founder included) holds Hive `schedule_<date>` rows with `status='completed'` while the cloud `scheduled_workouts` row stays at `status='planned'` for those dates. Once Bugs B.1 + B.2 ship, future writes stay consistent — but existing divergence won't self-heal without an explicit re-push.
- 2026-05-10 d9b2c5 — Saturday's locally-completed workout was overwritten back to 'planned' on every cold-start restore, because cloud still held the older 'planned' row (Bug B.1's FK violation prevented push) and `_restoreScheduledWorkouts` was unconditionally cloud-authoritative for status/completed_at.
- 2026-05-10 c8e4a1 — 10 PostgrestException 23503 (scheduled_workouts_template_id_fkey) errors fired in 5 seconds on the founder's account at 2026-05-10 12:45 UTC. Saturday's completed workout never reached cloud and the calendar tick vanished after force-restart.

### coach_interactions (3 bugs)
- 2026-05-29 9e1d4c — >
- 2026-05-04 bb3acc — Morning alert Edge Function computed day-of-week and date strings in UTC instead of IST, sending wrong day greetings after 18:30 IST.
- 2026-05-04 4c8788 — AI coach message count was recomputed from Supabase on every render, causing unnecessary round-trips; cache key was not IST-aware, causing stale counts across midnight.

### blast_radius_commit_autotag (1 bugs)
- 2026-05-29 c3d8a1 — >

### alert_detection_edge_function_health (1 bugs)
- 2026-05-28 b1f4e2 — >

### rank_monotonic_current_code (1 bugs)
- 2026-05-27 3a7b9f — |

### exercise_library_cloud_seed (1 bugs)
- 2026-05-27 ada3fb — |

### source_grep_contract_test_recovery_post_refactor (1 bugs)
- 2026-05-24 2b705b — |

### writer_reader_drift_batch_2026_05_24 (1 bugs)
- 2026-05-24 524d12 — |

### week_selector_past_phase_scroll (1 bugs)
- 2026-05-23 85a684 — |

### graduation_phase2_preview (1 bugs)
- 2026-05-23 ea1059 — |

### singleton_lifecycle_registry (2 bugs)
- 2026-05-22 7f2a8c — |
- 2026-05-21 7a3e1c — |

### subscription_gate (1 bugs)
- 2026-05-22 7b3eaf — |

### rank_promotion_celebration (1 bugs)
- 2026-05-22 9aa2c1 — |

### proactive_coach_promotion (1 bugs)
- 2026-05-22 8b1f33 — |

### scheduled_workouts_mutations (3 bugs)
- 2026-05-22 b0baa5 — |
- 2026-05-12 9e2c1a — |
- 2026-05-12 8f3d22 — |

### phase_unlock_end_to_end (1 bugs)
- 2026-05-22 ec4d27 — |

### phase_unlock_card_surface_gate (1 bugs)
- 2026-05-22 0e7714 — |

### hive_session_init_race (1 bugs)
- 2026-05-22 dc52a4 — |

### exercise_logs_read_path (2 bugs)
- 2026-05-22 89d56c — |
- 2026-05-12 f4c9e1 — After completing today's morning workout via the active-workout flow, the Edit Workout Log sheet shows "No exercise logs for this day" — blank. Cloud workout_log_exercises HAS the 5 rows for the founder on 2026-05-11 (completed_at 05:19 UTC = May 11 10:49 IST). Local Hive also has them at correct keys.

### food_text_analysis (1 bugs)
- 2026-05-22 599d49 — |

### ai_snapshot_building (2 bugs)
- 2026-05-22 b4a09c — |
- 2026-05-17 93aeac — |

### workout_schedule_service_split (1 bugs)
- 2026-05-22 d882ca — |

### restore_completeness (9 bugs)
- 2026-05-22 4a3b08 — |
- 2026-05-08 b2ac5d — Multiple restore failures — _restoreXxx methods keyed Hive by cloud UUID instead of deterministic WriteService key (calendar dup explosion); _restoreUserProfile missed users.full_name so greeting showed USER; _restoreScheduledWorkouts had early-skip closing Mon-only DONE marker; templates upsert caused 23503 FK loops. Telemetry sweep added 22 new op_types.
- 2026-05-07 5c61ed — Multiple issues — restore stack had HiveUserSession ordering bugs causing 30+ cold-start restore failures logged to client_errors; receipt chips needed per-set rendering; 5 IST drift sites remained; process bootstrap docs (sot_registry, naming_conventions, pre-commit hook) were missing.
- 2026-05-04 ad7664 — Streak freezes, notifications inbox entries, and diet plan were written to Hive but never pushed to cloud, so they were silently lost on reinstall.
- 2026-05-04 239999 — restoreFromCloud did not pull streak freezes, notifications inbox, saved diet plan, rank promotions, or coaching notes, so reinstalling lost all these surfaces.
- 2026-05-04 89d079 — Hard-deleting an auth user CASCADE-deleted community contributions (custom foods, exercises, reviews) that should be retained pseudonymously for community signal.
- 2026-05-04 776478 — Streak freezes, notifications inbox, and saved diet plan had no cloud backing, so reinstalling the app silently lost these surfaces for paying users.
- 2026-05-04 72ea41 — No server-side hard-delete path existed for DPDP §17 compliance, so user data could not be fully erased on account deletion request.
- 2026-05-04 d33c12 — No client-side account deletion UI existed for DPDP §17 compliance; users had no way to request hard erasure of their data.

### edge_function_deploy_reversibility (1 bugs)
- 2026-05-21 b3ecf2 — |

### typography_canonical_source (1 bugs)
- 2026-05-21 1f4a8b — |

### referral_redemption (1 bugs)
- 2026-05-21 2d1c8a — |

### profile_write_service (1 bugs)
- 2026-05-21 3cbbce — |

### dependency_canonical_http_client (1 bugs)
- 2026-05-21 3e9d39 — |

### post_signin_destination (1 bugs)
- 2026-05-21 17ae38 — |

### ai_coach_repository_split_A10 (1 bugs)
- 2026-05-21 9c2b1f — |

### sync_domain_full_migration_A6 (1 bugs)
- 2026-05-21 2b8d4e — |

### sync_domain_interface_scaffold_A6 (1 bugs)
- 2026-05-21 5a0b31 — |

### weight_trend_range (1 bugs)
- 2026-05-20 b3f7a2 — |

### usage_weeks_signup_age (1 bugs)
- 2026-05-20 c2a91f — |

### restore_long_pole_timing_visibility (1 bugs)
- 2026-05-19 4f8e2d — |

### streak_freeze_refill_restore_race (1 bugs)
- 2026-05-19 9c4a17 — |

### weight_log_provider_invalidation_race (1 bugs)
- 2026-05-18 w7r4c3 — |

### swap_undo_snackbar_modal_stack (1 bugs)
- 2026-05-18 s1n4c0 — |

### streak_freeze_value_clamp_on_read (1 bugs)
- 2026-05-18 f8c1a5 — |

### ai_tool_wall_clock_and_media_proxy_error_class (1 bugs)
- 2026-05-18 t1m5b0 — |

### restore_completeness_symmetric (1 bugs)
- 2026-05-17 4dd7e2 — |

### partial_unique_arbiter_safety (1 bugs)
- 2026-05-17 9d2a47 — |

### nutrition_delete_canonical_writer (1 bugs)
- 2026-05-17 d1e7e6 — |

### current_streak_single_reader (1 bugs)
- 2026-05-17 41507e — |

### paywall_single_purchase_path (1 bugs)
- 2026-05-17 40c401 — |

### migration_live_verify_gate (1 bugs)
- 2026-05-17 1c3401 — |

### streak_freeze_refill_extract (1 bugs)
- 2026-05-17 5fe338 — |

### rank_promotion_local_sync (1 bugs)
- 2026-05-17 4a37e7 — |

### apk_size_gate_strict_mode (1 bugs)
- 2026-05-17 c84e33 — |

### cross_account_guard_exempt_declaration (1 bugs)
- 2026-05-17 3a7c1e — |

### marked_done_without_logging_ux (1 bugs)
- 2026-05-17 7c4e5d — |

### reader_manifest_exhaustive_completeness (1 bugs)
- 2026-05-17 0a1e17 — |

### workout_read_service (1 bugs)
- 2026-05-17 8d85c2 — |

### snapshot_contract_enforcement (1 bugs)
- 2026-05-17 c0e3a5 — |

### razorpay_webhook_handler_correctness (1 bugs)
- 2026-05-17 9a7c14 — |

### verify_payment_payload_completeness (1 bugs)
- 2026-05-17 b3e052 — |

### ai_media_proxy_user_scope_assertion (1 bugs)
- 2026-05-17 5e055f — |

### verify_payment_notes_user_id_guard (1 bugs)
- 2026-05-17 c8f229 — |

### clean_orphan_media_bucket_target (1 bugs)
- 2026-05-17 c1ea30 — |

### cron_edge_function_auth_gate (1 bugs)
- 2026-05-17 c4031b — |

### delete_account_storage_purge_recursive (1 bugs)
- 2026-05-17 a2d0e1 — |

### doc_internal_consistency_table_count (1 bugs)
- 2026-05-17 d0c352 — |

### train_provider_workout_read_service_delegation (1 bugs)
- 2026-05-17 39ead9 — |

### snapshot_writer_contract (1 bugs)
- 2026-05-17 7faa3b — |

### (unspecified) (9 bugs)
- 2026-05-16 2026-05-16-workout-schedule-service-bypass — 
- 2026-05-16 2026-05-16-sync-coach-cross-channel-dedup — 
- 2026-05-16 2026-05-16-rank-widget-migration — 
- 2026-05-16 2026-05-16-ai-proxy-placeholder-resolution — 
- 2026-05-16 2026-05-16-dead-columns-dropped — 
- 2026-05-16 2026-05-16-doc-updates — 
- 2026-05-16 de29b8 — 
- 2026-05-16 2026-05-16-gate-coverage-and-dead-code — 
- 2026-05-16 2026-05-16-logpr-bypass — 

### client_errors_telemetry_pipeline (1 bugs)
- 2026-05-16 9d12af — |

### workout_log_id_session_scoping (1 bugs)
- 2026-05-16 daffac — |

### terms_acceptance_audit_trail (1 bugs)
- 2026-05-16 2026-05-16-terms-accepted-at-dpdp — |

### ErrorTelemetry + sync success/failure signal + cron auth (1 bugs)
- 2026-05-16 2026-05-16-telemetry-hardening — Telemetry framework had five compounding observability gaps surfaced by audit Agent 7 — no success-path emission on 5 low-usage sync methods (cannot distinguish "feature unused" from "silently failing"), no cron-execution telemetry (F10.5), no `_shared/cron_auth.ts` (F9.1 — Test #16 P1-D drift class), generic numbered op_types defeating triage (F10.3), and undetected HIGH_PRIORITY_OP_TYPES client/server drift (F10.4).

### sleep_logs (1 bugs)
- 2026-05-16 5beed5 — |

### workout_schedule_completion_cloud_projection (1 bugs)
- 2026-05-16 2026-05-16-schedule-completion-duration — |

### referral_restore_completeness (1 bugs)
- 2026-05-16 2026-05-16-referral-restore-completeness — |

### prediction_card_display (1 bugs)
- 2026-05-16 2c1c0d — |

### exercise_personal_records (1 bugs)
- 2026-05-16 cb1ab1 — |

### ai_media_proxy_status_code_classification (1 bugs)
- 2026-05-16 913261 — |

### ai_media_proxy_classification (1 bugs)
- 2026-05-16 5bea3e — |

### onboarding_completed_at (3 bugs)
- 2026-05-16 1bfeed — |
- 2026-05-04 8cc429 — Identity screen allowed proceeding without sex selection and showed wrong step label (missing 01·05 display).
- 2026-05-03 f9acbc — MissionBriefScreen crashed or showed wrong state when navigated to in readOnly mode because the readOnly param was absent.

### ai_coach_interactions_dedup (1 bugs)
- 2026-05-16 a17bc3 — Founder's `ai_coach_interactions` table shows 6 rows for the same `user_message='curd 200gms whey 1.5 scoops cashew 6'` (3 timestamps × 2 channels). Each "Analyze with AI" tap during Gemini 502 storm produced (a) a Hive `coach_*` row, (b) a server-side placeholder row (channel=food_text_analysis, model_used=pending), and (c) a sync-time orphan row (channel=in_app_orphan). No client-side circuit breaker — user can tap retry indefinitely and each tap fans out to 3 cloud rows.

### exlog_key_sot (1 bugs)
- 2026-05-16 a16c1a — |

### health_write_service (1 bugs)
- 2026-05-16 e7a516 — |

### sync_natural_key_guard (1 bugs)
- 2026-05-15 9f4ab2 — |

### edge_function_cold_start_resilience (3 bugs)
- 2026-05-15 c01d57 — |
- 2026-05-12 0a7b9f — Two surfaces affected. (G) Food text analysis returned "The AI is temporarily unavailable. Please try again in a minute." after the user typed a meal description and tapped Analyse & Log. (H) Telemetry shows push_snapshot FunctionException(status 503, BOOT_ERROR) for sumit1 at 06:46 UTC.
- 2026-05-12 7c4e1a — User tapped "Analyse & Log" on Nutrition → Log Food → AI tab. Got toast "The AI is temporarily unavailable. Please try again in a minute." Same error class also fires from AI coach `logMealByText` tool dispatch when ai-proxy is cold. Edge-function logs show two consecutive POST /ai-proxy 502 BAD_GATEWAY at 05:08:05 UTC (8475 ms) and 05:08:13 UTC (6654 ms); the next successful call ~3 min later took 20219 ms (warm-start completion).

### debugging_methodology (1 bugs)
- 2026-05-15 4e9515 — Founder asked for a "debugging" skill earlier in the session; both `superpowers:debugging` and `debugging` returned `Unknown skill`. The project's `.claude/skills/` directory did not exist. Debugging methodology was tribal knowledge spread across CLAUDE.md §19, MEMORY.md feedback_* files, and project_apk_test_*.md retrospectives — not invocable as a single skill. Result: every batch since Test #6 has re-discovered the same writer/reader drift class because the methodology to catch it was undocumented as a skill.

### cloud_upsert_natural_key_contract (2 bugs)
- 2026-05-15 25e91d — |
- 2026-05-12 3f8a91 — |

### sync_fanout_workout_domain (2 bugs)
- 2026-05-15 76c8f4 — PostgREST raises 42P10 "no unique or exclusion constraint matching the ON CONFLICT specification" on every upsert to workout_logs (onConflict=user_id,date,exercise_name), workout_log_exercises (onConflict=workout_log_id,exercise_id,set_number) and nutrition_logs (onConflict=user_id,date,meal_type); 47 client_errors rows for a single user in a 60-second window on 2026-05-15 04:10 UTC.
- 2026-05-04 b621c6 — Four pre-existing test failures in rank_service_test and sync_gap_test reflected outdated test assumptions from pre-Test #6 architecture.

### cron_auth (1 bugs)
- 2026-05-15 5a65bd — pr-detection Edge Function cron returns 401 every 15 minutes; same shape affects 6 other C-4-gated proactive trigger functions (re-engagement, plateau-alert, protein-gap-alert, workout-window-closing, evaluate-rank-promotions, streak-guardian, i-see-you-callout, clean-orphan-media — every function with verify_jwt=false that imports the C-4 in-function cron-auth-gate).

### custom_exercises_mutations (1 bugs)
- 2026-05-15 a5d29c — |

### muster_to_profile_bridge (1 bugs)
- 2026-05-12 8c4ee3 — After completing the post-onboarding muster flow (MusterScreen) and entering shoulders as a known injury and legs as the body-part priority, Edit Profile continued to show injuries=['none'] and physique_focus='balanced'. Muster answers persisted to coachBox only and never bridged into userBox['profile'] — the AI coach saw the answers, but Edit Profile and the plan generator did not.

### workout_log_exercises_input_validation (1 bugs)
- 2026-05-12 e6a2d4 — "LAST: 50KG · 135 REPS" rendered above Leg Extension in active workout screen — 135 reps per set is unrealistic. Cloud `workout_log_exercises` had 3 corrupt rows from May 7 with set_number=15 + reps=110-150 (bulk-completion aggregates misinterpreted as per-set).

### ai_media_proxy_error_handling (1 bugs)
- 2026-05-12 d8e5b3 — Photo upload to AI coach → "Sorry, I couldn't analyse that photo. Please try again." Zero client_errors rows for ai-media-proxy in last 12h — generic fallback fires silently without telemetry.

### schedule_exercise_field_types (1 bugs)
- 2026-05-12 a2f9e1 — Home renders "Something went wrong" ErrorState after the user schedules a custom template for today. Crash repeats on every cold-start. Telemetry shows 5x widget_error_fallback with message "type 'String' is not a subtype of type 'int?' in type cast".

### template_exercises_cloud_tail_rows (1 bugs)
- 2026-05-12 b3c8d2 — Founder's templates "Back Day A", "Leg Day A", "Push Day" each showed 14-15 exercise rows with only 4-5 distinct names ("triplicated"). Editing the template + removing duplicates + saving brought the dupes back on next reopen.

### exercise_set_field_name_contract (1 bugs)
- 2026-05-12 6e1b45 — |

### today_workout_snapshot_reads_logged (1 bugs)
- 2026-05-12 a13a01 — User asks AI coach "how was my workout today?" after partially completing a Pull-day session (logged 4 of 8 prescribed exercises — Lat Pulldown, Dumbbell Row, Hanging Leg Raise, Concentration Curl). Coach replied with the FULL planned 8-exercise list as if everything had been completed, because today_workout.exercises emits the schedule_<date> entry verbatim regardless of how many exlog_* rows exist for the day.

### hive_user_session_static_state (1 bugs)
- 2026-05-12 c7d4f6 — After signing out as Upendra and signing up as new account sumit1@gmail.com, the Profile screen showed Upendra's full profile data (full_name=Upendra, dob=1988-06-30, height=174cm, weight=78.3kg, target=80kg). Cloud was correct for both accounts (sumit1's cloud user_profile row had Sumit/2001-01-01/175cm/75kg). The leak was in local Hive userBox['profile'].

### cross_account_riverpod_cache_race (1 bugs)
- 2026-05-12 7bd154 — After signing out as Upendra and signing up as sumit1@gmail.com on the same session, Edit Profile rendered Upendra's profile (174 cm / 77.8 kg / DOB 1988-06-30) until the app was force-killed and reopened. The Riverpod cache held the previous user's profile because providers rebuilt on the Supabase auth event before HiveUserSession.openForUser had completed swapping the box owner.

### user_scoped_riverpod_providers (1 bugs)
- 2026-05-12 c4055a — |

### day_rollover_provider_invalidation (1 bugs)
- 2026-05-12 b7e3f1 — On Sunday morning cold start, home today-card showed Saturday's completed workout ("BACK DAY A · DONE · Lat Pulldown 40kg") even though the IST calendar had advanced to Sunday May 10.

### workout_receipt_rendering (1 bugs)
- 2026-05-12 a2b3c4 — |

### exercise_log_per_set (1 bugs)
- 2026-05-12 e1f8a2 — |

### last_performance_per_set_semantics (1 bugs)
- 2026-05-12 a8f1c2 — "Active workout screen pre-fills REPS input with 85 on every set of Hanging Leg Raise (4 prescribed sets × 14 reps, bodyweight). 85 is the sum of the user's previous 7-set session [10,15,10,15,10,10,15]; weight_kg field similarly carries the max of the previous session's per-set weights instead of the first set's weight."

### write_service_bypass_detector (1 bugs)
- 2026-05-11 7ad0cc — No source-grep guardrail enforced the WriteService SoT contract for `exlog_*`, `wlog_*`, `nlog_*`, `saved_meal_*` Hive prefixes. C-8 + C-12 closed half a dozen bypass sites manually; without a detector, new code can re-open the class. While writing the detector, a 7th bypass was caught — `_relogFromHistory` in `search_mode_body.dart` wrote `nlog_<ts>` directly with the legacy flat-totals shape (no items[]), same C-12 sibling class.

### profile_signout_auth_notifier (1 bugs)
- 2026-05-11 7ad0ca — `ProfileScreen._performSignOut` called `supabase.auth.signOut()` + `UserRepository.clearAllData()` directly, bypassing `AuthNotifier.signOut()` and — critically — skipping `HiveUserSession.deleteAllFilesForCurrentUser()`. Per-user namespaced Hive files survived on disk after sign-out → re-opens the cross-account leak class that CLAUDE.md §19 documents as closed by namespacing. Next sign-in's legacy migration sweep could re-import them.

### rls_with_check_completeness (1 bugs)
- 2026-05-11 7ad029 — 35 RLS policies on UPDATE / ALL had USING expressions but no WITH CHECK; meaning a user could UPDATE their own row's user_id to another user's UUID, transferring or poisoning cross-user data.

### templates_sync_fanout (1 bugs)
- 2026-05-11 7ad0cb — `TemplatesNotifier.saveTemplate` + `.updateTemplate` wrote `tmpl_*` rows to Hive but fired NO cloud sync — `workout_templates`/`template_exercises` rows only reached cloud via weekly full sync (up to 24h delay). `TemplatesNotifier.deleteTemplate` fired `pushSnapshot` but missed `syncWorkoutData`, so the cloud `workout_templates` row stayed orphaned forever — next restore re-imported the "deleted" template.

### subscriptions_rls (1 bugs)
- 2026-05-11 7ad0c1 — subscriptions table had open INSERT/UPDATE/DELETE RLS policies plus nullable Razorpay columns; any authenticated user could self-grant indefinite PRO with no payment trail.

### streak_progress_service (1 bugs)
- 2026-05-11 7ad0d2 — `streak_freezes_available` + `streak_freeze_used_dates` + `streak_freezes_last_refill` had TWO independent writers — `StreakFreezeNotifier._refillIfNewWeek` (weekly +1) and `WorkoutRepository._calculateStreak(consume:true)` (missed-day burn). Each path was a synchronous read-modify-write today, but contract drift risk was high — any future change introducing an `await` mid-flight would open a same-process race. The CROSS-DEVICE race is real now — a stale snapshot from device A could overwrite a freshly-consumed value on device B if `syncFreezes` arrived in the wrong order. (Hermes-R2 Round 2 #3 — "Refill ↔ consume race on streak freezes (lost update)", NEW CRITICAL.)

### streak_cqrs_split (1 bugs)
- 2026-05-11 7ad0d1 — `WorkoutRepository.calculateCurrentStreak()` was documented as a "read" but had side effects — consumed streak freezes for missed days and persisted the new state to Hive + cloud on every invocation. Four read-only call sites (RankService cron / splash, streakProvider for home pill, rank_service_record_sheet display, AI snapshot) ran this method routinely. A user with 1 freeze available and 1 missed day would have that freeze burned by the first cron eval, but if the cron fired 3× in a window, race conditions could burn 3 freezes for the same day. UI rebuilds, hot reload, dev tools — every trigger of those surfaces silently mutated freeze state.

### splash_post_auth_session_gate (1 bugs)
- 2026-05-11 7ad0c7 — 4 splash-time post-auth fire-and-forget startup paths (`RankService.evaluateAndPromote`, `SubscriptionService.refreshFromSupabase`, `ScheduledWorkoutsResyncMigrator.runIfNeeded`, splash `_autoGenerateNextPhaseForPro`) read user-scoped Hive boxes BEFORE `_ensureLocalUser` has opened the namespaced session. Every box read threw `HiveUserSession not opened`; the surrounding catch swallowed it; rank promotions / PRO refresh / one-shot resync / PRO auto-generate next phase silently no-opped on every cold start. Test #12.6 added defensive bootstrap to only the SyncService path; the other 4 still raced.

### silent_debugprint_catch (1 bugs)
- 2026-05-11 7ad0d0 — `catch (e) { debugPrint(...); }` patterns across `lib/core/services/` + `lib/shared/repositories/` logged to the device console but emitted NO Crashlytics signal + NO `client_errors` row. Production users hit the bug, devs never saw it. Multiple instances over Test #12 series + this audit (Bug A, C-2, rank_service hot path) traced back to this silent-swallow class.

### security_definer_hardening (1 bugs)
- 2026-05-11 7ad035 — 5 SECURITY DEFINER functions had no search_path config (injection risk); coach_tool_invocations_v view ran as creator bypassing RLS; 9 SECURITY DEFINER functions granted EXECUTE to anon and authenticated allowing PostgREST RPC bypass of Edge Function business rules.

### rls_policy_cleanup (1 bugs)
- 2026-05-11 7ad054 — rank_ladder had RLS enabled with zero policies (deny-all client reads); promo_code_uses INSERT policy was scoped to roles=public with WITH CHECK=true allowing any authenticated user to insert audit rows directly via PostgREST.

### reactive_subscription_three_sites (1 bugs)
- 2026-05-11 7ad0cd — 3 surfaces (`userStatsProvider`, `train_screen` WeekSelector.onSelect, `swap_sheet`) snapshot `SubscriptionService.instance.isPro()` at build/init time and never reactively rebuild when the user upgrades to PRO mid-session. Same stale-PRO class APK Test #12 / C-2 already closed for the home screen + roadmap surfaces. Result — user pays for PRO, the stats card still says "free", week selector still routes to the read-only preview screen, swap sheet still enforces free-tier restrictions until the page is reopened.

### chat_workout_draft_write_service (1 bugs)
- 2026-05-11 7ad0c8 — `submitWorkoutDraft` (the chat-confirmation handler for AI-coach-detected workouts) wrote `exlog_<ts>_<hash>` and `wlog_<ts>` rows directly to Hive with the *legacy* field shape (`sets_completed`, no `sets[]`, no `set_number`, no IST-stable key, no per-set rows). Bypassed `WorkoutWriteService`. Result — receipts and AI snapshot readers (`_getThisWeekWorkouts` / `_getPersonalRecords` / `_getMealsToday`) silently dropped every chat-confirmed workout because they filter on the new field shape introduced by Test #8. AI coach gave advice based on a workout history that excluded every "I did 3x10 squats" message the user confirmed.

### cron_auth_gate (1 bugs)
- 2026-05-11 7ad0c4 — 8 cron Edge Functions had verify_jwt false at the gateway AND no manual auth check at handler entry. Anyone with the function URL could trigger expensive Gemini fanout, OneSignal pushes, or DB scans across the entire user base.

### cross_account_guard_on_open (1 bugs)
- 2026-05-11 7ad0c6 — splash_screen.dart cross-account Hive leak guard was a no-op on every cold start. `HiveService.instance.userBox` is a `GuardedBox` that throws `HiveUserSession not opened` before any `openForUser` has run; the try/catch swallowed it and the guard never executed. Android Auto Backup restores / dev-build Hive copies / legacy migration races could leave a foreign profile.id inside the new user's namespaced box and the safety net CLAUDE.md §19 promises did not actually run.

### delete_account_rate_limit (1 bugs)
- 2026-05-11 7ad009 — delete-account Edge Function had no rate limit on the confirmation-token check. A malicious actor knowing a target's 8-char user_id prefix could repeatedly POST attempts; each fires Razorpay + DB queries before the 400 reject — DoS vector at scale.

### deterministic_uuid_v5_keys (1 bugs)
- 2026-05-11 7ad0d4 — 3 deterministic-key helpers (`_nlogKeyForRestore` in sync_service, `exlogKey` in workout_write_service, `_stableItemsHash` in nutrition_write_service) computed their 8-char tag via `String.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0')`. Dart's `String.hashCode` is NOT guaranteed stable across VM versions / isolates / platforms — cross-device round-trip (cloud → Hive on restore, or sync between devices) could produce different tags for the same logical tuple → duplicate Hive rows for what should be one row.

### edge_function_ist_sweep (1 bugs)
- 2026-05-11 7ad0d3 — 7 Edge Function date-key sites used UTC midnight (`new Date().toISOString().split("T")[0]`, `setUTCHours(0,0,0,0)`, etc.) for rate-limit windows, snapshot keys, and look-back cutoffs. For Indian users (UTC+5:30), the UTC date doesn't roll over until 05:30 IST — so the daily 10-msg cap reset at dawn, vision cap reset at 05:30, weekly recalcs covered the wrong 7-day window, and monthly prediction re-trigger cutoffs were off by 5h30m.

### edge_input_validation (1 bugs)
- 2026-05-11 7ad0d6 — 3 Edge Function input-validation gaps. (H-21) ai-proxy `scan_meal` + `cart_auditor` accepted `body.image` (base64) with NO size validation — a 50MB+ blob would forward to Gemini unbounded, burning cost + Edge Function memory. ai-media-proxy already enforces 5MB; ai-proxy was the gap. (H-22) ai-proxy `food_text_analysis` accepted `body.text` with NO length cap, while the chat channel had a 5000-char cap on `message`. (H-23) ai-media-proxy PRO image-chat path had NO per-day rate limit — a compromised PRO token could drain unlimited Gemini-vision quota in minutes.

### full_name_email_prefix (1 bugs)
- 2026-05-11 7ad0ce — Email-signup users (Supabase Auth's email flow carries no metadata) had `public.users.full_name` permanently seeded with `email.split('@').first`. The `_ensureLocalUser` upsert ran with `ignoreDuplicates: true` so the email-prefix seed stuck FOREVER. AI coach + weekly recap + every greeting addressed users by their email prefix for the lifetime of the account.

### storage_policy_dedupe (1 bugs)
- 2026-05-11 7ad038 — H-38 disposition — Path 1 (dedupe SELECT policies). Supabase advisor flagged `public_bucket_allows_listing` on storage buckets `avatars` + `banners`. Inspection found 3 duplicate SELECT policies per bucket (6 redundant rows in pg_policies). Founder elected Path 1 cosmetic cleanup + accept the public-bucket UX trade-off (avatars need anonymous `<img src>` rendering for app UI).

### error_telemetry_funnel_completion (1 bugs)
- 2026-05-11 7ad0e0 — Phase 8 cleanup deferred the remaining 21 grandfathered `catch (e) { debugPrint(...) }` patterns in `lib/core/services/` + `lib/shared/repositories/` to a follow-up batch. Per audit doc §4 H-42 finding + the audit's "no deferrals" discipline rule, this batch retrofits ALL remaining grandfathered files — 20 services + 4 repositories. Each catch now pairs the existing `debugPrint(...)` with `unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: '<op_type>'))` so production silent failures surface in Crashlytics + the `client_errors` table.

### nutrition_write_service_expansion (1 bugs)
- 2026-05-11 7ad0c9 — 4 nutrition mutations bypassed `NutritionWriteService` (the documented sole writer per CLAUDE.md §15). `SavedMealsNotifier.saveMealPreset` / `.relogSavedMeal` / `.deleteSavedMeal` + `FoodLogNotifier.restoreFoodLog` each wrote `nutritionBox` rows directly, with `relogSavedMeal` ALSO firing the legacy `NutritionRepository.syncLogToSupabase` double-write. Side effects — provider-invalidation drift (notifiers fired their own list, didn't share the WriteService canonical batch), legacy flat-totals shape on relog (no `items[]`), and the double cloud-write path producing 2 rows per re-log when the timing aligned. Additionally `WaterNotifier.addWater` + `.decrement` built non-IST date keys for `water_ml_<date>`, breaking the IST-anchored contract per CLAUDE.md.

### payment_hardening (1 bugs)
- 2026-05-11 7ad0d5 — 3 payment-stack hardening gaps. (H-18) verify-payment's `.insert()` fallback after upsert error did not catch Postgres 23505 (unique_violation), so a concurrent webhook + verify-payment race would surface as a 500-ish error response instead of treating the existing row as success. (H-19) razorpay-webhook auto-captured `payment.authorized` events BEFORE the idempotency pre-SELECT, so a replayed `payment.authorized` for an already-captured payment fired a second Razorpay capture call → Razorpay 4xx ("already captured") → we returned 502 → Razorpay retried the same loop. (H-20) `RazorpayService._pollAndActivate` ran `Future.delayed` poll retries with no cancellation — if the user signed out / signed in as a different account mid-poll, the loop would write PRO state to the WRONG user's Hive.

### payment_in_flight_event_based (1 bugs)
- 2026-05-11 7ad0cf — `SubscriptionService` payment grace window was a pure time-based `paymentInFlightUntil` ISO timestamp. Two pathologies — (a) a slow webhook past 10 min flips grace to false even though we're still legitimately awaiting verdict, so refreshFromSupabase / verifyFromServer can downgrade a paying user; (b) a fast confirmation in 5s leaves the window open for another 9:55, masking unrelated downgrade events during that window (e.g. server returns is_pro=false for a different reason and the grace check suppresses it).

### phase5_schema_completeness (1 bugs)
- 2026-05-11 7ad0d7 — 6 schema-completeness gaps. (H-13) `_restoreCustomExercises/Foods` wrote to legacy LIST keys (`custom_exercises` / `custom_foods`) while every reader scans per-key (`custom_exercise_*` / `custom_food_*`) → restored items vanished from `getCustomExercises()` and never re-synced. (H-14) `syncCommunityItems` had no `.limit()` or pagination — every app launch downloaded the entire approved community library. (H-25/26/27/28) Missing UNIQUE constraints / index across 4 tables — cross-device sync race could create duplicates that double-count. (H-31) `community_reviews` existed on prod but had no migration in source (Dashboard-created). (H-33) Two migration files shared the `050` prefix; filesystem ordering non-deterministic. (H-34) Source vs prod migration count mismatch.

### phase6_contract_tests (1 bugs)
- 2026-05-11 7ad0d8 — 11 invariants documented in CLAUDE.md / audit findings / prior bug retros had no automated guardrail. Future code changes could silently remove them. Examples — delete-account skips confirmation_token check, razorpay-webhook drops the 5-min replay window, ai-proxy stops catching the food-text rate-limit trigger error, `isPro()` accidentally returns `true` on null expiry in release, `gate()` stops calling `verifyFromServer` for high-value features, exercise_selector cascade drops the universalPool fallback, etc.

### phase7_integration_scaffolds (1 bugs)
- 2026-05-11 7ad0d9 — 10+ critical end-to-end flows had no integration test coverage at all — Razorpay purchase (the entire payment stack), sign-up + onboarding traverse, delete-account (DPDP §17 irreversible), cross-account isolation, cross-device restore, workout completion → receipt → share, streak freeze refill ↔ consume, plan generator → first workout, custom exercise submission flow, promo code apply, AI coach tool-calling. Audit recommended building out the scaffolding even if the bodies are skipped pending device-CI infrastructure.

### anon_jwt_leak (1 bugs)
- 2026-05-11 7ad0c3 — .claude/settings.local.json was tracked in git AND contained the Supabase anon JWT in committed permission entries; the same JWT also appears in git history (lib/core/constants/app_constants.dart commit ef878af, removed in 5c40925) so simple file removal does not retire the leaked credential.

### promote_community_item_admin_gate (1 bugs)
- 2026-05-11 7ad0c5 — promote-community-item ran as service-role with verify_jwt only at gateway level - any authenticated user could call POST functions v1 promote-community-item and trigger global writes to food_database and exercise_library. The 10-vote community threshold was the only caller-identity gate.

### phase8_cleanup (1 bugs)
- 2026-05-11 7ad0da — Phase 8 cleanup catch-all. (Hive sequential) `HiveService.init` opened 9 shared boxes serially via a for-loop — sequential file I/O wasted 150-300 ms of cold-start time. (community_review_sheet `as Map`) two `f as Map` / `e as Map` casts at lines 71+77 would TypeError on a non-Map row (PostgREST schema drift would crash the sheet). (H-42 retrofit batch) 28 grandfathered `catch (e) { debugPrint(...) }` sites remain after the audit's first batch; 4 hot-path services retained the silent-swallow pattern — health_sync_service (4 sites — fires on every splash), razorpay_service (8 sites — payment flow), stat_snapshot_service (5 sites — onboarding + promotion + manual snapshots), subscription_service (1 site — refreshFromSupabase failures only surfaced via the log-client-error helper, not Crashlytics).

### workout_template_sync (1 bugs)
- 2026-05-10 a8b2c7 — _syncWorkoutTemplates used a DELETE-then-INSERT pattern for child template_exercises rows. If the DELETE succeeded but a subsequent INSERT errored mid-loop (network blip, FK constraint, payload error), the user's template was left with PARTIAL children — half the exercises missing, no audit trail. Next sync re-DELETED + tried again. Idempotent on success but lossy on partial failure.

### streak_freezes (3 bugs)
- 2026-05-10 c5d2a8 — Streak pill showed only ❄ <available> (single digit), so a PRO user with 1 freeze remaining had no signal that capacity was 3 — and a user at 0 freezes had the snowflake section invisible entirely.
- 2026-05-10 b3d8f9 — PRO user who burns all 3 streak freezes in week 1 gets back to 3 the following Monday — full reset, no incentive to save freezes.
- 2026-05-10 d4e5f6 — Cloud user_progress default for streak_freezes_available was 2 — neither matched free baseline (1) nor PRO max (3). Fresh accounts got an inconsistent middle-ground value before the client's first refill ladders them.

### cross_account_isolation (1 bugs)
- 2026-05-10 f4d6c2 — 3 cross-account isolation tests in test/auth/cross_account_isolation_test.dart were stubbed with `skip:` referencing HiveService.lastAuthenticatedUserIdKey — a constant from an abandoned Plan A namespacing prototype. The test file added zero coverage to the actually-shipped HiveUserSession + GuardedBox surface.

### ai_coach_chat_history (1 bugs)
- 2026-05-10 e8a3b1 — Opening the AI coach screen lands the scroll position at 0 (oldest message at top). User has to manually scroll down through the entire transcript just to see the latest exchange and reach the input row.

### log_client_error_payload (1 bugs)
- 2026-05-10 task22 — No diagnose-docs existed for ~35 fix/feat commits since Test #11 (merge 0babf83), meaning /build-apk Gate 10 would trip on all historical commits lacking diagnose coverage.

### error_telemetry_helper (1 bugs)
- 2026-05-08 b0fd76 — Telemetry payload had no contract (any shape was accepted, breaking structured log queries); restore had a race condition where stale tmpl_* keys from earlier broken restores accumulated and caused duplicate templates across APK upgrades.

### workout_templates (1 bugs)
- 2026-05-08 5a36ad — Sync stack had systemic failures — workout templates were not deduped (UNIQUE constraint added), streak pill showed cached value instead of live calculateCurrentStreak(), completed_at was overwritten to NOW on every sync retry corrupting founder's Tue+Wed logs.

### subscription_state (3 bugs)
- 2026-05-06 69276a — subscriptionInfoProvider was not invalidated on cold-start subscription state writes (verify, downgrade), so PRO status changes did not propagate to the UI until next hot restart.
- 2026-05-06 979a8e — PRO upgrade did not reflect immediately in train screen; train expanded view showed 0 sets; macros displayed incorrectly — three stacked bugs from the first on-device audit.
- 2026-05-04 5d2ff1 — razorpay-webhook derived plan (monthly/yearly) from client-supplied body.plan instead of payment amount, allowing a monthly payment to grant yearly entitlement.

### subscription_payment_grace_window (2 bugs)
- 2026-05-06 d9b546 — PRO unlock still failed systemically across multiple code paths; logging_type repair migrator was not library-aware, repairing to wrong types for exercises present in the library.
- 2026-05-06 5456c4 — Multiple issues in one batch — PRO upgrade did not unlock after payment, receipt showed wrong set counts, today card had duplicate text, weight chart decimals were static, swap kept stale logging_type, WardSetChips was duplicated in two surfaces.

### hive_field_name_nlog (6 bugs)
- 2026-05-06 fe579a — ai_coach_repository called istDateStr(istNow()) causing a double IST shift — plan summaries showed wrong date and eta_next_promotion dates were off by one day.
- 2026-05-04 39f8ce — AI breakdown card silently disappeared after save with no user feedback, making users believe the meal was not logged.
- 2026-05-04 933330 — Post-account-deletion null user_id in community rows caused promote-community-item to crash; three additional IST date escape sites wrote UTC dates to Hive.
- 2026-05-04 26b360 — AI snapshot and usage counter resets used UTC or device-local dates instead of IST, causing midnight-crossing mismatches for Indian users.
- 2026-05-04 acdcfb — FoodLogNotifier wrote flat-totals nlog_* rows without items[] array, so cloud nutrition_log_items got 0 rows for those logs and AI coach/weekly-report saw no meal items.
- 2026-05-04 0f8d54 — Usage counters incremented on meal save rather than on API call, so users who analysed without saving saw incorrect 'remaining' counts diverging from server rate-limit trigger.

### hive_field_name_exlog (2 bugs)
- 2026-05-06 519075 — Cloud-side audit surfaced multiple failures — logging_type repair migrator needed systematic rebuild, razorpay 409 detection was dead code (FunctionException class), sync had IST gaps, train screen had stale receipt rendering.
- 2026-05-04 270ea3 — Workout restore wrote Hive keys using cloud UUIDs instead of deterministic WriteService keys, causing exercise logs to be unreadable by receipt and calendar readers.

### sync_fanout_nutrition_domain (1 bugs)
- 2026-05-06 344121 — Second cloud-side audit revealed 4 bugs — NutritionWriteService.onStateChanged hook missing, foodLogProvider missing from invalidation set, LoggingTypeRepairMigrator had unhandled edge cases, and app.dart was not wiring the new hook.

### user_scoped_hive_keys (2 bugs)
- 2026-05-05 8a2e9b — 25 additional user-scoped configBox keys remained after the Test #10.1 hotfix (6 keys), and OneSignal player_id was never synced to cloud, causing push unsub to silently no-op on account deletion.
- 2026-05-04 617ea1 — User-scoped data (isPro flag, prediction text, localActivationAt) persisted in shared configBox and leaked to the next account signed in on the same device.

### cross_cutting (4 bugs)
- 2026-05-04 2c645c — Welcome screen displayed misleading 'no streaks' copy and app.dart showed a 'restart' error message that does not resolve any real issue.
- 2026-05-04 4c49d6 — Logo rendered at full resolution on splash without cacheWidth hint, causing unnecessarily large decode on low-memory devices.
- 2026-05-04 40a426 — V4 plan generator had 38 cascade fallback failures (universalPool picks) because the exercise library pool was too shallow for advanced slot targets.
- 2026-05-04 f631f0 — Profile screen called Supabase and Edge Functions directly from widget code, bypassing the repository pattern and making the calls untestable and hard to audit.

### water_target (1 bugs)
- 2026-05-04 11bcfb — Four UI sites hardcoded 3000 ml for water target instead of computing it from user weight and activity, causing incorrect 100% at 3L for light users.

### coaching_notes (1 bugs)
- 2026-05-04 d9d77c — Captain voice prompts were duplicated across proactive trigger Edge Functions instead of sharing a single source, risking voice drift between triggers.

## By feature directory

## Chronological (latest first)

| Date | Bug ID | Symptom | Concept | Test path |
|---|---|---|---|---|
| 2026-05-29 | 7c2a8b | > | workout_completion_status | test/sync/restore_field_canonical_test.dart |
| 2026-05-29 | 9e1d4c | > | coach_interactions | test/contracts/proactive_coach_promotion_test.dart |
| 2026-05-29 | c3d8a1 | > | blast_radius_commit_autotag | not_applicable (shell git-hook behavior; verified by simulating the hook against a temp commit-message file with a staged path) |
| 2026-05-28 | b1f4e2 | > | alert_detection_edge_function_health | not_applicable (live cron behavior; verified via cron.job_run_details query — source-grep contract test would not catch a column-name mismatch that only fails at runtime against live schema) |
| 2026-05-27 | 3a7b9f | \| | rank_monotonic_current_code | test/contracts/rank_no_demotion_behavioral_test.dart |
| 2026-05-27 | ada3fb | \| | exercise_library_cloud_seed | test/contracts/exercise_library_cloud_seeded_test.dart |
| 2026-05-24 | 2b705b | \| | source_grep_contract_test_recovery_post_refactor | this doc IS the recovery contract; flutter test exit 0 is the contract |
| 2026-05-24 | 524d12 | \| | writer_reader_drift_batch_2026_05_24 | test/contracts/nlog_key_canonical_test.dart |
| 2026-05-23 | 85a684 | \| | week_selector_past_phase_scroll | test/contracts/week_selector_past_phases_test.dart |
| 2026-05-23 | ea1059 | \| | graduation_phase2_preview | test/contracts/graduation_phase2_preview_dynamic_test.dart |
| 2026-05-22 | 7f2a8c | \| | singleton_lifecycle_registry | test/contracts/singleton_provider_invariant_test.dart |
| 2026-05-22 | 7b3eaf | \| | subscription_gate | test/contracts/subscription_gate_catcherror_test.dart |
| 2026-05-22 | 9aa2c1 | \| | rank_promotion_celebration | test/contracts/promotion_celebration_wiring_test.dart |
| 2026-05-22 | 8b1f33 | \| | proactive_coach_promotion | test/contracts/proactive_coach_promotion_test.dart |
| 2026-05-22 | b0baa5 | \| | scheduled_workouts_mutations | test/contracts/phase_unlock_start_date_test.dart |
| 2026-05-22 | ec4d27 | \| | phase_unlock_end_to_end | test/contracts/phase_unlock_end_to_end_test.dart |
| 2026-05-22 | 0e7714 | \| | phase_unlock_card_surface_gate | test/contracts/phase_unlock_card_thursday_gate_test.dart |
| 2026-05-22 | dc52a4 | \| | hive_session_init_race | test/contracts/splash_no_userbox_touch_test.dart |
| 2026-05-22 | 89d56c | \| | exercise_logs_read_path | test/contracts/graduation_stats_provider_field_test.dart |
| 2026-05-22 | 599d49 | \| | food_text_analysis | test/contracts/food_ai_telemetry_retry_test.dart |
| 2026-05-22 | b4a09c | \| | ai_snapshot_building | test/ai_coach/meals_today_snapshot_test.dart |
| 2026-05-22 | d882ca | \| | workout_schedule_service_split | test/contracts/workout_schedule_split_invariant_test.dart |
| 2026-05-22 | 4a3b08 | \| | restore_completeness | test/contracts/restoring_screen_timeout_test.dart |
| 2026-05-21 | b3ecf2 | \| | edge_function_deploy_reversibility | scripts/check_edge_function_rollback_script.dart |
| 2026-05-21 | 1f4a8b | \| | typography_canonical_source | test/contracts/no_raw_google_fonts_test.dart |
| 2026-05-21 | 7a3e1c | \| | singleton_lifecycle_registry | test/contracts/singleton_lifecycle_registry_test.dart |
| 2026-05-21 | 2d1c8a | \| | referral_redemption | test/contracts/referral_repository_only_test.dart |
| 2026-05-21 | 3cbbce | \| | profile_write_service | test/contracts/profile_write_service_only_test.dart |
| 2026-05-21 | 3e9d39 | \| | dependency_canonical_http_client | scripts/check_no_http_package.dart |
| 2026-05-21 | 17ae38 | \| | post_signin_destination | test/contracts/auth_session_bootstrapper_test.dart |
| 2026-05-21 | 9c2b1f | \| | ai_coach_repository_split_A10 | test/contracts/ai_snapshot_builder_only_test.dart |
| 2026-05-21 | 2b8d4e | \| | sync_domain_full_migration_A6 | test/contracts/sync_domain_full_migration_test.dart |
| 2026-05-21 | 5a0b31 | \| | sync_domain_interface_scaffold_A6 | test/contracts/sync_domain_interface_test.dart |
| 2026-05-20 | b3f7a2 | \| | weight_trend_range | test/contracts/weight_sparkline_all_chip_and_footer_link_test.dart |
| 2026-05-20 | c2a91f | \| | usage_weeks_signup_age | test/contracts/usage_weeks_uses_supabase_signup_test.dart |
| 2026-05-19 | 4f8e2d | \| | restore_long_pole_timing_visibility | test/contracts/streak_freeze_refill_telemetry_test.dart |
| 2026-05-19 | 9c4a17 | \| | streak_freeze_refill_restore_race | test/contracts/streak_freeze_refill_race_test.dart |
| 2026-05-18 | w7r4c3 | \| | weight_log_provider_invalidation_race | test/contracts/weight_log_invalidation_awaitable_test.dart |
| 2026-05-18 | s1n4c0 | \| | swap_undo_snackbar_modal_stack | test/features/train/swap_undo_snackbar_dismisses_test.dart |
| 2026-05-18 | f8c1a5 | \| | streak_freeze_value_clamp_on_read | test/contracts/streak_freeze_value_clamped_on_read_test.dart |
| 2026-05-18 | t1m5b0 | \| | ai_tool_wall_clock_and_media_proxy_error_class | test/contracts/get_progress_summary_parallel_queries_test.dart |
| 2026-05-17 | 4dd7e2 | \| | restore_completeness_symmetric | test/contracts/restore_round_trip_field_coverage_test.dart |
| 2026-05-17 | 9d2a47 | \| | partial_unique_arbiter_safety | test/contracts/partial_unique_arbiter_inventory_test.dart |
| 2026-05-17 | d1e7e6 | \| | nutrition_delete_canonical_writer | test/contracts/nutrition_delete_routes_through_write_service_test.dart |
| 2026-05-17 | 41507e | \| | current_streak_single_reader | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 40c401 | \| | paywall_single_purchase_path | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 1c3401 | \| | migration_live_verify_gate | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 5fe338 | \| | streak_freeze_refill_extract | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 4a37e7 | \| | rank_promotion_local_sync | test/contracts/rank_service_local_profile_update_test.dart |
| 2026-05-17 | c84e33 | \| | apk_size_gate_strict_mode | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 3a7c1e | \| | cross_account_guard_exempt_declaration | test/contracts/auth_invalidation_contract_test.dart |
| 2026-05-17 | 7c4e5d | \| | marked_done_without_logging_ux | test/contracts/marked_done_vs_logged_ux_test.dart |
| 2026-05-17 | 0a1e17 | \| | reader_manifest_exhaustive_completeness | test/contracts/reader_manifest_exhaustiveness_test.dart |
| 2026-05-17 | 8d85c2 | \| | workout_read_service | test/contracts/workout_read_service_per_set_semantic_test.dart |
| 2026-05-17 | c0e3a5 | \| | snapshot_contract_enforcement | test/contracts/snapshot_contract_gate_test.dart |
| 2026-05-17 | 93aeac | \| | ai_snapshot_building | test/contracts/snapshot_contract_self_consistency_test.dart |
| 2026-05-17 | 9a7c14 | \| | razorpay_webhook_handler_correctness | test/contracts/razorpay_webhook_supabase_client_decl_order_test.dart |
| 2026-05-17 | b3e052 | \| | verify_payment_payload_completeness | test/contracts/verify_payment_payload_completeness_test.dart |
| 2026-05-17 | 5e055f | \| | ai_media_proxy_user_scope_assertion | test/contracts/ai_media_proxy_user_scope_test.dart |
| 2026-05-17 | c8f229 | \| | verify_payment_notes_user_id_guard | test/contracts/verify_payment_notes_user_id_required_test.dart |
| 2026-05-17 | c1ea30 | \| | clean_orphan_media_bucket_target | "must add: test/contracts/clean_orphan_media_targets_chat_media_test.dart" |
| 2026-05-17 | c4031b | \| | cron_edge_function_auth_gate | test/contracts/cron_auth_adoption_test.dart |
| 2026-05-17 | a2d0e1 | \| | delete_account_storage_purge_recursive | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | d0c352 | \| | doc_internal_consistency_table_count | scripts/check_doc_internal_consistency.dart |
| 2026-05-17 | 39ead9 | \| | train_provider_workout_read_service_delegation | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 7faa3b | \| | snapshot_writer_contract | test/contracts/snapshot_orphan_reader_aliases_test.dart |
| 2026-05-16 | 2026-05-16-workout-schedule-service-bypass |  |  |  |
| 2026-05-16 | 9d12af | \| | client_errors_telemetry_pipeline | test/safety/error_telemetry_rate_limit_test.dart |
| 2026-05-16 | daffac | \| | workout_log_id_session_scoping | test/contracts/load_all_exercise_prs_per_set_semantic_test.dart |
| 2026-05-16 | 2026-05-16-terms-accepted-at-dpdp | \| | terms_acceptance_audit_trail | test/contracts/terms_signup_writes_test.dart |
| 2026-05-16 | 2026-05-16-telemetry-hardening | Telemetry framework had five compounding observability gaps surfaced by audit Agent 7 — no success-path emission on 5 low-usage sync methods (cannot distinguish "feature unused" from "silently failing"), no cron-execution telemetry (F10.5), no `_shared/cron_auth.ts` (F9.1 — Test #16 P1-D drift class), generic numbered op_types defeating triage (F10.3), and undetected HIGH_PRIORITY_OP_TYPES client/server drift (F10.4). | ErrorTelemetry + sync success/failure signal + cron auth | test/contracts/high_priority_op_types_parity_test.dart |
| 2026-05-16 | 2026-05-16-sync-coach-cross-channel-dedup |  |  |  |
| 2026-05-16 | 5beed5 | \| | sleep_logs | test/contracts/sleep_chat_routes_through_health_write_service_test.dart |
| 2026-05-16 | 2026-05-16-schedule-completion-duration | \| | workout_schedule_completion_cloud_projection | test/contracts/schedule_completion_duration_writer_to_reader_test.dart |
| 2026-05-16 | 2026-05-16-referral-restore-completeness | \| | referral_restore_completeness | test/contracts/restore_completeness_writes_test.dart |
| 2026-05-16 | 2026-05-16-rank-widget-migration |  |  |  |
| 2026-05-16 | 2c1c0d | \| | prediction_card_display | test/contracts/prediction_card_onboarding_copy_test.dart |
| 2026-05-16 | cb1ab1 | \| | exercise_personal_records | test/contracts/load_all_exercise_prs_per_set_semantic_test.dart |
| 2026-05-16 | 913261 | \| | ai_media_proxy_status_code_classification | test/contracts/ai_media_proxy_status_code_classification_test.dart |
| 2026-05-16 | 5bea3e | \| | ai_media_proxy_classification | test/contracts/edge_function_storage_race_retry_test.dart |
| 2026-05-16 | 1bfeed | \| | onboarding_completed_at | test/contracts/onboarding_completed_migrated_key_test.dart |
| 2026-05-16 | 2026-05-16-ai-proxy-placeholder-resolution |  |  |  |
| 2026-05-16 | a17bc3 | Founder's `ai_coach_interactions` table shows 6 rows for the same `user_message='curd 200gms whey 1.5 scoops cashew 6'` (3 timestamps × 2 channels). Each "Analyze with AI" tap during Gemini 502 storm produced (a) a Hive `coach_*` row, (b) a server-side placeholder row (channel=food_text_analysis, model_used=pending), and (c) a sync-time orphan row (channel=in_app_orphan). No client-side circuit breaker — user can tap retry indefinitely and each tap fans out to 3 cloud rows. | ai_coach_interactions_dedup | test/ai_coach/coach_writer_dedup_test.dart |
| 2026-05-16 | 2026-05-16-dead-columns-dropped |  |  |  |
| 2026-05-16 | 2026-05-16-doc-updates |  |  |  |
| 2026-05-16 | a16c1a | \| | exlog_key_sot | test/contracts/exlog_key_canonical_test.dart |
| 2026-05-16 | de29b8 |  |  |  |
| 2026-05-16 | 2026-05-16-gate-coverage-and-dead-code |  |  |  |
| 2026-05-16 | e7a516 | \| | health_write_service | "test/contracts/health_write_service_writer_to_reader_test.dart" |
| 2026-05-16 | 2026-05-16-logpr-bypass |  |  |  |
| 2026-05-15 | 9f4ab2 | \| | sync_natural_key_guard | test/contracts/sync_natural_key_guard_test.dart |
| 2026-05-15 | c01d57 | \| | edge_function_cold_start_resilience | test/contracts/edge_function_cold_start_retry_behavioral_test.dart |
| 2026-05-15 | 4e9515 | Founder asked for a "debugging" skill earlier in the session; both `superpowers:debugging` and `debugging` returned `Unknown skill`. The project's `.claude/skills/` directory did not exist. Debugging methodology was tribal knowledge spread across CLAUDE.md §19, MEMORY.md feedback_* files, and project_apk_test_*.md retrospectives — not invocable as a single skill. Result: every batch since Test #6 has re-discovered the same writer/reader drift class because the methodology to catch it was undocumented as a skill. | debugging_methodology | "n/a — process discipline addition; the SKILL.md file itself is the contract, and § 5 self-evolution rule is enforced by the next debugging session's output contract (§ 4)" |
| 2026-05-15 | 25e91d | \| | cloud_upsert_natural_key_contract | test/sql/onconflict_live_arbiter.sql |
| 2026-05-15 | 76c8f4 | PostgREST raises 42P10 "no unique or exclusion constraint matching the ON CONFLICT specification" on every upsert to workout_logs (onConflict=user_id,date,exercise_name), workout_log_exercises (onConflict=workout_log_id,exercise_id,set_number) and nutrition_logs (onConflict=user_id,date,meal_type); 47 client_errors rows for a single user in a 60-second window on 2026-05-15 04:10 UTC. | sync_fanout_workout_domain | test/contracts/sync_onconflict_natural_key_test.dart |
| 2026-05-15 | 5a65bd | pr-detection Edge Function cron returns 401 every 15 minutes; same shape affects 6 other C-4-gated proactive trigger functions (re-engagement, plateau-alert, protein-gap-alert, workout-window-closing, evaluate-rank-promotions, streak-guardian, i-see-you-callout, clean-orphan-media — every function with verify_jwt=false that imports the C-4 in-function cron-auth-gate). | cron_auth | "n/a — operational/config drift, not field-rename class" |
| 2026-05-15 | a5d29c | \| | custom_exercises_mutations | test/widgets/swap_sheet_custom_exercises_test.dart |
| 2026-05-12 | 8c4ee3 | After completing the post-onboarding muster flow (MusterScreen) and entering shoulders as a known injury and legs as the body-part priority, Edit Profile continued to show injuries=['none'] and physique_focus='balanced'. Muster answers persisted to coachBox only and never bridged into userBox['profile'] — the AI coach saw the answers, but Edit Profile and the plan generator did not. | muster_to_profile_bridge | test/contracts/muster_profile_bridge_test.dart |
| 2026-05-12 | e6a2d4 | "LAST: 50KG · 135 REPS" rendered above Leg Extension in active workout screen — 135 reps per set is unrealistic. Cloud `workout_log_exercises` had 3 corrupt rows from May 7 with set_number=15 + reps=110-150 (bulk-completion aggregates misinterpreted as per-set). | workout_log_exercises_input_validation | test/contracts/rep_input_validation_test.dart |
| 2026-05-12 | 9e2c1a | \| | scheduled_workouts_mutations | test/contracts/restore_template_schedule_test.dart |
| 2026-05-12 | d8e5b3 | Photo upload to AI coach → "Sorry, I couldn't analyse that photo. Please try again." Zero client_errors rows for ai-media-proxy in last 12h — generic fallback fires silently without telemetry. | ai_media_proxy_error_handling | test/contracts/ai_media_proxy_telemetry_test.dart |
| 2026-05-12 | a2f9e1 | Home renders "Something went wrong" ErrorState after the user schedules a custom template for today. Crash repeats on every cold-start. Telemetry shows 5x widget_error_fallback with message "type 'String' is not a subtype of type 'int?' in type cast". | schedule_exercise_field_types | test/contracts/schedule_exercise_field_types_test.dart |
| 2026-05-12 | 3f8a91 | \| | cloud_upsert_natural_key_contract | test/contracts/sync_onconflict_natural_key_test.dart |
| 2026-05-12 | b3c8d2 | Founder's templates "Back Day A", "Leg Day A", "Push Day" each showed 14-15 exercise rows with only 4-5 distinct names ("triplicated"). Editing the template + removing duplicates + saving brought the dupes back on next reopen. | template_exercises_cloud_tail_rows | test/contracts/template_exercises_tail_vacuum_test.dart |
| 2026-05-12 | 6e1b45 | \| | exercise_set_field_name_contract | test/contracts/timed_exercise_render_contract_test.dart |
| 2026-05-12 | a9f3d2 | Home today-card showed "BACK DAY A · DONE" (green DONE pill) for Sat May 9, but the calendar-strip's Sat May 9 cell showed only the gold today-border with NO checkmark, while earlier completed days (Mon May 4) correctly showed a checkmark. | workout_completion_status | "must add: test/contracts/today_card_vs_calendar_strip_same_source_test.dart" |
| 2026-05-12 | a13a01 | User asks AI coach "how was my workout today?" after partially completing a Pull-day session (logged 4 of 8 prescribed exercises — Lat Pulldown, Dumbbell Row, Hanging Leg Raise, Concentration Curl). Coach replied with the FULL planned 8-exercise list as if everything had been completed, because today_workout.exercises emits the schedule_<date> entry verbatim regardless of how many exlog_* rows exist for the day. | today_workout_snapshot_reads_logged | "test/contracts/today_workout_reads_logged_contract_test.dart" |
| 2026-05-12 | d4e9c1 | \| | workout_completion_status | test/contracts/logout_login_round_trip_test.dart |
| 2026-05-12 | 8f3d22 | \| | scheduled_workouts_mutations | test/contracts/template_schedule_completed_day_test.dart |
| 2026-05-12 | c7d4f6 | After signing out as Upendra and signing up as new account sumit1@gmail.com, the Profile screen showed Upendra's full profile data (full_name=Upendra, dob=1988-06-30, height=174cm, weight=78.3kg, target=80kg). Cloud was correct for both accounts (sumit1's cloud user_profile row had Sumit/2001-01-01/175cm/75kg). The leak was in local Hive userBox['profile']. | hive_user_session_static_state | test/safety/hive_user_session_concurrency_test.dart |
| 2026-05-12 | 7bd154 | After signing out as Upendra and signing up as sumit1@gmail.com on the same session, Edit Profile rendered Upendra's profile (174 cm / 77.8 kg / DOB 1988-06-30) until the app was force-killed and reopened. The Riverpod cache held the previous user's profile because providers rebuilt on the Supabase auth event before HiveUserSession.openForUser had completed swapping the box owner. | cross_account_riverpod_cache_race | test/contracts/auth_invalidation_timing_test.dart |
| 2026-05-12 | c4055a | \| | user_scoped_riverpod_providers | test/contracts/auth_invalidation_contract_test.dart |
| 2026-05-12 | b7e3f1 | On Sunday morning cold start, home today-card showed Saturday's completed workout ("BACK DAY A · DONE · Lat Pulldown 40kg") even though the IST calendar had advanced to Sunday May 10. | day_rollover_provider_invalidation | "test/contracts/cold_start_day_rollover_test.dart" |
| 2026-05-12 | a2b3c4 | \| | workout_receipt_rendering | test/contracts/duration_seconds_aggregate_populated_test.dart |
| 2026-05-12 | 0a7b9f | Two surfaces affected. (G) Food text analysis returned "The AI is temporarily unavailable. Please try again in a minute." after the user typed a meal description and tapped Analyse & Log. (H) Telemetry shows push_snapshot FunctionException(status 503, BOOT_ERROR) for sumit1 at 06:46 UTC. | edge_function_cold_start_resilience | test/contracts/edge_function_503_retry_test.dart |
| 2026-05-12 | f4c9e1 | After completing today's morning workout via the active-workout flow, the Edit Workout Log sheet shows "No exercise logs for this day" — blank. Cloud workout_log_exercises HAS the 5 rows for the founder on 2026-05-11 (completed_at 05:19 UTC = May 11 10:49 IST). Local Hive also has them at correct keys. | exercise_logs_read_path | test/contracts/edit_log_id_injection_test.dart |
| 2026-05-12 | e1f8a2 | \| | exercise_log_per_set | test/contracts/edit_workout_log_sets_field_contract_test.dart |
| 2026-05-12 | a8f1c2 | "Active workout screen pre-fills REPS input with 85 on every set of Hanging Leg Raise (4 prescribed sets × 14 reps, bodyweight). 85 is the sum of the user's previous 7-set session [10,15,10,15,10,10,15]; weight_kg field similarly carries the max of the previous session's per-set weights instead of the first set's weight." | last_performance_per_set_semantics | test/contracts/last_performance_per_set_contract_test.dart |
| 2026-05-12 | 7c4e1a | User tapped "Analyse & Log" on Nutrition → Log Food → AI tab. Got toast "The AI is temporarily unavailable. Please try again in a minute." Same error class also fires from AI coach `logMealByText` tool dispatch when ai-proxy is cold. Edge-function logs show two consecutive POST /ai-proxy 502 BAD_GATEWAY at 05:08:05 UTC (8475 ms) and 05:08:13 UTC (6654 ms); the next successful call ~3 min later took 20219 ms (warm-start completion). | edge_function_cold_start_resilience | test/contracts/retry_loop_guard_test.dart |
| 2026-05-11 | 7ad0cc | No source-grep guardrail enforced the WriteService SoT contract for `exlog_*`, `wlog_*`, `nlog_*`, `saved_meal_*` Hive prefixes. C-8 + C-12 closed half a dozen bypass sites manually; without a detector, new code can re-open the class. While writing the detector, a 7th bypass was caught — `_relogFromHistory` in `search_mode_body.dart` wrote `nlog_<ts>` directly with the legacy flat-totals shape (no items[]), same C-12 sibling class. | write_service_bypass_detector | test/contracts/write_service_bypass_detector_test.dart |
| 2026-05-11 | 7ad0ca | `ProfileScreen._performSignOut` called `supabase.auth.signOut()` + `UserRepository.clearAllData()` directly, bypassing `AuthNotifier.signOut()` and — critically — skipping `HiveUserSession.deleteAllFilesForCurrentUser()`. Per-user namespaced Hive files survived on disk after sign-out → re-opens the cross-account leak class that CLAUDE.md §19 documents as closed by namespacing. Next sign-in's legacy migration sweep could re-import them. | profile_signout_auth_notifier | test/contracts/profile_signout_routes_through_auth_notifier_test.dart |
| 2026-05-11 | 7ad029 | 35 RLS policies on UPDATE / ALL had USING expressions but no WITH CHECK; meaning a user could UPDATE their own row's user_id to another user's UUID, transferring or poisoning cross-user data. | rls_with_check_completeness | "n/a — SQL-only migration verified via MCP query (0 missing post-apply)" |
| 2026-05-11 | 7ad0cb | `TemplatesNotifier.saveTemplate` + `.updateTemplate` wrote `tmpl_*` rows to Hive but fired NO cloud sync — `workout_templates`/`template_exercises` rows only reached cloud via weekly full sync (up to 24h delay). `TemplatesNotifier.deleteTemplate` fired `pushSnapshot` but missed `syncWorkoutData`, so the cloud `workout_templates` row stayed orphaned forever — next restore re-imported the "deleted" template. | templates_sync_fanout | test/sync/template_sync_gap_test.dart |
| 2026-05-11 | 7ad0c1 | subscriptions table had open INSERT/UPDATE/DELETE RLS policies plus nullable Razorpay columns; any authenticated user could self-grant indefinite PRO with no payment trail. | subscriptions_rls | test/contracts/no_client_subscriptions_writes_test.dart |
| 2026-05-11 | 7ad0d2 | `streak_freezes_available` + `streak_freeze_used_dates` + `streak_freezes_last_refill` had TWO independent writers — `StreakFreezeNotifier._refillIfNewWeek` (weekly +1) and `WorkoutRepository._calculateStreak(consume:true)` (missed-day burn). Each path was a synchronous read-modify-write today, but contract drift risk was high — any future change introducing an `await` mid-flight would open a same-process race. The CROSS-DEVICE race is real now — a stale snapshot from device A could overwrite a freshly-consumed value on device B if `syncFreezes` arrived in the wrong order. (Hermes-R2 Round 2 #3 — "Refill ↔ consume race on streak freezes (lost update)", NEW CRITICAL.) | streak_progress_service | test/contracts/streak_progress_service_concurrency_test.dart |
| 2026-05-11 | 7ad0d1 | `WorkoutRepository.calculateCurrentStreak()` was documented as a "read" but had side effects — consumed streak freezes for missed days and persisted the new state to Hive + cloud on every invocation. Four read-only call sites (RankService cron / splash, streakProvider for home pill, rank_service_record_sheet display, AI snapshot) ran this method routinely. A user with 1 freeze available and 1 missed day would have that freeze burned by the first cron eval, but if the cron fired 3× in a window, race conditions could burn 3 freezes for the same day. UI rebuilds, hot reload, dev tools — every trigger of those surfaces silently mutated freeze state. | streak_cqrs_split | test/contracts/streak_currentstreak_is_pure_test.dart |
| 2026-05-11 | 7ad0c7 | 4 splash-time post-auth fire-and-forget startup paths (`RankService.evaluateAndPromote`, `SubscriptionService.refreshFromSupabase`, `ScheduledWorkoutsResyncMigrator.runIfNeeded`, splash `_autoGenerateNextPhaseForPro`) read user-scoped Hive boxes BEFORE `_ensureLocalUser` has opened the namespaced session. Every box read threw `HiveUserSession not opened`; the surrounding catch swallowed it; rank promotions / PRO refresh / one-shot resync / PRO auto-generate next phase silently no-opped on every cold start. Test #12.6 added defensive bootstrap to only the SyncService path; the other 4 still raced. | splash_post_auth_session_gate | test/contracts/splash_post_auth_session_gate_test.dart |
| 2026-05-11 | 7ad0d0 | `catch (e) { debugPrint(...); }` patterns across `lib/core/services/` + `lib/shared/repositories/` logged to the device console but emitted NO Crashlytics signal + NO `client_errors` row. Production users hit the bug, devs never saw it. Multiple instances over Test #12 series + this audit (Bug A, C-2, rank_service hot path) traced back to this silent-swallow class. | silent_debugprint_catch | test/contracts/no_silent_debugprint_in_services_test.dart |
| 2026-05-11 | 7ad035 | 5 SECURITY DEFINER functions had no search_path config (injection risk); coach_tool_invocations_v view ran as creator bypassing RLS; 9 SECURITY DEFINER functions granted EXECUTE to anon and authenticated allowing PostgREST RPC bypass of Edge Function business rules. | security_definer_hardening | "n/a — SQL-only migration verified via MCP pre/post queries" |
| 2026-05-11 | 7ad054 | rank_ladder had RLS enabled with zero policies (deny-all client reads); promo_code_uses INSERT policy was scoped to roles=public with WITH CHECK=true allowing any authenticated user to insert audit rows directly via PostgREST. | rls_policy_cleanup | "n/a — SQL-only migration verified via MCP pre/post queries" |
| 2026-05-11 | 7ad0cd | 3 surfaces (`userStatsProvider`, `train_screen` WeekSelector.onSelect, `swap_sheet`) snapshot `SubscriptionService.instance.isPro()` at build/init time and never reactively rebuild when the user upgrades to PRO mid-session. Same stale-PRO class APK Test #12 / C-2 already closed for the home screen + roadmap surfaces. Result — user pays for PRO, the stats card still says "free", week selector still routes to the read-only preview screen, swap sheet still enforces free-tier restrictions until the page is reopened. | reactive_subscription_three_sites | test/contracts/reactive_subscription_three_sites_test.dart |
| 2026-05-11 | 7ad0c8 | `submitWorkoutDraft` (the chat-confirmation handler for AI-coach-detected workouts) wrote `exlog_<ts>_<hash>` and `wlog_<ts>` rows directly to Hive with the *legacy* field shape (`sets_completed`, no `sets[]`, no `set_number`, no IST-stable key, no per-set rows). Bypassed `WorkoutWriteService`. Result — receipts and AI snapshot readers (`_getThisWeekWorkouts` / `_getPersonalRecords` / `_getMealsToday`) silently dropped every chat-confirmed workout because they filter on the new field shape introduced by Test #8. AI coach gave advice based on a workout history that excluded every "I did 3x10 squats" message the user confirmed. | chat_workout_draft_write_service | test/contracts/conversational_log_handler_uses_write_service_test.dart |
| 2026-05-11 | 7ad0c4 | 8 cron Edge Functions had verify_jwt false at the gateway AND no manual auth check at handler entry. Anyone with the function URL could trigger expensive Gemini fanout, OneSignal pushes, or DB scans across the entire user base. | cron_auth_gate | "n/a — Edge Function gate verified per-function via curl" |
| 2026-05-11 | 7ad0c6 | splash_screen.dart cross-account Hive leak guard was a no-op on every cold start. `HiveService.instance.userBox` is a `GuardedBox` that throws `HiveUserSession not opened` before any `openForUser` has run; the try/catch swallowed it and the guard never executed. Android Auto Backup restores / dev-build Hive copies / legacy migration races could leave a foreign profile.id inside the new user's namespaced box and the safety net CLAUDE.md §19 promises did not actually run. | cross_account_guard_on_open | test/safety/cross_account_guard_on_open_test.dart |
| 2026-05-11 | 7ad009 | delete-account Edge Function had no rate limit on the confirmation-token check. A malicious actor knowing a target's 8-char user_id prefix could repeatedly POST attempts; each fires Razorpay + DB queries before the 400 reject — DoS vector at scale. | delete_account_rate_limit | "n/a — Edge Function rate-limit verified via curl" |
| 2026-05-11 | 7ad0d4 | 3 deterministic-key helpers (`_nlogKeyForRestore` in sync_service, `exlogKey` in workout_write_service, `_stableItemsHash` in nutrition_write_service) computed their 8-char tag via `String.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0')`. Dart's `String.hashCode` is NOT guaranteed stable across VM versions / isolates / platforms — cross-device round-trip (cloud → Hive on restore, or sync between devices) could produce different tags for the same logical tuple → duplicate Hive rows for what should be one row. | deterministic_uuid_v5_keys | "n/a — covered by existing exlog/nlog migrator tests + cross-device round-trip implicit in the migrator suite" |
| 2026-05-11 | 7ad0d3 | 7 Edge Function date-key sites used UTC midnight (`new Date().toISOString().split("T")[0]`, `setUTCHours(0,0,0,0)`, etc.) for rate-limit windows, snapshot keys, and look-back cutoffs. For Indian users (UTC+5:30), the UTC date doesn't roll over until 05:30 IST — so the daily 10-msg cap reset at dawn, vision cap reset at 05:30, weekly recalcs covered the wrong 7-day window, and monthly prediction re-trigger cutoffs were off by 5h30m. | edge_function_ist_sweep | "n/a — TS Edge Function sweep; verification is via the existing morning-alert + daily-snapshot reads that already use istNow()" |
| 2026-05-11 | 7ad0d6 | 3 Edge Function input-validation gaps. (H-21) ai-proxy `scan_meal` + `cart_auditor` accepted `body.image` (base64) with NO size validation — a 50MB+ blob would forward to Gemini unbounded, burning cost + Edge Function memory. ai-media-proxy already enforces 5MB; ai-proxy was the gap. (H-22) ai-proxy `food_text_analysis` accepted `body.text` with NO length cap, while the chat channel had a 5000-char cap on `message`. (H-23) ai-media-proxy PRO image-chat path had NO per-day rate limit — a compromised PRO token could drain unlimited Gemini-vision quota in minutes. | edge_input_validation | "n/a — TS Edge Function input bounds; verified by deploy + manual oversize tests" |
| 2026-05-11 | 7ad0ce | Email-signup users (Supabase Auth's email flow carries no metadata) had `public.users.full_name` permanently seeded with `email.split('@').first`. The `_ensureLocalUser` upsert ran with `ignoreDuplicates: true` so the email-prefix seed stuck FOREVER. AI coach + weekly recap + every greeting addressed users by their email prefix for the lifetime of the account. | full_name_email_prefix | test/contracts/full_name_backfill_test.dart |
| 2026-05-11 | 7ad038 | H-38 disposition — Path 1 (dedupe SELECT policies). Supabase advisor flagged `public_bucket_allows_listing` on storage buckets `avatars` + `banners`. Inspection found 3 duplicate SELECT policies per bucket (6 redundant rows in pg_policies). Founder elected Path 1 cosmetic cleanup + accept the public-bucket UX trade-off (avatars need anonymous `<img src>` rendering for app UI). | storage_policy_dedupe | "n/a" |
| 2026-05-11 | 7ad0e0 | Phase 8 cleanup deferred the remaining 21 grandfathered `catch (e) { debugPrint(...) }` patterns in `lib/core/services/` + `lib/shared/repositories/` to a follow-up batch. Per audit doc §4 H-42 finding + the audit's "no deferrals" discipline rule, this batch retrofits ALL remaining grandfathered files — 20 services + 4 repositories. Each catch now pairs the existing `debugPrint(...)` with `unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: '<op_type>'))` so production silent failures surface in Crashlytics + the `client_errors` table. | error_telemetry_funnel_completion | test/contracts/no_silent_debugprint_in_services_test.dart |
| 2026-05-11 | 7ad0c9 | 4 nutrition mutations bypassed `NutritionWriteService` (the documented sole writer per CLAUDE.md §15). `SavedMealsNotifier.saveMealPreset` / `.relogSavedMeal` / `.deleteSavedMeal` + `FoodLogNotifier.restoreFoodLog` each wrote `nutritionBox` rows directly, with `relogSavedMeal` ALSO firing the legacy `NutritionRepository.syncLogToSupabase` double-write. Side effects — provider-invalidation drift (notifiers fired their own list, didn't share the WriteService canonical batch), legacy flat-totals shape on relog (no `items[]`), and the double cloud-write path producing 2 rows per re-log when the timing aligned. Additionally `WaterNotifier.addWater` + `.decrement` built non-IST date keys for `water_ml_<date>`, breaking the IST-anchored contract per CLAUDE.md. | nutrition_write_service_expansion | test/contracts/saved_meals_writer_to_reader_test.dart |
| 2026-05-11 | 7ad0d5 | 3 payment-stack hardening gaps. (H-18) verify-payment's `.insert()` fallback after upsert error did not catch Postgres 23505 (unique_violation), so a concurrent webhook + verify-payment race would surface as a 500-ish error response instead of treating the existing row as success. (H-19) razorpay-webhook auto-captured `payment.authorized` events BEFORE the idempotency pre-SELECT, so a replayed `payment.authorized` for an already-captured payment fired a second Razorpay capture call → Razorpay 4xx ("already captured") → we returned 502 → Razorpay retried the same loop. (H-20) `RazorpayService._pollAndActivate` ran `Future.delayed` poll retries with no cancellation — if the user signed out / signed in as a different account mid-poll, the loop would write PRO state to the WRONG user's Hive. | payment_hardening | "n/a — TS Edge Function + Dart fire-and-forget callbacks; verified via deploy + manual race scenarios documented in CLAUDE.md §16" |
| 2026-05-11 | 7ad0cf | `SubscriptionService` payment grace window was a pure time-based `paymentInFlightUntil` ISO timestamp. Two pathologies — (a) a slow webhook past 10 min flips grace to false even though we're still legitimately awaiting verdict, so refreshFromSupabase / verifyFromServer can downgrade a paying user; (b) a fast confirmation in 5s leaves the window open for another 9:55, masking unrelated downgrade events during that window (e.g. server returns is_pro=false for a different reason and the grace check suppresses it). | payment_in_flight_event_based | test/subscription/payment_grace_window_test.dart |
| 2026-05-11 | 7ad0d7 | 6 schema-completeness gaps. (H-13) `_restoreCustomExercises/Foods` wrote to legacy LIST keys (`custom_exercises` / `custom_foods`) while every reader scans per-key (`custom_exercise_*` / `custom_food_*`) → restored items vanished from `getCustomExercises()` and never re-synced. (H-14) `syncCommunityItems` had no `.limit()` or pagination — every app launch downloaded the entire approved community library. (H-25/26/27/28) Missing UNIQUE constraints / index across 4 tables — cross-device sync race could create duplicates that double-count. (H-31) `community_reviews` existed on prod but had no migration in source (Dashboard-created). (H-33) Two migration files shared the `050` prefix; filesystem ordering non-deterministic. (H-34) Source vs prod migration count mismatch. | phase5_schema_completeness | "n/a — schema migrations applied directly; covered by existing migrator + sync tests" |
| 2026-05-11 | 7ad0d8 | 11 invariants documented in CLAUDE.md / audit findings / prior bug retros had no automated guardrail. Future code changes could silently remove them. Examples — delete-account skips confirmation_token check, razorpay-webhook drops the 5-min replay window, ai-proxy stops catching the food-text rate-limit trigger error, `isPro()` accidentally returns `true` on null expiry in release, `gate()` stops calling `verifyFromServer` for high-value features, exercise_selector cascade drops the universalPool fallback, etc. | phase6_contract_tests | test/contracts/audit_2026_05_11_t1_t11_contracts_test.dart |
| 2026-05-11 | 7ad0d9 | 10+ critical end-to-end flows had no integration test coverage at all — Razorpay purchase (the entire payment stack), sign-up + onboarding traverse, delete-account (DPDP §17 irreversible), cross-account isolation, cross-device restore, workout completion → receipt → share, streak freeze refill ↔ consume, plan generator → first workout, custom exercise submission flow, promo code apply, AI coach tool-calling. Audit recommended building out the scaffolding even if the bodies are skipped pending device-CI infrastructure. | phase7_integration_scaffolds | test/contracts/phase7_integration_scaffolds_present_test.dart |
| 2026-05-11 | 7ad0c3 | .claude/settings.local.json was tracked in git AND contained the Supabase anon JWT in committed permission entries; the same JWT also appears in git history (lib/core/constants/app_constants.dart commit ef878af, removed in 5c40925) so simple file removal does not retire the leaked credential. | anon_jwt_leak | "n/a — JWT rotation is a Supabase Dashboard action (user-action U-2)" |
| 2026-05-11 | 7ad0c5 | promote-community-item ran as service-role with verify_jwt only at gateway level - any authenticated user could call POST functions v1 promote-community-item and trigger global writes to food_database and exercise_library. The 10-vote community threshold was the only caller-identity gate. | promote_community_item_admin_gate | "n/a — Edge Function gate change verified via curl pre + post deploy" |
| 2026-05-11 | 7ad0da | Phase 8 cleanup catch-all. (Hive sequential) `HiveService.init` opened 9 shared boxes serially via a for-loop — sequential file I/O wasted 150-300 ms of cold-start time. (community_review_sheet `as Map`) two `f as Map` / `e as Map` casts at lines 71+77 would TypeError on a non-Map row (PostgREST schema drift would crash the sheet). (H-42 retrofit batch) 28 grandfathered `catch (e) { debugPrint(...) }` sites remain after the audit's first batch; 4 hot-path services retained the silent-swallow pattern — health_sync_service (4 sites — fires on every splash), razorpay_service (8 sites — payment flow), stat_snapshot_service (5 sites — onboarding + promotion + manual snapshots), subscription_service (1 site — refreshFromSupabase failures only surfaced via the log-client-error helper, not Crashlytics). | phase8_cleanup | test/contracts/no_silent_debugprint_in_services_test.dart |
| 2026-05-10 | a8b2c7 | _syncWorkoutTemplates used a DELETE-then-INSERT pattern for child template_exercises rows. If the DELETE succeeded but a subsequent INSERT errored mid-loop (network blip, FK constraint, payload error), the user's template was left with PARTIAL children — half the exercises missing, no audit trail. Next sync re-DELETED + tried again. Idempotent on success but lossy on partial failure. | workout_template_sync | test/contracts/template_exercises_upsert_test.dart |
| 2026-05-10 | a7c1e2 | Calendar checkmarks for May 5/6/7 vanished on the founder's account after restore, despite cloud workout_logs and scheduled_workouts.status='completed' being correct for those dates. | workout_completion_status | test/contracts/stale_completion_guard_test.dart |
| 2026-05-10 | e3f7a8 | A subset of users (founder included) holds Hive `schedule_<date>` rows with `status='completed'` while the cloud `scheduled_workouts` row stays at `status='planned'` for those dates. Once Bugs B.1 + B.2 ship, future writes stay consistent — but existing divergence won't self-heal without an explicit re-push. | workout_completion_status | test/safety/scheduled_workouts_resync_migrator_test.dart |
| 2026-05-10 | d9b2c5 | Saturday's locally-completed workout was overwritten back to 'planned' on every cold-start restore, because cloud still held the older 'planned' row (Bug B.1's FK violation prevented push) and `_restoreScheduledWorkouts` was unconditionally cloud-authoritative for status/completed_at. | workout_completion_status | test/contracts/restore_non_destructive_test.dart |
| 2026-05-10 | c5d2a8 | Streak pill showed only ❄ <available> (single digit), so a PRO user with 1 freeze remaining had no signal that capacity was 3 — and a user at 0 freezes had the snowflake section invisible entirely. | streak_freezes | test/home/streak_freeze_pill_xy_test.dart |
| 2026-05-10 | b3d8f9 | PRO user who burns all 3 streak freezes in week 1 gets back to 3 the following Monday — full reset, no incentive to save freezes. | streak_freezes | test/home/streak_freeze_refill_ladder_test.dart |
| 2026-05-10 | c8e4a1 | 10 PostgrestException 23503 (scheduled_workouts_template_id_fkey) errors fired in 5 seconds on the founder's account at 2026-05-10 12:45 UTC. Saturday's completed workout never reached cloud and the calendar tick vanished after force-restart. | workout_completion_status | test/contracts/scheduled_workouts_fk_resilience_test.dart |
| 2026-05-10 | f4d6c2 | 3 cross-account isolation tests in test/auth/cross_account_isolation_test.dart were stubbed with `skip:` referencing HiveService.lastAuthenticatedUserIdKey — a constant from an abandoned Plan A namespacing prototype. The test file added zero coverage to the actually-shipped HiveUserSession + GuardedBox surface. | cross_account_isolation | test/auth/cross_account_isolation_test.dart |
| 2026-05-10 | e8a3b1 | Opening the AI coach screen lands the scroll position at 0 (oldest message at top). User has to manually scroll down through the entire transcript just to see the latest exchange and reach the input row. | ai_coach_chat_history | test/ai_coach/initial_scroll_to_bottom_test.dart |
| 2026-05-10 | d4e5f6 | Cloud user_progress default for streak_freezes_available was 2 — neither matched free baseline (1) nor PRO max (3). Fresh accounts got an inconsistent middle-ground value before the client's first refill ladders them. | streak_freezes | "n/a — migration + 2-line constants" |
| 2026-05-10 | task22 | No diagnose-docs existed for ~35 fix/feat commits since Test #11 (merge 0babf83), meaning /build-apk Gate 10 would trip on all historical commits lacking diagnose coverage. | log_client_error_payload | "n/a — backfill" |
| 2026-05-08 | b0fd76 | Telemetry payload had no contract (any shape was accepted, breaking structured log queries); restore had a race condition where stale tmpl_* keys from earlier broken restores accumulated and caused duplicate templates across APK upgrades. | error_telemetry_helper | "n/a — backfill" |
| 2026-05-08 | 5a36ad | Sync stack had systemic failures — workout templates were not deduped (UNIQUE constraint added), streak pill showed cached value instead of live calculateCurrentStreak(), completed_at was overwritten to NOW on every sync retry corrupting founder's Tue+Wed logs. | workout_templates | "n/a — backfill" |
| 2026-05-08 | b2ac5d | Multiple restore failures — _restoreXxx methods keyed Hive by cloud UUID instead of deterministic WriteService key (calendar dup explosion); _restoreUserProfile missed users.full_name so greeting showed USER; _restoreScheduledWorkouts had early-skip closing Mon-only DONE marker; templates upsert caused 23503 FK loops. Telemetry sweep added 22 new op_types. | restore_completeness | "n/a — backfill" |
| 2026-05-07 | 5c61ed | Multiple issues — restore stack had HiveUserSession ordering bugs causing 30+ cold-start restore failures logged to client_errors; receipt chips needed per-set rendering; 5 IST drift sites remained; process bootstrap docs (sot_registry, naming_conventions, pre-commit hook) were missing. | restore_completeness | "n/a — backfill" |
| 2026-05-06 | 69276a | subscriptionInfoProvider was not invalidated on cold-start subscription state writes (verify, downgrade), so PRO status changes did not propagate to the UI until next hot restart. | subscription_state | "n/a — backfill" |
| 2026-05-06 | 979a8e | PRO upgrade did not reflect immediately in train screen; train expanded view showed 0 sets; macros displayed incorrectly — three stacked bugs from the first on-device audit. | subscription_state | "n/a — backfill" |
| 2026-05-06 | d9b546 | PRO unlock still failed systemically across multiple code paths; logging_type repair migrator was not library-aware, repairing to wrong types for exercises present in the library. | subscription_payment_grace_window | "n/a — backfill" |
| 2026-05-06 | fe579a | ai_coach_repository called istDateStr(istNow()) causing a double IST shift — plan summaries showed wrong date and eta_next_promotion dates were off by one day. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-06 | 519075 | Cloud-side audit surfaced multiple failures — logging_type repair migrator needed systematic rebuild, razorpay 409 detection was dead code (FunctionException class), sync had IST gaps, train screen had stale receipt rendering. | hive_field_name_exlog | "n/a — backfill" |
| 2026-05-06 | 5456c4 | Multiple issues in one batch — PRO upgrade did not unlock after payment, receipt showed wrong set counts, today card had duplicate text, weight chart decimals were static, swap kept stale logging_type, WardSetChips was duplicated in two surfaces. | subscription_payment_grace_window | "n/a — backfill" |
| 2026-05-06 | 344121 | Second cloud-side audit revealed 4 bugs — NutritionWriteService.onStateChanged hook missing, foodLogProvider missing from invalidation set, LoggingTypeRepairMigrator had unhandled edge cases, and app.dart was not wiring the new hook. | sync_fanout_nutrition_domain | "n/a — backfill" |
| 2026-05-05 | 8a2e9b | 25 additional user-scoped configBox keys remained after the Test #10.1 hotfix (6 keys), and OneSignal player_id was never synced to cloud, causing push unsub to silently no-op on account deletion. | user_scoped_hive_keys | "n/a — backfill" |
| 2026-05-04 | 270ea3 | Workout restore wrote Hive keys using cloud UUIDs instead of deterministic WriteService keys, causing exercise logs to be unreadable by receipt and calendar readers. | hive_field_name_exlog | "n/a — backfill" |
| 2026-05-04 | 2c645c | Welcome screen displayed misleading 'no streaks' copy and app.dart showed a 'restart' error message that does not resolve any real issue. | cross_cutting | "n/a — backfill" |
| 2026-05-04 | 11bcfb | Four UI sites hardcoded 3000 ml for water target instead of computing it from user weight and activity, causing incorrect 100% at 3L for light users. | water_target | "n/a — backfill" |
| 2026-05-04 | b621c6 | Four pre-existing test failures in rank_service_test and sync_gap_test reflected outdated test assumptions from pre-Test #6 architecture. | sync_fanout_workout_domain | "n/a — backfill" |
| 2026-05-04 | 4c49d6 | Logo rendered at full resolution on splash without cacheWidth hint, causing unnecessarily large decode on low-memory devices. | cross_cutting | "n/a — backfill" |
| 2026-05-04 | ad7664 | Streak freezes, notifications inbox entries, and diet plan were written to Hive but never pushed to cloud, so they were silently lost on reinstall. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | 239999 | restoreFromCloud did not pull streak freezes, notifications inbox, saved diet plan, rank promotions, or coaching notes, so reinstalling lost all these surfaces. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | 5d2ff1 | razorpay-webhook derived plan (monthly/yearly) from client-supplied body.plan instead of payment amount, allowing a monthly payment to grant yearly entitlement. | subscription_state | "n/a — backfill" |
| 2026-05-04 | 39f8ce | AI breakdown card silently disappeared after save with no user feedback, making users believe the meal was not logged. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | 933330 | Post-account-deletion null user_id in community rows caused promote-community-item to crash; three additional IST date escape sites wrote UTC dates to Hive. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | bb3acc | Morning alert Edge Function computed day-of-week and date strings in UTC instead of IST, sending wrong day greetings after 18:30 IST. | coach_interactions | "n/a — backfill" |
| 2026-05-04 | 89d079 | Hard-deleting an auth user CASCADE-deleted community contributions (custom foods, exercises, reviews) that should be retained pseudonymously for community signal. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | 776478 | Streak freezes, notifications inbox, and saved diet plan had no cloud backing, so reinstalling the app silently lost these surfaces for paying users. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | 4c8788 | AI coach message count was recomputed from Supabase on every render, causing unnecessary round-trips; cache key was not IST-aware, causing stale counts across midnight. | coach_interactions | "n/a — backfill" |
| 2026-05-04 | 26b360 | AI snapshot and usage counter resets used UTC or device-local dates instead of IST, causing midnight-crossing mismatches for Indian users. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | 8cc429 | Identity screen allowed proceeding without sex selection and showed wrong step label (missing 01·05 display). | onboarding_completed_at | "n/a — backfill" |
| 2026-05-04 | acdcfb | FoodLogNotifier wrote flat-totals nlog_* rows without items[] array, so cloud nutrition_log_items got 0 rows for those logs and AI coach/weekly-report saw no meal items. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | 40a426 | V4 plan generator had 38 cascade fallback failures (universalPool picks) because the exercise library pool was too shallow for advanced slot targets. | cross_cutting | "n/a — backfill" |
| 2026-05-04 | 72ea41 | No server-side hard-delete path existed for DPDP §17 compliance, so user data could not be fully erased on account deletion request. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | d33c12 | No client-side account deletion UI existed for DPDP §17 compliance; users had no way to request hard erasure of their data. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | 617ea1 | User-scoped data (isPro flag, prediction text, localActivationAt) persisted in shared configBox and leaked to the next account signed in on the same device. | user_scoped_hive_keys | "n/a — backfill" |
| 2026-05-04 | 0f8d54 | Usage counters incremented on meal save rather than on API call, so users who analysed without saving saw incorrect 'remaining' counts diverging from server rate-limit trigger. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | d9d77c | Captain voice prompts were duplicated across proactive trigger Edge Functions instead of sharing a single source, risking voice drift between triggers. | coaching_notes | "n/a — backfill" |
| 2026-05-04 | f631f0 | Profile screen called Supabase and Edge Functions directly from widget code, bypassing the repository pattern and making the calls untestable and hard to audit. | cross_cutting | "n/a — backfill" |
| 2026-05-03 | f9acbc | MissionBriefScreen crashed or showed wrong state when navigated to in readOnly mode because the readOnly param was absent. | onboarding_completed_at | "n/a — backfill" |
