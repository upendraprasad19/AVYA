# Bug Directory (auto-generated)

Re-run: `dart run scripts/build_bug_index.dart`

## By recurrence class

## By concept

### An allow-list whose input set was enumerated from one source (things new-worktree.sh copies in, and Flutter build products) while a SECOND producer of ignored files — the test suite itself — wrote into the same tree and was never enumerated. The tool's protective leg is correct and stays correct; what was wrong is that it treated a regenerable artifact as precious, so the failure direction was inert-not-destructive. That is the right direction to fail, which is exactly why it survived: nothing broke loudly, worktrees just quietly never retired. (1 bugs)
- 2026-08-25 f2a9c7 — Any worktree that had merely RUN the full test suite could never be retired. `retire_worktree.dart` reported "1 non-regenerable ignored file(s)" and KEPT the worktree forever, because…

### Documentation-as-executable-input drift. A runbook command is not prose — it is an input to a prod control plane, and it had drifted from the live state it addresses with nothing pinning the two together. The failure would also have been SILENT: deploy_via_api.js tolerates HTTP 401 for ai-proxy in its post-deploy smoke step, so the deploy prints "Smoke OK" over a dead function. This is the bad-news-vs-no-news class — a 401 meant "healthy module rejected you" before the change and would have meant "gateway killed everything" after it, with no way to tell them apart from the smoke output alone. (1 bugs)
- 2026-08-24 b2d8e4 — The operator runbook docs/operations/FOUNDER_LAPTOP_HANDOFF.md instructed the founder to redeploy ai-proxy with verify_jwt=true. Live config is false, and deliberately so. Running the documented line…

### hold_snapshot_block (1 bugs)
- 2026-08-21 b6e1f4 — FOB-3 of OI-60. The AI coach asserts a falsehood to every holder, every week. The snapshot sends `progress.current_week` and `current_plan_summary.week` derived from `getCurrentWeekNumber()`, which…

### founder_metrics_engagement (1 bugs)
- 2026-08-20 c7a3b9 — FOB-5 of OI-60, two defects in one function, one LIVE on the founder dashboard. (1) `founder_metrics_engagement().ai_messages_today` counted EVERY row of `ai_coach_interactions` with no channel…

### hold_week_telemetry (1 bugs)
- 2026-08-20 a7e4c2 — Hermes P1-D + P1-E. FOB-5 existed because five phase_1_day_29_* events had ZERO consumers, making the free-tier hold mechanic unobservable. It replaced them with hold_week_started plus three SQL…

### hold_week_identity (2 bugs)
- 2026-08-20 f4c8e1 — FOB-1 of OI-60. Six in-repo surfaces printed the clamped week 4 to a free-tier holder, at every hold ordinal, forever. `getCurrentWeekNumber()` (workout_schedule_read_service.dart:1096) ends in…
- 2026-08-20 d5b8f3 — Hermes P1-A. FOB-1 (f4c8e1) fixed six surfaces that reached the clamped week through getCurrentWeekNumber(), and declared the class closed. It was not: holdWeek() ALSO persists the projected number…

### pre_push_ci_parity (1 bugs)
- 2026-08-20 b2e9f4 — `scripts/pre-push.sh` blocked a push whose commit was fully green in CI's own terms. The full-suite gate ran a bare `flutter test` while CI runs `flutter test test/ --exclude-tags golden` under `TZ:…

### guard_accepts_mention_instead_of_invocation (1 bugs)
- 2026-08-17 c8b3e6 — The git-safety PreToolUse hook — the only mechanical guard forcing every commit and push through scripts/safe_commit.sh / safe_push.sh, and the only block on a `--no-verify` bypass — could be turned…

### hook_coverage_and_dart_invocation_cost (1 bugs)
- 2026-08-17 d3f1a7 — Two symptoms with one shape, both surfaced by the founder asking why the pipeline is slow and why the OI board number mismatch survived it. (1) SPEED: every commit paid ~182 s of discipline gates, of…

### edge_function_gateway_vs_function_error_contract (1 bugs)
- 2026-08-16 c8f4a2 — `main` is RED. The CI job `Supabase Integration Tests` fails on its `Run Edge Function tests` step, on a SINGLE assertion: `test/edge_functions/redeem_referral_test.dart:46`, RR-1 "Missing auth…

### delete_boundary_independent_of_credential (1 bugs)
- 2026-08-15 d3b8f1 — `SupabaseTestHelper.cleanup()` issues `DELETE ... eq('user_id', id)` across 12 tables of the PRODUCTION project `dedsavbjuwgarrhphgnl`, and CI runs it on every push to `main`. On `main` there is NO…

### cron_registry_parity (1 bugs)
- 2026-08-15 c8e5b3 — Two log tables grew without bound: cron.job_run_details (~29,044 rows) and public.client_errors (~10,654 rows). A migration named `log_table_retention` was applied to prod on 2026-08-15 to bound them…

### qa_credentials_from_environment (1 bugs)
- 2026-08-15 f7a2c4 — The CI job `Supabase Integration Tests` fails on every push to `main` with `AuthApiException: Invalid login credentials, statusCode: 400`. The suites sign in as `qa@icanbefitter.com`, and a live query…

### sync_domain_push_writer_to_cloud (1 bugs)
- 2026-08-15 b6e1d4 — Three tests in `test/supabase/sync_service_test.dart` fail against the live project: T3 with `PGRST204` (no `exercise_name` column on `workout_logs`), T4 and T5 with `22P02` (a client string id into a…

### unresolved_conflict_markers_committed (1 bugs)
- 2026-08-14 c9f4e2 — `docs/audit/open_issues.md` on `main` at `5d1c6f12` carried three unresolved git conflict markers — an open marker at :2821, a bare separator at :2892 and a close marker naming `supabase-test-http` at…

### edge_function_token_freshness (2 bugs)
- 2026-08-13 d7b1f8 — During the 2026-08-13 23:03-23:19 IST backend outage, the app issued auth requests that piled up rather than queueing behind one another, and every one of them sat holding a connection for 10-36…
- 2026-06-09 d3a1c7 — APK +34 obs 3 — AI features (chat, food logging, weekly report) intermittently failed with no useful error, while ai-proxy itself was ACTIVE (v70) and still logging interactions. client_errors showed…

### streaks (2 bugs)
- 2026-08-13 a3f8d1 — TWO defects in the same six lines of ActiveWorkoutNotifier.completeWorkout's weekly-streak block. (1) FOB-2, flag-gated: getCurrentWeekNumber() clamps to [1,4] and a hold week starts at plan_start+28,…
- 2026-05-31 5e8a1c — Surfaced by the year-simulation harness: after amar completed Phase 1 (15 of 16 scheduled workouts over 4 weeks, ~85% adherence with a single missed day), the rank did NOT progress — it stayed at SD2…

### oi_board_id_uniqueness (1 bugs)
- 2026-08-13 b7e3d1 — Six OI ids — OI-100 through OI-105 — each named TWO entirely different issues: one set filed on `main`, one on branch `post38-auth-fixes`. Merging the two boards produced NO conflict: git saw…

### git_hook_env_leak (1 bugs)
- 2026-08-13 4f2a9e — The merge-commit regression-catalog walk fails with "at least one recent regression test FAILED" on tests that are green everywhere else. Observed while merging `supabase-http-fix`: 9 failures across…

### auth_signin_completion (1 bugs)
- 2026-08-13 a9c4e2 — Founder signed in as test6@gmail.com on the prod web build (app.icanbefitter.com/#/sign-in) at 2026-08-13 23:03 IST. The SIGN IN WITH EMAIL button entered its spinner state and never left it — no…

### subprocess_test_timeout_under_suite_parallelism (1 bugs)
- 2026-08-13 c3f9a7 — The merge-commit regression walk (`scripts/check_regression_catalog.dart`) fails intermittently with a DIFFERENT number of failures each run — measured 11, 7, 8, then 4 across four attempts on the…

### test_binding_http_mock_masks_real_network (1 bugs)
- 2026-08-12 a7e3c1 — Every test in test/supabase/ fails at setUpAll with `AuthUnknownException(message: Received an empty response with status code 400)`. The message reads exactly like Supabase rejecting the anon key, so…

### test_binding_stubs_http_for_integration_tests (1 bugs)
- 2026-08-12 3b7e1c — Every file in test/supabase/ dies in setUpAll with `AuthUnknownException(message: Received an empty response with status code 400, originalError: Instance of 'Response', statusCode: 400)` the moment…

### landing_verification_probe_conflation (1 bugs)
- 2026-08-11 d4f9b2 — scripts/safe_push.sh — the ONLY sanctioned push path and the file whose entire purpose is to be trusted about whether a push landed — exits 0 having verified nothing whenever `git ls-remote` cannot…

### deploy_smoke_tolerated_codes (1 bugs)
- 2026-08-10 a7c3f9 — Deploying log-client-error v13 returned HTTP 201 with a healthy ACTIVE function, and then printed "Smoke FAIL — HTTP 401 (not in tolerated set [400])" followed by rollback instructions. The deploy was…

### test_isolation_intra_file (1 bugs)
- 2026-08-10 f3c7a2 — Three tests in worktree_config_integrity_e2e_test.dart pass when the whole file runs but FAIL when run individually — `--plain-name "warn-only"` gives 1 failed, the full file gives 6 passed. Worse,…

### onboarding_completed_at (8 bugs)
- 2026-08-10 c2e9f4 — Founder (upendraprasad19@gmail.com, auth.users.id d7a67a37-0b05-4f0a- b13c-388bff3cb59b) signed in with GOOGLE to an account created by email in May, force-closed the app during a slow restore,…
- 2026-08-03 d4e8a2 — NOT a live incident — a static-tracing risk flagged in b3f9e7's own "Known residual gap" section, investigated and closed here. Nothing under lib/features/onboarding/ called…
- 2026-08-03 a3f6d9 — Founder (upendraprasad19@gmail.com, auth.users.id d7a67a37-0b05-4f0a- b13c-388bff3cb59b) reported: "I was trying to access the app, but from restoring it is going to onboarding page." Confirmed via…
- 2026-06-28 c4d8a2 — Live data (test7@gmail.com): a fully-onboarded user — users.onboarding_completed = true, a complete user_profile (date_of_birth, primary_goal, fitness_experience, days_per_week, current_weight) and a…
- 2026-05-30 e2a4f7 — Surfaced during live web E2E (amar@gmail.com). Browser console at sign-in: "[AuthSessionBootstrapper.resolveDestination] PostgrestException(code 42703: column user_profile.full_name does not exist)".…
- 2026-05-16 1bfeed — Onboarded users (cloud `user_profile` populated with goal/weight/phase) could land on `/onboarding/mission-brief` on fresh install when (a) cloud `user_profile.onboarding_completed_at` was NULL (cloud…
- 2026-05-04 8cc429 — Identity screen allowed proceeding without sex selection and showed wrong step label (missing 01·05 display).
- 2026-05-03 f9acbc — MissionBriefScreen crashed or showed wrong state when navigated to in readOnly mode because the readOnly param was absent.

### worktree_retirement_allow_list (1 bugs)
- 2026-08-10 d7b3e9 — `scripts/retire_worktree.dart` — the worktree-retirement command — would DELETE gitignored files that no process can recreate, while reporting the worktree as "merged + clean + pushed". Three…

### worktree_config_integrity (1 bugs)
- 2026-08-09 a4f7c2 — `git rev-parse --show-toplevel` returned `.../.claude/worktrees/post38-auth-fixes` from EVERY worktree in the repo and from the shared main folder. A session working in…

### notification_cron_eligibility_and_pro_gate (1 bugs)
- 2026-08-09 e3b9d7 — TWO notification-cron defects reported by the founder from their own phone and account, 2026-08-05 / 2026-08-07. (1) STREAK-GUARDIAN SENT A SELF-CONTRADICTING PUSH. A single notification read "Don't…

### past_phase_display_recovery (1 bugs)
- 2026-08-09 c9e4b7 — Founder, live web 2026-08-05, account upendraprasad19@gmail.com: the Train screen's week selector showed NO past-phase history despite the account being on Phase 2 with a completed Phase 1 on record.…

### signout_teardown_window_and_restore_op_ceiling (1 bugs)
- 2026-08-09 b7e4c1 — TWO defects on the auth/session path, both reported by the founder from live web on 2026-08-05, both fixed here because they share the same root class — an unbounded or ambiguous state read during a…

### claude_md_section_citation — the pointer from a source comment to a numbered
section of root `CLAUDE.md`. The schema below is writer/reader-shaped because
this drift IS writer/reader drift; the writer just happens to be a document
rather than a Hive box. (1 bugs)
- 2026-08-07 b2f7a4 — 138 `CLAUDE.md §N` citations in `.dart` / `.ts` / `.sql` / `.js` comments pointed at root-CLAUDE.md sections that do not exist. Root's real headings are exactly `0, 1, 2, 2a, 3, 4, 5, 6, 7`; the…

### notification_preferences (1 bugs)
- 2026-08-07 a7e3d1 — Two defects on the same surface, both filed as OI-76. (1) COUNT. The Profile tab's Notifications row subtitle reads "N/M enabled". It counted all 10 registry keys, including `protein_alerts` and…

### community_review_queue (1 bugs)
- 2026-08-07 d5b8c2 — `promote-community-item` (daily cron, job `promote_community_item_daily`) opened both of its promotion paths with a call to the Postgres RPC `community_votes_summary`. That function does not exist —…

### session_owner_inflight_guard (1 bugs)
- 2026-08-06 e5c2d1 — In one 1.0.0+38 session the founder signed out of user d7a67a37 (12:31:01 UTC) and signed into 9e6bde97 via Google (12:31:37). client_errors then shows, over roughly twelve seconds, 22 × "new row…

### equipment_exclusion_filter (2 bugs)
- 2026-08-06 e2d6b8 — A user opens Edit Profile, selects the equipment they do NOT have (e.g. cables), and saves. The selection persists and syncs to cloud. Their generated plan then prescribes exercises requiring exactly…
- 2026-07-17 b7a4e2 — On every GENERATED workout plan, gym users (basic_gym / full_gym) NEVER received the gym-cardio warmup moves (_gymCardio: Jump Rope / Cycling (Stationary) / Running (Treadmill)) or the gym finisher…

### oauth_signin_completion (1 bugs)
- 2026-08-06 d3a7c9 — Founder taps CONTINUE WITH GOOGLE on APK 1.0.0+38, completes Google consent, and the app sits on the sign-in screen with BOTH buttons spinning forever. Force-quitting and reopening lands on Home,…

### notifications_inbox_id_contract (1 bugs)
- 2026-08-06 a4f1c8 — client_errors shows 6 × PostgrestException 22P02 "invalid input syntax for type uuid: local-welcome-1786019702890010" against sync_notifications_inbox_entry in one 1.0.0+38 session. Nobody reported it…

### preauth_error_telemetry (1 bugs)
- 2026-08-06 b6e4f2 — Founder hits "Could not send reset link. Try again." on the web app. The code that produced that message also calls ErrorTelemetry.logEvent('auth_forgot_password_send_failed'), so there should have…

### password_recovery_session (1 bugs)
- 2026-08-06 c9e2b7 — Founder requests a password reset FROM THE ANDROID APP, receives the email, opens the link (which loads the web app), lands on the branded SET NEW PASSWORD screen, types a new password, and gets "Auth…

### plan_review_record_gate (1 bugs)
- 2026-08-05 a7f3c2 — scripts/check_plan_review_record_exists.dart — the keystone merge-to-main gate — carried a numbered, self-documented hole in its own source. OI-58b's "one-record-one-landing" rule (a branch that lands…

### git_safety_tooling (1 bugs)
- 2026-08-03 c9f4e1 — Two independent, real (not hypothetical) gaps in the git-safety tooling that CLAUDE.md §4.3 already relies on. (1) A 2026-08-03 near-miss during the terms-accepted-fix backfill follow-up: a foreground…

### phase_advance_write_path (1 bugs)
- 2026-08-03 b4e9c7 — `lib/features/train/screens/graduation_screen.dart` reached 909 lines against Gate 43's 800-line ceiling and passed only because it had been added to the gate's transitional allow-list — the FIRST…

### repo_gate_content_hygiene (1 bugs)
- 2026-08-03 e7c3b9 — The terms-accepted-fix batch (b3f9e7) hit 3 pre-existing gate-tripping content bugs only when its commit finally reached the full gate loop for the first time (earlier attempts failed before reaching…

### phase_progress_current_phase (cloud→Hive restore merge half) (1 bugs)
- 2026-08-03 d1f6b3 — A cloud→Hive `progress` restore silently LOWERS `current_phase` (and two other lifetime counters) on a device that advanced locally and has not yet pushed. No guard, no telemetry, no trace: the user…

### welcome_screen_hero_layout (1 bugs)
- 2026-08-03 e7c2a4 — Founder screenshot of app.icanbefitter.com/#/onboarding (the pre-auth welcome/marketing screen) showed the "BEGIN ENLISTMENT →" button overlapping with "03 · Coach that holds you to your own…

### subscription_state (isPro/gate CQRS split) (1 bugs)
- 2026-08-02 a9c4e1 — A Riverpod provider's build method invalidates itself. `SubscriptionInfoNotifier.build()` — the data source behind the PRO pill — calls `isPro()`, which on an expired or cross-account row calls…

### auth_google_oauth_redirect (1 bugs)
- 2026-08-02 f2b8a1 — Google sign-in was never live in prod despite functionality-flow.md asserting "Email + Google OAuth work normally" — no Google OAuth client existed in Google Cloud Console (google-services.json…

### workout_receipt_rendering + workout_log_edit_surface (exlog aggregate read) (1 bugs)
- 2026-08-02 d4e7c2 — A cloud-restored workout renders wrong on two surfaces. The receipt shows 0 duration for a timed/cardio exercise that has a real total, and the Edit Workout Log sheet shows a BLANK sets box and a…

### terms_acceptance (1 bugs)
- 2026-08-02 b3f9e7 — Founder spotted `users.terms_accepted_at` / `terms_version` NULL for every row in the live Supabase dashboard, including a row created the same day (2026-08-02 13:11:55, hours before this…

### auth_password_reset_post_success_navigation (1 bugs)
- 2026-08-01 c8f1d3 — A user requests a password reset from the web app, gets the email, clicks the link, lands on the "SET NEW PASSWORD" screen (Wardroom-branded, "RECRUIT REGISTRY" / "SET NEW PASSWORD", two password…

### phase_progress_current_phase (2 bugs)
- 2026-08-01 c8f3d1 — Every path that advances a user to the next training phase computed the new phase number BEFORE a real, slow plan generation and wrote it after. A concurrent advancer landing inside that window was…
- 2026-06-02 a3f8c1 — On the Train screen the week-selector strip showed TWO "PHASE I" sections — a completed "PHASE I (DONE)" with weeks W1 (Apr 27–May 3) … W4 (May 18–24) AND a second, current "PHASE I" with fresh weeks.…

### unbounded_postgrest_reads_in_cron (1 bugs)
- 2026-08-01 d3f7b2 — Every fan-out read in the cron Edge Function fleet silently stopped at 1000 rows. PostgREST caps an un-ranged response at db-max-rows and returns HTTP 200 with error===null, so a truncated candidate…

### reengagement_silent_candidate_detection (1 bugs)
- 2026-07-31 a4e1c9 — OI-48 (audit finding, corrected twice — 2026-07-27 re-scope, 2026-07-29 board correction — down to a single real remaining instance): the `re-engagement` cron-dispatched Edge Function's Path B…

### coach_media_consent (1 bugs)
- 2026-07-30 f4a7c2 — OI-25 (2026-05-17, founder's own product note in migration 070's header: "i intend to store coach uploaded media. We ask user does he want to store the pic for future reference and on consent we save…

### cross_device_progress_optimistic_lock (1 bugs)
- 2026-07-30 e6b9c4 — OI-45 finding 2's cross-device half, explicitly scoped OUT of Unit 3a (progress-map-consolidation, diagnose d5c8a3, 2026-07-30): Unit 3a closed the SAME-DEVICE stale-snapshot lost-update on…

### progress_map_writer_consolidation (1 bugs)
- 2026-07-30 d5c8a3 — OI-45 named UserRepository's progress-map writers (updateProgress/saveProgress, user_repository.dart) as a HIGH lost-update race, originally citing 4 writers; a prior board-correction pass (Unit 1 of…

### ai_coach_daily_cap_enforcement (1 bugs)
- 2026-07-29 f4a19c — OI-46 (audit finding, re-verified 2026-07-29) named a `channel='in_app'` gap that does not exist as a live value. The real gaps, found during re-verification: (1) chat's free-tier 10/day cap…

### gate_fail_closed_discipline (2 bugs)
- 2026-07-29 d7a3f9 — CI's Audit Gates job failed on 96c6fac2 — the enforcement-infra merge commit that had already landed on main — with "Gate failed: check_closes_oi_cited.dart". The same commit's local pre-commit hook…
- 2026-07-29 a9f2c6 — Three gates shipped in this batch exited 0 while doing nothing. An OI whose status read `BLOCKED` vanished from OPEN_INDEX.md with no error; an OI whose status line read `- **Status:** CLOSED` escaped…

### usage_counter_display_and_vision_cap_value (1 bugs)
- 2026-07-29 c9e3b1 — OI-45 named `UsageCounterService.increment()` (usage_counter_service.dart:100-106) as CRITICAL — "cross-device race could let users bypass daily caps... Pattern: final c = read(); write(c+1) with no…

### bug_history_index (1 bugs)
- 2026-07-28 c4e8a2 — 237 of 344 entries in docs/diagnoses/INDEX.md carried no symptom text — just a bare `>`, `>-` or `|`. CLAUDE.md §4.1.5 makes grepping that index the mandatory first step before any root-cause…

### gate_test_environment_hermeticity (1 bugs)
- 2026-07-28 c3f8e1 — main went RED on 10dffc90. Two PRE-EXISTING gate e2e tests failed in CI while passing locally and through both pre-commit and pre-push: the gate they spawn inherited CI's real GITHUB_EVENT_PATH, whose…

### ci_remote_dependency_resilience (1 bugs)
- 2026-07-28 e1b7d4 — `main` went red twice in 25 CI runs on commits that touched no Deno code, both times with `Import 'https://esm.sh/@supabase/supabase-js@2.39.0' failed: 522` at clean-orphan-media/index.ts:2. 522 is a…

### plan_review_record_enforcement (2 bugs)
- 2026-07-28 d9b4e7 — Commits pushed straight to main skipped the keystone plan-review gate entirely — it exited at `rev-parse HEAD^2` before reading anything. Observed twice on account-tier auth code that landed with no…
- 2026-07-27 a7f3d1 — The merge-to-main keystone gate returned PASS for changes it was built to block. A branch could lower its own tier by editing the registry in the same commit, and content written while resolving a…

### blast_radius_registry_coverage (2 bugs)
- 2026-07-27 a3d7b1 — Ten enforcement scripts — two of the four git hooks setup-hooks.sh installs, both sanctioned write wrappers, the whole rule-22 diagnose-doc chain, and two hard-fail discipline gates — were all feature…
- 2026-07-27 c9f1d3 — scripts/check_code_review_pass_exists.dart — the gate that decides whether a catastrophic-tier diff has an accepted review — was itself feature tier. A change to it cleared no review gate at all: no…

### git_safety_hook_contract (1 bugs)
- 2026-07-27 b7e4c2 — The two tests guarding the raw-`git commit` block fail whenever a conflicted merge is in progress — which is precisely when the pre-commit hook runs the full suite. Any integration merge with a…

### notification_preferences_emission (1 bugs)
- 2026-07-27 d4e8b2 — Every notification toggle in Settings was decorative. Verified live: 0 of 91 user_daily_snapshots rows carried a notification_preferences key, so every server-side check fell through to its permissive…

### code_review_pass_enforcement (1 bugs)
- 2026-07-27 b2e6c4 — The catastrophic-tier review gate was satisfied by an untracked file. It hashed the staged diff but checked the working tree for the review, so a docs/reviews/<hash>-review.md that was never git-added…

### device_session_identity_binding (1 bugs)
- 2026-07-27 e7b3c5 — Sign-out cleared Hive and Supabase but released nothing the device holds outside them. After user A signed out the handset was still OneSignal external_id = A and Crashlytics userIdentifier = A, so…

### llm_prompt_input_sanitization (1 bugs)
- 2026-07-27 f4a9c2 — User-editable text was interpolated raw into LLM prompts across the Edge Function tree. A newline in a display name, a meal description, or a conversation turn starts what reads to the model as a…

### cron_auth_gate (2 bugs)
- 2026-07-26 c3f8a1 — Every cron-dispatched Edge Function that carries the isAuthorizedCronCall gate returns HTTP 401 on every tick — 17 of the 18 HTTP cron jobs. No push notification has been delivered to any user for at…
- 2026-05-11 7ad0c4 — 8 cron Edge Functions had verify_jwt false at the gateway AND no manual auth check at handler entry. Anyone with the function URL could trigger expensive Gemini fanout, OneSignal pushes, or DB scans…

### keystone_gate_branch_recovery (1 bugs)
- 2026-07-26 d3f8a2 — Three defects in the §4.12 keystone gate's branch-recovery step, all of which either redden main for legitimate work or let a merge pass on the wrong review: (1) a GitHub PR merge subject ("Merge pull…

### ci_concurrency_cancels_keystone_gate (1 bugs)
- 2026-07-26 e4a7c1 — Two merges to main in quick succession: the second push cancels the first push's still-running workflow. The `plan-review-record` job — the ONLY place the §4.12 keystone gate executes — therefore…

### subscription_state (7 bugs)
- 2026-07-26 a7d2e9 — morning-alert sends Gemini-generated PRO-tier copy to users whose subscription lapsed. Live at discovery: zero users were genuinely PRO, yet six were being treated as PRO and receiving paid-tier…
- 2026-06-16 a1c9f4 — On live web (test2@gmail.com), applying AVYA-TESTCODE in Profile → "Apply Referral Code" returns "Internal server error" (HTTP 500). Reproduced on a CALM backend (so not the Free-tier compute…
- 2026-06-08 b4e2a9 — delete-account Edge Function SELECTs subscriptions.razorpay_subscription_id, a column that never existed (the app uses one-time Razorpay orders, not recurring subscriptions). PostgREST returns 42703;…
- 2026-05-31 c7e1a4 — During the live-web year-sim (driving amar to Lieutenant), the dev PRO grant was silently wiped within ~1 second of being granted — BEFORE the sim loop started. The `/dev` autorun logged `isPro right…
- 2026-05-06 979a8e — PRO upgrade did not reflect immediately in train screen; train expanded view showed 0 sets; macros displayed incorrectly — three stacked bugs from the first on-device audit.
- 2026-05-06 69276a — subscriptionInfoProvider was not invalidated on cold-start subscription state writes (verify, downgrade), so PRO status changes did not propagate to the UI until next hot restart.
- 2026-05-04 5d2ff1 — razorpay-webhook derived plan (monthly/yearly) from client-supplied body.plan instead of payment amount, allowing a monthly payment to grant yearly entitlement.

### hold_display_read_path (1 bugs)
- 2026-07-25 c8b3f2 — Two defects in the free-tier "Hold the Line" DISPLAY, both found by a LIVE walkthrough on test7 (flag flipped ON via the /dev Flags card, time-travelled to the day-29 wall, three holds taken) — the…

### auth_password_reset_pkce_detection (1 bugs)
- 2026-07-23 b7d4e2 — Password-recovery email link (https://app.icanbefitter.com/reset?code=<uuid>) lands on the SPA, briefly shows /restoring, then routes to /onboarding instead of the in-app reset-password form. The user…

### auth_password_reset_timing (1 bugs)
- 2026-07-23 9f5c41 — Password-recovery email link lands on the SPA but GoRouter immediately routes to /sign-in instead of /reset. The URL hash containing `type=recovery&access_token=...` is consumed by GoRouter before…

### auth_password_reset (1 bugs)
- 2026-07-22 e9f2a4 — Forgot-password email link points to `http://127.0.0.1:3000/reset` instead of `https://app.icanbefitter.com/reset`. User never reaches the reset-password form. The Supabase Cloud Auth dashboard Site…

### program_week_projection (1 bugs)
- 2026-07-21 c9f4a2 — `user_progress.current_week` is a dead constant. Every writer sets the literal `1` (user_repository.dart:136, onboarding_provider.dart:473/786, graduation_screen.dart:673, pro_phase_advance.dart:107,…

### scheduled_workouts_mutations (4 bugs)
- 2026-07-21 d7f3a9 — The free-tier "Hold the Line" mechanic (`redoWeek4`) was broken three ways and its extension was not durable. `redoWeek4` (workout_schedule_write_service.dart:172) (a) started the new week on a…
- 2026-05-22 b0baa5 — Founder tapped GENERATE NEXT PHASE the second time on 2026-05-21 evening (after Theme F2 unblocked the silent gate). Plan generation fired, BUT: the train screen then showed a new Phase 1 starting…
- 2026-05-12 8f3d22 — `WorkoutScheduleService.assignTemplateToDate` silently returns `void` when the target date's schedule entry has `status == 'completed'`. The caller in `train_screen._scheduleTemplate` iterates over…
- 2026-05-12 9e2c1a — Founder on +22 fresh install (Hive wiped, restored from cloud) sees Monday 2026-05-11 day card header rendering the original plan-generator name "PUSH A" instead of the assigned template name "Leg Day…

### exercise_logs_read_path (7 bugs)
- 2026-07-20 a3c8e2 — A completed workout could be written to a PAST date. `completeWorkout` dated the whole session from `state.workoutDay?.date` — the plan-day being performed — and `CurrentPlanData.todayWorkout`'s…
- 2026-06-06 e4a8b1 — A just-logged exercise vanished from the Train/receipt UI after the user closed + reopened the app ("the logged exercise was gone"), while the schedule change and the weight log from the same session…
- 2026-06-06 d9a4f2 — workout_log_sets PER-SET rows with reps > 1000 were silently dropped: the cloud CHECK wls_reps_realistic (<= 1000) rejected them with 23514 and the sync catch swallowed it, so the per-set row (read by…
- 2026-06-05 e7b3c9 — workout_log_exercises SUMMARY rows with reps > 1000 were silently dropped: the cloud CHECK wle_reps_realistic (<= 1000) rejected them with 23514 and the sync catch swallowed it, so the per-exercise…
- 2026-05-31 7d3f0a — Surfaced by the year-simulation harness: SyncService._syncExerciseLogs logs repeated PostgrestException(code 23514, "new row for relation workout_log_exercises violates check constraint…
- 2026-05-22 89d56c — Founder unlocked Phase 2 graduation card 2026-05-21 and saw TOTAL SETS = 0 alongside 30 PRs / 15 workouts / 2 week streak. Cloud data shows hundreds of completed sets across Phase 1. Every user on…
- 2026-05-12 f4c9e1 — After completing today's morning workout via the active-workout flow, the Edit Workout Log sheet shows "No exercise logs for this day" — blank. Cloud workout_log_exercises HAS the 5 rows for the…

### workout_completion_status (8 bugs)
- 2026-07-20 b7f30a — Tapping START on Home's Today's Workout card dead-ended. The handler was a bare `onStart: () => context.go('/train/active-workout')` (home_screen.dart:875) — pure navigation with no call to…
- 2026-05-29 7c2a8b — After any cloud restore (reinstall, new device, logout then login) every workout session name ("Push A", "Pull B") is replaced by the literal "Workout" in home history, receipt headers, and the AI…
- 2026-05-12 d4e9c1 — Founder logged Saturday May 9 BACK DAY A. Cloud confirmed scheduled_workouts row has status='completed'. After logout → login on Sunday May 10, the calendar strip showed S9 with NO checkmark.…
- 2026-05-12 a9f3d2 — Home today-card showed "BACK DAY A · DONE" (green DONE pill) for Sat May 9, but the calendar-strip's Sat May 9 cell showed only the gold today-border with NO checkmark, while earlier completed days…
- 2026-05-10 c8e4a1 — 10 PostgrestException 23503 (scheduled_workouts_template_id_fkey) errors fired in 5 seconds on the founder's account at 2026-05-10 12:45 UTC. Saturday's completed workout never reached cloud and the…
- 2026-05-10 d9b2c5 — Saturday's locally-completed workout was overwritten back to 'planned' on every cold-start restore, because cloud still held the older 'planned' row (Bug B.1's FK violation prevented push) and…
- 2026-05-10 e3f7a8 — A subset of users (founder included) holds Hive `schedule_<date>` rows with `status='completed'` while the cloud `scheduled_workouts` row stays at `status='planned'` for those dates. Once Bugs B.1 +…
- 2026-05-10 a7c1e2 — Calendar checkmarks for May 5/6/7 vanished on the founder's account after restore, despite cloud workout_logs and scheduled_workouts.status='completed' being correct for those dates.

### exercise_equipment_tier (1 bugs)
- 2026-07-19 d4e8a1 — Exercises doable with little/no equipment were HIDDEN from the tiers they belong to because their `equipment_tier` array skipped the middle tiers: Glute Bridge tagged ["bodyweight","full_gym"]…

### exercise_library_schema (1 bugs)
- 2026-07-19 e1a7c4 — 9 exercises E252-E260 (Wall Sit, Bodyweight Good Morning, Doorframe Curl, Towel Row, Negative Pull Up, Glute Kickback, Dumbbell Calf Raise, Split Squat, Incline Dumbbell Press) used a DIFFERENT…

### exercise_injury_tags (1 bugs)
- 2026-07-19 f4c1e8 — The always-on queryV4 injury filter (exercise_repository.dart:335-345) excludes an exercise for an injured user ONLY when the exercise's injury_contraindications list CONTAINS the user's injury token;…

### universal_pool_fallback (1 bugs)
- 2026-07-19 c3f9b2 — The V4 last-resort fallback pool `universalPoolV4` (attempt-5 of the cascade) had duplicate + wrong-pattern entries: horizontal_pull = ['Inverted Row','TRX Row', 'Inverted Row','Dead Bug'] (Inverted…

### plan_phase_expiry (3 bugs)
- 2026-07-18 a4e2d9 — REG-1 (surfaced by the Batch-8 W2.5 regression audit). A PRO user whose phase has expired is auto-advanced to the next phase by a SILENT splash pass (`_autoGenerateNextPhaseForPro`), which is fired…
- 2026-06-09 a1d4f9 — APK +34 obs 1/5.1/6 — Home "Start Workout" said "not scheduled", the Train week strip highlighted a wrong/last week as TODAY with "No workouts scheduled", and the plan looked expired — even though the…
- 2026-06-09 b6e1c3 — APK +34 obs 1/6 — the Train week strip highlighted a wrong/last week as TODAY (image 1: Phase II W1 marked current while W2-W6 showed completed ticks; image 4: Phase IV W12 highlighted as TODAY with…

### admin_route_reachability (1 bugs)
- 2026-07-16 b3f9a1 — Opening app.icanbefitter.com/admin on the web lands on the normal Home screen, not the founder admin dashboard (URL bar became /admin/#/home). The dashboard code, server gate, and Edge Functions are…

### equipment_needed_shape (1 bugs)
- 2026-07-14 e9d1c7 — Selecting any of 9 exercises (E252–E260: Wall Sit, Bodyweight Good Morning, Doorframe Curl, Towel Row, Negative Pull Up, Glute Kickback, Dumbbell Calf Raise, Split Squat, Incline Dumbbell Press) from…

### admin_dashboard_metrics_snapshot (1 bugs)
- 2026-07-13 a9d3f1 — The three public.founder_metrics_*() SECURITY DEFINER functions (migration 101) were EXECUTE-able by the anon and authenticated roles. Because they are SECURITY DEFINER (they count across all users,…

### coach_plan_generation_phase_stamp (1 bugs)
- 2026-07-12 9c3e7a — Two coupled coach plan-generation defects. (1) Item ② / G8: the AI-coach "regenerate my plan" and "switch goal" tools (both routed through the shared RegeneratePlanPlanner) called…

### injury_contraindication_filter (1 bugs)
- 2026-07-12 a1f6c3 — Injuries were collected everywhere (onboarding default, Edit-Profile chips, AI-coach muster) but the plan engine's contraindication filter excluded ESSENTIALLY ZERO exercises for most users — a safety…

### injury_vocabulary_contract (1 bugs)
- 2026-07-12 d3f8a1 — The warmup/cooldown attached to every generated workout day is built from HARDCODED per-dayType name-lists (WarmupCooldownSelector `_dynamicWarmup` / `_cooldownStretches` / `_bodyweightCardio` /…

### deno_ci_environment_version_drift (1 bugs)
- 2026-07-09 c3d8a9 — Immediately after merging the deno-type-debt-cleanup work (which widened the CI `deno check` step from 3 named files to the full supabase/functions/ tree, claiming 0 errors), the CI run on main…

### n/a — UI reachability fix (no SoT concept; no writer/reader contract change) (1 bugs)
- 2026-07-08 f8c0de — Founder-reported live (test7, 2026-07-04): tapping the AI-coach "Go PRO" at the 10/10 free daily limit did nothing. Root cause read from source: at the limit the composer shows a gold "Daily limit…

### edge_function_unchecked_read_hardening (1 bugs)
- 2026-07-08 a7e2c4 — 12 Edge-Function read sites destructure `.data` (or `await Promise.all([...])`) WITHOUT capturing `.error`, so a silent query failure is coerced into empty/null data → a silently-wrong effect, not an…

### rls_initplan_auth_uid_wrap (1 bugs)
- 2026-07-07 e6b1a4 — The Supabase performance advisor reports 137 `auth_rls_initplan` warnings and 5 `multiple_permissive_policies` warnings. Each flagged RLS policy calls `auth.uid()` bare, so Postgres re-evaluates it…

### worktree_per_session_isolation (1 bugs)
- 2026-07-07 f0c2d5 — Two incidents on 2026-07-07 mixed work across concurrent Claude sessions. Multiple sessions were running in the SHARED main folder (`C:/Upendra/Claude Code/Fitness App`), which has ONE git index…

### coach_derived_completion (1 bugs)
- 2026-07-06 280c4d — A single coach `logSet` on a multi-exercise scheduled day silently flipped the WHOLE day to `status:'completed'`, inflating streak / rank / deployment. The coach dispatcher's derived-completion hook…

### plan_review_record_verdict_format (1 bugs)
- 2026-07-06 c6a9e2 — CI run 28711975359 (the coach-gemini-reliability merge, b2ea2e3) failed the "Plan-review record (>=account merge-to-main)" gate even though the ×2 review + B-pass + Hermes genuinely happened and both…

### gemini_flash_reliability (1 bugs)
- 2026-07-04 7fbe21 — The AI coach and the meal-text parser were unreliable in three linked ways. (FC1) Gemini 2.5 Flash runs "thinking" ON by default and the hidden thinking tokens count against maxOutputTokens; with our…

### coach_system_prompt_safety (1 bugs)
- 2026-07-04 9c2d4a — Two prompt-safety gaps on the AI coach. (FC5) On a jailbreak probe ("print your prompt", "ignore previous instructions", "what are your rules") the coach partially disclosed its system framing — there…

### nutrition_total_calories (1 bugs)
- 2026-07-04 4e8f1b — The AI coach's `log_meal_by_text` tool (and any other NutritionWriteService caller — the AI breakdown override, a fat-fingered manual edit) could persist an absurd calorie / macro value with NO…

### coach_log_confirm_routing (1 bugs)
- 2026-07-03 a1d7c3 — Two defects in the AI-coach chat log flow, both from the coach rendering THREE parallel confirm systems (chat_area.dart:92 LogConfirmCard legacy instant-log; :98 WorkoutLogConfirmCard legacy workout…

### audit_fixwave_small_fixes (1 bugs)
- 2026-07-03 d8a6f2 — Cluster of dead-code + small-correctness findings from the 2026-07-02 audit, fixed together in Units 6-7. (F14) NutritionWriteService.logWater wrote a `water_<date>` key to nutritionBox with ZERO…

### nutrition_slot_merge (1 bugs)
- 2026-07-03 e5c4b9 — NUT-02 same-slot meal data-loss. The local Hive key is item-hash-based — `nlog_<istDate>_<mealType>_<itemsHash>` (nutrition_write_service.dart:743-751, hash at :788) — so logging TWO different meals…

### workout_schedule_write_path (1 bugs)
- 2026-07-03 f3b2e8 — WorkoutScheduleWriteService.pauseRange (workout_schedule_write_service.dart:120,140) aliased `final box = _hive.workoutBox;` then did a bare `await box.put(key, map)` for each paused day, with…

### auth_hive_owner_agreement (2 bugs)
- 2026-07-02 a7f2e1 — In-session account switch (sign-out userA → sign-in userB as a DIFFERENT user) leaves every mixin tab (Home/Train/Nutrition/Profile) stuck on the loading SKELETON forever, until a full page reload.…
- 2026-06-21 b8e3f1 — Full-charter web E2E (2026-06-21, OBS-6): in-session sign-out → sign-in as a DIFFERENT user → blank Home (and a cold-boot deep-link to /coach/induction showed "Something went wrong"). Root cause:…

### urine_color_logs (1 bugs)
- 2026-06-28 b6d3f9 — HealthWriteService.logUrine writes urine_color_<date> into healthBox, then fires SyncService.syncNutritionData(). But syncNutritionData's fan-out is _syncNutritionLogs + _syncWaterLogs +…

### rank_gate_copy_truthfulness (1 bugs)
- 2026-06-28 f1a9d3 — OBS-1 (founder, live web signup): the induction "I COMMIT" screen promised "Make Sub Lieutenant rank — 104 workouts on this app" and "104 workouts is roughly six months of disciplined training". The…

### snapshot_fanout_coalescing (1 bugs)
- 2026-06-27 e7c1a9 — Every Hive write across health / nutrition / workout / schedule fires unawaited(SyncService.instance.pushSnapshot()) (~50 call-sites) — each a separate `daily-snapshot` Edge Function invoke. During…

### scheduled_workouts_idempotent_upsert_skip (1 bugs)
- 2026-06-27 b4f7e2 — Live telemetry (project dedsavbjuwgarrhphgnl, user e34b04a9) showed a RETURNING login made ~190 cloud ops, of which ~96 were `upsert_scheduled_workout` — one full UNCONDITIONAL re-upload of the entire…

### fire_and_forget_sync_coalescing (1 bugs)
- 2026-06-27 c4f8d2 — Live telemetry (project dedsavbjuwgarrhphgnl, user e34b04a9) proved the client phones the cloud far too often. A FRESH SIGNUP fired ~90 cloud ops in 27 s — syncWorkoutData() (the SoT fan-out) fired…

### ai_snapshot_building (4 bugs)
- 2026-06-26 f3c8d1 — Founder-directed AI-chat investigation (2026-06-26) — the AI Coach sends `AiSnapshotBuilder.buildAiContext()` to Gemini on EVERY chat turn (and the same snapshot, pushed to `user_daily_snapshots`, is…
- 2026-06-01 a9c3e2 — Driving the AI coach live as amar (a year-sim power user), EVERY message failed with "Your coaching context is unusually large. Please try a shorter question." The server-side snapshot guard…
- 2026-05-22 b4a09c — Pre-commit hook fails with 4 undefined-method errors blocking all commits on main since 2026-05-21: - `test/ai_coach/meals_today_snapshot_test.dart:68,108,128` calls…
- 2026-05-17 93aeac — `AiCoachRepository.buildAiContext()` emits ~48 keys into a JSON blob. 13 Edge Functions consume it via two paths: (A) ai-proxy / ai-media-proxy stringify the whole blob into the Gemini system prompt;…

### hive_first_boot_onboarding_no_blocking_cloud_await (1 bugs)
- 2026-06-26 a1f9c4 — Live web E2E (test6@gmail.com, fresh signup, Unit G walk). Two stuck-screen hangs with no error and no escape, both on the critical boot/onboarding path: (1) the onboarding Plan screen's REPORT FOR…

### streak_current_days_cloud_persist (1 bugs)
- 2026-06-25 e9d4b7 — Full-charter web E2E (2026-06-21, OBS-8b): after idle days the cloud `user_progress.current_streak_days` stayed STALE (e.g. 1 when the streak had actually decayed to 0). The day-rollover reckon…

### e2e_cosmetic_copy_sweep (1 bugs)
- 2026-06-23 e5c1a2 — Full-charter web E2E (2026-06-21) cosmetic + copy observations (Unit C of the fix arc). OBS-1: Home Today-card macro row RenderFlex right-overflow (~2.5-15px) at ~390px. OBS-5: subscription card shows…

### nutrition_target_canonical_read (1 bugs)
- 2026-06-23 c8a1f4 — Full-charter web E2E (2026-06-21, OBS-11): the Home nutrition snapshot showed 2540 cal / 140 g protein (correct, the stored canonical user_profile target) while the Nutrition tab "Today's Summary"…

### streak_freeze_denominator_grant_decay (1 bugs)
- 2026-06-18 f9d2e7 — Founder report: PRO had been active 7 days but the Home streak-freeze chip still showed "1/1", not "3/3"; and on deeper investigation the streak read 1 and freezes read 1 even though the last two days…

### client_web_platform_gating (1 bugs)
- 2026-06-14 d8f3a2 — Live web (test2). (obs 2b) Tapping CONNECT on the Health Sync card "got stuck on the Health Connect page" — on web there is no Health Connect / HealthKit binding, so the native permission flow…

### onboarding_bodyfat_calc_input (1 bugs)
- 2026-06-14 c3f2d8 — Live web (test2) + audit. The SAVED onboarding calorie target ignored the user's body-fat: a user who typed 12% got the SAME daily_calories as a skip-user, because both the onboarding COMMIT…

### user_scoped_box_before_openForUser (1 bugs)
- 2026-06-13 a7c3f8 — Web boot console (Obs#3, live web E2E): "[main] coach_memory backfill failed: Bad state: HiveUserSession not opened — cannot wrap user-scoped box \"coachBox\". Call HiveUserSession.openForUser(userId)…

### edge_function_cross_user_read_rls_context (2 bugs)
- 2026-06-13 c7d4f1 — Profile -> Submissions -> COMMUNITY REVIEW always shows "No items to review right now", for EVERY user, even when other users have submitted unapproved custom foods/exercises. The community-vote ->…
- 2026-06-13 d2b9e6 — Live web E2E (test2@gmail.com, Unit 1). Applying a referral code ALWAYS failed — the Profile "Apply Referral Code" sheet showed "Network error. Try again in a moment." and the welcome-stash redeem at…

### platform_guarded_native_init (1 bugs)
- 2026-06-13 b2e9d3 — Web boot console (Obs#2, live web E2E): "[main] Firebase/Crashlytics init failed: Null check operator used on a null value". main() ran Firebase.initializeApp() + FirebaseCrashlytics.instance.* with…

### edge_function_caller_token_freshness (1 bugs)
- 2026-06-13 c4f1a7 — Live web E2E (Obs#9): on the DPDP "Type to confirm" erasure screen, tapping the enabled "IRREVERSIBLE — DELETE MY ACCOUNT" button surfaced "Couldn't delete account. Try again or contact support." and…

### expanded_starved_by_fixed_siblings (1 bugs)
- 2026-06-13 b9c4f1 — Obs#7 (live web E2E, cosmetic): on the AI food-analysis result card (ai_breakdown_card._buildItemRow), item names ("Boiled Eggs", "Chicken Breast 100g") rendered VERTICALLY — one character per line.…

### responsive_picker_host (1 bugs)
- 2026-06-13 e8a2c1 — Obs#5 (live web E2E, potential onboarding BLOCKER): on the ~698px web mobile- frame the stock Material TIME picker (muster Q2 wake/train time) showed its OK/Cancel action row BELOW the visible frame…

### onboarding_preview_commit_calc_parity (1 bugs)
- 2026-06-13 f1b6d4 — Obs#6 (live web E2E): the onboarding plan-PREVIEW card (plan_screen step 05) showed "2867 KCAL" but the SAVED + home-displayed daily_calories was 3200 — the number the user commits to differed from…

### signup_aware_restore_copy (1 bugs)
- 2026-06-13 d5e1b9 — Obs#1 (live web E2E, founder report): "when i created a new account (because i had clicked on signup) why was i shown 'loading your account'? it should say something like account creation in…

### realtime_teardown_on_reconnect_exhaustion (1 bugs)
- 2026-06-13 a3d7e2 — Obs#8 (live web E2E console): "[realtime] weight_logs stream error: RealtimeSubscribeException channelError" recurring (WS close 1006/1000). The PRO realtime weight_logs subscription (Telegram→app…

### commit_gate_hash_stability (1 bugs)
- 2026-06-12 f4d1b7 — Two commit-gate tooling bugs surfaced during the f1c8e4 commit gauntlet, both in the "stable staged-diff hash" path the catastrophic review gate (check_code_review_pass_exists.dart) relies on: (#2)…

### postgrest_builder_has_no_catch_method (1 bugs)
- 2026-06-12 d5b2f8 — The SECOND never-run delete-account bug, revealed the instant the e8a1c3 auth fix let the erasure path execute for the first time. With a VALID token, the EF now passed auth, ran the full erasure, and…

### edge_function_user_token_validation_pattern (1 bugs)
- 2026-06-12 e8a1c3 — Live web E2E (test1@gmail.com, Obs#10). The delete-account Edge Function (DPDP §17 erasure) rejected EVERY valid user token with 401 "unauthenticated" — so no user could delete their account via the…

### dpdp_erasure_must_not_block_on_external_dependency (1 bugs)
- 2026-06-12 a2c8e6 — Quarterly audit (L21 lens) finding F1, founder-authorized fix. The delete-account Edge Function (DPDP §17 erasure) cancels the user's Razorpay subscription BEFORE deleting the account (correct —…

### hive_field_name_wlog (1 bugs)
- 2026-06-12 f1c8e4 — Quarterly audit deep-verify finding (surfaced while verifying apk34 c2e8b4). The canonical LIVE completion writer WorkoutWriteService.markCompleted (which the A-13 derive-only refactor made "replace…

### orphan_completion_wlog_completeness (1 bugs)
- 2026-06-12 b3f9d1 — Quarterly audit (L1 lens) finding F1, confirmed post-f1c8e4. The orphan-completion restore branch (_restoreScheduleCompletions, the "no local schedule row for this date" / out-of-plan-window case in…

### weekly_workout_count_ist_window (1 bugs)
- 2026-06-12 e7a2c4 — Quarterly audit (L1/IST lens) finding. getWeeklyWorkoutCounts (workout_repository.dart) — the reader behind the reports "This Week" tile + the 4-week frequency chart — anchored its rolling window on…

### security_definer_function_exposure (1 bugs)
- 2026-06-11 c9b3e2 — The quarterly audit's live-DB pass (Supabase security advisor + pg_proc inspection) found several SECURITY DEFINER functions in schema public that were EXECUTE-able by the anon and/or authenticated…

### streak_freeze_progress_merge (1 bugs)
- 2026-06-11 a8f3d1 — Quarterly audit (L27 concurrency lens) finding. The slow-boot flip (ADR-0014) lands a returning user on /home BEFORE the restore's Step C (_restoreFreezes) runs. On /home the streak walk…

### profile_image_url_display (1 bugs)
- 2026-06-09 b1f3a7 — APK +34 obs 4 — the Profile avatar AND banner images re-download from the network every single time the user navigates to the Profile tab. They are not served from the local cache, so each visit shows…

### weekly_report_data (1 bugs)
- 2026-06-09 c2e8b4 — APK +34 obs 2 — the Weekly Report ("Weekly Dispatch") "This Week" summary card showed "19 Workouts" — an impossible weekly number. The value was the LIFETIME total_workouts_done shown under a "This…

### restore_completeness (13 bugs)
- 2026-06-09 e9b4a2 — APK +34 obs 5.2 — Home showed streak "0 DAYS" though cloud user_progress.current_streak_days was 2 and the user had recent completions (last_workout_date 2026-06-06). After a reinstall the client-side…
- 2026-06-07 c5a1f2 — A returning, signed-in user waited >1 minute on cold start: RestoringScreen._goHome unconditionally awaited the full since='2020-01-01' cloud restore before navigating to /home (the background-restore…
- 2026-06-06 a7d3f1 — After a fresh-install restore the Train screen showed the wrong week/phase (Home "WK 4", Train banner "WEEK 4 OF 12", Roadmap "33% complete", "Week 6 hasn't started yet") AND every not-yet-completed…
- 2026-06-05 4e8b1d — First cold start was very slow. Live telemetry (restore_completed) showed the full cloud restore = 37.6s and it BLOCKED the RestoringScreen before /home. Step A alone = 25.8s, dominated by the FIRST…
- 2026-05-22 4a3b08 — Founder saw the "This is taking a while. CONTINUE →" escape-hatch button surface on the RestoringScreen on every cold start, even though the restore was progressing normally. Root cause: APK +28/+30…
- 2026-05-08 b2ac5d — Multiple restore failures — _restoreXxx methods keyed Hive by cloud UUID instead of deterministic WriteService key (calendar dup explosion); _restoreUserProfile missed users.full_name so greeting…
- 2026-05-07 5c61ed — Multiple issues — restore stack had HiveUserSession ordering bugs causing 30+ cold-start restore failures logged to client_errors; receipt chips needed per-set rendering; 5 IST drift sites remained;…
- 2026-05-04 d33c12 — No client-side account deletion UI existed for DPDP §17 compliance; users had no way to request hard erasure of their data.
- 2026-05-04 72ea41 — No server-side hard-delete path existed for DPDP §17 compliance, so user data could not be fully erased on account deletion request.
- 2026-05-04 776478 — Streak freezes, notifications inbox, and saved diet plan had no cloud backing, so reinstalling the app silently lost these surfaces for paying users.
- 2026-05-04 89d079 — Hard-deleting an auth user CASCADE-deleted community contributions (custom foods, exercises, reviews) that should be retained pseudonymously for community signal.
- 2026-05-04 239999 — restoreFromCloud did not pull streak freezes, notifications inbox, saved diet plan, rank promotions, or coaching notes, so reinstalling lost all these surfaces.
- 2026-05-04 ad7664 — Streak freezes, notifications inbox entries, and diet plan were written to Hive but never pushed to cloud, so they were silently lost on reinstall.

### realtime_sync_resilience (1 bugs)
- 2026-06-09 a7f2e9 — Two sync-resilience gaps surfaced in the APK +34 live telemetry: (BUG-H) the realtime weight_logs stream channelError'd 113x (WS close 1002) and never recovered — only "token expired" triggered a…

### fitness_goal_resolution (2 bugs)
- 2026-06-08 a4f7e1 — The AI coach's `regeneratePlanBlock` tool exposed a `goal` z.enum that omitted 'recompose' (only build_muscle / lose_fat / general_fitness / strength). Its sibling `switchGoal` had 'recompose' added…
- 2026-06-07 f19a7c — The default onboarding goal "Recompose" emitted key 'recomp', which plan_screen._mapGoal translated to the token 'recompose' — a value no calculator recognised. BmrCalculator's goal switch fell to…

### rank_monotonic_current_code (4 bugs)
- 2026-06-08 d7c3f1 — The nightly evaluate-rank-promotions cron's completionRateOverWindow (_shared/rank_engine.ts) SELECTed scheduled_workouts.reason — a column that exists only in the client's local Hive model, never in…
- 2026-05-31 b9f4d2 — Surfaced while wiring the deployment-driven rank ladder: the server cron `evaluate-rank-promotions` SELECTs four columns from `user_progress` (current_streak_days, deployments_complete,…
- 2026-05-30 f4b2c9 — Surfaced during live web E2E. After onboarding, amar@gmail.com had ZERO rank_promotions rows (not even the SD2 floor) and the browser console showed "[RankService.evaluateAndPromote]…
- 2026-05-27 3a7b9f — Founder-as-user "upendra" (auth.users d7a67a37-0b05-4f0a-b13c-388bff3cb59b) earned SD1 (ordinal 1) on 2026-05-21 14:35 UTC at streak=7, week=2, 15 workouts. Approximately 7 hours later (2026-05-21…

### workout_receipt_rendering (3 bugs)
- 2026-06-08 a3e8f1 — workout_log_exercises.set_number and workout_log_sets.set_number carried a CHECK bound of <=10 (wle_set_number_realistic / wls_set_number_realistic). >10 sets per exercise is legitimate (drop sets,…
- 2026-06-05 6f1a2c — The workout receipt / share card (Home "View Card", day-detail sheet, post- completion sheet — the shareable card with AVYA branding + QR) rendered a hardcoded "PHASE 1" subtitle even when the user…
- 2026-05-12 a2b3c4 — Cloud column `workout_log_exercises.duration_seconds` is always NULL for rows written by the modern `WorkoutWriteService`. The `SyncService._syncExerciseLogs` projection writes `'duration_seconds':…

### std_encoding_dead_export_deploy_rot (1 bugs)
- 2026-06-08 d4c8e1 — During the Batch 6 audit deploy (2026-06-08), redeploying razorpay-webhook (the live Razorpay payment webhook) returned HTTP 503 BOOT_ERROR ("Function failed to start") on EVERY request — the webhook…

### edge_function_duplicate_const_boot_failure (1 bugs)
- 2026-06-08 f5d8c3 — verify-payment failed to BOOT (module-load SyntaxError) — every authenticated call returned a gateway 5xx, so the client's payment-verification fallback was dead. Cause: the Batch-6 F31/F33 refactor…

### ai_free_message_limit (1 bugs)
- 2026-06-07 f1a70c — The client declared the free AI-coach cap as 15 messages/day and ran a client-only 30-day trial, while the server (ai-proxy) enforces 10/day FOREVER with no trial (OQ-1). Two user-facing failures: (1)…

### honest_surface_integrity (1 bugs)
- 2026-06-07 e2a1f7 — Three user-facing surfaces showed fabricated or misleading content under an honesty-led brand. F10: the home AI-insight card rendered a CONST "QUICK WINS" macro rail beneath a live-AI "AI COACH ·…

### hardcoded_value_centralization (1 bugs)
- 2026-06-07 15c0de — Hardcoded values/figures had drifted from their single source of truth. F13: AppConstants.appVersion lagged at '1.0.0+28' while pubspec was '1.0.0+33', so client_errors / telemetry rows from builds…

### ist_date_key_consistency (1 bugs)
- 2026-06-07 157d0c — Across home / train / nutrition / AI-coach / profile, many READERS built a device-local 'YYYY-MM-DD' date key ('${x.year}-${x.month.toString().padLeft(2,'0')}-${x.day...}') while their WRITERS key by…

### server_edge_function_and_cron_hardening (1 bugs)
- 2026-06-07 b3f0d9 — Eight server-side Edge-Function / cron defects from the 2026-06-07 audit. F44 (SECURITY): proactive-coach-promotion ran verify_jwt=false with NO auth gate, so an unauthenticated POST drove Gemini cost…

### writer_reader_drift_and_dead_reads (1 bugs)
- 2026-06-07 c4d9b2 — Five writer/reader-hygiene defects. F2: the rank-ladder DEPLOYMENTS tile read progress total_workouts_done while the RANK card read deployments_complete — two surfaces showing different numbers for…

### client_ux_flow_and_restore_correctness (1 bugs)
- 2026-06-07 a8e3c5 — Twelve client UX/flow/restore defects from the 2026-06-07 audit. F3: the streak explainer claimed "+1 each week you complete at least 80% of scheduled workouts", but the real algorithm is +1 per…

### alert_threshold_tuning (1 bugs)
- 2026-06-06 f0b9d3 — The alert_client_errors_spike cron paged critical for benign volume. Alert #24 fired "client_errors spike: 354 rows in last hour" (critical) for what was the founder's own reinstall/restore burst on…

### coach_interactions (4 bugs)
- 2026-06-06 c3f9a1 — Two AI-coach interactions saved within the same millisecond both minted the Hive key coach_<ms>; the second coachBox.put overwrote the first (silent data loss). Surfaced as a non-deterministic CI…
- 2026-05-29 9e1d4c — Every rank promotion silently fails to deliver its celebration — no AI congrats message is stored and no OneSignal "Promotion Day" push is sent.
- 2026-05-04 4c8788 — AI coach message count was recomputed from Supabase on every render, causing unnecessary round-trips; cache key was not IST-aware, causing stale counts across midnight.
- 2026-05-04 bb3acc — Morning alert Edge Function computed day-of-week and date strings in UTC instead of IST, sending wrong day greetings after 18:30 IST.

### check_and_sync_null_safety (1 bugs)
- 2026-06-05 c5e1b7 — Recurring "_TypeError: Null check operator used on a null value" on the check_and_sync path (op_types check_and_sync / sync_service_if_2) in the live telemetry of the founder's account (d7a67a37),…

### ci_local_ci_parity (1 bugs)
- 2026-06-05 c4d8e1 — CI was red on `main` for days (every job died in ~1 min at `flutter pub get`: CI pinned Flutter 3.29.x / Dart 3.7.2 while pubspec required sdk ^3.11.1). The Flutter-pin bump to 3.41.4 unblocked pub…

### biometric_sync_state (1 bugs)
- 2026-06-05 9a5c3f — Profile → Health sync: after tapping CONNECT for Health Connect, the sheet still showed "Tap to enable / CONNECT" (disconnected). Only after navigating away and back did it show "Connected".

### nutrition_recent_logs_name (1 bugs)
- 2026-06-05 8b3d4e — The Home "Recent Logs" list rendered every logged food as "Unknown" (e.g. "Unknown — 61 kcal — P2·C2·F4"), while the SAME meals showed their correct names on the Nutrition tab.

### phase_blocks_bucketing (1 bugs)
- 2026-06-05 7d2e6b — pastPhaseBlocks() bucketed past schedule rows by 28-day CALENDAR windows. A single phase whose rows span >28 calendar days (gaps/overlaps) split across two buckets → over-count → the…

### week_completion_check (1 bugs)
- 2026-06-05 2c9f7a — Train week strip, two issues: (3a) current-phase week chips never showed a completion check mark (only past-phase chips did), so a completed current week looked un-done; (3b) the strip was a bare…

### user_progress_updated_at (1 bugs)
- 2026-06-05 a2d8f4 — user_progress.updated_at was frozen at the row's created_at (account creation) even though the row's data advanced (last_workout_date = today, total_workouts current). Surfaced in the live audit of…

### sync_fanout_nutrition_domain (3 bugs)
- 2026-06-03 f7e3a1 — The d4b8e2 sweep (workout_logs / weight / sleep / body / wle / wls) left TWO nutrition tables on the same un-user-scoped deterministic-id pattern — found by the Hermes deep-pass and folded into this…
- 2026-06-01 c9f2a7 — Driving the AI coach live as amar (a year-sim power user), a coach `logMealByText` wrote to Hive correctly — the Nutrition Today's Summary card bumped exactly right (4314 -> 4644 kcal, protein 290 ->…
- 2026-05-06 344121 — Second cloud-side audit revealed 4 bugs — NutritionWriteService.onStateChanged hook missing, foodLogProvider missing from invalidation set, LoggingTypeRepairMigrator had unhandled edge cases, and…

### saved_meals (1 bugs)
- 2026-06-03 b8d5c2 — Surfaced by the f7e3a1 B-pass (Finding 1) while reviewing the saved-meals sync. `NutritionWriteService.saveMealPreset` keyed the local Hive row by `saved_meal_<millisecondsSinceEpoch>`, but the cloud…

### sync_fanout_workout_domain (3 bugs)
- 2026-06-02 d4b8e2 — Investigating the weekly report's "0 workouts" for upendra, the cloud had workout_log_exercises rows through today but NO workout_logs session-summary row newer than 05-21. Root: the cloud sync id was…
- 2026-05-15 76c8f4 — PostgREST raises 42P10 "no unique or exclusion constraint matching the ON CONFLICT specification" on every upsert to workout_logs (onConflict=user_id,date,exercise_name), workout_log_exercises…
- 2026-05-04 b621c6 — Four pre-existing test failures in rank_service_test and sync_gap_test reflected outdated test assumptions from pre-Test #6 architecture.

### ui_header_no_clip (1 bugs)
- 2026-06-02 b2e9d4 — Tab-screen headings clipped to an ellipsis: the Train screen showed "Intensificati…" (phase name "Intensification") and the Nutrition screen showed "Fueling the pl…". Both used a single-line Text…

### weekly_report_target_and_freshness (1 bugs)
- 2026-06-02 c7a1f5 — The Weekly Report showed a calorie/protein target (3141 kcal / 155 g) that disagreed with every other surface (Nutrition / Profile / Diet Plan all show 3069 kcal / 140 g), and "0 workouts / 0%…

### weight_trend_home_chart (1 bugs)
- 2026-06-02 e1c6a9 — On the Home weight view, logging a weight after a 7+ day gap rendered a single isolated dot — misleading (reads as a stray entry, not a trend). The old WardSpark sparkline only plotted points inside…

### ai_coach_tool_loop_gemini_resilience (1 bugs)
- 2026-06-01 d4f1c2 — Driving the AI coach live as amar, messages intermittently came back with "I had trouble reaching the model. Try again in a moment." — and the SAME message succeeded on a manual retry seconds later.…

### nutrition_summary_macro_row_layout (1 bugs)
- 2026-06-01 7e3c91 — On the Nutrition tab's TODAY'S SUMMARY card (driven live as amar), the macro rows showed Flutter's debug RenderFlex stripe banner ("RIGHT OVERFLOWED BY N PIXELS", rendered vertically on the right…

### past_week_history_display (1 bugs)
- 2026-06-01 f4e1d9 — Completed past-phase weeks in the Train week-selector render every day as a generic "Workout" with no exercise count and no way to see what was done — a flat read-only list (the "Completed history"…

### ist_date_clock_seam (1 bugs)
- 2026-05-31 b7c2d9 — The /dev time-travel buttons (and the injectable clock seam in ist_date.dart) did not actually move phase / rank / streak logic: jumping the clock +12 weeks left the Train week selector,…

### edge_function_dependency_resolution (1 bugs)
- 2026-05-31 f2d8ae — `ai-proxy` host-shell redeploy failed twice with HTTP 400 "Module not found https://deno.land/x/zod@v3.25.76/mod.ts". The deno.land/x zod module was removed upstream and now returns HTTP 404, so the…

### home_today_macro_column_layout (1 bugs)
- 2026-05-30 c9e0a4 — Live web (amar@gmail.com), Home Today card: three "A RenderFlex overflowed by N pixels on the right" exceptions (12 / 29 / 9.5 px) rendered as yellow/black overflow stripes on the FUEL / PROTEIN /…

### hive_session_init_race (2 bugs)
- 2026-05-30 d5c1b8 — Surfaced during live web E2E by reloading onto the /#/coach/induction hash route. The app rendered GoRouter's error page ("Page Not Found") with: "GoException: Exception during redirect: Bad state:…
- 2026-05-22 dc52a4 — Founder install of APK Test #16.2 +30 on 2026-05-20. Telemetry pulled 2026-05-21 showed `day_rollover_streak_freeze_refill` failing with "Bad state: HiveUserSession not opened — cannot wrap…

### user_stat_snapshot_7d_averages (1 bugs)
- 2026-05-30 a7c3e1 — Surfaced during AUDIT-1 (systematic schema-reference audit, 2026-05-30). StatSnapshotService._compute7dAverages selected two columns that do not exist: `daily_steps.total_steps` (real column: `steps`)…

### train_plan_header_render (1 bugs)
- 2026-05-30 b1f4d2 — Live web (amar@gmail.com): the Train tab renders "Failed to load workouts / Tap to retry" even though Home's Today card shows the same plan correctly (PHASE 1 / UPPER / 70 MIN · 7 EX). RETRY does not…

### weight_logs_realtime_stream (1 bugs)
- 2026-05-30 e3f1a7 — Live web (amar@gmail.com): recurring console "[realtime] weight_logs stream error: RealtimeSubscribeException(status: channelError, ...)" (3x in 14 min) and 156 client_errors rows…

### blast_radius_commit_autotag (1 bugs)
- 2026-05-29 c3d8a1 — The Blast-radius auto-prepend (Track 2 deliverable) never fired. Neither the mega-commit (7d31f40) nor the cron-fix commit (7490dc9) received the expected "Blast-radius: <tier>" line in the commit…

### alert_detection_edge_function_health (1 bugs)
- 2026-05-28 b1f4e2 — alert_edge_function_health pg_cron job failed every 15 minutes since migration 076 shipped, with "ERROR: column status_code does not exist". No edge-function-health alerting was actually running;…

### exercise_library_cloud_seed (1 bugs)
- 2026-05-27 ada3fb — The `/sync-claude-md` audit on 2026-05-27 found that the cloud `exercise_library` table contained 0 rows. The food parallel (`food_database`) was correctly seeded — 1,431 rows present from migration…

### writer_reader_drift_batch_2026_05_24 (1 bugs)
- 2026-05-24 524d12 — The 2026-05-24 ECC adoption batch shipped the writer-reader-drift-detector subagent (B1). Its first run on workout + nutrition domains surfaced 9 drift instances across the writer/reader contract —…

### source_grep_contract_test_recovery_post_refactor (1 bugs)
- 2026-05-24 2b705b — 53 of 2354 unit tests fail on `claude/blissful-neumann-bb2fb7` (merged to main as `cf82347`). All 53 are stale source-grep contract tests rendered obsolete by the B5 audit's refactor work (A2 + A10 +…

### graduation_phase2_preview (1 bugs)
- 2026-05-23 ea1059 — Founder reviewed the Theme H-followup mockup 2026-05-23 and spotted that the graduation screen's Phase 2 preview card hardcodes `5 DAYS/WEEK · WEEKS 5-8 · POWER + HYPERTROPHY` and a static 5-day…

### week_selector_past_phase_scroll (1 bugs)
- 2026-05-23 85a684 — Founder reviewed the Theme H-followup mockup 2026-05-23 and clarified the original "scroll back to see completed phases" wish: the desired surface is INLINE in the train screen's existing…

### workout_schedule_service_split (1 bugs)
- 2026-05-22 d882ca — `lib/core/services/workout_schedule_service.dart` had grown to ~1970 lines and absorbed four distinct responsibilities: 1. Plan generation orchestration (generateAndSchedule,…

### singleton_lifecycle_registry (2 bugs)
- 2026-05-22 7f2a8c — Seven services were instantiated as `static final XxxService instance = XxxService._()` singletons: - SubscriptionService, SyncService, WorkoutScheduleService, UsageCounterService, AiService,…
- 2026-05-21 7a3e1c — Audit finding A7 (score 14): seven `static .instance` core services live OUTSIDE the Riverpod graph and hold mutable in-memory state that survives HiveUserSession user swaps: -…

### food_text_analysis (1 bugs)
- 2026-05-22 599d49 — Founder opened Nutrition → Log Food → AI tab → typed → tapped ANALYSE & LOG → got the toast "The AI is temporarily unavailable. Please try again in a minute." (founder IS PRO with active…

### phase_unlock_card_surface_gate (1 bugs)
- 2026-05-22 0e7714 — Founder mid-Phase-1-Week-4 (Wed 2026-05-21) saw the UNLOCK PHASE 2 card and asked "since when does the user start seeing unlock phase 2? or subsequent phases? it should open up on thursday of the last…

### phase_unlock_end_to_end (1 bugs)
- 2026-05-22 ec4d27 — Two issues bundled (same code path, same surface): F: Founder tapped GENERATE NEXT PHASE 2026-05-21. After Theme F2 unblocked the silent gate, the unlock fired BUT: (a) no loading state — button…

### proactive_coach_promotion (1 bugs)
- 2026-05-22 8b1f33 — Founder ranked up SD2 → LT recently and the AVYA coach said nothing about it. The pre-existing coach surface is reactive — responds only to user messages. No proactive-message infrastructure existed:…

### rank_promotion_celebration (1 bugs)
- 2026-05-22 9aa2c1 — Founder promoted SD2 → LT recently. `RankService.evaluateAndPromote` successfully detected the rank change, wrote the `rank_promotions` cloud row, updated `user_profile.current_rank_code`, mirrored to…

### subscription_gate (1 bugs)
- 2026-05-22 7b3eaf — Founder tapped GENERATE NEXT PHASE on graduation screen 2026-05-21 evening — nothing happened. No navigation. No error toast. No paywall. No telemetry in `train_graduation_generate_phase_2_failed`.…

### sync_domain_full_migration_A6 (1 bugs)
- 2026-05-21 2b8d4e — `lib/core/services/sync_service.dart` plus its 8 `part of` files under `lib/core/services/sync/` host every sync + restore helper as private methods on the SyncService singleton. The restore-vs-sync…

### ai_coach_repository_split_A10 (1 bugs)
- 2026-05-21 9c2b1f — `lib/features/ai_coach/repositories/ai_coach_repository.dart` was 2127 lines carrying FOUR distinct contracts in one class: (1) AI snapshot building — `buildAiContext()` + ~40 private read helpers…

### post_signin_destination (1 bugs)
- 2026-05-21 17ae38 — Two coupled architecture-debt findings on the post-sign-in path. A1 (score 24): `lib/features/auth/providers/auth_provider.dart` was a god-provider. Its `_ensureLocalUser` method did Postgres CRUD on…

### dependency_canonical_http_client (1 bugs)
- 2026-05-21 3e9d39 — Two dependencies under `lib/` were duplicating the same capability — HTTP client. `package:http ^1.6.0` (declared in pubspec) was used by: - `lib/core/services/ai_service.dart` — `http.Client`,…

### edge_function_deploy_reversibility (1 bugs)
- 2026-05-21 b3ecf2 — Edge Function deploys were forward-only. When a bad deploy hit prod (caught via `client_errors` spike per B1 / I4 alert, or a user report), the operator's only path was: `git checkout <previous SHA>`…

### profile_write_service (1 bugs)
- 2026-05-21 3cbbce — Profile map mutations (goal changes from the AI Coach, weight updates from the home weight tile, post-sign-in cloud merge, brand-new user stub creation, phase_started_at stamping during onboarding…

### referral_redemption (1 bugs)
- 2026-05-21 2d1c8a — Three profile-tab readers (referral_eligibility_provider, promotion_history_provider) and one apply-referral writer (apply_referral_sheet) bypassed the repository pattern and called Supabase directly…

### sync_domain_interface_scaffold_A6 (1 bugs)
- 2026-05-21 5a0b31 — `lib/core/services/sync_service.dart` (1395 lines) plus 8 `part of` files under `lib/core/services/sync/` (5577 lines total) host every sync + restore helper as private methods on a single…

### typography_canonical_source (1 bugs)
- 2026-05-21 1f4a8b — `lib/core/theme/typography.dart` exists as the canonical Wardroom 3-font system (`AppTypography.body`, `.bodyM`, `.mono`, `.h1`, etc.) but only ~2 production files routed through it. The other 175…

### usage_weeks_signup_age (1 bugs)
- 2026-05-20 c2a91f — Founder reported "How do I see weekly report? Nothing is happening on clicking it?" on 2026-05-20 after almost 4 weeks of use. The Profile REPORTS section's Weekly Report hero card permanently…

### weight_trend_range (1 bugs)
- 2026-05-20 b3f7a2 — Founder asked on 2026-05-20: "in the weight graph in dashboard screen, what if user wants to see more than 90 days data?" The dashboard Weight Trend card…

### streak_freeze_refill_restore_race (1 bugs)
- 2026-05-19 9c4a17 — Founder install of APK Test #16.2 on 2026-05-19 (Tue). Home dashboard rendered "0/3" streak freezes and surfaced the "Streak Freeze used! 0 remaining this week." SnackBar despite the founder NOT…

### restore_long_pole_timing_visibility (1 bugs)
- 2026-05-19 4f8e2d — Founder install of APK Test #16.2 on 2026-05-19 (Tue). RestoringScreen sat on "Pulling your dispatch. Stand by, soldier." long enough for the 15-second safety-net timer at restoring_screen.dart:42 to…

### ai_tool_wall_clock_and_media_proxy_error_class (1 bugs)
- 2026-05-18 t1m5b0 — Two related AI-coach failures within a single session. Failure A (08:34 IST). User asked "how was my workout today and in this phase till now?". The coach replied: "Recruit, the system timed out…

### streak_freeze_value_clamp_on_read (1 bugs)
- 2026-05-18 f8c1a5 — On Monday 2026-05-18 IST, the Daily letterhead streak chip rendered "4 DAYS / 8/3" where the freeze badge shows 8 available against a maximum of 3 (PRO tier cap). User reported the Monday weekly…

### swap_undo_snackbar_modal_stack (1 bugs)
- 2026-05-18 s1n4c0 — During an active workout, the user opened the swap sheet on an exercise, tapped "+ ADD EXERCISE" and created "Barbell Jump Squats" via the inline CreateCustomExerciseSheet. The "Swapped X to Y / UNDO"…

### weight_log_provider_invalidation_race (1 bugs)
- 2026-05-18 w7r4c3 — User logged the first weight entry for 2026-05-18 (IST) via the Home bottom-sheet weight logger. The "WEIGHT TREND" home card x-axis rendered the new dot at MAY 18 with the correct value (77.9 kg),…

### cross_account_guard_exempt_declaration (1 bugs)
- 2026-05-17 3a7c1e — No live symptom — preventive enforcement. The existing `auth_invalidation_contract_test.dart` (post APK Test #15.3 / Bug c4055a) already auto-discovers new providers in `lib/features/` and enforces…

### marked_done_without_logging_ux (1 bugs)
- 2026-05-17 7c4e5d — On APK +27 fresh install, founder observed: (a) tapping "VIEW WORKOUT CARD" on Friday May 15's calendar day detail did nothing (silent no-op). (b) train_screen showed "FRI · HYBRID A · DONE · No…

### reader_manifest_exhaustive_completeness (1 bugs)
- 2026-05-17 0a1e17 — The build-apk Gate 18 script `scripts/check_reader_manifest_complete.dart` only enforced the "forbidden-patterns absent" half of the reader-side manifest contract. It did NOT enforce "every source…

### workout_read_service (1 bugs)
- 2026-05-17 8d85c2 — The reader side of the workout / nutrition / health domains had no canonical home. Each consumer re-implemented the same semantic inline. When the PR cumulative bug shipped on APK +27 (founder install…

### snapshot_contract_enforcement (1 bugs)
- 2026-05-17 c0e3a5 — No live symptom — preventive infrastructure. OI-07 built the snapshot contract manifest. OI-03 is the gate that ENFORCES the manifest. F3-1.1 (`coach_notes` vs `coaching_notes`) was the cross-system…

### razorpay_webhook_handler_correctness (1 bugs)
- 2026-05-17 9a7c14 — Razorpay webhook threw `ReferenceError: Cannot access 'supabaseClient' before initialization` on every `payment.captured` / `payment.authorized` event that wasn't an early-return (HMAC fail / age…

### verify_payment_payload_completeness (1 bugs)
- 2026-05-17 b3e052 — verify-payment Edge Function inserted/upserted `subscriptions` rows without the `razorpay_signature` column. Since migration 052 (2026-05-13) that column is NOT NULL. Every fallback path (when webhook…

### ai_media_proxy_user_scope_assertion (1 bugs)
- 2026-05-17 5e055f — ai-media-proxy validated only that the supplied `media_url` started with `${SUPABASE_URL}/storage/v1/object/`, then fetched the URL with `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}`. Service…

### verify_payment_notes_user_id_guard (1 bugs)
- 2026-05-17 c8f229 — verify-payment ownership check at `if (notesUserId && notesUserId !== userId) { return 403; }` was fail-open when `payment.notes.user_id` was absent. An attacker who learns a captured Razorpay…

### clean_orphan_media_bucket_target (1 bugs)
- 2026-05-17 c1ea30 — `clean-orphan-media` daily cron deleted from `coach-media` bucket — which migration 070 (also shipped 2026-05-17) had designated as long-term consented retention. Transient analysis bucket is…

### cron_edge_function_auth_gate (1 bugs)
- 2026-05-17 c4031b — 3 cron-invoked Edge Functions (expiry-reminder, morning-alert, rolling-context) created service-role clients without calling `isAuthorizedCronCall(req)`. Public POSTs could trigger expensive fan-outs:…

### delete_account_storage_purge_recursive (1 bugs)
- 2026-05-17 a2d0e1 — delete-account Edge Function only listed top-level entries under `userId/` for each Storage bucket. Nested paths (`userId/2026/photo.jpg`, `userId/subfolder/...`) survived account deletion. DPDP §17…

### apk_size_gate_strict_mode (1 bugs)
- 2026-05-17 c84e33 — `scripts/check_apk_size_within_bounds.dart` (Gate 13) silent-skipped with exit 0 when the APK artifact was missing. In a clean CI or wrong-order pipeline the gate green-checks without actually…

### migration_live_verify_gate (1 bugs)
- 2026-05-17 1c3401 — Existing `check_migrations_applied.dart` (Gate 14) compared local migration filenames against `backups/applied_migrations.json` — a manually maintained snapshot. If the snapshot is stale or someone…

### doc_internal_consistency_table_count (1 bugs)
- 2026-05-17 d0c352 — CLAUDE.md §2 (Tech Stack quick-summary) line 130 claimed "21 tables". CLAUDE.md §7 (Database Schema header) line 380 said "46 Tables". AGENTS.md line 95 mirrored the §2 stale figure. §7 was bumped on…

### nutrition_delete_canonical_writer (1 bugs)
- 2026-05-17 d1e7e6 — `DeleteNutritionLogNotifier.deleteFoodLog` wrote the `recent_deletes` audit log + called `box.delete(logId)` directly, bypassing `NutritionWriteService.deleteLog`. Same writer/reader drift class…

### rank_promotion_local_sync (1 bugs)
- 2026-05-17 4a37e7 — After a rank promotion, the cloud `user_profile.current_rank_code` was updated but the local Hive profile served the OLD rank to all rank-reading widgets (Profile / Home / Rank chip / Phase Roadmap)…

### streak_freeze_refill_extract (1 bugs)
- 2026-05-17 5fe338 — `StreakFreezeNotifier.build()` called `_refillIfNewWeek()` which eventually called `StreakProgressService.instance.commitRefill(...)`. Riverpod write-on-read anti-pattern: every provider rebuild (auth…

### train_provider_workout_read_service_delegation (1 bugs)
- 2026-05-17 39ead9 — `train_provider._getLastPerformance` (line 43) and `exerciseHistoryProvider` (line 131) iterated `hive.workoutBox.values` inline and filtered `if (log['type'] != 'exercise_log')` — depended on the…

### paywall_single_purchase_path (1 bugs)
- 2026-05-17 40c401 — `paywall_sheet_phase_variant.dart` rendered a phase-unlock pitch bottom sheet, but its UPGRADE TO PRO CTA called `Navigator.pop()` with a deferred-checkout note — never actually invoked any purchase…

### current_streak_single_reader (1 bugs)
- 2026-05-17 41507e — Home + Rank widgets called `WorkoutRepository.currentStreak()` (live walk-back through `schedule_*` keys). Profile + Reports read cached `current_streak_weeks` from `user_progress`. The cached field…

### snapshot_writer_contract (1 bugs)
- 2026-05-17 7faa3b — Silent personalization degradation. OI-07's snapshot contract manifest surfaced 11 orphan readers — cron Edge Functions reading named fields from `user_daily_snapshots.snapshot_json` that…

### partial_unique_arbiter_safety (1 bugs)
- 2026-05-17 9d2a47 — No live symptom — preventive audit. Migration 064 (APK Test #16) fixed the 42P10 silent-data-loss class on 3 tables (workout_logs, workout_log_exercises, nutrition_logs). The audit-comprehensiveness…

### restore_completeness_symmetric (1 bugs)
- 2026-05-17 4dd7e2 — Obs 1 of 2026-05-16 (`daffac`) was a live instance of incomplete restore: writer (`WorkoutWriteService.logExercise`) stamped `workout_log_id` on every exlog row, but `_restoreExerciseLogs` did NOT…

### (unspecified) (9 bugs)
- 2026-05-16 2026-05-16-ai-proxy-placeholder-resolution — `ai_coach_interactions` table accumulated stuck rows with `model_used='pending'` and empty `ai_response`. Live audit on 2026-05-16 found 8 such rows spanning 2026-05-11 → 2026-05-15 (4 on…
- 2026-05-16 2026-05-16-dead-columns-dropped — 17 cloud columns across 7 tables were 100% NULL across all live rows (audit Agent 3 / Cluster 4 live SQL on 2026-05-16). Each had at least one of these failure modes:
- 2026-05-16 2026-05-16-doc-updates — CLAUDE.md and `docs/sot_registry.yaml` need to track the audit-2026-05-16 architectural changes so the next contributor sees the canonical patterns:
- 2026-05-16 de29b8 — Not a bug — the audit-2026-05-16 framework deliverable: 6 new gate scripts plus 6 new contract tests codifying discipline rules that until then existed only as prose. Carries a symptom line so the bug…
- 2026-05-16 2026-05-16-gate-coverage-and-dead-code — Three orthogonal issues bundled into one diagnose-doc:
- 2026-05-16 2026-05-16-logpr-bypass — The AI coach `logPR` tool (one of 24 tools registered in `_shared/tools/registry.ts`) routes user-claimed PR attempts through the legacy `WorkoutRepository.logSetWithPrRescan` method instead of the…
- 2026-05-16 2026-05-16-rank-widget-migration — CLAUDE.md §9 "Wardroom primitives" Legacy section documented `RankChip` + `RankInsignia` as "slated for removal — do not introduce new usages", but 5 active callsites remained for 3 weeks after the…
- 2026-05-16 2026-05-16-sync-coach-cross-channel-dedup — `ai_coach_interactions` accumulated paired duplicate rows for one logical user turn. Live audit on 2026-05-16 found **8 cross-channel pairs** spanning 2026-05-11 → 2026-05-15. Each pair: same…
- 2026-05-16 2026-05-16-workout-schedule-service-bypass — `WorkoutScheduleService` had 13 direct `workoutBox.put` callsites — every schedule mutation (template assignment, swap exercise, shorten day, mark completed/skipped/travel, copy week, restore…

### ai_coach_interactions_dedup (1 bugs)
- 2026-05-16 a17bc3 — Founder's `ai_coach_interactions` table shows 6 rows for the same `user_message='curd 200gms whey 1.5 scoops cashew 6'` (3 timestamps × 2 channels). Each "Analyze with AI" tap during Gemini 502 storm…

### exlog_key_sot (1 bugs)
- 2026-05-16 a16c1a — Founder on +24 APK install (May 14 2026) reported two problems observed live in the production app: 1. Train screen rendered 26+ exercise rows under May 14 when only 4 exercises had actually been…

### health_write_service (1 bugs)
- 2026-05-16 e7a516 — Two related health-domain defects rolled into one architectural fix: (1) F2-R2 — `BiometricNotifier.logSleep` wrote `sleep_log_<dateStr>` using device-local `now.year-now.month-now.day`. At IST…

### client_errors_telemetry_pipeline (1 bugs)
- 2026-05-16 9d12af — Hidden observability bug — silent for an unknown number of days. `supabase/functions/log-client-error/index.ts` enforced a per-user rate limit of 100 events/24h. Past the threshold, the function…

### ai_media_proxy_status_code_classification (1 bugs)
- 2026-05-16 913261 — Founder sent a photo via AI Coach at 13:32 IST 2026-05-15. Edge Function logs show POST 500 ai-media-proxy version 16, execution_time_ms 14587. Client surfaced "Sorry, I couldn't analyse that photo.…

### ai_media_proxy_classification (1 bugs)
- 2026-05-16 5bea3e — AI coach photo analysis still fails on first attempt after the Test #16.1 / Bug 913261 classification fix. Chat bubble correctly renders the red-bordered "PHOTO FAILED · Tap to retry" tile (the new UI…

### exercise_personal_records (1 bugs)
- 2026-05-16 cb1ab1 — Live screenshot 2026-05-16 (founder on APK +27 fresh install, signed in as upendraprasad19@gmail.com): home stats grid + PR snapshot showed cumulative SUM as "best per-set" value for non-weighted…

### prediction_card_display (1 bugs)
- 2026-05-16 2c1c0d — Profile prediction card showed "Complete onboarding to get your personalised fitness prediction" for an already-onboarded user (founder, APK +27 fresh install). Goal/weight/phase were all populated;…

### referral_restore_completeness (1 bugs)
- 2026-05-16 2026-05-16-referral-restore-completeness — Founder reported during APK Test #2 (2026-04-25) generated a referral code via Profile -> Invite Friends. Two weeks later, on a fresh reinstall (sumitt@gmail.com cross-device login flow), the Invite…

### workout_schedule_completion_cloud_projection (1 bugs)
- 2026-05-16 2026-05-16-schedule-completion-duration — `workout_schedule_completions.duration_seconds` is 100% NULL in cloud across all production users (11/11 rows; verified by Agent 3 live SQL in `docs/audit/2026-05-16/findings-agent-3.md` § F3-1.3).…

### sleep_logs (1 bugs)
- 2026-05-16 5beed5 — AI coach reported "your sleep data isn't logged" despite the user having reported sleep through the same coach minutes earlier. The chat turn succeeded (assistant bubble responded with confirmation),…

### ErrorTelemetry + sync success/failure signal + cron auth (1 bugs)
- 2026-05-16 2026-05-16-telemetry-hardening — Telemetry framework had five compounding observability gaps surfaced by audit Agent 7 — no success-path emission on 5 low-usage sync methods (cannot distinguish "feature unused" from "silently…

### terms_acceptance_audit_trail (1 bugs)
- 2026-05-16 2026-05-16-terms-accepted-at-dpdp — Cloud `users.terms_accepted_at` and `users.terms_version` are 100% NULL across every production row (live SQL: `null_count = 4 / total = 4` for both columns at audit time). DPDP §22 requires the…

### workout_log_id_session_scoping (1 bugs)
- 2026-05-16 daffac — Three symptoms from the same fresh-install session — same writer/reader drift class manifesting in different readers: (1) Tapping "View Workout Card" on home calendar day detail did nothing — silent…

### edge_function_cold_start_resilience (3 bugs)
- 2026-05-15 c01d57 — Edge Function logs at 09:33 IST show 3× ai-proxy 502 BAD_GATEWAY with execution_times 6.1s / 6.6s / 7.2s in rapid succession. The Test #15.3 retry schedule `[1500, 4000]` ms (~5.5 s total wait) was…
- 2026-05-12 7c4e1a — User tapped "Analyse & Log" on Nutrition → Log Food → AI tab. Got toast "The AI is temporarily unavailable. Please try again in a minute." Same error class also fires from AI coach `logMealByText`…
- 2026-05-12 0a7b9f — Two surfaces affected. (G) Food text analysis returned "The AI is temporarily unavailable. Please try again in a minute." after the user typed a meal description and tapped Analyse & Log. (H)…

### debugging_methodology (1 bugs)
- 2026-05-15 4e9515 — Founder asked for a "debugging" skill earlier in the session; both `superpowers:debugging` and `debugging` returned `Unknown skill`. The project's `.claude/skills/` directory did not exist. Debugging…

### cloud_upsert_natural_key_contract (2 bugs)
- 2026-05-15 25e91d — Source-grep contract tests (test/contracts/sync_onconflict_natural_key_test.dart and siblings) pin the client `onConflict:` string but cannot prove the live Postgres schema has a UNIQUE / EXCLUDE…
- 2026-05-12 3f8a91 — Production telemetry `client_errors` shows 31 × `upsert_exercise_log` + 16 × `upsert_nutrition_log` PostgrestException 23505 over 24h. The parent summary row (workout_log_exercises / nutrition_logs)…

### cron_auth (1 bugs)
- 2026-05-15 5a65bd — pr-detection Edge Function cron returns 401 every 15 minutes; same shape affects 6 other C-4-gated proactive trigger functions (re-engagement, plateau-alert, protein-gap-alert, workout-window-closing,…

### custom_exercises_mutations (1 bugs)
- 2026-05-15 a5d29c — Founder searched "Single Leg Front" in the active-workout SWAP EXERCISE picker on a fresh install. The picker returned "No matching exercises found" even though his custom exercise `Single Leg Front…

### sync_natural_key_guard (1 bugs)
- 2026-05-15 9f4ab2 — Hypothetical (defence-in-depth) — no production occurrence yet. If the natural-key columns on `workout_logs`, `workout_log_exercises`, `workout_log_sets`, or `nutrition_logs` ever become NULLable…

### ai_media_proxy_error_handling (1 bugs)
- 2026-05-12 d8e5b3 — Photo upload to AI coach → "Sorry, I couldn't analyse that photo. Please try again." Zero client_errors rows for ai-media-proxy in last 12h — generic fallback fires silently without telemetry.

### hive_user_session_static_state (1 bugs)
- 2026-05-12 c7d4f6 — After signing out as Upendra and signing up as new account sumit1@gmail.com, the Profile screen showed Upendra's full profile data (full_name=Upendra, dob=1988-06-30, height=174cm, weight=78.3kg,…

### cross_account_riverpod_cache_race (1 bugs)
- 2026-05-12 7bd154 — After signing out as Upendra and signing up as sumit1@gmail.com on the same session, Edit Profile rendered Upendra's profile (174 cm / 77.8 kg / DOB 1988-06-30) until the app was force-killed and…

### user_scoped_riverpod_providers (1 bugs)
- 2026-05-12 c4055a — After signOut+signUp on the same app session, every user-scoped Riverpod provider continues to serve the previous user's cached state even though Hive boxes have correctly switched to the new user's…

### day_rollover_provider_invalidation (1 bugs)
- 2026-05-12 b7e3f1 — On Sunday morning cold start, home today-card showed Saturday's completed workout ("BACK DAY A · DONE · Lat Pulldown 40kg") even though the IST calendar had advanced to Sunday May 10.

### exercise_log_per_set (1 bugs)
- 2026-05-12 e1f8a2 — When the user opens the Edit Workout Log sheet for a previously-completed exercise that was logged via the modern WorkoutWriteService (post-Test-#6), the per-set inputs show the legacy aggregate…

### last_performance_per_set_semantics (1 bugs)
- 2026-05-12 a8f1c2 — "Active workout screen pre-fills REPS input with 85 on every set of Hanging Leg Raise (4 prescribed sets × 14 reps, bodyweight). 85 is the sum of the user's previous 7-set session…

### muster_to_profile_bridge (1 bugs)
- 2026-05-12 8c4ee3 — After completing the post-onboarding muster flow (MusterScreen) and entering shoulders as a known injury and legs as the body-part priority, Edit Profile continued to show injuries=['none'] and…

### workout_log_exercises_input_validation (1 bugs)
- 2026-05-12 e6a2d4 — "LAST: 50KG · 135 REPS" rendered above Leg Extension in active workout screen — 135 reps per set is unrealistic. Cloud `workout_log_exercises` had 3 corrupt rows from May 7 with set_number=15 +…

### schedule_exercise_field_types (1 bugs)
- 2026-05-12 a2f9e1 — Home renders "Something went wrong" ErrorState after the user schedules a custom template for today. Crash repeats on every cold-start. Telemetry shows 5x widget_error_fallback with message "type…

### template_exercises_cloud_tail_rows (1 bugs)
- 2026-05-12 b3c8d2 — Founder's templates "Back Day A", "Leg Day A", "Push Day" each showed 14-15 exercise rows with only 4-5 distinct names ("triplicated"). Editing the template + removing duplicates + saving brought the…

### exercise_set_field_name_contract (1 bugs)
- 2026-05-12 6e1b45 — On Train screen day card (Monday 2026-05-11), Handstand Hold renders as "3 sets · 0s" and Jump Rope as "2 sets · 0s" instead of showing per-set duration chips for the durations the user logged (10s ×…

### today_workout_snapshot_reads_logged (1 bugs)
- 2026-05-12 a13a01 — User asks AI coach "how was my workout today?" after partially completing a Pull-day session (logged 4 of 8 prescribed exercises — Lat Pulldown, Dumbbell Row, Hanging Leg Raise, Concentration Curl).…

### anon_jwt_leak (1 bugs)
- 2026-05-11 7ad0c3 — .claude/settings.local.json was tracked in git AND contained the Supabase anon JWT in committed permission entries; the same JWT also appears in git history (lib/core/constants/app_constants.dart…

### chat_workout_draft_write_service (1 bugs)
- 2026-05-11 7ad0c8 — `submitWorkoutDraft` (the chat-confirmation handler for AI-coach-detected workouts) wrote `exlog_<ts>_<hash>` and `wlog_<ts>` rows directly to Hive with the *legacy* field shape (`sets_completed`, no…

### cross_account_guard_on_open (1 bugs)
- 2026-05-11 7ad0c6 — splash_screen.dart cross-account Hive leak guard was a no-op on every cold start. `HiveService.instance.userBox` is a `GuardedBox` that throws `HiveUserSession not opened` before any `openForUser` has…

### delete_account_rate_limit (1 bugs)
- 2026-05-11 7ad009 — delete-account Edge Function had no rate limit on the confirmation-token check. A malicious actor knowing a target's 8-char user_id prefix could repeatedly POST attempts; each fires Razorpay + DB…

### deterministic_uuid_v5_keys (1 bugs)
- 2026-05-11 7ad0d4 — 3 deterministic-key helpers (`_nlogKeyForRestore` in sync_service, `exlogKey` in workout_write_service, `_stableItemsHash` in nutrition_write_service) computed their 8-char tag via…

### edge_function_ist_sweep (1 bugs)
- 2026-05-11 7ad0d3 — 7 Edge Function date-key sites used UTC midnight (`new Date().toISOString().split("T")[0]`, `setUTCHours(0,0,0,0)`, etc.) for rate-limit windows, snapshot keys, and look-back cutoffs. For Indian users…

### edge_input_validation (1 bugs)
- 2026-05-11 7ad0d6 — 3 Edge Function input-validation gaps. (H-21) ai-proxy `scan_meal` + `cart_auditor` accepted `body.image` (base64) with NO size validation — a 50MB+ blob would forward to Gemini unbounded, burning…

### full_name_email_prefix (1 bugs)
- 2026-05-11 7ad0ce — Email-signup users (Supabase Auth's email flow carries no metadata) had `public.users.full_name` permanently seeded with `email.split('@').first`. The `_ensureLocalUser` upsert ran with…

### storage_policy_dedupe (1 bugs)
- 2026-05-11 7ad038 — H-38 disposition — Path 1 (dedupe SELECT policies). Supabase advisor flagged `public_bucket_allows_listing` on storage buckets `avatars` + `banners`. Inspection found 3 duplicate SELECT policies per…

### error_telemetry_funnel_completion (1 bugs)
- 2026-05-11 7ad0e0 — Phase 8 cleanup deferred the remaining 21 grandfathered `catch (e) { debugPrint(...) }` patterns in `lib/core/services/` + `lib/shared/repositories/` to a follow-up batch. Per audit doc §4 H-42…

### nutrition_write_service_expansion (1 bugs)
- 2026-05-11 7ad0c9 — 4 nutrition mutations bypassed `NutritionWriteService` (the documented sole writer per CLAUDE.md §15). `SavedMealsNotifier.saveMealPreset` / `.relogSavedMeal` / `.deleteSavedMeal` +…

### payment_hardening (1 bugs)
- 2026-05-11 7ad0d5 — 3 payment-stack hardening gaps. (H-18) verify-payment's `.insert()` fallback after upsert error did not catch Postgres 23505 (unique_violation), so a concurrent webhook + verify-payment race would…

### payment_in_flight_event_based (1 bugs)
- 2026-05-11 7ad0cf — `SubscriptionService` payment grace window was a pure time-based `paymentInFlightUntil` ISO timestamp. Two pathologies — (a) a slow webhook past 10 min flips grace to false even though we're still…

### phase5_schema_completeness (1 bugs)
- 2026-05-11 7ad0d7 — 6 schema-completeness gaps. (H-13) `_restoreCustomExercises/Foods` wrote to legacy LIST keys (`custom_exercises` / `custom_foods`) while every reader scans per-key (`custom_exercise_*` /…

### phase6_contract_tests (1 bugs)
- 2026-05-11 7ad0d8 — 11 invariants documented in CLAUDE.md / audit findings / prior bug retros had no automated guardrail. Future code changes could silently remove them. Examples — delete-account skips confirmation_token…

### phase7_integration_scaffolds (1 bugs)
- 2026-05-11 7ad0d9 — 10+ critical end-to-end flows had no integration test coverage at all — Razorpay purchase (the entire payment stack), sign-up + onboarding traverse, delete-account (DPDP §17 irreversible),…

### phase8_cleanup (1 bugs)
- 2026-05-11 7ad0da — Phase 8 cleanup catch-all. (Hive sequential) `HiveService.init` opened 9 shared boxes serially via a for-loop — sequential file I/O wasted 150-300 ms of cold-start time. (community_review_sheet `as…

### profile_signout_auth_notifier (1 bugs)
- 2026-05-11 7ad0ca — `ProfileScreen._performSignOut` called `supabase.auth.signOut()` + `UserRepository.clearAllData()` directly, bypassing `AuthNotifier.signOut()` and — critically — skipping…

### promote_community_item_admin_gate (1 bugs)
- 2026-05-11 7ad0c5 — promote-community-item ran as service-role with verify_jwt only at gateway level - any authenticated user could call POST functions v1 promote-community-item and trigger global writes to food_database…

### reactive_subscription_three_sites (1 bugs)
- 2026-05-11 7ad0cd — 3 surfaces (`userStatsProvider`, `train_screen` WeekSelector.onSelect, `swap_sheet`) snapshot `SubscriptionService.instance.isPro()` at build/init time and never reactively rebuild when the user…

### rls_policy_cleanup (1 bugs)
- 2026-05-11 7ad054 — rank_ladder had RLS enabled with zero policies (deny-all client reads); promo_code_uses INSERT policy was scoped to roles=public with WITH CHECK=true allowing any authenticated user to insert audit…

### security_definer_hardening (1 bugs)
- 2026-05-11 7ad035 — 5 SECURITY DEFINER functions had no search_path config (injection risk); coach_tool_invocations_v view ran as creator bypassing RLS; 9 SECURITY DEFINER functions granted EXECUTE to anon and…

### silent_debugprint_catch (1 bugs)
- 2026-05-11 7ad0d0 — `catch (e) { debugPrint(...); }` patterns across `lib/core/services/` + `lib/shared/repositories/` logged to the device console but emitted NO Crashlytics signal + NO `client_errors` row. Production…

### splash_post_auth_session_gate (1 bugs)
- 2026-05-11 7ad0c7 — 4 splash-time post-auth fire-and-forget startup paths (`RankService.evaluateAndPromote`, `SubscriptionService.refreshFromSupabase`, `ScheduledWorkoutsResyncMigrator.runIfNeeded`, splash…

### streak_cqrs_split (1 bugs)
- 2026-05-11 7ad0d1 — `WorkoutRepository.calculateCurrentStreak()` was documented as a "read" but had side effects — consumed streak freezes for missed days and persisted the new state to Hive + cloud on every invocation.…

### streak_progress_service (1 bugs)
- 2026-05-11 7ad0d2 — `streak_freezes_available` + `streak_freeze_used_dates` + `streak_freezes_last_refill` had TWO independent writers — `StreakFreezeNotifier._refillIfNewWeek` (weekly +1) and…

### subscriptions_rls (1 bugs)
- 2026-05-11 7ad0c1 — subscriptions table had open INSERT/UPDATE/DELETE RLS policies plus nullable Razorpay columns; any authenticated user could self-grant indefinite PRO with no payment trail.

### templates_sync_fanout (1 bugs)
- 2026-05-11 7ad0cb — `TemplatesNotifier.saveTemplate` + `.updateTemplate` wrote `tmpl_*` rows to Hive but fired NO cloud sync — `workout_templates`/`template_exercises` rows only reached cloud via weekly full sync (up to…

### rls_with_check_completeness (1 bugs)
- 2026-05-11 7ad029 — 35 RLS policies on UPDATE / ALL had USING expressions but no WITH CHECK; meaning a user could UPDATE their own row's user_id to another user's UUID, transferring or poisoning cross-user data.

### write_service_bypass_detector (1 bugs)
- 2026-05-11 7ad0cc — No source-grep guardrail enforced the WriteService SoT contract for `exlog_*`, `wlog_*`, `nlog_*`, `saved_meal_*` Hive prefixes. C-8 + C-12 closed half a dozen bypass sites manually; without a…

### log_client_error_payload (1 bugs)
- 2026-05-10 task22 — No diagnose-docs existed for ~35 fix/feat commits since Test #11 (merge 0babf83), meaning /build-apk Gate 10 would trip on all historical commits lacking diagnose coverage.

### streak_freezes (3 bugs)
- 2026-05-10 d4e5f6 — Cloud user_progress default for streak_freezes_available was 2 — neither matched free baseline (1) nor PRO max (3). Fresh accounts got an inconsistent middle-ground value before the client's first…
- 2026-05-10 b3d8f9 — PRO user who burns all 3 streak freezes in week 1 gets back to 3 the following Monday — full reset, no incentive to save freezes.
- 2026-05-10 c5d2a8 — Streak pill showed only ❄ <available> (single digit), so a PRO user with 1 freeze remaining had no signal that capacity was 3 — and a user at 0 freezes had the snowflake section invisible entirely.

### ai_coach_chat_history (1 bugs)
- 2026-05-10 e8a3b1 — Opening the AI coach screen lands the scroll position at 0 (oldest message at top). User has to manually scroll down through the entire transcript just to see the latest exchange and reach the input…

### cross_account_isolation (1 bugs)
- 2026-05-10 f4d6c2 — 3 cross-account isolation tests in test/auth/cross_account_isolation_test.dart were stubbed with `skip:` referencing HiveService.lastAuthenticatedUserIdKey — a constant from an abandoned Plan A…

### workout_template_sync (1 bugs)
- 2026-05-10 a8b2c7 — _syncWorkoutTemplates used a DELETE-then-INSERT pattern for child template_exercises rows. If the DELETE succeeded but a subsequent INSERT errored mid-loop (network blip, FK constraint, payload…

### workout_templates (1 bugs)
- 2026-05-08 5a36ad — Sync stack had systemic failures — workout templates were not deduped (UNIQUE constraint added), streak pill showed cached value instead of live calculateCurrentStreak(), completed_at was overwritten…

### error_telemetry_helper (1 bugs)
- 2026-05-08 b0fd76 — Telemetry payload had no contract (any shape was accepted, breaking structured log queries); restore had a race condition where stale tmpl_* keys from earlier broken restores accumulated and caused…

### subscription_payment_grace_window (2 bugs)
- 2026-05-06 5456c4 — Multiple issues in one batch — PRO upgrade did not unlock after payment, receipt showed wrong set counts, today card had duplicate text, weight chart decimals were static, swap kept stale…
- 2026-05-06 d9b546 — PRO unlock still failed systemically across multiple code paths; logging_type repair migrator was not library-aware, repairing to wrong types for exercises present in the library.

### hive_field_name_exlog (2 bugs)
- 2026-05-06 519075 — Cloud-side audit surfaced multiple failures — logging_type repair migrator needed systematic rebuild, razorpay 409 detection was dead code (FunctionException class), sync had IST gaps, train screen…
- 2026-05-04 270ea3 — Workout restore wrote Hive keys using cloud UUIDs instead of deterministic WriteService keys, causing exercise logs to be unreadable by receipt and calendar readers.

### hive_field_name_nlog (6 bugs)
- 2026-05-06 fe579a — ai_coach_repository called istDateStr(istNow()) causing a double IST shift — plan summaries showed wrong date and eta_next_promotion dates were off by one day.
- 2026-05-04 39f8ce — AI breakdown card silently disappeared after save with no user feedback, making users believe the meal was not logged.
- 2026-05-04 0f8d54 — Usage counters incremented on meal save rather than on API call, so users who analysed without saving saw incorrect 'remaining' counts diverging from server rate-limit trigger.
- 2026-05-04 acdcfb — FoodLogNotifier wrote flat-totals nlog_* rows without items[] array, so cloud nutrition_log_items got 0 rows for those logs and AI coach/weekly-report saw no meal items.
- 2026-05-04 26b360 — AI snapshot and usage counter resets used UTC or device-local dates instead of IST, causing midnight-crossing mismatches for Indian users.
- 2026-05-04 933330 — Post-account-deletion null user_id in community rows caused promote-community-item to crash; three additional IST date escape sites wrote UTC dates to Hive.

### user_scoped_hive_keys (2 bugs)
- 2026-05-05 8a2e9b — 25 additional user-scoped configBox keys remained after the Test #10.1 hotfix (6 keys), and OneSignal player_id was never synced to cloud, causing push unsub to silently no-op on account deletion.
- 2026-05-04 617ea1 — User-scoped data (isPro flag, prediction text, localActivationAt) persisted in shared configBox and leaked to the next account signed in on the same device.

### coaching_notes (1 bugs)
- 2026-05-04 d9d77c — Captain voice prompts were duplicated across proactive trigger Edge Functions instead of sharing a single source, risking voice drift between triggers.

### cross_cutting (4 bugs)
- 2026-05-04 40a426 — V4 plan generator had 38 cascade fallback failures (universalPool picks) because the exercise library pool was too shallow for advanced slot targets.
- 2026-05-04 f631f0 — Profile screen called Supabase and Edge Functions directly from widget code, bypassing the repository pattern and making the calls untestable and hard to audit.
- 2026-05-04 4c49d6 — Logo rendered at full resolution on splash without cacheWidth hint, causing unnecessarily large decode on low-memory devices.
- 2026-05-04 2c645c — Welcome screen displayed misleading 'no streaks' copy and app.dart showed a 'restart' error message that does not resolve any real issue.

### water_target (1 bugs)
- 2026-05-04 11bcfb — Four UI sites hardcoded 3000 ml for water target instead of computing it from user weight and activity, causing incorrect 100% at 3L for light users.

## By feature directory

## Chronological (latest first)

| Date | Bug ID | Symptom | Concept | Test path |
|---|---|---|---|---|
| 2026-08-25 | f2a9c7 | Any worktree that had merely RUN the full test suite could never be retired. `retire_worktree.dart` reported "1 non-regenerable ignored file(s)" and KEPT the worktree forever, because… | An allow-list whose input set was enumerated from one source (things new-worktree.sh copies in, and Flutter build products) while a SECOND producer of ignored files — the test suite itself — wrote into the same tree and was never enumerated. The tool's protective leg is correct and stays correct; what was wrong is that it treated a regenerable artifact as precious, so the failure direction was inert-not-destructive. That is the right direction to fail, which is exactly why it survived: nothing broke loudly, worktrees just quietly never retired. | test/scripts/retire_worktree_lib_test.dart |
| 2026-08-24 | b2d8e4 | The operator runbook docs/operations/FOUNDER_LAPTOP_HANDOFF.md instructed the founder to redeploy ai-proxy with verify_jwt=true. Live config is false, and deliberately so. Running the documented line… | Documentation-as-executable-input drift. A runbook command is not prose — it is an input to a prod control plane, and it had drifted from the live state it addresses with nothing pinning the two together. The failure would also have been SILENT: deploy_via_api.js tolerates HTTP 401 for ai-proxy in its post-deploy smoke step, so the deploy prints "Smoke OK" over a dead function. This is the bad-news-vs-no-news class — a 401 meant "healthy module rejected you" before the change and would have meant "gateway killed everything" after it, with no way to tell them apart from the smoke output alone. | test/contracts/runbook_deploy_verify_jwt_test.dart |
| 2026-08-21 | b6e1f4 | FOB-3 of OI-60. The AI coach asserts a falsehood to every holder, every week. The snapshot sends `progress.current_week` and `current_plan_summary.week` derived from `getCurrentWeekNumber()`, which… | hold_snapshot_block | test/contracts/hold_snapshot_block_behavioral_test.dart |
| 2026-08-20 | c7a3b9 | FOB-5 of OI-60, two defects in one function, one LIVE on the founder dashboard. (1) `founder_metrics_engagement().ai_messages_today` counted EVERY row of `ai_coach_interactions` with no channel… | founder_metrics_engagement | test/contracts/hold_week_mechanic_behavioral_test.dart |
| 2026-08-20 | a7e4c2 | Hermes P1-D + P1-E. FOB-5 existed because five phase_1_day_29_* events had ZERO consumers, making the free-tier hold mechanic unobservable. It replaced them with hold_week_started plus three SQL… | hold_week_telemetry | test/contracts/admin_hold_telemetry_renders_behavioral_test.dart |
| 2026-08-20 | f4c8e1 | FOB-1 of OI-60. Six in-repo surfaces printed the clamped week 4 to a free-tier holder, at every hold ordinal, forever. `getCurrentWeekNumber()` (workout_schedule_read_service.dart:1096) ends in… | hold_week_identity | test/contracts/hold_week_identity_behavioral_test.dart |
| 2026-08-20 | d5b8f3 | Hermes P1-A. FOB-1 (f4c8e1) fixed six surfaces that reached the clamped week through getCurrentWeekNumber(), and declared the class closed. It was not: holdWeek() ALSO persists the projected number… | hold_week_identity | test/contracts/hold_week_identity_behavioral_test.dart |
| 2026-08-20 | b2e9f4 | `scripts/pre-push.sh` blocked a push whose commit was fully green in CI's own terms. The full-suite gate ran a bare `flutter test` while CI runs `flutter test test/ --exclude-tags golden` under `TZ:… | pre_push_ci_parity | test/scripts/pre_push_matches_ci_invocation_test.dart |
| 2026-08-17 | c8b3e6 | The git-safety PreToolUse hook — the only mechanical guard forcing every commit and push through scripts/safe_commit.sh / safe_push.sh, and the only block on a `--no-verify` bypass — could be turned… | guard_accepts_mention_instead_of_invocation | test/contracts/git_safety_lib_test.dart — five new cases in the "MENTION IS NOT AN INVOCATION" block (mention in a commit message, in a preceding echo, in a trailing shell comment, a prefix on a NON-git statement, and the mirror asserting env(1)/stacked/post-cd prefixes still work). The pre-existing case "finds it on any statement, not just the first" had PINNED the broken behaviour and was rewritten to require the prefix to lead the git statement itself. |
| 2026-08-17 | d3f1a7 | Two symptoms with one shape, both surfaced by the founder asking why the pipeline is slow and why the OI board number mismatch survived it. (1) SPEED: every commit paid ~182 s of discipline gates, of… | hook_coverage_and_dart_invocation_cost | test/scripts/oi_numbering_lib_test.dart (20 tests: pure predicate + e2e against real throwaway git repos) and test/scripts/dart_bin_resolver_test.dart (9 tests, including the MIRROR test that fails if any hook reverts to a bare `dart run` or drops the `. _dart_bin.sh` source line). Plus 30 new assertions in test/contracts/git_safety_lib_test.dart for the env-prefix bypass found en route. |
| 2026-08-16 | c8f4a2 | `main` is RED. The CI job `Supabase Integration Tests` fails on its `Run Edge Function tests` step, on a SINGLE assertion: `test/edge_functions/redeem_referral_test.dart:46`, RR-1 "Missing auth… | edge_function_gateway_vs_function_error_contract | test/edge_functions/redeem_referral_test.dart |
| 2026-08-15 | d3b8f1 | `SupabaseTestHelper.cleanup()` issues `DELETE ... eq('user_id', id)` across 12 tables of the PRODUCTION project `dedsavbjuwgarrhphgnl`, and CI runs it on every push to `main`. On `main` there is NO… | delete_boundary_independent_of_credential | test/supabase/cleanup_target_guard_test.dart |
| 2026-08-15 | c8e5b3 | Two log tables grew without bound: cron.job_run_details (~29,044 rows) and public.client_errors (~10,654 rows). A migration named `log_table_retention` was applied to prod on 2026-08-15 to bound them… | cron_registry_parity | test/scripts/cron_registry_snapshot_gate_test.dart |
| 2026-08-15 | f7a2c4 | The CI job `Supabase Integration Tests` fails on every push to `main` with `AuthApiException: Invalid login credentials, statusCode: 400`. The suites sign in as `qa@icanbefitter.com`, and a live query… | qa_credentials_from_environment | test/supabase/cleanup_target_guard_test.dart |
| 2026-08-15 | b6e1d4 | Three tests in `test/supabase/sync_service_test.dart` fail against the live project: T3 with `PGRST204` (no `exercise_name` column on `workout_logs`), T4 and T5 with `22P02` (a client string id into a… | sync_domain_push_writer_to_cloud | test/supabase/sync_service_test.dart |
| 2026-08-14 | c9f4e2 | `docs/audit/open_issues.md` on `main` at `5d1c6f12` carried three unresolved git conflict markers — an open marker at :2821, a bare separator at :2892 and a close marker naming `supabase-test-http` at… | unresolved_conflict_markers_committed | test/scripts/no_conflict_markers_test.dart |
| 2026-08-13 | d7b1f8 | During the 2026-08-13 23:03-23:19 IST backend outage, the app issued auth requests that piled up rather than queueing behind one another, and every one of them sat holding a connection for 10-36… | edge_function_token_freshness | test/contracts/token_refresh_join_behavioral_test.dart |
| 2026-08-13 | a3f8d1 | TWO defects in the same six lines of ActiveWorkoutNotifier.completeWorkout's weekly-streak block. (1) FOB-2, flag-gated: getCurrentWeekNumber() clamps to [1,4] and a hold week starts at plan_start+28,… | streaks | test/contracts/hold_week_streak_identity_behavioral_test.dart |
| 2026-08-13 | b7e3d1 | Six OI ids — OI-100 through OI-105 — each named TWO entirely different issues: one set filed on `main`, one on branch `post38-auth-fixes`. Merging the two boards produced NO conflict: git saw… | oi_board_id_uniqueness | test/contracts/oi_index_test.dart |
| 2026-08-13 | 4f2a9e | The merge-commit regression-catalog walk fails with "at least one recent regression test FAILED" on tests that are green everywhere else. Observed while merging `supabase-http-fix`: 9 failures across… | git_hook_env_leak | test/scripts/regression_catalog_lib_test.dart |
| 2026-08-13 | a9c4e2 | Founder signed in as test6@gmail.com on the prod web build (app.icanbefitter.com/#/sign-in) at 2026-08-13 23:03 IST. The SIGN IN WITH EMAIL button entered its spinner state and never left it — no… | auth_signin_completion | test/contracts/sign_in_timeout_behavioral_test.dart |
| 2026-08-13 | c3f9a7 | The merge-commit regression walk (`scripts/check_regression_catalog.dart`) fails intermittently with a DIFFERENT number of failures each run — measured 11, 7, 8, then 4 across four attempts on the… | subprocess_test_timeout_under_suite_parallelism | test/contracts/git_safety_hook_integration_test.dart |
| 2026-08-12 | a7e3c1 | Every test in test/supabase/ fails at setUpAll with `AuthUnknownException(message: Received an empty response with status code 400)`. The message reads exactly like Supabase rejecting the anon key, so… | test_binding_http_mock_masks_real_network | test/scripts/supabase_test_helper_http_test.dart |
| 2026-08-12 | 3b7e1c | Every file in test/supabase/ dies in setUpAll with `AuthUnknownException(message: Received an empty response with status code 400, originalError: Instance of 'Response', statusCode: 400)` the moment… | test_binding_stubs_http_for_integration_tests | test/supabase/http_override_restored_test.dart |
| 2026-08-11 | d4f9b2 | scripts/safe_push.sh — the ONLY sanctioned push path and the file whose entire purpose is to be trusted about whether a push landed — exits 0 having verified nothing whenever `git ls-remote` cannot… | landing_verification_probe_conflation | test/scripts/safe_push_test.dart |
| 2026-08-10 | a7c3f9 | Deploying log-client-error v13 returned HTTP 201 with a healthy ACTIVE function, and then printed "Smoke FAIL — HTTP 401 (not in tolerated set [400])" followed by rollback instructions. The deploy was… | deploy_smoke_tolerated_codes | "not_applicable — see regression_test_planned for why, and what was done instead" |
| 2026-08-10 | f3c7a2 | Three tests in worktree_config_integrity_e2e_test.dart pass when the whole file runs but FAIL when run individually — `--plain-name "warn-only"` gives 1 failed, the full file gives 6 passed. Worse,… | test_isolation_intra_file | test/scripts/worktree_config_integrity_e2e_test.dart |
| 2026-08-10 | c2e9f4 | Founder (upendraprasad19@gmail.com, auth.users.id d7a67a37-0b05-4f0a- b13c-388bff3cb59b) signed in with GOOGLE to an account created by email in May, force-closed the app during a slow restore,… | onboarding_completed_at | test/contracts/local_onboarding_evidence_behavioral_test.dart |
| 2026-08-10 | d7b3e9 | `scripts/retire_worktree.dart` — the worktree-retirement command — would DELETE gitignored files that no process can recreate, while reporting the worktree as "merged + clean + pushed". Three… | worktree_retirement_allow_list | test/scripts/retire_worktree_lib_test.dart |
| 2026-08-09 | a4f7c2 | `git rev-parse --show-toplevel` returned `.../.claude/worktrees/post38-auth-fixes` from EVERY worktree in the repo and from the shared main folder. A session working in… | worktree_config_integrity | test/scripts/worktree_config_integrity_e2e_test.dart |
| 2026-08-09 | e3b9d7 | TWO notification-cron defects reported by the founder from their own phone and account, 2026-08-05 / 2026-08-07. (1) STREAK-GUARDIAN SENT A SELF-CONTRADICTING PUSH. A single notification read "Don't… | notification_cron_eligibility_and_pro_gate | test/contracts/streak_guardian_eligibility_test.dart |
| 2026-08-09 | c9e4b7 | Founder, live web 2026-08-05, account upendraprasad19@gmail.com: the Train screen's week selector showed NO past-phase history despite the account being on Phase 2 with a completed Phase 1 on record.… | past_phase_display_recovery | test/contracts/past_phase_display_recovery_behavioral_test.dart |
| 2026-08-09 | b7e4c1 | TWO defects on the auth/session path, both reported by the founder from live web on 2026-08-05, both fixed here because they share the same root class — an unbounded or ambiguous state read during a… | signout_teardown_window_and_restore_op_ceiling | test/contracts/signout_router_guard_behavioral_test.dart |
| 2026-08-07 | b2f7a4 | 138 `CLAUDE.md §N` citations in `.dart` / `.ts` / `.sql` / `.js` comments pointed at root-CLAUDE.md sections that do not exist. Root's real headings are exactly `0, 1, 2, 2a, 3, 4, 5, 6, 7`; the… | claude_md_section_citation — the pointer from a source comment to a numbered
section of root `CLAUDE.md`. The schema below is writer/reader-shaped because
this drift IS writer/reader drift; the writer just happens to be a document
rather than a Hive box. | test/scripts/claude_md_citations_letter_suffix_test.dart |
| 2026-08-07 | a7e3d1 | Two defects on the same surface, both filed as OI-76. (1) COUNT. The Profile tab's Notifications row subtitle reads "N/M enabled". It counted all 10 registry keys, including `protein_alerts` and… | notification_preferences | test/contracts/notification_pro_key_scoping_test.dart |
| 2026-08-07 | d5b8c2 | `promote-community-item` (daily cron, job `promote_community_item_daily`) opened both of its promotion paths with a call to the Postgres RPC `community_votes_summary`. That function does not exist —… | community_review_queue | test/contracts/promote_community_vote_tally_test.dart |
| 2026-08-06 | e5c2d1 | In one 1.0.0+38 session the founder signed out of user d7a67a37 (12:31:01 UTC) and signed into 9e6bde97 via Google (12:31:37). client_errors then shows, over roughly twelve seconds, 22 × "new row… | session_owner_inflight_guard | test/contracts/session_owner_inflight_guard_behavioral_test.dart |
| 2026-08-06 | e2d6b8 | A user opens Edit Profile, selects the equipment they do NOT have (e.g. cables), and saves. The selection persists and syncs to cloud. Their generated plan then prescribes exercises requiring exactly… | equipment_exclusion_filter | test/contracts/equipment_exclusion_filter_behavioral_test.dart |
| 2026-08-06 | d3a7c9 | Founder taps CONTINUE WITH GOOGLE on APK 1.0.0+38, completes Google consent, and the app sits on the sign-in screen with BOTH buttons spinning forever. Force-quitting and reopening lands on Home,… | oauth_signin_completion | test/contracts/google_oauth_session_navigation_behavioral_test.dart |
| 2026-08-06 | a4f1c8 | client_errors shows 6 × PostgrestException 22P02 "invalid input syntax for type uuid: local-welcome-1786019702890010" against sync_notifications_inbox_entry in one 1.0.0+38 session. Nobody reported it… | notifications_inbox_id_contract | test/contracts/notifications_inbox_uuid_id_behavioral_test.dart |
| 2026-08-06 | b6e4f2 | Founder hits "Could not send reset link. Try again." on the web app. The code that produced that message also calls ErrorTelemetry.logEvent('auth_forgot_password_send_failed'), so there should have… | preauth_error_telemetry | test/contracts/error_telemetry_payload_contract_test.dart |
| 2026-08-06 | c9e2b7 | Founder requests a password reset FROM THE ANDROID APP, receives the email, opens the link (which loads the web app), lands on the branded SET NEW PASSWORD screen, types a new password, and gets "Auth… | password_recovery_session | test/contracts/password_recovery_code_flow_behavioral_test.dart |
| 2026-08-05 | a7f3c2 | scripts/check_plan_review_record_exists.dart — the keystone merge-to-main gate — carried a numbered, self-documented hole in its own source. OI-58b's "one-record-one-landing" rule (a branch that lands… | plan_review_record_gate | test/scripts/plan_review_record_gate_e2e_test.dart |
| 2026-08-03 | c9f4e1 | Two independent, real (not hypothetical) gaps in the git-safety tooling that CLAUDE.md §4.3 already relies on. (1) A 2026-08-03 near-miss during the terms-accepted-fix backfill follow-up: a foreground… | git_safety_tooling | test/contracts/git_lock_concurrency_test.dart (3a — real concurrent processes, not mocked timing; 5 tests after round-2's fix round, see below), test/scripts/plan_review_record_gate_e2e_test.dart (3b — 3 new tests appended to the existing E2E suite for this gate), test/scripts/safe_merge_test.dart (3c — real bare-remote + clone E2E, including the seeded-stale-origin scenario and, after round-2, the multi-word -m passthrough), test/scripts/safe_push_test.dart (NEW in round-2's fix round — safe_push.sh had zero prior coverage; this pins only the EXTRA_ARGS fix that batch actually changed there, not the pre-existing SSH-keepalive/retry logic). |
| 2026-08-03 | b4e9c7 | `lib/features/train/screens/graduation_screen.dart` reached 909 lines against Gate 43's 800-line ceiling and passed only because it had been added to the gate's transitional allow-list — the FIRST… | phase_advance_write_path | test/contracts/pro_phase_advance_behavioral_test.dart |
| 2026-08-03 | d4e8a2 | NOT a live incident — a static-tracing risk flagged in b3f9e7's own "Known residual gap" section, investigated and closed here. Nothing under lib/features/onboarding/ called… | onboarding_completed_at | test/contracts/onboarding_hive_session_open_before_write_test.dart |
| 2026-08-03 | e7c3b9 | The terms-accepted-fix batch (b3f9e7) hit 3 pre-existing gate-tripping content bugs only when its commit finally reached the full gate loop for the first time (earlier attempts failed before reaching… | repo_gate_content_hygiene | test/scripts/claude_md_citations_letter_suffix_test.dart |
| 2026-08-03 | d1f6b3 | A cloud→Hive `progress` restore silently LOWERS `current_phase` (and two other lifetime counters) on a device that advanced locally and has not yet pushed. No guard, no telemetry, no trace: the user… | phase_progress_current_phase (cloud→Hive restore merge half) | test/contracts/progress_restore_monotonic_behavioral_test.dart |
| 2026-08-03 | a3f6d9 | Founder (upendraprasad19@gmail.com, auth.users.id d7a67a37-0b05-4f0a- b13c-388bff3cb59b) reported: "I was trying to access the app, but from restoring it is going to onboarding page." Confirmed via… | onboarding_completed_at | test/contracts/restoring_screen_local_onboarded_flag_stamp_test.dart |
| 2026-08-03 | e7c2a4 | Founder screenshot of app.icanbefitter.com/#/onboarding (the pre-auth welcome/marketing screen) showed the "BEGIN ENLISTMENT →" button overlapping with "03 · Coach that holds you to your own… | welcome_screen_hero_layout | test/widgets/onboarding/welcome_screen_short_viewport_test.dart |
| 2026-08-02 | a9c4e1 | A Riverpod provider's build method invalidates itself. `SubscriptionInfoNotifier.build()` — the data source behind the PRO pill — calls `isPro()`, which on an expired or cross-account row calls… | subscription_state (isPro/gate CQRS split) | test/contracts/subscription_cqrs_behavioral_test.dart |
| 2026-08-02 | f2b8a1 | Google sign-in was never live in prod despite functionality-flow.md asserting "Email + Google OAuth work normally" — no Google OAuth client existed in Google Cloud Console (google-services.json… | auth_google_oauth_redirect | test/contracts/google_oauth_redirect_flow_test.dart |
| 2026-08-02 | d4e7c2 | A cloud-restored workout renders wrong on two surfaces. The receipt shows 0 duration for a timed/cardio exercise that has a real total, and the Edit Workout Log sheet shows a BLANK sets box and a… | workout_receipt_rendering + workout_log_edit_surface (exlog aggregate read) | test/contracts/exlog_aggregate_read_behavioral_test.dart |
| 2026-08-02 | b3f9e7 | Founder spotted `users.terms_accepted_at` / `terms_version` NULL for every row in the live Supabase dashboard, including a row created the same day (2026-08-02 13:11:55, hours before this… | terms_acceptance | test/contracts/terms_acceptance_behavioral_test.dart |
| 2026-08-01 | c8f1d3 | A user requests a password reset from the web app, gets the email, clicks the link, lands on the "SET NEW PASSWORD" screen (Wardroom-branded, "RECRUIT REGISTRY" / "SET NEW PASSWORD", two password… | auth_password_reset_post_success_navigation | test/contracts/password_reset_redirect_flow_test.dart |
| 2026-08-01 | c8f3d1 | Every path that advances a user to the next training phase computed the new phase number BEFORE a real, slow plan generation and wrote it after. A concurrent advancer landing inside that window was… | phase_progress_current_phase | test/contracts/pro_phase_advance_behavioral_test.dart |
| 2026-08-01 | d3f7b2 | Every fan-out read in the cron Edge Function fleet silently stopped at 1000 rows. PostgREST caps an un-ranged response at db-max-rows and returns HTTP 200 with error===null, so a truncated candidate… | unbounded_postgrest_reads_in_cron | supabase/functions/_shared/paged_fetch_test.ts |
| 2026-07-31 | a4e1c9 | OI-48 (audit finding, corrected twice — 2026-07-27 re-scope, 2026-07-29 board correction — down to a single real remaining instance): the `re-engagement` cron-dispatched Edge Function's Path B… | reengagement_silent_candidate_detection | supabase/functions/re-engagement/index_test.ts |
| 2026-07-30 | f4a7c2 | OI-25 (2026-05-17, founder's own product note in migration 070's header: "i intend to store coach uploaded media. We ask user does he want to store the pic for future reference and on consent we save… | coach_media_consent | test/contracts/coach_media_consent_test.dart, test/contracts/coach_media_repository_test.dart, test/widgets/chat_bubble_media_consent_test.dart, test/router/saved_coach_photos_route_test.dart, test/contracts/ai_media_proxy_ssrf_allowlist_test.dart (extended), test/widgets/saved_coach_photos_screen_test.dart (NEW, B-pass finding 2) |
| 2026-07-30 | e6b9c4 | OI-45 finding 2's cross-device half, explicitly scoped OUT of Unit 3a (progress-map-consolidation, diagnose d5c8a3, 2026-07-30): Unit 3a closed the SAME-DEVICE stale-snapshot lost-update on… | cross_device_progress_optimistic_lock | test/contracts/restore_user_snapshot_freezes_projection_parity_test.dart (NEW, Hermes C11, 2 tests) — pins restore-user-snapshot/index.ts's freezes projection column list against SyncService._restoreFreezes's own select, since nothing did before (the H-1 shape contract was comment-only on both sides). test/sql/cross_device_progress_optimistic_lock_verify.sql — grew from 8 to 14 (round-1) to 19 (Hermes: Case 15 proves FOR UPDATE takes a real pg_locks-visible RowShareLock; Cases 16-19 regression-test the NULL-guard/GREATEST/last-refill- COALESCE fixes), all green, re-run live 2026-07-30. test/contracts/cross_device_progress_optimistic_lock_wiring_test.dart (grew 37 (Hermes L37 corrected this doc's earlier miscount of 38, confirmed by me via `flutter test`) -> 45 (B-pass round-2's 6 findings, see that section, added/ renamed assertions) -> 46 (round-3 Finding 1 added the mergeRpcParamsPreferringNonNull wiring check, see Round-3 section) — 46 tests, all green, re-verified 2026-07-30: source-structure tests pinning the RPC-wiring shape, the bounded single-retry contract for all THREE now-protected sync methods (syncFreezes, _syncUserProgress, pushOnboardingProgressSnapshot), the shared _stampProgressVersion helper, the round-1 P0 grant-fix regex, the round-1 P2 COALESCE-default regex, and — via a comment-stripped source-grep on the migration file itself — that the ::date cast fix + the ON CONFLICT DO NOTHING guard cannot be silently reverted). test/sync/merge_rpc_params_preferring_non_null_test.dart (NEW, round-3 Finding 1, 6 tests) — genuine BEHAVIORAL (not source-grep) coverage for SyncService.mergeRpcParamsPreferringNonNull, including the exact onboarding detected_experience_level-drop regression scenario Finding 1 surfaced. test/sql/cross_device_progress_optimistic_lock_verify.sql (NEW, extended to 14 cases by round-1-review fixes — live-Postgres behavioral verification in a rollback transaction, mirroring test/sql/onconflict_live_arbiter.sql's established harness; run via `dart run scripts/check_onconflict_live_arbiter.dart --sql test/sql/cross_device_progress_optimistic_lock_verify.sql`). Cases 9-13 apply the FIXED grant block (REVOKE FROM PUBLIC, anon, authenticated) within the same rolled-back transaction and assert has_function_privilege for anon/authenticated/ service_role on update_user_progress_snapshot, PLUS a symmetry re-check on update_streak_progress — this is the exact pre-apply grant verification round-1 review said the ::date-cast-bug method would have caught the P0 with, now actually applied to grants too. Case 14 is the P2 regression test (all-null core-4 fresh insert COALESCEs to schema defaults 1/1/0/0). All 14 cases re-run live 2026-07-30 post-fix, all 'ok'. Extended (not duplicated) test/sql/security_definer_anon_revoke.sql with 4 more UNION ALL rows for update_user_progress_snapshot's grants — this file's own convention is to run POST-apply as a final live confirmation against the real, applied function (not a substitute for the pre-apply cases 9-13 above, which already independently proved the grant fix works before the migration is ever applied for real). |
| 2026-07-30 | d5c8a3 | OI-45 named UserRepository's progress-map writers (updateProgress/saveProgress, user_repository.dart) as a HIGH lost-update race, originally citing 4 writers; a prior board-correction pass (Unit 1 of… | progress_map_writer_consolidation | test/contracts/user_repository_progress_stale_snapshot_test.dart (NEW — "OLD pattern documents the bug" / "NEW pattern proves the fix" pair, plus 3 concurrent-dispatch invariant tests carried over from the removed-mutex design). test/contracts/badge_service_synchronous_invariant_test.dart (NEW — source-grep tripwire: checkAndUnlock/checkAll must never become async). test/contracts/ health_sync_service_dedup_test.dart (NEW — source-grep contract for the _syncInFlight dedup guard's structure; kept at source-grep level, matching the sibling unit3_web_ux_gates_test.dart's own established restraint for this exact file — HealthSyncService reaches the unmocked `health` plugin platform channel, and _ensureConfigured's unawaited Health().configure() call risks an unhandled async rejection if actually invoked in this test suite). |
| 2026-07-29 | f4a19c | OI-46 (audit finding, re-verified 2026-07-29) named a `channel='in_app'` gap that does not exist as a live value. The real gaps, found during re-verification: (1) chat's free-tier 10/day cap… | ai_coach_daily_cap_enforcement | test/contracts/chat_app_daily_cap_test.dart, test/contracts/vision_analysis_daily_cap_test.dart, test/contracts/onboarding_required_fields_test.dart, test/onboarding/resume_route_resolver_test.dart |
| 2026-07-29 | d7a3f9 | CI's Audit Gates job failed on 96c6fac2 — the enforcement-infra merge commit that had already landed on main — with "Gate failed: check_closes_oi_cited.dart". The same commit's local pre-commit hook… | gate_fail_closed_discipline | test/contracts/gate_wiring_args_required_test.dart |
| 2026-07-29 | a9f2c6 | Three gates shipped in this batch exited 0 while doing nothing. An OI whose status read `BLOCKED` vanished from OPEN_INDEX.md with no error; an OI whose status line read `- **Status:** CLOSED` escaped… | gate_fail_closed_discipline | test/contracts/oi_index_test.dart |
| 2026-07-29 | c9e3b1 | OI-45 named `UsageCounterService.increment()` (usage_counter_service.dart:100-106) as CRITICAL — "cross-device race could let users bypass daily caps... Pattern: final c = read(); write(c+1) with no… | usage_counter_display_and_vision_cap_value | test/contracts/usage_counter_service_mutex_test.dart, test/contracts/usage_counter_service_race_behavioral_test.dart, test/contracts/vision_analysis_daily_cap_test.dart, test/features/ai_coach/message_limit_cache_test.dart |
| 2026-07-28 | c4e8a2 | 237 of 344 entries in docs/diagnoses/INDEX.md carried no symptom text — just a bare `>`, `>-` or `\|`. CLAUDE.md §4.1.5 makes grepping that index the mandatory first step before any root-cause… | bug_history_index | test/contracts/bug_index_frontmatter_test.dart |
| 2026-07-28 | c3f8e1 | main went RED on 10dffc90. Two PRE-EXISTING gate e2e tests failed in CI while passing locally and through both pre-commit and pre-push: the gate they spawn inherited CI's real GITHUB_EVENT_PATH, whose… | gate_test_environment_hermeticity | test/contracts/gate_e2e_env_hermetic_test.dart |
| 2026-07-28 | e1b7d4 | `main` went red twice in 25 CI runs on commits that touched no Deno code, both times with `Import 'https://esm.sh/@supabase/supabase-js@2.39.0' failed: 522` at clean-orphan-media/index.ts:2. 522 is a… | ci_remote_dependency_resilience | not_applicable |
| 2026-07-28 | d9b4e7 | Commits pushed straight to main skipped the keystone plan-review gate entirely — it exited at `rev-parse HEAD^2` before reading anything. Observed twice on account-tier auth code that landed with no… | plan_review_record_enforcement | test/scripts/version_bump_exemption_test.dart |
| 2026-07-27 | a3d7b1 | Ten enforcement scripts — two of the four git hooks setup-hooks.sh installs, both sanctioned write wrappers, the whole rule-22 diagnose-doc chain, and two hard-fail discipline gates — were all feature… | blast_radius_registry_coverage | test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart |
| 2026-07-27 | b7e4c2 | The two tests guarding the raw-`git commit` block fail whenever a conflicted merge is in progress — which is precisely when the pre-commit hook runs the full suite. Any integration merge with a… | git_safety_hook_contract | test/contracts/git_safety_hook_integration_test.dart |
| 2026-07-27 | a7f3d1 | The merge-to-main keystone gate returned PASS for changes it was built to block. A branch could lower its own tier by editing the registry in the same commit, and content written while resolving a… | plan_review_record_enforcement | test/scripts/gate_input_family_e2e_test.dart |
| 2026-07-27 | d4e8b2 | Every notification toggle in Settings was decorative. Verified live: 0 of 91 user_daily_snapshots rows carried a notification_preferences key, so every server-side check fell through to its permissive… | notification_preferences_emission | test/contracts/notification_preferences_writer_to_reader_test.dart |
| 2026-07-27 | b2e6c4 | The catastrophic-tier review gate was satisfied by an untracked file. It hashed the staged diff but checked the working tree for the review, so a docs/reviews/<hash>-review.md that was never git-added… | code_review_pass_enforcement | test/contracts/review_gate_staged_content_not_working_tree_test.dart |
| 2026-07-27 | c9f1d3 | scripts/check_code_review_pass_exists.dart — the gate that decides whether a catastrophic-tier diff has an accepted review — was itself feature tier. A change to it cleared no review gate at all: no… | blast_radius_registry_coverage | test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart |
| 2026-07-27 | e7b3c5 | Sign-out cleared Hive and Supabase but released nothing the device holds outside them. After user A signed out the handset was still OneSignal external_id = A and Crashlytics userIdentifier = A, so… | device_session_identity_binding | test/contracts/signout_unbinds_sdk_identity_test.dart |
| 2026-07-27 | f4a9c2 | User-editable text was interpolated raw into LLM prompts across the Edge Function tree. A newline in a display name, a meal description, or a conversation turn starts what reads to the model as a… | llm_prompt_input_sanitization | supabase/functions/_shared/prompt_sites_sanitized.test.ts |
| 2026-07-26 | c3f8a1 | Every cron-dispatched Edge Function that carries the isAuthorizedCronCall gate returns HTTP 401 on every tick — 17 of the 18 HTTP cron jobs. No push notification has been delivered to any user for at… | cron_auth_gate | test/contracts/cron_auth_adoption_test.dart |
| 2026-07-26 | d3f8a2 | Three defects in the §4.12 keystone gate's branch-recovery step, all of which either redden main for legitimate work or let a merge pass on the wrong review: (1) a GitHub PR merge subject ("Merge pull… | keystone_gate_branch_recovery | test/scripts/plan_review_record_lib_test.dart |
| 2026-07-26 | e4a7c1 | Two merges to main in quick succession: the second push cancels the first push's still-running workflow. The `plan-review-record` job — the ONLY place the §4.12 keystone gate executes — therefore… | ci_concurrency_cancels_keystone_gate | test/contracts/ci_workflow_concurrency_test.dart |
| 2026-07-26 | a7d2e9 | morning-alert sends Gemini-generated PRO-tier copy to users whose subscription lapsed. Live at discovery: zero users were genuinely PRO, yet six were being treated as PRO and receiving paid-tier… | subscription_state | test/contracts/pro_predicate_adoption_test.dart |
| 2026-07-25 | c8b3f2 | Two defects in the free-tier "Hold the Line" DISPLAY, both found by a LIVE walkthrough on test7 (flag flipped ON via the /dev Flags card, time-travelled to the day-29 wall, three holds taken) — the… | hold_display_read_path | test/contracts/hold_display_read_path_test.dart |
| 2026-07-23 | b7d4e2 | Password-recovery email link (https://app.icanbefitter.com/reset?code=<uuid>) lands on the SPA, briefly shows /restoring, then routes to /onboarding instead of the in-app reset-password form. The user… | auth_password_reset_pkce_detection | test/contracts/password_recovery_detector_test.dart |
| 2026-07-23 | 9f5c41 | Password-recovery email link lands on the SPA but GoRouter immediately routes to /sign-in instead of /reset. The URL hash containing `type=recovery&access_token=...` is consumed by GoRouter before… | auth_password_reset_timing | test/contracts/password_reset_redirect_flow_test.dart |
| 2026-07-22 | e9f2a4 | Forgot-password email link points to `http://127.0.0.1:3000/reset` instead of `https://app.icanbefitter.com/reset`. User never reaches the reset-password form. The Supabase Cloud Auth dashboard Site… | auth_password_reset | test/contracts/password_reset_redirect_flow_test.dart |
| 2026-07-21 | c9f4a2 | `user_progress.current_week` is a dead constant. Every writer sets the literal `1` (user_repository.dart:136, onboarding_provider.dart:473/786, graduation_screen.dart:673, pro_phase_advance.dart:107,… | program_week_projection | test/contracts/program_week_projection_behavioral_test.dart |
| 2026-07-21 | d7f3a9 | The free-tier "Hold the Line" mechanic (`redoWeek4`) was broken three ways and its extension was not durable. `redoWeek4` (workout_schedule_write_service.dart:172) (a) started the new week on a… | scheduled_workouts_mutations | test/contracts/hold_week_mechanic_behavioral_test.dart |
| 2026-07-20 | a3c8e2 | A completed workout could be written to a PAST date. `completeWorkout` dated the whole session from `state.workoutDay?.date` — the plan-day being performed — and `CurrentPlanData.todayWorkout`'s… | exercise_logs_read_path | test/contracts/session_date_and_home_start_behavioral_test.dart |
| 2026-07-20 | b7f30a | Tapping START on Home's Today's Workout card dead-ended. The handler was a bare `onStart: () => context.go('/train/active-workout')` (home_screen.dart:875) — pure navigation with no call to… | workout_completion_status | test/contracts/session_date_and_home_start_behavioral_test.dart |
| 2026-07-19 | d4e8a1 | Exercises doable with little/no equipment were HIDDEN from the tiers they belong to because their `equipment_tier` array skipped the middle tiers: Glute Bridge tagged ["bodyweight","full_gym"]… | exercise_equipment_tier | test/contracts/equipment_tier_consistency_test.dart |
| 2026-07-19 | e1a7c4 | 9 exercises E252-E260 (Wall Sit, Bodyweight Good Morning, Doorframe Curl, Towel Row, Negative Pull Up, Glute Kickback, Dumbbell Calf Raise, Split Squat, Incline Dumbbell Press) used a DIFFERENT… | exercise_library_schema | test/contracts/exercise_library_schema_contract_test.dart |
| 2026-07-19 | f4c1e8 | The always-on queryV4 injury filter (exercise_repository.dart:335-345) excludes an exercise for an injured user ONLY when the exercise's injury_contraindications list CONTAINS the user's injury token;… | exercise_injury_tags | test/contracts/injury_undertag_13b_contract_test.dart |
| 2026-07-19 | c3f9b2 | The V4 last-resort fallback pool `universalPoolV4` (attempt-5 of the cascade) had duplicate + wrong-pattern entries: horizontal_pull = ['Inverted Row','TRX Row', 'Inverted Row','Dead Bug'] (Inverted… | universal_pool_fallback | test/contracts/universal_pool_mirror_test.dart |
| 2026-07-18 | a4e2d9 | REG-1 (surfaced by the Batch-8 W2.5 regression audit). A PRO user whose phase has expired is auto-advanced to the next phase by a SILENT splash pass (`_autoGenerateNextPhaseForPro`), which is fired… | plan_phase_expiry | test/contracts/pro_phase_expiry_surface_test.dart |
| 2026-07-17 | b7a4e2 | On every GENERATED workout plan, gym users (basic_gym / full_gym) NEVER received the gym-cardio warmup moves (_gymCardio: Jump Rope / Cycling (Stationary) / Running (Treadmill)) or the gym finisher… | equipment_exclusion_filter | test/contracts/wu2_gym_cardio_gate_behavioral_test.dart |
| 2026-07-16 | b3f9a1 | Opening app.icanbefitter.com/admin on the web lands on the normal Home screen, not the founder admin dashboard (URL bar became /admin/#/home). The dashboard code, server gate, and Edge Functions are… | admin_route_reachability | test/contracts/restoring_next_destination_test.dart |
| 2026-07-14 | e9d1c7 | Selecting any of 9 exercises (E252–E260: Wall Sit, Bodyweight Good Morning, Doorframe Curl, Towel Row, Negative Pull Up, Glute Kickback, Dumbbell Calf Raise, Split Squat, Incline Dumbbell Press) from… | equipment_needed_shape | test/contracts/equipment_needed_shape_test.dart |
| 2026-07-13 | a9d3f1 | The three public.founder_metrics_*() SECURITY DEFINER functions (migration 101) were EXECUTE-able by the anon and authenticated roles. Because they are SECURITY DEFINER (they count across all users,… | admin_dashboard_metrics_snapshot | test/contracts/admin_metrics_functions_role_revoke_test.dart |
| 2026-07-12 | 9c3e7a | Two coupled coach plan-generation defects. (1) Item ② / G8: the AI-coach "regenerate my plan" and "switch goal" tools (both routed through the shared RegeneratePlanPlanner) called… | coach_plan_generation_phase_stamp | test/contracts/coach_regen_phase_stamp_behavioral_test.dart |
| 2026-07-12 | a1f6c3 | Injuries were collected everywhere (onboarding default, Edit-Profile chips, AI-coach muster) but the plan engine's contraindication filter excluded ESSENTIALLY ZERO exercises for most users — a safety… | injury_contraindication_filter | test/contracts/injury_filter_behavioral_test.dart |
| 2026-07-12 | d3f8a1 | The warmup/cooldown attached to every generated workout day is built from HARDCODED per-dayType name-lists (WarmupCooldownSelector `_dynamicWarmup` / `_cooldownStretches` / `_bodyweightCardio` /… | injury_vocabulary_contract | test/contracts/warmup_injury_filter_behavioral_test.dart |
| 2026-07-09 | c3d8a9 | Immediately after merging the deno-type-debt-cleanup work (which widened the CI `deno check` step from 3 named files to the full supabase/functions/ tree, claiming 0 errors), the CI run on main… | deno_ci_environment_version_drift | No separate Dart/Deno contract test file — the regression-detection mechanism IS the CI job itself: `.github/workflows/test.yml`'s "Deno type-check (full tree)" step (`deno check --node-modules-dir=auto supabase/functions/`), which is exactly the step that caught this. See regression_test_planned for how this is verified going forward. |
| 2026-07-08 | f8c0de | Founder-reported live (test7, 2026-07-04): tapping the AI-coach "Go PRO" at the 10/10 free daily limit did nothing. Root cause read from source: at the limit the composer shows a gold "Daily limit… | n/a — UI reachability fix (no SoT concept; no writer/reader contract change) | test/contracts/coach_go_pro_cta_reachable_test.dart |
| 2026-07-08 | a7e2c4 | 12 Edge-Function read sites destructure `.data` (or `await Promise.all([...])`) WITHOUT capturing `.error`, so a silent query failure is coerced into empty/null data → a silently-wrong effect, not an… | edge_function_unchecked_read_hardening | supabase/functions/_shared/tools/__tests__/unit_c_read_hardening_test.ts |
| 2026-07-07 | e6b1a4 | The Supabase performance advisor reports 137 `auth_rls_initplan` warnings and 5 `multiple_permissive_policies` warnings. Each flagged RLS policy calls `auth.uid()` bare, so Postgres re-evaluates it… | rls_initplan_auth_uid_wrap | test/sql/rls_initplan_ab_verify.sql (live A/B leak check — plain / EXISTS / OR-shape / consolidated shapes) + must add a source-presence contract test asserting migration 100 exists and is listed in backups/applied_migrations.json once applied. |
| 2026-07-07 | f0c2d5 | Two incidents on 2026-07-07 mixed work across concurrent Claude sessions. Multiple sessions were running in the SHARED main folder (`C:/Upendra/Claude Code/Fitness App`), which has ONE git index… | worktree_per_session_isolation | test/contracts/check_commit_from_worktree_test.dart |
| 2026-07-06 | 280c4d | A single coach `logSet` on a multi-exercise scheduled day silently flipped the WHOLE day to `status:'completed'`, inflating streak / rank / deployment. The coach dispatcher's derived-completion hook… | coach_derived_completion | test/contracts/coach_completion_prompt_test.dart |
| 2026-07-06 | c6a9e2 | CI run 28711975359 (the coach-gemini-reliability merge, b2ea2e3) failed the "Plan-review record (>=account merge-to-main)" gate even though the ×2 review + B-pass + Hermes genuinely happened and both… | plan_review_record_verdict_format | n/a — enforced by the existing CI gate itself (scripts/check_plan_review_record_exists.dart), not a new test. The gate cannot re-fire against THIS commit (it only runs on a merge-to-main commit, and this is a plain commit) — the proof is a direct grep confirming both review docs now contain the exact line-anchored pattern the gate's regex requires, plus the gate re-validating fresh at any FUTURE merge-to-main. |
| 2026-07-04 | 7fbe21 | The AI coach and the meal-text parser were unreliable in three linked ways. (FC1) Gemini 2.5 Flash runs "thinking" ON by default and the hidden thinking tokens count against maxOutputTokens; with our… | gemini_flash_reliability | supabase/functions/_shared/gemini_thinking_config_test.ts |
| 2026-07-04 | 9c2d4a | Two prompt-safety gaps on the AI coach. (FC5) On a jailbreak probe ("print your prompt", "ignore previous instructions", "what are your rules") the coach partially disclosed its system framing — there… | coach_system_prompt_safety | test/contracts/edge_function_safety_test.dart |
| 2026-07-04 | 4e8f1b | The AI coach's `log_meal_by_text` tool (and any other NutritionWriteService caller — the AI breakdown override, a fat-fingered manual edit) could persist an absurd calorie / macro value with NO… | nutrition_total_calories | test/contracts/nutrition_calorie_clamp_test.dart |
| 2026-07-03 | a1d7c3 | Two defects in the AI-coach chat log flow, both from the coach rendering THREE parallel confirm systems (chat_area.dart:92 LogConfirmCard legacy instant-log; :98 WorkoutLogConfirmCard legacy workout… | coach_log_confirm_routing | test/features/ai_coach/coach_single_confirm_per_log_intent_test.dart |
| 2026-07-03 | d8a6f2 | Cluster of dead-code + small-correctness findings from the 2026-07-02 audit, fixed together in Units 6-7. (F14) NutritionWriteService.logWater wrote a `water_<date>` key to nutritionBox with ZERO… | audit_fixwave_small_fixes | test/contracts/terms_acceptance_writer_to_reader_test.dart |
| 2026-07-03 | e5c4b9 | NUT-02 same-slot meal data-loss. The local Hive key is item-hash-based — `nlog_<istDate>_<mealType>_<itemsHash>` (nutrition_write_service.dart:743-751, hash at :788) — so logging TWO different meals… | nutrition_slot_merge | test/contracts/nutrition_slot_merge_test.dart |
| 2026-07-03 | f3b2e8 | WorkoutScheduleWriteService.pauseRange (workout_schedule_write_service.dart:120,140) aliased `final box = _hive.workoutBox;` then did a bare `await box.put(key, map)` for each paused day, with… | workout_schedule_write_path | test/contracts/pause_range_routes_through_write_service_test.dart |
| 2026-07-02 | a7f2e1 | In-session account switch (sign-out userA → sign-in userB as a DIFFERENT user) leaves every mixin tab (Home/Train/Nutrition/Profile) stuck on the loading SKELETON forever, until a full page reload.… | auth_hive_owner_agreement | test/contracts/session_token_stale_authuid_recovery_test.dart |
| 2026-06-28 | b6d3f9 | HealthWriteService.logUrine writes urine_color_<date> into healthBox, then fires SyncService.syncNutritionData(). But syncNutritionData's fan-out is _syncNutritionLogs + _syncWaterLogs +… | urine_color_logs | test/contracts/log_urine_sync_routing_test.dart |
| 2026-06-28 | c4d8a2 | Live data (test7@gmail.com): a fully-onboarded user — users.onboarding_completed = true, a complete user_profile (date_of_birth, primary_goal, fitness_experience, days_per_week, current_weight) and a… | onboarding_completed_at | test/contracts/onboarding_completed_at_durable_writer_test.dart |
| 2026-06-28 | f1a9d3 | OBS-1 (founder, live web signup): the induction "I COMMIT" screen promised "Make Sub Lieutenant rank — 104 workouts on this app" and "104 workouts is roughly six months of disciplined training". The… | rank_gate_copy_truthfulness | test/ai_coach/induction_pledge_test.dart |
| 2026-06-27 | e7c1a9 | Every Hive write across health / nutrition / workout / schedule fires unawaited(SyncService.instance.pushSnapshot()) (~50 call-sites) — each a separate `daily-snapshot` Edge Function invoke. During… | snapshot_fanout_coalescing | test/contracts/pushsnapshot_debounce_behavioral_test.dart |
| 2026-06-27 | b4f7e2 | Live telemetry (project dedsavbjuwgarrhphgnl, user e34b04a9) showed a RETURNING login made ~190 cloud ops, of which ~96 were `upsert_scheduled_workout` — one full UNCONDITIONAL re-upload of the entire… | scheduled_workouts_idempotent_upsert_skip | test/contracts/sync_scheduled_payload_hash_index_writer_to_reader_test.dart |
| 2026-06-27 | c4f8d2 | Live telemetry (project dedsavbjuwgarrhphgnl, user e34b04a9) proved the client phones the cloud far too often. A FRESH SIGNUP fired ~90 cloud ops in 27 s — syncWorkoutData() (the SoT fan-out) fired… | fire_and_forget_sync_coalescing | test/contracts/sync_coalescer_behavioral_test.dart |
| 2026-06-26 | f3c8d1 | Founder-directed AI-chat investigation (2026-06-26) — the AI Coach sends `AiSnapshotBuilder.buildAiContext()` to Gemini on EVERY chat turn (and the same snapshot, pushed to `user_daily_snapshots`, is… | ai_snapshot_building | test/contracts/ai_snapshot_builder_only_test.dart |
| 2026-06-26 | a1f9c4 | Live web E2E (test6@gmail.com, fresh signup, Unit G walk). Two stuck-screen hangs with no error and no escape, both on the critical boot/onboarding path: (1) the onboarding Plan screen's REPORT FOR… | hive_first_boot_onboarding_no_blocking_cloud_await | test/contracts/boot_onboarding_hive_first_test.dart |
| 2026-06-25 | e9d4b7 | Full-charter web E2E (2026-06-21, OBS-8b): after idle days the cloud `user_progress.current_streak_days` stayed STALE (e.g. 1 when the streak had actually decayed to 0). The day-rollover reckon… | streak_current_days_cloud_persist | test/contracts/streak_decay_reckon_permanent_ledger_test.dart |
| 2026-06-23 | e5c1a2 | Full-charter web E2E (2026-06-21) cosmetic + copy observations (Unit C of the fix arc). OBS-1: Home Today-card macro row RenderFlex right-overflow (~2.5-15px) at ~390px. OBS-5: subscription card shows… | e2e_cosmetic_copy_sweep | test/contracts/title_case_name_test.dart |
| 2026-06-23 | c8a1f4 | Full-charter web E2E (2026-06-21, OBS-11): the Home nutrition snapshot showed 2540 cal / 140 g protein (correct, the stored canonical user_profile target) while the Nutrition tab "Today's Summary"… | nutrition_target_canonical_read | test/contracts/nutrition_target_carb_dualname_test.dart |
| 2026-06-21 | b8e3f1 | Full-charter web E2E (2026-06-21, OBS-6): in-session sign-out → sign-in as a DIFFERENT user → blank Home (and a cold-boot deep-link to /coach/induction showed "Something went wrong"). Root cause:… | auth_hive_owner_agreement | test/contracts/wrap_user_scoped_box_null_owner_authenticated_test.dart |
| 2026-06-18 | f9d2e7 | Founder report: PRO had been active 7 days but the Home streak-freeze chip still showed "1/1", not "3/3"; and on deeper investigation the streak read 1 and freezes read 1 even though the last two days… | streak_freeze_denominator_grant_decay | test/contracts/streak_freeze_first_pro_grant_behavioral_test.dart |
| 2026-06-16 | a1c9f4 | On live web (test2@gmail.com), applying AVYA-TESTCODE in Profile → "Apply Referral Code" returns "Internal server error" (HTTP 500). Reproduced on a CALM backend (so not the Free-tier compute… | subscription_state | test/contracts/referral_trial_subscription_grant_test.dart |
| 2026-06-14 | d8f3a2 | Live web (test2). (obs 2b) Tapping CONNECT on the Health Sync card "got stuck on the Health Connect page" — on web there is no Health Connect / HealthKit binding, so the native permission flow… | client_web_platform_gating | test/contracts/unit3_web_ux_gates_test.dart |
| 2026-06-14 | c3f2d8 | Live web (test2) + audit. The SAVED onboarding calorie target ignored the user's body-fat: a user who typed 12% got the SAME daily_calories as a skip-user, because both the onboarding COMMIT… | onboarding_bodyfat_calc_input | test/contracts/onboarding_bodyfat_calc_test.dart |
| 2026-06-13 | a7c3f8 | Web boot console (Obs#3, live web E2E): "[main] coach_memory backfill failed: Bad state: HiveUserSession not opened — cannot wrap user-scoped box \"coachBox\". Call HiveUserSession.openForUser(userId)… | user_scoped_box_before_openForUser | test/contracts/coach_backfill_after_openforuser_test.dart |
| 2026-06-13 | c7d4f1 | Profile -> Submissions -> COMMUNITY REVIEW always shows "No items to review right now", for EVERY user, even when other users have submitted unapproved custom foods/exercises. The community-vote ->… | edge_function_cross_user_read_rls_context | test/contracts/community_review_rls_context_c7d4f1_test.dart |
| 2026-06-13 | b2e9d3 | Web boot console (Obs#2, live web E2E): "[main] Firebase/Crashlytics init failed: Null check operator used on a null value". main() ran Firebase.initializeApp() + FirebaseCrashlytics.instance.* with… | platform_guarded_native_init | test/contracts/crashlytics_web_guard_test.dart |
| 2026-06-13 | c4f1a7 | Live web E2E (Obs#9): on the DPDP "Type to confirm" erasure screen, tapping the enabled "IRREVERSIBLE — DELETE MY ACCOUNT" button surfaced "Couldn't delete account. Try again or contact support." and… | edge_function_caller_token_freshness | test/contracts/delete_account_fresh_token_test.dart |
| 2026-06-13 | b9c4f1 | Obs#7 (live web E2E, cosmetic): on the AI food-analysis result card (ai_breakdown_card._buildItemRow), item names ("Boiled Eggs", "Chicken Breast 100g") rendered VERTICALLY — one character per line.… | expanded_starved_by_fixed_siblings | test/contracts/food_card_name_single_line_test.dart |
| 2026-06-13 | e8a2c1 | Obs#5 (live web E2E, potential onboarding BLOCKER): on the ~698px web mobile- frame the stock Material TIME picker (muster Q2 wake/train time) showed its OK/Cancel action row BELOW the visible frame… | responsive_picker_host | test/contracts/responsive_picker_host_test.dart |
| 2026-06-13 | f1b6d4 | Obs#6 (live web E2E): the onboarding plan-PREVIEW card (plan_screen step 05) showed "2867 KCAL" but the SAVED + home-displayed daily_calories was 3200 — the number the user commits to differed from… | onboarding_preview_commit_calc_parity | test/contracts/plan_screen_targets_match_completeOnboarding_test.dart |
| 2026-06-13 | d2b9e6 | Live web E2E (test2@gmail.com, Unit 1). Applying a referral code ALWAYS failed — the Profile "Apply Referral Code" sheet showed "Network error. Try again in a moment." and the welcome-stash redeem at… | edge_function_cross_user_read_rls_context | test/contracts/referral_redeem_success_contract_test.dart |
| 2026-06-13 | d5e1b9 | Obs#1 (live web E2E, founder report): "when i created a new account (because i had clicked on signup) why was i shown 'loading your account'? it should say something like account creation in… | signup_aware_restore_copy | test/contracts/restoring_signup_copy_test.dart |
| 2026-06-13 | a3d7e2 | Obs#8 (live web E2E console): "[realtime] weight_logs stream error: RealtimeSubscribeException channelError" recurring (WS close 1006/1000). The PRO realtime weight_logs subscription (Telegram→app… | realtime_teardown_on_reconnect_exhaustion | test/contracts/weight_realtime_teardown_on_exhaustion_test.dart |
| 2026-06-12 | f4d1b7 | Two commit-gate tooling bugs surfaced during the f1c8e4 commit gauntlet, both in the "stable staged-diff hash" path the catastrophic review gate (check_code_review_pass_exists.dart) relies on: (#2)… | commit_gate_hash_stability | test/contracts/review_gate_hash_raw_bytes_test.dart |
| 2026-06-12 | d5b2f8 | The SECOND never-run delete-account bug, revealed the instant the e8a1c3 auth fix let the erasure path execute for the first time. With a VALID token, the EF now passed auth, ran the full erasure, and… | postgrest_builder_has_no_catch_method | test/contracts/delete_account_auth_pattern_test.dart |
| 2026-06-12 | e8a1c3 | Live web E2E (test1@gmail.com, Obs#10). The delete-account Edge Function (DPDP §17 erasure) rejected EVERY valid user token with 401 "unauthenticated" — so no user could delete their account via the… | edge_function_user_token_validation_pattern | test/contracts/delete_account_auth_pattern_test.dart |
| 2026-06-12 | a2c8e6 | Quarterly audit (L21 lens) finding F1, founder-authorized fix. The delete-account Edge Function (DPDP §17 erasure) cancels the user's Razorpay subscription BEFORE deleting the account (correct —… | dpdp_erasure_must_not_block_on_external_dependency | test/contracts/delete_account_razorpay_cancel_nonfatal_test.dart |
| 2026-06-12 | f1c8e4 | Quarterly audit deep-verify finding (surfaced while verifying apk34 c2e8b4). The canonical LIVE completion writer WorkoutWriteService.markCompleted (which the A-13 derive-only refactor made "replace… | hive_field_name_wlog | test/contracts/markcompleted_wlog_counted_test.dart |
| 2026-06-12 | b3f9d1 | Quarterly audit (L1 lens) finding F1, confirmed post-f1c8e4. The orphan-completion restore branch (_restoreScheduleCompletions, the "no local schedule row for this date" / out-of-plan-window case in… | orphan_completion_wlog_completeness | test/contracts/orphan_completion_synthesizes_wlog_test.dart |
| 2026-06-12 | e7a2c4 | Quarterly audit (L1/IST lens) finding. getWeeklyWorkoutCounts (workout_repository.dart) — the reader behind the reports "This Week" tile + the 4-week frequency chart — anchored its rolling window on… | weekly_workout_count_ist_window | test/contracts/weekly_workout_counts_ist_test.dart |
| 2026-06-11 | c9b3e2 | The quarterly audit's live-DB pass (Supabase security advisor + pg_proc inspection) found several SECURITY DEFINER functions in schema public that were EXECUTE-able by the anon and/or authenticated… | security_definer_function_exposure | test/contracts/security_definer_revoke_migration_test.dart |
| 2026-06-11 | a8f3d1 | Quarterly audit (L27 concurrency lens) finding. The slow-boot flip (ADR-0014) lands a returning user on /home BEFORE the restore's Step C (_restoreFreezes) runs. On /home the streak walk… | streak_freeze_progress_merge | test/contracts/restore_freezes_merge_test.dart |
| 2026-06-09 | d3a1c7 | APK +34 obs 3 — AI features (chat, food logging, weekly report) intermittently failed with no useful error, while ai-proxy itself was ACTIVE (v70) and still logging interactions. client_errors showed… | edge_function_token_freshness | test/contracts/edge_function_token_freshness_test.dart |
| 2026-06-09 | a1d4f9 | APK +34 obs 1/5.1/6 — Home "Start Workout" said "not scheduled", the Train week strip highlighted a wrong/last week as TODAY with "No workouts scheduled", and the plan looked expired — even though the… | plan_phase_expiry | test/contracts/plan_expiry_respects_schedule_test.dart |
| 2026-06-09 | b1f3a7 | APK +34 obs 4 — the Profile avatar AND banner images re-download from the network every single time the user navigates to the Profile tab. They are not served from the local cache, so each visit shows… | profile_image_url_display | test/contracts/profile_image_url_stable_test.dart |
| 2026-06-09 | c2e8b4 | APK +34 obs 2 — the Weekly Report ("Weekly Dispatch") "This Week" summary card showed "19 Workouts" — an impossible weekly number. The value was the LIFETIME total_workouts_done shown under a "This… | weekly_report_data | test/contracts/reports_this_week_count_test.dart |
| 2026-06-09 | e9b4a2 | APK +34 obs 5.2 — Home showed streak "0 DAYS" though cloud user_progress.current_streak_days was 2 and the user had recent completions (last_workout_date 2026-06-06). After a reinstall the client-side… | restore_completeness | test/contracts/restore_orphan_completion_test.dart |
| 2026-06-09 | a7f2e9 | Two sync-resilience gaps surfaced in the APK +34 live telemetry: (BUG-H) the realtime weight_logs stream channelError'd 113x (WS close 1002) and never recovered — only "token expired" triggered a… | realtime_sync_resilience | test/contracts/sync_resilience_test.dart |
| 2026-06-09 | b6e1c3 | APK +34 obs 1/6 — the Train week strip highlighted a wrong/last week as TODAY (image 1: Phase II W1 marked current while W2-W6 showed completed ticks; image 4: Phase IV W12 highlighted as TODAY with… | plan_phase_expiry | test/contracts/train_expired_state_test.dart |
| 2026-06-08 | a4f7e1 | The AI coach's `regeneratePlanBlock` tool exposed a `goal` z.enum that omitted 'recompose' (only build_muscle / lose_fat / general_fitness / strength). Its sibling `switchGoal` had 'recompose' added… | fitness_goal_resolution | test/contracts/ai_proxy_goal_enum_parity_test.dart |
| 2026-06-08 | b4e2a9 | delete-account Edge Function SELECTs subscriptions.razorpay_subscription_id, a column that never existed (the app uses one-time Razorpay orders, not recurring subscriptions). PostgREST returns 42703;… | subscription_state | scripts/check_schema_column_refs.dart |
| 2026-06-08 | d7c3f1 | The nightly evaluate-rank-promotions cron's completionRateOverWindow (_shared/rank_engine.ts) SELECTed scheduled_workouts.reason — a column that exists only in the client's local Hive model, never in… | rank_monotonic_current_code | scripts/check_schema_column_refs.dart |
| 2026-06-08 | a3e8f1 | workout_log_exercises.set_number and workout_log_sets.set_number carried a CHECK bound of <=10 (wle_set_number_realistic / wls_set_number_realistic). >10 sets per exercise is legitimate (drop sets,… | workout_receipt_rendering | test/contracts/constraint_boundary_clamp_test.dart |
| 2026-06-08 | d4c8e1 | During the Batch 6 audit deploy (2026-06-08), redeploying razorpay-webhook (the live Razorpay payment webhook) returned HTTP 503 BOOT_ERROR ("Function failed to start") on EVERY request — the webhook… | std_encoding_dead_export_deploy_rot | scripts/check_std_encoding_import_rot.dart |
| 2026-06-08 | f5d8c3 | verify-payment failed to BOOT (module-load SyntaxError) — every authenticated call returned a gateway 5xx, so the client's payment-verification fallback was dead. Cause: the Batch-6 F31/F33 refactor… | edge_function_duplicate_const_boot_failure | test/contracts/audit_2026_06_07_batch6_server_test.dart |
| 2026-06-07 | f1a70c | The client declared the free AI-coach cap as 15 messages/day and ran a client-only 30-day trial, while the server (ai-proxy) enforces 10/day FOREVER with no trial (OQ-1). Two user-facing failures: (1)… | ai_free_message_limit | test/contracts/ai_message_limit_parity_test.dart |
| 2026-06-07 | e2a1f7 | Three user-facing surfaces showed fabricated or misleading content under an honesty-led brand. F10: the home AI-insight card rendered a CONST "QUICK WINS" macro rail beneath a live-AI "AI COACH ·… | honest_surface_integrity | test/contracts/audit_2026_06_07_batch5_regression_test.dart |
| 2026-06-07 | 15c0de | Hardcoded values/figures had drifted from their single source of truth. F13: AppConstants.appVersion lagged at '1.0.0+28' while pubspec was '1.0.0+33', so client_errors / telemetry rows from builds… | hardcoded_value_centralization | scripts/check_app_version_matches_pubspec.dart |
| 2026-06-07 | 157d0c | Across home / train / nutrition / AI-coach / profile, many READERS built a device-local 'YYYY-MM-DD' date key ('${x.year}-${x.month.toString().padLeft(2,'0')}-${x.day...}') while their WRITERS key by… | ist_date_key_consistency | scripts/check_local_date_key_drift.dart |
| 2026-06-07 | b3f0d9 | Eight server-side Edge-Function / cron defects from the 2026-06-07 audit. F44 (SECURITY): proactive-coach-promotion ran verify_jwt=false with NO auth gate, so an unauthenticated POST drove Gemini cost… | server_edge_function_and_cron_hardening | test/contracts/audit_2026_06_07_batch6_server_test.dart |
| 2026-06-07 | c4d9b2 | Five writer/reader-hygiene defects. F2: the rank-ladder DEPLOYMENTS tile read progress total_workouts_done while the RANK card read deployments_complete — two surfaces showing different numbers for… | writer_reader_drift_and_dead_reads | test/contracts/audit_2026_06_07_batch5_regression_test.dart |
| 2026-06-07 | f19a7c | The default onboarding goal "Recompose" emitted key 'recomp', which plan_screen._mapGoal translated to the token 'recompose' — a value no calculator recognised. BmrCalculator's goal switch fell to… | fitness_goal_resolution | test/contracts/recompose_goal_targets_test.dart |
| 2026-06-07 | c5a1f2 | A returning, signed-in user waited >1 minute on cold start: RestoringScreen._goHome unconditionally awaited the full since='2020-01-01' cloud restore before navigating to /home (the background-restore… | restore_completeness | test/contracts/restore_local_wins_additive_test.dart |
| 2026-06-07 | a8e3c5 | Twelve client UX/flow/restore defects from the 2026-06-07 audit. F3: the streak explainer claimed "+1 each week you complete at least 80% of scheduled workouts", but the real algorithm is +1 per… | client_ux_flow_and_restore_correctness | test/contracts/audit_2026_06_07_batch5_regression_test.dart |
| 2026-06-06 | f0b9d3 | The alert_client_errors_spike cron paged critical for benign volume. Alert #24 fired "client_errors spike: 354 rows in last hour" (critical) for what was the founder's own reinstall/restore burst on… | alert_threshold_tuning | test/contracts/alert_thresholds_sync_test.dart |
| 2026-06-06 | c3f9a1 | Two AI-coach interactions saved within the same millisecond both minted the Hive key coach_<ms>; the second coachBox.put overwrote the first (silent data loss). Surfaced as a non-deterministic CI… | coach_interactions | test/ai_coach/coach_writer_dedup_test.dart |
| 2026-06-06 | e4a8b1 | A just-logged exercise vanished from the Train/receipt UI after the user closed + reopened the app ("the logged exercise was gone"), while the schedule change and the weight log from the same session… | exercise_logs_read_path | test/contracts/workout_write_durable_index_test.dart |
| 2026-06-06 | a7d3f1 | After a fresh-install restore the Train screen showed the wrong week/phase (Home "WK 4", Train banner "WEEK 4 OF 12", Roadmap "33% complete", "Week 6 hasn't started yet") AND every not-yet-completed… | restore_completeness | test/contracts/restore_plan_json_authoritative_test.dart |
| 2026-06-06 | d9a4f2 | workout_log_sets PER-SET rows with reps > 1000 were silently dropped: the cloud CHECK wls_reps_realistic (<= 1000) rejected them with 23514 and the sync catch swallowed it, so the per-set row (read by… | exercise_logs_read_path | test/contracts/cloud_sync_fixes_2026_06_05_test.dart |
| 2026-06-05 | c5e1b7 | Recurring "_TypeError: Null check operator used on a null value" on the check_and_sync path (op_types check_and_sync / sync_service_if_2) in the live telemetry of the founder's account (d7a67a37),… | check_and_sync_null_safety | test/contracts/cloud_sync_fixes_2026_06_05_test.dart |
| 2026-06-05 | c4d8e1 | CI was red on `main` for days (every job died in ~1 min at `flutter pub get`: CI pinned Flutter 3.29.x / Dart 3.7.2 while pubspec required sdk ^3.11.1). The Flutter-pin bump to 3.41.4 unblocked pub… | ci_local_ci_parity | test/contracts/template_exercises_upsert_test.dart |
| 2026-06-05 | 4e8b1d | First cold start was very slow. Live telemetry (restore_completed) showed the full cloud restore = 37.6s and it BLOCKED the RestoringScreen before /home. Step A alone = 25.8s, dominated by the FIRST… | restore_completeness | test/contracts/background_restore_test.dart |
| 2026-06-05 | 9a5c3f | Profile → Health sync: after tapping CONNECT for Health Connect, the sheet still showed "Tap to enable / CONNECT" (disconnected). Only after navigating away and back did it show "Connected". | biometric_sync_state | test/contracts/biometric_sync_state_test.dart |
| 2026-06-05 | 8b3d4e | The Home "Recent Logs" list rendered every logged food as "Unknown" (e.g. "Unknown — 61 kcal — P2·C2·F4"), while the SAME meals showed their correct names on the Nutrition tab. | nutrition_recent_logs_name | test/contracts/nutrition_recent_logs_name_test.dart |
| 2026-06-05 | 7d2e6b | pastPhaseBlocks() bucketed past schedule rows by 28-day CALENDAR windows. A single phase whose rows span >28 calendar days (gaps/overlaps) split across two buckets → over-count → the… | phase_blocks_bucketing | test/contracts/past_phase_bucketing_test.dart |
| 2026-06-05 | 6f1a2c | The workout receipt / share card (Home "View Card", day-detail sheet, post- completion sheet — the shareable card with AVYA branding + QR) rendered a hardcoded "PHASE 1" subtitle even when the user… | workout_receipt_rendering | test/contracts/receipt_phase_for_date_test.dart |
| 2026-06-05 | 2c9f7a | Train week strip, two issues: (3a) current-phase week chips never showed a completion check mark (only past-phase chips did), so a completed current week looked un-done; (3b) the strip was a bare… | week_completion_check | test/contracts/week_completion_check_test.dart |
| 2026-06-05 | a2d8f4 | user_progress.updated_at was frozen at the row's created_at (account creation) even though the row's data advanced (last_workout_date = today, total_workouts current). Surfaced in the live audit of… | user_progress_updated_at | test/contracts/cloud_sync_fixes_2026_06_05_test.dart |
| 2026-06-05 | e7b3c9 | workout_log_exercises SUMMARY rows with reps > 1000 were silently dropped: the cloud CHECK wle_reps_realistic (<= 1000) rejected them with 23514 and the sync catch swallowed it, so the per-exercise… | exercise_logs_read_path | test/contracts/cloud_sync_fixes_2026_06_05_test.dart |
| 2026-06-03 | f7e3a1 | The d4b8e2 sweep (workout_logs / weight / sleep / body / wle / wls) left TWO nutrition tables on the same un-user-scoped deterministic-id pattern — found by the Hermes deep-pass and folded into this… | sync_fanout_nutrition_domain | test/contracts/sync_user_scoped_natural_keys_test.dart |
| 2026-06-03 | b8d5c2 | Surfaced by the f7e3a1 B-pass (Finding 1) while reviewing the saved-meals sync. `NutritionWriteService.saveMealPreset` keyed the local Hive row by `saved_meal_<millisecondsSinceEpoch>`, but the cloud… | saved_meals | test/contracts/saved_meal_key_canonical_test.dart |
| 2026-06-02 | d4b8e2 | Investigating the weekly report's "0 workouts" for upendra, the cloud had workout_log_exercises rows through today but NO workout_logs session-summary row newer than 05-21. Root: the cloud sync id was… | sync_fanout_workout_domain | test/contracts/sync_user_scoped_natural_keys_test.dart |
| 2026-06-02 | b2e9d4 | Tab-screen headings clipped to an ellipsis: the Train screen showed "Intensificati…" (phase name "Intensification") and the Nutrition screen showed "Fueling the pl…". Both used a single-line Text… | ui_header_no_clip | test/contracts/tab_header_no_clip_test.dart |
| 2026-06-02 | a3f8c1 | On the Train screen the week-selector strip showed TWO "PHASE I" sections — a completed "PHASE I (DONE)" with weeks W1 (Apr 27–May 3) … W4 (May 18–24) AND a second, current "PHASE I" with fresh weeks.… | phase_progress_current_phase | test/contracts/phase_progress_reconciler_test.dart |
| 2026-06-02 | c7a1f5 | The Weekly Report showed a calorie/protein target (3141 kcal / 155 g) that disagreed with every other surface (Nutrition / Profile / Diet Plan all show 3069 kcal / 140 g), and "0 workouts / 0%… | weekly_report_target_and_freshness | test/contracts/weekly_report_canonical_target_test.dart |
| 2026-06-02 | e1c6a9 | On the Home weight view, logging a weight after a 7+ day gap rendered a single isolated dot — misleading (reads as a stray entry, not a trend). The old WardSpark sparkline only plotted points inside… | weight_trend_home_chart | test/contracts/weight_trend_chart_gap_connect_test.dart |
| 2026-06-01 | a9c3e2 | Driving the AI coach live as amar (a year-sim power user), EVERY message failed with "Your coaching context is unusually large. Please try a shorter question." The server-side snapshot guard… | ai_snapshot_building | test/contracts/ai_snapshot_budget_trim_test.dart |
| 2026-06-01 | d4f1c2 | Driving the AI coach live as amar, messages intermittently came back with "I had trouble reaching the model. Try again in a moment." — and the SAME message succeeded on a manual retry seconds later.… | ai_coach_tool_loop_gemini_resilience | supabase/functions/_shared/gemini_backoff_retry_test.ts |
| 2026-06-01 | 7e3c91 | On the Nutrition tab's TODAY'S SUMMARY card (driven live as amar), the macro rows showed Flutter's debug RenderFlex stripe banner ("RIGHT OVERFLOWED BY N PIXELS", rendered vertically on the right… | nutrition_summary_macro_row_layout | test/contracts/nutrition_summary_macro_row_no_overflow_test.dart |
| 2026-06-01 | c9f2a7 | Driving the AI coach live as amar (a year-sim power user), a coach `logMealByText` wrote to Hive correctly — the Nutrition Today's Summary card bumped exactly right (4314 -> 4644 kcal, protein 290 ->… | sync_fanout_nutrition_domain | test/contracts/sync_nutrition_log_id_resolved_before_upsert_test.dart |
| 2026-06-01 | f4e1d9 | Completed past-phase weeks in the Train week-selector render every day as a generic "Workout" with no exercise count and no way to see what was done — a flat read-only list (the "Completed history"… | past_week_history_display | test/contracts/past_week_history_derives_from_logs_test.dart |
| 2026-05-31 | b7c2d9 | The /dev time-travel buttons (and the injectable clock seam in ist_date.dart) did not actually move phase / rank / streak logic: jumping the clock +12 weeks left the Train week selector,… | ist_date_clock_seam | test/contracts/clock_seam_nowwall_test.dart |
| 2026-05-31 | b9f4d2 | Surfaced while wiring the deployment-driven rank ladder: the server cron `evaluate-rank-promotions` SELECTs four columns from `user_progress` (current_streak_days, deployments_complete,… | rank_monotonic_current_code | test/contracts/deployments_complete_writer_to_reader_test.dart |
| 2026-05-31 | c7e1a4 | During the live-web year-sim (driving amar to Lieutenant), the dev PRO grant was silently wiped within ~1 second of being granted — BEFORE the sim loop started. The `/dev` autorun logged `isPro right… | subscription_state | test/contracts/subscription_paused_for_simulation_guard_test.dart |
| 2026-05-31 | 5e8a1c | Surfaced by the year-simulation harness: after amar completed Phase 1 (15 of 16 scheduled workouts over 4 weeks, ~85% adherence with a single missed day), the rank did NOT progress — it stayed at SD2… | streaks | test/contracts/streak_frozen_day_persists_protection_test.dart |
| 2026-05-31 | 7d3f0a | Surfaced by the year-simulation harness: SyncService._syncExerciseLogs logs repeated PostgrestException(code 23514, "new row for relation workout_log_exercises violates check constraint… | exercise_logs_read_path | test/contracts/workout_log_exercises_cumulative_reps_test.dart |
| 2026-05-31 | f2d8ae | `ai-proxy` host-shell redeploy failed twice with HTTP 400 "Module not found https://deno.land/x/zod@v3.25.76/mod.ts". The deno.land/x zod module was removed upstream and now returns HTTP 404, so the… | edge_function_dependency_resolution | test/contracts/no_denoland_zod_import_test.dart |
| 2026-05-30 | c9e0a4 | Live web (amar@gmail.com), Home Today card: three "A RenderFlex overflowed by N pixels on the right" exceptions (12 / 29 / 9.5 px) rendered as yellow/black overflow stripes on the FUEL / PROTEIN /… | home_today_macro_column_layout | n/a |
| 2026-05-30 | d5c1b8 | Surfaced during live web E2E by reloading onto the /#/coach/induction hash route. The app rendered GoRouter's error page ("Page Not Found") with: "GoException: Exception during redirect: Bad state:… | hive_session_init_race | test/contracts/induction_service_session_guard_test.dart |
| 2026-05-30 | f4b2c9 | Surfaced during live web E2E. After onboarding, amar@gmail.com had ZERO rank_promotions rows (not even the SD2 floor) and the browser console showed "[RankService.evaluateAndPromote]… | rank_monotonic_current_code | test/contracts/dispatch_proactive_coach_promotion_columns_test.dart |
| 2026-05-30 | e2a4f7 | Surfaced during live web E2E (amar@gmail.com). Browser console at sign-in: "[AuthSessionBootstrapper.resolveDestination] PostgrestException(code 42703: column user_profile.full_name does not exist)".… | onboarding_completed_at | test/contracts/auth_session_bootstrapper_test.dart |
| 2026-05-30 | a7c3e1 | Surfaced during AUDIT-1 (systematic schema-reference audit, 2026-05-30). StatSnapshotService._compute7dAverages selected two columns that do not exist: `daily_steps.total_steps` (real column: `steps`)… | user_stat_snapshot_7d_averages | test/contracts/stat_snapshot_7d_averages_columns_test.dart |
| 2026-05-30 | b1f4d2 | Live web (amar@gmail.com): the Train tab renders "Failed to load workouts / Tap to retry" even though Home's Today card shows the same plan correctly (PHASE 1 / UPPER / 70 MIN · 7 EX). RETRY does not… | train_plan_header_render | scripts/check_container_color_decoration.dart |
| 2026-05-30 | e3f1a7 | Live web (amar@gmail.com): recurring console "[realtime] weight_logs stream error: RealtimeSubscribeException(status: channelError, ...)" (3x in 14 min) and 156 client_errors rows… | weight_logs_realtime_stream | test/contracts/weight_logs_realtime_publication_test.dart |
| 2026-05-29 | c3d8a1 | The Blast-radius auto-prepend (Track 2 deliverable) never fired. Neither the mega-commit (7d31f40) nor the cron-fix commit (7490dc9) received the expected "Blast-radius: <tier>" line in the commit… | blast_radius_commit_autotag | not_applicable (shell git-hook behavior; verified by simulating the hook against a temp commit-message file with a staged path) |
| 2026-05-29 | 9e1d4c | Every rank promotion silently fails to deliver its celebration — no AI congrats message is stored and no OneSignal "Promotion Day" push is sent. | coach_interactions | test/contracts/proactive_coach_promotion_test.dart |
| 2026-05-29 | 7c2a8b | After any cloud restore (reinstall, new device, logout then login) every workout session name ("Push A", "Pull B") is replaced by the literal "Workout" in home history, receipt headers, and the AI… | workout_completion_status | test/sync/restore_field_canonical_test.dart |
| 2026-05-28 | b1f4e2 | alert_edge_function_health pg_cron job failed every 15 minutes since migration 076 shipped, with "ERROR: column status_code does not exist". No edge-function-health alerting was actually running;… | alert_detection_edge_function_health | not_applicable (live cron behavior; verified via cron.job_run_details query — source-grep contract test would not catch a column-name mismatch that only fails at runtime against live schema) |
| 2026-05-27 | ada3fb | The `/sync-claude-md` audit on 2026-05-27 found that the cloud `exercise_library` table contained 0 rows. The food parallel (`food_database`) was correctly seeded — 1,431 rows present from migration… | exercise_library_cloud_seed | test/contracts/exercise_library_cloud_seeded_test.dart |
| 2026-05-27 | 3a7b9f | Founder-as-user "upendra" (auth.users d7a67a37-0b05-4f0a-b13c-388bff3cb59b) earned SD1 (ordinal 1) on 2026-05-21 14:35 UTC at streak=7, week=2, 15 workouts. Approximately 7 hours later (2026-05-21… | rank_monotonic_current_code | test/contracts/rank_no_demotion_behavioral_test.dart |
| 2026-05-24 | 524d12 | The 2026-05-24 ECC adoption batch shipped the writer-reader-drift-detector subagent (B1). Its first run on workout + nutrition domains surfaced 9 drift instances across the writer/reader contract —… | writer_reader_drift_batch_2026_05_24 | test/contracts/nlog_key_canonical_test.dart |
| 2026-05-24 | 2b705b | 53 of 2354 unit tests fail on `claude/blissful-neumann-bb2fb7` (merged to main as `cf82347`). All 53 are stale source-grep contract tests rendered obsolete by the B5 audit's refactor work (A2 + A10 +… | source_grep_contract_test_recovery_post_refactor | this doc IS the recovery contract; flutter test exit 0 is the contract |
| 2026-05-23 | ea1059 | Founder reviewed the Theme H-followup mockup 2026-05-23 and spotted that the graduation screen's Phase 2 preview card hardcodes `5 DAYS/WEEK · WEEKS 5-8 · POWER + HYPERTROPHY` and a static 5-day… | graduation_phase2_preview | test/contracts/graduation_phase2_preview_dynamic_test.dart |
| 2026-05-23 | 85a684 | Founder reviewed the Theme H-followup mockup 2026-05-23 and clarified the original "scroll back to see completed phases" wish: the desired surface is INLINE in the train screen's existing… | week_selector_past_phase_scroll | test/contracts/week_selector_past_phases_test.dart |
| 2026-05-22 | d882ca | `lib/core/services/workout_schedule_service.dart` had grown to ~1970 lines and absorbed four distinct responsibilities: 1. Plan generation orchestration (generateAndSchedule,… | workout_schedule_service_split | test/contracts/workout_schedule_split_invariant_test.dart |
| 2026-05-22 | 7f2a8c | Seven services were instantiated as `static final XxxService instance = XxxService._()` singletons: - SubscriptionService, SyncService, WorkoutScheduleService, UsageCounterService, AiService,… | singleton_lifecycle_registry | test/contracts/singleton_provider_invariant_test.dart |
| 2026-05-22 | b4a09c | Pre-commit hook fails with 4 undefined-method errors blocking all commits on main since 2026-05-21: - `test/ai_coach/meals_today_snapshot_test.dart:68,108,128` calls… | ai_snapshot_building | test/ai_coach/meals_today_snapshot_test.dart |
| 2026-05-22 | 599d49 | Founder opened Nutrition → Log Food → AI tab → typed → tapped ANALYSE & LOG → got the toast "The AI is temporarily unavailable. Please try again in a minute." (founder IS PRO with active… | food_text_analysis | test/contracts/food_ai_telemetry_retry_test.dart |
| 2026-05-22 | 89d56c | Founder unlocked Phase 2 graduation card 2026-05-21 and saw TOTAL SETS = 0 alongside 30 PRs / 15 workouts / 2 week streak. Cloud data shows hundreds of completed sets across Phase 1. Every user on… | exercise_logs_read_path | test/contracts/graduation_stats_provider_field_test.dart |
| 2026-05-22 | dc52a4 | Founder install of APK Test #16.2 +30 on 2026-05-20. Telemetry pulled 2026-05-21 showed `day_rollover_streak_freeze_refill` failing with "Bad state: HiveUserSession not opened — cannot wrap… | hive_session_init_race | test/contracts/splash_no_userbox_touch_test.dart |
| 2026-05-22 | 0e7714 | Founder mid-Phase-1-Week-4 (Wed 2026-05-21) saw the UNLOCK PHASE 2 card and asked "since when does the user start seeing unlock phase 2? or subsequent phases? it should open up on thursday of the last… | phase_unlock_card_surface_gate | test/contracts/phase_unlock_card_thursday_gate_test.dart |
| 2026-05-22 | ec4d27 | Two issues bundled (same code path, same surface): F: Founder tapped GENERATE NEXT PHASE 2026-05-21. After Theme F2 unblocked the silent gate, the unlock fired BUT: (a) no loading state — button… | phase_unlock_end_to_end | test/contracts/phase_unlock_end_to_end_test.dart |
| 2026-05-22 | b0baa5 | Founder tapped GENERATE NEXT PHASE the second time on 2026-05-21 evening (after Theme F2 unblocked the silent gate). Plan generation fired, BUT: the train screen then showed a new Phase 1 starting… | scheduled_workouts_mutations | test/contracts/phase_unlock_start_date_test.dart |
| 2026-05-22 | 8b1f33 | Founder ranked up SD2 → LT recently and the AVYA coach said nothing about it. The pre-existing coach surface is reactive — responds only to user messages. No proactive-message infrastructure existed:… | proactive_coach_promotion | test/contracts/proactive_coach_promotion_test.dart |
| 2026-05-22 | 9aa2c1 | Founder promoted SD2 → LT recently. `RankService.evaluateAndPromote` successfully detected the rank change, wrote the `rank_promotions` cloud row, updated `user_profile.current_rank_code`, mirrored to… | rank_promotion_celebration | test/contracts/promotion_celebration_wiring_test.dart |
| 2026-05-22 | 4a3b08 | Founder saw the "This is taking a while. CONTINUE →" escape-hatch button surface on the RestoringScreen on every cold start, even though the restore was progressing normally. Root cause: APK +28/+30… | restore_completeness | test/contracts/restoring_screen_timeout_test.dart |
| 2026-05-22 | 7b3eaf | Founder tapped GENERATE NEXT PHASE on graduation screen 2026-05-21 evening — nothing happened. No navigation. No error toast. No paywall. No telemetry in `train_graduation_generate_phase_2_failed`.… | subscription_gate | test/contracts/subscription_gate_catcherror_test.dart |
| 2026-05-21 | 2b8d4e | `lib/core/services/sync_service.dart` plus its 8 `part of` files under `lib/core/services/sync/` host every sync + restore helper as private methods on the SyncService singleton. The restore-vs-sync… | sync_domain_full_migration_A6 | test/contracts/sync_domain_full_migration_test.dart |
| 2026-05-21 | 9c2b1f | `lib/features/ai_coach/repositories/ai_coach_repository.dart` was 2127 lines carrying FOUR distinct contracts in one class: (1) AI snapshot building — `buildAiContext()` + ~40 private read helpers… | ai_coach_repository_split_A10 | test/contracts/ai_snapshot_builder_only_test.dart |
| 2026-05-21 | 17ae38 | Two coupled architecture-debt findings on the post-sign-in path. A1 (score 24): `lib/features/auth/providers/auth_provider.dart` was a god-provider. Its `_ensureLocalUser` method did Postgres CRUD on… | post_signin_destination | test/contracts/auth_session_bootstrapper_test.dart |
| 2026-05-21 | 3e9d39 | Two dependencies under `lib/` were duplicating the same capability — HTTP client. `package:http ^1.6.0` (declared in pubspec) was used by: - `lib/core/services/ai_service.dart` — `http.Client`,… | dependency_canonical_http_client | scripts/check_no_http_package.dart |
| 2026-05-21 | b3ecf2 | Edge Function deploys were forward-only. When a bad deploy hit prod (caught via `client_errors` spike per B1 / I4 alert, or a user report), the operator's only path was: `git checkout <previous SHA>`… | edge_function_deploy_reversibility | scripts/check_edge_function_rollback_script.dart |
| 2026-05-21 | 3cbbce | Profile map mutations (goal changes from the AI Coach, weight updates from the home weight tile, post-sign-in cloud merge, brand-new user stub creation, phase_started_at stamping during onboarding… | profile_write_service | test/contracts/profile_write_service_only_test.dart |
| 2026-05-21 | 2d1c8a | Three profile-tab readers (referral_eligibility_provider, promotion_history_provider) and one apply-referral writer (apply_referral_sheet) bypassed the repository pattern and called Supabase directly… | referral_redemption | test/contracts/referral_repository_only_test.dart |
| 2026-05-21 | 7a3e1c | Audit finding A7 (score 14): seven `static .instance` core services live OUTSIDE the Riverpod graph and hold mutable in-memory state that survives HiveUserSession user swaps: -… | singleton_lifecycle_registry | test/contracts/singleton_lifecycle_registry_test.dart |
| 2026-05-21 | 5a0b31 | `lib/core/services/sync_service.dart` (1395 lines) plus 8 `part of` files under `lib/core/services/sync/` (5577 lines total) host every sync + restore helper as private methods on a single… | sync_domain_interface_scaffold_A6 | test/contracts/sync_domain_interface_test.dart |
| 2026-05-21 | 1f4a8b | `lib/core/theme/typography.dart` exists as the canonical Wardroom 3-font system (`AppTypography.body`, `.bodyM`, `.mono`, `.h1`, etc.) but only ~2 production files routed through it. The other 175… | typography_canonical_source | test/contracts/no_raw_google_fonts_test.dart |
| 2026-05-20 | c2a91f | Founder reported "How do I see weekly report? Nothing is happening on clicking it?" on 2026-05-20 after almost 4 weeks of use. The Profile REPORTS section's Weekly Report hero card permanently… | usage_weeks_signup_age | test/contracts/usage_weeks_uses_supabase_signup_test.dart |
| 2026-05-20 | b3f7a2 | Founder asked on 2026-05-20: "in the weight graph in dashboard screen, what if user wants to see more than 90 days data?" The dashboard Weight Trend card… | weight_trend_range | test/contracts/weight_sparkline_all_chip_and_footer_link_test.dart |
| 2026-05-19 | 9c4a17 | Founder install of APK Test #16.2 on 2026-05-19 (Tue). Home dashboard rendered "0/3" streak freezes and surfaced the "Streak Freeze used! 0 remaining this week." SnackBar despite the founder NOT… | streak_freeze_refill_restore_race | test/contracts/streak_freeze_refill_race_test.dart |
| 2026-05-19 | 4f8e2d | Founder install of APK Test #16.2 on 2026-05-19 (Tue). RestoringScreen sat on "Pulling your dispatch. Stand by, soldier." long enough for the 15-second safety-net timer at restoring_screen.dart:42 to… | restore_long_pole_timing_visibility | test/contracts/streak_freeze_refill_telemetry_test.dart |
| 2026-05-18 | t1m5b0 | Two related AI-coach failures within a single session. Failure A (08:34 IST). User asked "how was my workout today and in this phase till now?". The coach replied: "Recruit, the system timed out… | ai_tool_wall_clock_and_media_proxy_error_class | test/contracts/get_progress_summary_parallel_queries_test.dart |
| 2026-05-18 | f8c1a5 | On Monday 2026-05-18 IST, the Daily letterhead streak chip rendered "4 DAYS / 8/3" where the freeze badge shows 8 available against a maximum of 3 (PRO tier cap). User reported the Monday weekly… | streak_freeze_value_clamp_on_read | test/contracts/streak_freeze_value_clamped_on_read_test.dart |
| 2026-05-18 | s1n4c0 | During an active workout, the user opened the swap sheet on an exercise, tapped "+ ADD EXERCISE" and created "Barbell Jump Squats" via the inline CreateCustomExerciseSheet. The "Swapped X to Y / UNDO"… | swap_undo_snackbar_modal_stack | test/features/train/swap_undo_snackbar_dismisses_test.dart |
| 2026-05-18 | w7r4c3 | User logged the first weight entry for 2026-05-18 (IST) via the Home bottom-sheet weight logger. The "WEIGHT TREND" home card x-axis rendered the new dot at MAY 18 with the correct value (77.9 kg),… | weight_log_provider_invalidation_race | test/contracts/weight_log_invalidation_awaitable_test.dart |
| 2026-05-17 | 3a7c1e | No live symptom — preventive enforcement. The existing `auth_invalidation_contract_test.dart` (post APK Test #15.3 / Bug c4055a) already auto-discovers new providers in `lib/features/` and enforces… | cross_account_guard_exempt_declaration | test/contracts/auth_invalidation_contract_test.dart |
| 2026-05-17 | 7c4e5d | On APK +27 fresh install, founder observed: (a) tapping "VIEW WORKOUT CARD" on Friday May 15's calendar day detail did nothing (silent no-op). (b) train_screen showed "FRI · HYBRID A · DONE · No… | marked_done_without_logging_ux | test/contracts/marked_done_vs_logged_ux_test.dart |
| 2026-05-17 | 0a1e17 | The build-apk Gate 18 script `scripts/check_reader_manifest_complete.dart` only enforced the "forbidden-patterns absent" half of the reader-side manifest contract. It did NOT enforce "every source… | reader_manifest_exhaustive_completeness | test/contracts/reader_manifest_exhaustiveness_test.dart |
| 2026-05-17 | 8d85c2 | The reader side of the workout / nutrition / health domains had no canonical home. Each consumer re-implemented the same semantic inline. When the PR cumulative bug shipped on APK +27 (founder install… | workout_read_service | test/contracts/workout_read_service_per_set_semantic_test.dart |
| 2026-05-17 | c0e3a5 | No live symptom — preventive infrastructure. OI-07 built the snapshot contract manifest. OI-03 is the gate that ENFORCES the manifest. F3-1.1 (`coach_notes` vs `coaching_notes`) was the cross-system… | snapshot_contract_enforcement | test/contracts/snapshot_contract_gate_test.dart |
| 2026-05-17 | 93aeac | `AiCoachRepository.buildAiContext()` emits ~48 keys into a JSON blob. 13 Edge Functions consume it via two paths: (A) ai-proxy / ai-media-proxy stringify the whole blob into the Gemini system prompt;… | ai_snapshot_building | test/contracts/snapshot_contract_self_consistency_test.dart |
| 2026-05-17 | 9a7c14 | Razorpay webhook threw `ReferenceError: Cannot access 'supabaseClient' before initialization` on every `payment.captured` / `payment.authorized` event that wasn't an early-return (HMAC fail / age… | razorpay_webhook_handler_correctness | test/contracts/razorpay_webhook_supabase_client_decl_order_test.dart |
| 2026-05-17 | b3e052 | verify-payment Edge Function inserted/upserted `subscriptions` rows without the `razorpay_signature` column. Since migration 052 (2026-05-13) that column is NOT NULL. Every fallback path (when webhook… | verify_payment_payload_completeness | test/contracts/verify_payment_payload_completeness_test.dart |
| 2026-05-17 | 5e055f | ai-media-proxy validated only that the supplied `media_url` started with `${SUPABASE_URL}/storage/v1/object/`, then fetched the URL with `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}`. Service… | ai_media_proxy_user_scope_assertion | test/contracts/ai_media_proxy_user_scope_test.dart |
| 2026-05-17 | c8f229 | verify-payment ownership check at `if (notesUserId && notesUserId !== userId) { return 403; }` was fail-open when `payment.notes.user_id` was absent. An attacker who learns a captured Razorpay… | verify_payment_notes_user_id_guard | test/contracts/verify_payment_notes_user_id_required_test.dart |
| 2026-05-17 | c1ea30 | `clean-orphan-media` daily cron deleted from `coach-media` bucket — which migration 070 (also shipped 2026-05-17) had designated as long-term consented retention. Transient analysis bucket is… | clean_orphan_media_bucket_target | "must add: test/contracts/clean_orphan_media_targets_chat_media_test.dart" |
| 2026-05-17 | c4031b | 3 cron-invoked Edge Functions (expiry-reminder, morning-alert, rolling-context) created service-role clients without calling `isAuthorizedCronCall(req)`. Public POSTs could trigger expensive fan-outs:… | cron_edge_function_auth_gate | test/contracts/cron_auth_adoption_test.dart |
| 2026-05-17 | a2d0e1 | delete-account Edge Function only listed top-level entries under `userId/` for each Storage bucket. Nested paths (`userId/2026/photo.jpg`, `userId/subfolder/...`) survived account deletion. DPDP §17… | delete_account_storage_purge_recursive | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | c84e33 | `scripts/check_apk_size_within_bounds.dart` (Gate 13) silent-skipped with exit 0 when the APK artifact was missing. In a clean CI or wrong-order pipeline the gate green-checks without actually… | apk_size_gate_strict_mode | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 1c3401 | Existing `check_migrations_applied.dart` (Gate 14) compared local migration filenames against `backups/applied_migrations.json` — a manually maintained snapshot. If the snapshot is stale or someone… | migration_live_verify_gate | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | d0c352 | CLAUDE.md §2 (Tech Stack quick-summary) line 130 claimed "21 tables". CLAUDE.md §7 (Database Schema header) line 380 said "46 Tables". AGENTS.md line 95 mirrored the §2 stale figure. §7 was bumped on… | doc_internal_consistency_table_count | scripts/check_doc_internal_consistency.dart |
| 2026-05-17 | d1e7e6 | `DeleteNutritionLogNotifier.deleteFoodLog` wrote the `recent_deletes` audit log + called `box.delete(logId)` directly, bypassing `NutritionWriteService.deleteLog`. Same writer/reader drift class… | nutrition_delete_canonical_writer | test/contracts/nutrition_delete_routes_through_write_service_test.dart |
| 2026-05-17 | 4a37e7 | After a rank promotion, the cloud `user_profile.current_rank_code` was updated but the local Hive profile served the OLD rank to all rank-reading widgets (Profile / Home / Rank chip / Phase Roadmap)… | rank_promotion_local_sync | test/contracts/rank_service_local_profile_update_test.dart |
| 2026-05-17 | 5fe338 | `StreakFreezeNotifier.build()` called `_refillIfNewWeek()` which eventually called `StreakProgressService.instance.commitRefill(...)`. Riverpod write-on-read anti-pattern: every provider rebuild (auth… | streak_freeze_refill_extract | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 39ead9 | `train_provider._getLastPerformance` (line 43) and `exerciseHistoryProvider` (line 131) iterated `hive.workoutBox.values` inline and filtered `if (log['type'] != 'exercise_log')` — depended on the… | train_provider_workout_read_service_delegation | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 40c401 | `paywall_sheet_phase_variant.dart` rendered a phase-unlock pitch bottom sheet, but its UPGRADE TO PRO CTA called `Navigator.pop()` with a deferred-checkout note — never actually invoked any purchase… | paywall_single_purchase_path | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 41507e | Home + Rank widgets called `WorkoutRepository.currentStreak()` (live walk-back through `schedule_*` keys). Profile + Reports read cached `current_streak_weeks` from `user_progress`. The cached field… | current_streak_single_reader | test/contracts/phase_c_oi_closures_test.dart |
| 2026-05-17 | 7faa3b | Silent personalization degradation. OI-07's snapshot contract manifest surfaced 11 orphan readers — cron Edge Functions reading named fields from `user_daily_snapshots.snapshot_json` that… | snapshot_writer_contract | test/contracts/snapshot_orphan_reader_aliases_test.dart |
| 2026-05-17 | 9d2a47 | No live symptom — preventive audit. Migration 064 (APK Test #16) fixed the 42P10 silent-data-loss class on 3 tables (workout_logs, workout_log_exercises, nutrition_logs). The audit-comprehensiveness… | partial_unique_arbiter_safety | test/contracts/partial_unique_arbiter_inventory_test.dart |
| 2026-05-17 | 4dd7e2 | Obs 1 of 2026-05-16 (`daffac`) was a live instance of incomplete restore: writer (`WorkoutWriteService.logExercise`) stamped `workout_log_id` on every exlog row, but `_restoreExerciseLogs` did NOT… | restore_completeness_symmetric | test/contracts/restore_round_trip_field_coverage_test.dart |
| 2026-05-16 | 2026-05-16-ai-proxy-placeholder-resolution | `ai_coach_interactions` table accumulated stuck rows with `model_used='pending'` and empty `ai_response`. Live audit on 2026-05-16 found 8 such rows spanning 2026-05-11 → 2026-05-15 (4 on… |  |  |
| 2026-05-16 | a17bc3 | Founder's `ai_coach_interactions` table shows 6 rows for the same `user_message='curd 200gms whey 1.5 scoops cashew 6'` (3 timestamps × 2 channels). Each "Analyze with AI" tap during Gemini 502 storm… | ai_coach_interactions_dedup | test/ai_coach/coach_writer_dedup_test.dart |
| 2026-05-16 | 2026-05-16-dead-columns-dropped | 17 cloud columns across 7 tables were 100% NULL across all live rows (audit Agent 3 / Cluster 4 live SQL on 2026-05-16). Each had at least one of these failure modes: |  |  |
| 2026-05-16 | 2026-05-16-doc-updates | CLAUDE.md and `docs/sot_registry.yaml` need to track the audit-2026-05-16 architectural changes so the next contributor sees the canonical patterns: |  |  |
| 2026-05-16 | a16c1a | Founder on +24 APK install (May 14 2026) reported two problems observed live in the production app: 1. Train screen rendered 26+ exercise rows under May 14 when only 4 exercises had actually been… | exlog_key_sot | test/contracts/exlog_key_canonical_test.dart |
| 2026-05-16 | de29b8 | Not a bug — the audit-2026-05-16 framework deliverable: 6 new gate scripts plus 6 new contract tests codifying discipline rules that until then existed only as prose. Carries a symptom line so the bug… |  |  |
| 2026-05-16 | 2026-05-16-gate-coverage-and-dead-code | Three orthogonal issues bundled into one diagnose-doc: |  |  |
| 2026-05-16 | e7a516 | Two related health-domain defects rolled into one architectural fix: (1) F2-R2 — `BiometricNotifier.logSleep` wrote `sleep_log_<dateStr>` using device-local `now.year-now.month-now.day`. At IST… | health_write_service | "test/contracts/health_write_service_writer_to_reader_test.dart" |
| 2026-05-16 | 2026-05-16-logpr-bypass | The AI coach `logPR` tool (one of 24 tools registered in `_shared/tools/registry.ts`) routes user-claimed PR attempts through the legacy `WorkoutRepository.logSetWithPrRescan` method instead of the… |  |  |
| 2026-05-16 | 9d12af | Hidden observability bug — silent for an unknown number of days. `supabase/functions/log-client-error/index.ts` enforced a per-user rate limit of 100 events/24h. Past the threshold, the function… | client_errors_telemetry_pipeline | test/safety/error_telemetry_rate_limit_test.dart |
| 2026-05-16 | 1bfeed | Onboarded users (cloud `user_profile` populated with goal/weight/phase) could land on `/onboarding/mission-brief` on fresh install when (a) cloud `user_profile.onboarding_completed_at` was NULL (cloud… | onboarding_completed_at | test/contracts/onboarding_completed_migrated_key_test.dart |
| 2026-05-16 | 913261 | Founder sent a photo via AI Coach at 13:32 IST 2026-05-15. Edge Function logs show POST 500 ai-media-proxy version 16, execution_time_ms 14587. Client surfaced "Sorry, I couldn't analyse that photo.… | ai_media_proxy_status_code_classification | test/contracts/ai_media_proxy_status_code_classification_test.dart |
| 2026-05-16 | 5bea3e | AI coach photo analysis still fails on first attempt after the Test #16.1 / Bug 913261 classification fix. Chat bubble correctly renders the red-bordered "PHOTO FAILED · Tap to retry" tile (the new UI… | ai_media_proxy_classification | test/contracts/edge_function_storage_race_retry_test.dart |
| 2026-05-16 | cb1ab1 | Live screenshot 2026-05-16 (founder on APK +27 fresh install, signed in as upendraprasad19@gmail.com): home stats grid + PR snapshot showed cumulative SUM as "best per-set" value for non-weighted… | exercise_personal_records | test/contracts/load_all_exercise_prs_per_set_semantic_test.dart |
| 2026-05-16 | 2c1c0d | Profile prediction card showed "Complete onboarding to get your personalised fitness prediction" for an already-onboarded user (founder, APK +27 fresh install). Goal/weight/phase were all populated;… | prediction_card_display | test/contracts/prediction_card_onboarding_copy_test.dart |
| 2026-05-16 | 2026-05-16-rank-widget-migration | CLAUDE.md §9 "Wardroom primitives" Legacy section documented `RankChip` + `RankInsignia` as "slated for removal — do not introduce new usages", but 5 active callsites remained for 3 weeks after the… |  |  |
| 2026-05-16 | 2026-05-16-referral-restore-completeness | Founder reported during APK Test #2 (2026-04-25) generated a referral code via Profile -> Invite Friends. Two weeks later, on a fresh reinstall (sumitt@gmail.com cross-device login flow), the Invite… | referral_restore_completeness | test/contracts/restore_completeness_writes_test.dart |
| 2026-05-16 | 2026-05-16-schedule-completion-duration | `workout_schedule_completions.duration_seconds` is 100% NULL in cloud across all production users (11/11 rows; verified by Agent 3 live SQL in `docs/audit/2026-05-16/findings-agent-3.md` § F3-1.3).… | workout_schedule_completion_cloud_projection | test/contracts/schedule_completion_duration_writer_to_reader_test.dart |
| 2026-05-16 | 5beed5 | AI coach reported "your sleep data isn't logged" despite the user having reported sleep through the same coach minutes earlier. The chat turn succeeded (assistant bubble responded with confirmation),… | sleep_logs | test/contracts/sleep_chat_routes_through_health_write_service_test.dart |
| 2026-05-16 | 2026-05-16-sync-coach-cross-channel-dedup | `ai_coach_interactions` accumulated paired duplicate rows for one logical user turn. Live audit on 2026-05-16 found **8 cross-channel pairs** spanning 2026-05-11 → 2026-05-15. Each pair: same… |  |  |
| 2026-05-16 | 2026-05-16-telemetry-hardening | Telemetry framework had five compounding observability gaps surfaced by audit Agent 7 — no success-path emission on 5 low-usage sync methods (cannot distinguish "feature unused" from "silently… | ErrorTelemetry + sync success/failure signal + cron auth | test/contracts/high_priority_op_types_parity_test.dart |
| 2026-05-16 | 2026-05-16-terms-accepted-at-dpdp | Cloud `users.terms_accepted_at` and `users.terms_version` are 100% NULL across every production row (live SQL: `null_count = 4 / total = 4` for both columns at audit time). DPDP §22 requires the… | terms_acceptance_audit_trail | test/contracts/terms_signup_writes_test.dart |
| 2026-05-16 | daffac | Three symptoms from the same fresh-install session — same writer/reader drift class manifesting in different readers: (1) Tapping "View Workout Card" on home calendar day detail did nothing — silent… | workout_log_id_session_scoping | test/contracts/load_all_exercise_prs_per_set_semantic_test.dart |
| 2026-05-16 | 2026-05-16-workout-schedule-service-bypass | `WorkoutScheduleService` had 13 direct `workoutBox.put` callsites — every schedule mutation (template assignment, swap exercise, shorten day, mark completed/skipped/travel, copy week, restore… |  |  |
| 2026-05-15 | c01d57 | Edge Function logs at 09:33 IST show 3× ai-proxy 502 BAD_GATEWAY with execution_times 6.1s / 6.6s / 7.2s in rapid succession. The Test #15.3 retry schedule `[1500, 4000]` ms (~5.5 s total wait) was… | edge_function_cold_start_resilience | test/contracts/edge_function_cold_start_retry_behavioral_test.dart |
| 2026-05-15 | 4e9515 | Founder asked for a "debugging" skill earlier in the session; both `superpowers:debugging` and `debugging` returned `Unknown skill`. The project's `.claude/skills/` directory did not exist. Debugging… | debugging_methodology | "n/a — process discipline addition; the SKILL.md file itself is the contract, and § 5 self-evolution rule is enforced by the next debugging session's output contract (§ 4)" |
| 2026-05-15 | 25e91d | Source-grep contract tests (test/contracts/sync_onconflict_natural_key_test.dart and siblings) pin the client `onConflict:` string but cannot prove the live Postgres schema has a UNIQUE / EXCLUDE… | cloud_upsert_natural_key_contract | test/sql/onconflict_live_arbiter.sql |
| 2026-05-15 | 76c8f4 | PostgREST raises 42P10 "no unique or exclusion constraint matching the ON CONFLICT specification" on every upsert to workout_logs (onConflict=user_id,date,exercise_name), workout_log_exercises… | sync_fanout_workout_domain | test/contracts/sync_onconflict_natural_key_test.dart |
| 2026-05-15 | 5a65bd | pr-detection Edge Function cron returns 401 every 15 minutes; same shape affects 6 other C-4-gated proactive trigger functions (re-engagement, plateau-alert, protein-gap-alert, workout-window-closing,… | cron_auth | "n/a — operational/config drift, not field-rename class" |
| 2026-05-15 | a5d29c | Founder searched "Single Leg Front" in the active-workout SWAP EXERCISE picker on a fresh install. The picker returned "No matching exercises found" even though his custom exercise `Single Leg Front… | custom_exercises_mutations | test/widgets/swap_sheet_custom_exercises_test.dart |
| 2026-05-15 | 9f4ab2 | Hypothetical (defence-in-depth) — no production occurrence yet. If the natural-key columns on `workout_logs`, `workout_log_exercises`, `workout_log_sets`, or `nutrition_logs` ever become NULLable… | sync_natural_key_guard | test/contracts/sync_natural_key_guard_test.dart |
| 2026-05-12 | d8e5b3 | Photo upload to AI coach → "Sorry, I couldn't analyse that photo. Please try again." Zero client_errors rows for ai-media-proxy in last 12h — generic fallback fires silently without telemetry. | ai_media_proxy_error_handling | test/contracts/ai_media_proxy_telemetry_test.dart |
| 2026-05-12 | 7c4e1a | User tapped "Analyse & Log" on Nutrition → Log Food → AI tab. Got toast "The AI is temporarily unavailable. Please try again in a minute." Same error class also fires from AI coach `logMealByText`… | edge_function_cold_start_resilience | test/contracts/retry_loop_guard_test.dart |
| 2026-05-12 | 8f3d22 | `WorkoutScheduleService.assignTemplateToDate` silently returns `void` when the target date's schedule entry has `status == 'completed'`. The caller in `train_screen._scheduleTemplate` iterates over… | scheduled_workouts_mutations | test/contracts/template_schedule_completed_day_test.dart |
| 2026-05-12 | c7d4f6 | After signing out as Upendra and signing up as new account sumit1@gmail.com, the Profile screen showed Upendra's full profile data (full_name=Upendra, dob=1988-06-30, height=174cm, weight=78.3kg,… | hive_user_session_static_state | test/safety/hive_user_session_concurrency_test.dart |
| 2026-05-12 | 7bd154 | After signing out as Upendra and signing up as sumit1@gmail.com on the same session, Edit Profile rendered Upendra's profile (174 cm / 77.8 kg / DOB 1988-06-30) until the app was force-killed and… | cross_account_riverpod_cache_race | test/contracts/auth_invalidation_timing_test.dart |
| 2026-05-12 | c4055a | After signOut+signUp on the same app session, every user-scoped Riverpod provider continues to serve the previous user's cached state even though Hive boxes have correctly switched to the new user's… | user_scoped_riverpod_providers | test/contracts/auth_invalidation_contract_test.dart |
| 2026-05-12 | b7e3f1 | On Sunday morning cold start, home today-card showed Saturday's completed workout ("BACK DAY A · DONE · Lat Pulldown 40kg") even though the IST calendar had advanced to Sunday May 10. | day_rollover_provider_invalidation | "test/contracts/cold_start_day_rollover_test.dart" |
| 2026-05-12 | a2b3c4 | Cloud column `workout_log_exercises.duration_seconds` is always NULL for rows written by the modern `WorkoutWriteService`. The `SyncService._syncExerciseLogs` projection writes `'duration_seconds':… | workout_receipt_rendering | test/contracts/duration_seconds_aggregate_populated_test.dart |
| 2026-05-12 | 0a7b9f | Two surfaces affected. (G) Food text analysis returned "The AI is temporarily unavailable. Please try again in a minute." after the user typed a meal description and tapped Analyse & Log. (H)… | edge_function_cold_start_resilience | test/contracts/edge_function_503_retry_test.dart |
| 2026-05-12 | f4c9e1 | After completing today's morning workout via the active-workout flow, the Edit Workout Log sheet shows "No exercise logs for this day" — blank. Cloud workout_log_exercises HAS the 5 rows for the… | exercise_logs_read_path | test/contracts/edit_log_id_injection_test.dart |
| 2026-05-12 | e1f8a2 | When the user opens the Edit Workout Log sheet for a previously-completed exercise that was logged via the modern WorkoutWriteService (post-Test-#6), the per-set inputs show the legacy aggregate… | exercise_log_per_set | test/contracts/edit_workout_log_sets_field_contract_test.dart |
| 2026-05-12 | a8f1c2 | "Active workout screen pre-fills REPS input with 85 on every set of Hanging Leg Raise (4 prescribed sets × 14 reps, bodyweight). 85 is the sum of the user's previous 7-set session… | last_performance_per_set_semantics | test/contracts/last_performance_per_set_contract_test.dart |
| 2026-05-12 | 8c4ee3 | After completing the post-onboarding muster flow (MusterScreen) and entering shoulders as a known injury and legs as the body-part priority, Edit Profile continued to show injuries=['none'] and… | muster_to_profile_bridge | test/contracts/muster_profile_bridge_test.dart |
| 2026-05-12 | e6a2d4 | "LAST: 50KG · 135 REPS" rendered above Leg Extension in active workout screen — 135 reps per set is unrealistic. Cloud `workout_log_exercises` had 3 corrupt rows from May 7 with set_number=15 +… | workout_log_exercises_input_validation | test/contracts/rep_input_validation_test.dart |
| 2026-05-12 | 9e2c1a | Founder on +22 fresh install (Hive wiped, restored from cloud) sees Monday 2026-05-11 day card header rendering the original plan-generator name "PUSH A" instead of the assigned template name "Leg Day… | scheduled_workouts_mutations | test/contracts/restore_template_schedule_test.dart |
| 2026-05-12 | d4e9c1 | Founder logged Saturday May 9 BACK DAY A. Cloud confirmed scheduled_workouts row has status='completed'. After logout → login on Sunday May 10, the calendar strip showed S9 with NO checkmark.… | workout_completion_status | test/contracts/logout_login_round_trip_test.dart |
| 2026-05-12 | a2f9e1 | Home renders "Something went wrong" ErrorState after the user schedules a custom template for today. Crash repeats on every cold-start. Telemetry shows 5x widget_error_fallback with message "type… | schedule_exercise_field_types | test/contracts/schedule_exercise_field_types_test.dart |
| 2026-05-12 | 3f8a91 | Production telemetry `client_errors` shows 31 × `upsert_exercise_log` + 16 × `upsert_nutrition_log` PostgrestException 23505 over 24h. The parent summary row (workout_log_exercises / nutrition_logs)… | cloud_upsert_natural_key_contract | test/contracts/sync_onconflict_natural_key_test.dart |
| 2026-05-12 | b3c8d2 | Founder's templates "Back Day A", "Leg Day A", "Push Day" each showed 14-15 exercise rows with only 4-5 distinct names ("triplicated"). Editing the template + removing duplicates + saving brought the… | template_exercises_cloud_tail_rows | test/contracts/template_exercises_tail_vacuum_test.dart |
| 2026-05-12 | 6e1b45 | On Train screen day card (Monday 2026-05-11), Handstand Hold renders as "3 sets · 0s" and Jump Rope as "2 sets · 0s" instead of showing per-set duration chips for the durations the user logged (10s ×… | exercise_set_field_name_contract | test/contracts/timed_exercise_render_contract_test.dart |
| 2026-05-12 | a9f3d2 | Home today-card showed "BACK DAY A · DONE" (green DONE pill) for Sat May 9, but the calendar-strip's Sat May 9 cell showed only the gold today-border with NO checkmark, while earlier completed days… | workout_completion_status | "must add: test/contracts/today_card_vs_calendar_strip_same_source_test.dart" |
| 2026-05-12 | a13a01 | User asks AI coach "how was my workout today?" after partially completing a Pull-day session (logged 4 of 8 prescribed exercises — Lat Pulldown, Dumbbell Row, Hanging Leg Raise, Concentration Curl).… | today_workout_snapshot_reads_logged | "test/contracts/today_workout_reads_logged_contract_test.dart" |
| 2026-05-11 | 7ad0c3 | .claude/settings.local.json was tracked in git AND contained the Supabase anon JWT in committed permission entries; the same JWT also appears in git history (lib/core/constants/app_constants.dart… | anon_jwt_leak | "n/a — JWT rotation is a Supabase Dashboard action (user-action U-2)" |
| 2026-05-11 | 7ad0c8 | `submitWorkoutDraft` (the chat-confirmation handler for AI-coach-detected workouts) wrote `exlog_<ts>_<hash>` and `wlog_<ts>` rows directly to Hive with the *legacy* field shape (`sets_completed`, no… | chat_workout_draft_write_service | test/contracts/conversational_log_handler_uses_write_service_test.dart |
| 2026-05-11 | 7ad0c4 | 8 cron Edge Functions had verify_jwt false at the gateway AND no manual auth check at handler entry. Anyone with the function URL could trigger expensive Gemini fanout, OneSignal pushes, or DB scans… | cron_auth_gate | "n/a — Edge Function gate verified per-function via curl" |
| 2026-05-11 | 7ad0c6 | splash_screen.dart cross-account Hive leak guard was a no-op on every cold start. `HiveService.instance.userBox` is a `GuardedBox` that throws `HiveUserSession not opened` before any `openForUser` has… | cross_account_guard_on_open | test/safety/cross_account_guard_on_open_test.dart |
| 2026-05-11 | 7ad009 | delete-account Edge Function had no rate limit on the confirmation-token check. A malicious actor knowing a target's 8-char user_id prefix could repeatedly POST attempts; each fires Razorpay + DB… | delete_account_rate_limit | "n/a — Edge Function rate-limit verified via curl" |
| 2026-05-11 | 7ad0d4 | 3 deterministic-key helpers (`_nlogKeyForRestore` in sync_service, `exlogKey` in workout_write_service, `_stableItemsHash` in nutrition_write_service) computed their 8-char tag via… | deterministic_uuid_v5_keys | "n/a — covered by existing exlog/nlog migrator tests + cross-device round-trip implicit in the migrator suite" |
| 2026-05-11 | 7ad0d3 | 7 Edge Function date-key sites used UTC midnight (`new Date().toISOString().split("T")[0]`, `setUTCHours(0,0,0,0)`, etc.) for rate-limit windows, snapshot keys, and look-back cutoffs. For Indian users… | edge_function_ist_sweep | "n/a — TS Edge Function sweep; verification is via the existing morning-alert + daily-snapshot reads that already use istNow()" |
| 2026-05-11 | 7ad0d6 | 3 Edge Function input-validation gaps. (H-21) ai-proxy `scan_meal` + `cart_auditor` accepted `body.image` (base64) with NO size validation — a 50MB+ blob would forward to Gemini unbounded, burning… | edge_input_validation | "n/a — TS Edge Function input bounds; verified by deploy + manual oversize tests" |
| 2026-05-11 | 7ad0ce | Email-signup users (Supabase Auth's email flow carries no metadata) had `public.users.full_name` permanently seeded with `email.split('@').first`. The `_ensureLocalUser` upsert ran with… | full_name_email_prefix | test/contracts/full_name_backfill_test.dart |
| 2026-05-11 | 7ad038 | H-38 disposition — Path 1 (dedupe SELECT policies). Supabase advisor flagged `public_bucket_allows_listing` on storage buckets `avatars` + `banners`. Inspection found 3 duplicate SELECT policies per… | storage_policy_dedupe | "n/a" |
| 2026-05-11 | 7ad0e0 | Phase 8 cleanup deferred the remaining 21 grandfathered `catch (e) { debugPrint(...) }` patterns in `lib/core/services/` + `lib/shared/repositories/` to a follow-up batch. Per audit doc §4 H-42… | error_telemetry_funnel_completion | test/contracts/no_silent_debugprint_in_services_test.dart |
| 2026-05-11 | 7ad0c9 | 4 nutrition mutations bypassed `NutritionWriteService` (the documented sole writer per CLAUDE.md §15). `SavedMealsNotifier.saveMealPreset` / `.relogSavedMeal` / `.deleteSavedMeal` +… | nutrition_write_service_expansion | test/contracts/saved_meals_writer_to_reader_test.dart |
| 2026-05-11 | 7ad0d5 | 3 payment-stack hardening gaps. (H-18) verify-payment's `.insert()` fallback after upsert error did not catch Postgres 23505 (unique_violation), so a concurrent webhook + verify-payment race would… | payment_hardening | "n/a — TS Edge Function + Dart fire-and-forget callbacks; verified via deploy + manual race scenarios documented in CLAUDE.md §16" |
| 2026-05-11 | 7ad0cf | `SubscriptionService` payment grace window was a pure time-based `paymentInFlightUntil` ISO timestamp. Two pathologies — (a) a slow webhook past 10 min flips grace to false even though we're still… | payment_in_flight_event_based | test/subscription/payment_grace_window_test.dart |
| 2026-05-11 | 7ad0d7 | 6 schema-completeness gaps. (H-13) `_restoreCustomExercises/Foods` wrote to legacy LIST keys (`custom_exercises` / `custom_foods`) while every reader scans per-key (`custom_exercise_*` /… | phase5_schema_completeness | "n/a — schema migrations applied directly; covered by existing migrator + sync tests" |
| 2026-05-11 | 7ad0d8 | 11 invariants documented in CLAUDE.md / audit findings / prior bug retros had no automated guardrail. Future code changes could silently remove them. Examples — delete-account skips confirmation_token… | phase6_contract_tests | test/contracts/audit_2026_05_11_t1_t11_contracts_test.dart |
| 2026-05-11 | 7ad0d9 | 10+ critical end-to-end flows had no integration test coverage at all — Razorpay purchase (the entire payment stack), sign-up + onboarding traverse, delete-account (DPDP §17 irreversible),… | phase7_integration_scaffolds | test/contracts/phase7_integration_scaffolds_present_test.dart |
| 2026-05-11 | 7ad0da | Phase 8 cleanup catch-all. (Hive sequential) `HiveService.init` opened 9 shared boxes serially via a for-loop — sequential file I/O wasted 150-300 ms of cold-start time. (community_review_sheet `as… | phase8_cleanup | test/contracts/no_silent_debugprint_in_services_test.dart |
| 2026-05-11 | 7ad0ca | `ProfileScreen._performSignOut` called `supabase.auth.signOut()` + `UserRepository.clearAllData()` directly, bypassing `AuthNotifier.signOut()` and — critically — skipping… | profile_signout_auth_notifier | test/contracts/profile_signout_routes_through_auth_notifier_test.dart |
| 2026-05-11 | 7ad0c5 | promote-community-item ran as service-role with verify_jwt only at gateway level - any authenticated user could call POST functions v1 promote-community-item and trigger global writes to food_database… | promote_community_item_admin_gate | "n/a — Edge Function gate change verified via curl pre + post deploy" |
| 2026-05-11 | 7ad0cd | 3 surfaces (`userStatsProvider`, `train_screen` WeekSelector.onSelect, `swap_sheet`) snapshot `SubscriptionService.instance.isPro()` at build/init time and never reactively rebuild when the user… | reactive_subscription_three_sites | test/contracts/reactive_subscription_three_sites_test.dart |
| 2026-05-11 | 7ad054 | rank_ladder had RLS enabled with zero policies (deny-all client reads); promo_code_uses INSERT policy was scoped to roles=public with WITH CHECK=true allowing any authenticated user to insert audit… | rls_policy_cleanup | "n/a — SQL-only migration verified via MCP pre/post queries" |
| 2026-05-11 | 7ad035 | 5 SECURITY DEFINER functions had no search_path config (injection risk); coach_tool_invocations_v view ran as creator bypassing RLS; 9 SECURITY DEFINER functions granted EXECUTE to anon and… | security_definer_hardening | "n/a — SQL-only migration verified via MCP pre/post queries" |
| 2026-05-11 | 7ad0d0 | `catch (e) { debugPrint(...); }` patterns across `lib/core/services/` + `lib/shared/repositories/` logged to the device console but emitted NO Crashlytics signal + NO `client_errors` row. Production… | silent_debugprint_catch | test/contracts/no_silent_debugprint_in_services_test.dart |
| 2026-05-11 | 7ad0c7 | 4 splash-time post-auth fire-and-forget startup paths (`RankService.evaluateAndPromote`, `SubscriptionService.refreshFromSupabase`, `ScheduledWorkoutsResyncMigrator.runIfNeeded`, splash… | splash_post_auth_session_gate | test/contracts/splash_post_auth_session_gate_test.dart |
| 2026-05-11 | 7ad0d1 | `WorkoutRepository.calculateCurrentStreak()` was documented as a "read" but had side effects — consumed streak freezes for missed days and persisted the new state to Hive + cloud on every invocation.… | streak_cqrs_split | test/contracts/streak_currentstreak_is_pure_test.dart |
| 2026-05-11 | 7ad0d2 | `streak_freezes_available` + `streak_freeze_used_dates` + `streak_freezes_last_refill` had TWO independent writers — `StreakFreezeNotifier._refillIfNewWeek` (weekly +1) and… | streak_progress_service | test/contracts/streak_progress_service_concurrency_test.dart |
| 2026-05-11 | 7ad0c1 | subscriptions table had open INSERT/UPDATE/DELETE RLS policies plus nullable Razorpay columns; any authenticated user could self-grant indefinite PRO with no payment trail. | subscriptions_rls | test/contracts/no_client_subscriptions_writes_test.dart |
| 2026-05-11 | 7ad0cb | `TemplatesNotifier.saveTemplate` + `.updateTemplate` wrote `tmpl_*` rows to Hive but fired NO cloud sync — `workout_templates`/`template_exercises` rows only reached cloud via weekly full sync (up to… | templates_sync_fanout | test/sync/template_sync_gap_test.dart |
| 2026-05-11 | 7ad029 | 35 RLS policies on UPDATE / ALL had USING expressions but no WITH CHECK; meaning a user could UPDATE their own row's user_id to another user's UUID, transferring or poisoning cross-user data. | rls_with_check_completeness | "n/a — SQL-only migration verified via MCP query (0 missing post-apply)" |
| 2026-05-11 | 7ad0cc | No source-grep guardrail enforced the WriteService SoT contract for `exlog_*`, `wlog_*`, `nlog_*`, `saved_meal_*` Hive prefixes. C-8 + C-12 closed half a dozen bypass sites manually; without a… | write_service_bypass_detector | test/contracts/write_service_bypass_detector_test.dart |
| 2026-05-10 | task22 | No diagnose-docs existed for ~35 fix/feat commits since Test #11 (merge 0babf83), meaning /build-apk Gate 10 would trip on all historical commits lacking diagnose coverage. | log_client_error_payload | "n/a — backfill" |
| 2026-05-10 | d4e5f6 | Cloud user_progress default for streak_freezes_available was 2 — neither matched free baseline (1) nor PRO max (3). Fresh accounts got an inconsistent middle-ground value before the client's first… | streak_freezes | "n/a — migration + 2-line constants" |
| 2026-05-10 | e8a3b1 | Opening the AI coach screen lands the scroll position at 0 (oldest message at top). User has to manually scroll down through the entire transcript just to see the latest exchange and reach the input… | ai_coach_chat_history | test/ai_coach/initial_scroll_to_bottom_test.dart |
| 2026-05-10 | f4d6c2 | 3 cross-account isolation tests in test/auth/cross_account_isolation_test.dart were stubbed with `skip:` referencing HiveService.lastAuthenticatedUserIdKey — a constant from an abandoned Plan A… | cross_account_isolation | test/auth/cross_account_isolation_test.dart |
| 2026-05-10 | c8e4a1 | 10 PostgrestException 23503 (scheduled_workouts_template_id_fkey) errors fired in 5 seconds on the founder's account at 2026-05-10 12:45 UTC. Saturday's completed workout never reached cloud and the… | workout_completion_status | test/contracts/scheduled_workouts_fk_resilience_test.dart |
| 2026-05-10 | b3d8f9 | PRO user who burns all 3 streak freezes in week 1 gets back to 3 the following Monday — full reset, no incentive to save freezes. | streak_freezes | test/home/streak_freeze_refill_ladder_test.dart |
| 2026-05-10 | c5d2a8 | Streak pill showed only ❄ <available> (single digit), so a PRO user with 1 freeze remaining had no signal that capacity was 3 — and a user at 0 freezes had the snowflake section invisible entirely. | streak_freezes | test/home/streak_freeze_pill_xy_test.dart |
| 2026-05-10 | d9b2c5 | Saturday's locally-completed workout was overwritten back to 'planned' on every cold-start restore, because cloud still held the older 'planned' row (Bug B.1's FK violation prevented push) and… | workout_completion_status | test/contracts/restore_non_destructive_test.dart |
| 2026-05-10 | e3f7a8 | A subset of users (founder included) holds Hive `schedule_<date>` rows with `status='completed'` while the cloud `scheduled_workouts` row stays at `status='planned'` for those dates. Once Bugs B.1 +… | workout_completion_status | test/safety/scheduled_workouts_resync_migrator_test.dart |
| 2026-05-10 | a7c1e2 | Calendar checkmarks for May 5/6/7 vanished on the founder's account after restore, despite cloud workout_logs and scheduled_workouts.status='completed' being correct for those dates. | workout_completion_status | test/contracts/stale_completion_guard_test.dart |
| 2026-05-10 | a8b2c7 | _syncWorkoutTemplates used a DELETE-then-INSERT pattern for child template_exercises rows. If the DELETE succeeded but a subsequent INSERT errored mid-loop (network blip, FK constraint, payload… | workout_template_sync | test/contracts/template_exercises_upsert_test.dart |
| 2026-05-08 | b2ac5d | Multiple restore failures — _restoreXxx methods keyed Hive by cloud UUID instead of deterministic WriteService key (calendar dup explosion); _restoreUserProfile missed users.full_name so greeting… | restore_completeness | "n/a — backfill" |
| 2026-05-08 | 5a36ad | Sync stack had systemic failures — workout templates were not deduped (UNIQUE constraint added), streak pill showed cached value instead of live calculateCurrentStreak(), completed_at was overwritten… | workout_templates | "n/a — backfill" |
| 2026-05-08 | b0fd76 | Telemetry payload had no contract (any shape was accepted, breaking structured log queries); restore had a race condition where stale tmpl_* keys from earlier broken restores accumulated and caused… | error_telemetry_helper | "n/a — backfill" |
| 2026-05-07 | 5c61ed | Multiple issues — restore stack had HiveUserSession ordering bugs causing 30+ cold-start restore failures logged to client_errors; receipt chips needed per-set rendering; 5 IST drift sites remained;… | restore_completeness | "n/a — backfill" |
| 2026-05-06 | 344121 | Second cloud-side audit revealed 4 bugs — NutritionWriteService.onStateChanged hook missing, foodLogProvider missing from invalidation set, LoggingTypeRepairMigrator had unhandled edge cases, and… | sync_fanout_nutrition_domain | "n/a — backfill" |
| 2026-05-06 | 5456c4 | Multiple issues in one batch — PRO upgrade did not unlock after payment, receipt showed wrong set counts, today card had duplicate text, weight chart decimals were static, swap kept stale… | subscription_payment_grace_window | "n/a — backfill" |
| 2026-05-06 | 519075 | Cloud-side audit surfaced multiple failures — logging_type repair migrator needed systematic rebuild, razorpay 409 detection was dead code (FunctionException class), sync had IST gaps, train screen… | hive_field_name_exlog | "n/a — backfill" |
| 2026-05-06 | fe579a | ai_coach_repository called istDateStr(istNow()) causing a double IST shift — plan summaries showed wrong date and eta_next_promotion dates were off by one day. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-06 | d9b546 | PRO unlock still failed systemically across multiple code paths; logging_type repair migrator was not library-aware, repairing to wrong types for exercises present in the library. | subscription_payment_grace_window | "n/a — backfill" |
| 2026-05-06 | 979a8e | PRO upgrade did not reflect immediately in train screen; train expanded view showed 0 sets; macros displayed incorrectly — three stacked bugs from the first on-device audit. | subscription_state | "n/a — backfill" |
| 2026-05-06 | 69276a | subscriptionInfoProvider was not invalidated on cold-start subscription state writes (verify, downgrade), so PRO status changes did not propagate to the UI until next hot restart. | subscription_state | "n/a — backfill" |
| 2026-05-05 | 8a2e9b | 25 additional user-scoped configBox keys remained after the Test #10.1 hotfix (6 keys), and OneSignal player_id was never synced to cloud, causing push unsub to silently no-op on account deletion. | user_scoped_hive_keys | "n/a — backfill" |
| 2026-05-04 | 39f8ce | AI breakdown card silently disappeared after save with no user feedback, making users believe the meal was not logged. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | d9d77c | Captain voice prompts were duplicated across proactive trigger Edge Functions instead of sharing a single source, risking voice drift between triggers. | coaching_notes | "n/a — backfill" |
| 2026-05-04 | 0f8d54 | Usage counters incremented on meal save rather than on API call, so users who analysed without saving saw incorrect 'remaining' counts diverging from server rate-limit trigger. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | 617ea1 | User-scoped data (isPro flag, prediction text, localActivationAt) persisted in shared configBox and leaked to the next account signed in on the same device. | user_scoped_hive_keys | "n/a — backfill" |
| 2026-05-04 | d33c12 | No client-side account deletion UI existed for DPDP §17 compliance; users had no way to request hard erasure of their data. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | 72ea41 | No server-side hard-delete path existed for DPDP §17 compliance, so user data could not be fully erased on account deletion request. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | 40a426 | V4 plan generator had 38 cascade fallback failures (universalPool picks) because the exercise library pool was too shallow for advanced slot targets. | cross_cutting | "n/a — backfill" |
| 2026-05-04 | acdcfb | FoodLogNotifier wrote flat-totals nlog_* rows without items[] array, so cloud nutrition_log_items got 0 rows for those logs and AI coach/weekly-report saw no meal items. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | 8cc429 | Identity screen allowed proceeding without sex selection and showed wrong step label (missing 01·05 display). | onboarding_completed_at | "n/a — backfill" |
| 2026-05-04 | 26b360 | AI snapshot and usage counter resets used UTC or device-local dates instead of IST, causing midnight-crossing mismatches for Indian users. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | 4c8788 | AI coach message count was recomputed from Supabase on every render, causing unnecessary round-trips; cache key was not IST-aware, causing stale counts across midnight. | coach_interactions | "n/a — backfill" |
| 2026-05-04 | 776478 | Streak freezes, notifications inbox, and saved diet plan had no cloud backing, so reinstalling the app silently lost these surfaces for paying users. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | 89d079 | Hard-deleting an auth user CASCADE-deleted community contributions (custom foods, exercises, reviews) that should be retained pseudonymously for community signal. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | bb3acc | Morning alert Edge Function computed day-of-week and date strings in UTC instead of IST, sending wrong day greetings after 18:30 IST. | coach_interactions | "n/a — backfill" |
| 2026-05-04 | 933330 | Post-account-deletion null user_id in community rows caused promote-community-item to crash; three additional IST date escape sites wrote UTC dates to Hive. | hive_field_name_nlog | "n/a — backfill" |
| 2026-05-04 | f631f0 | Profile screen called Supabase and Edge Functions directly from widget code, bypassing the repository pattern and making the calls untestable and hard to audit. | cross_cutting | "n/a — backfill" |
| 2026-05-04 | 5d2ff1 | razorpay-webhook derived plan (monthly/yearly) from client-supplied body.plan instead of payment amount, allowing a monthly payment to grant yearly entitlement. | subscription_state | "n/a — backfill" |
| 2026-05-04 | 239999 | restoreFromCloud did not pull streak freezes, notifications inbox, saved diet plan, rank promotions, or coaching notes, so reinstalling lost all these surfaces. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | ad7664 | Streak freezes, notifications inbox entries, and diet plan were written to Hive but never pushed to cloud, so they were silently lost on reinstall. | restore_completeness | "n/a — backfill" |
| 2026-05-04 | 4c49d6 | Logo rendered at full resolution on splash without cacheWidth hint, causing unnecessarily large decode on low-memory devices. | cross_cutting | "n/a — backfill" |
| 2026-05-04 | b621c6 | Four pre-existing test failures in rank_service_test and sync_gap_test reflected outdated test assumptions from pre-Test #6 architecture. | sync_fanout_workout_domain | "n/a — backfill" |
| 2026-05-04 | 11bcfb | Four UI sites hardcoded 3000 ml for water target instead of computing it from user weight and activity, causing incorrect 100% at 3L for light users. | water_target | "n/a — backfill" |
| 2026-05-04 | 2c645c | Welcome screen displayed misleading 'no streaks' copy and app.dart showed a 'restart' error message that does not resolve any real issue. | cross_cutting | "n/a — backfill" |
| 2026-05-04 | 270ea3 | Workout restore wrote Hive keys using cloud UUIDs instead of deterministic WriteService keys, causing exercise logs to be unreadable by receipt and calendar readers. | hive_field_name_exlog | "n/a — backfill" |
| 2026-05-03 | f9acbc | MissionBriefScreen crashed or showed wrong state when navigated to in readOnly mode because the readOnly param was absent. | onboarding_completed_at | "n/a — backfill" |
