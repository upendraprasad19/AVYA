# Single-owner audit — pass 2 (2026-09-26)

Read-only. 6 parallel agents + coordinator spot-checks. Repo HEAD fafec56. Live DB = dedsavbjuwgarrhphgnl (SELECT only).
Legend: ✅ = coordinator re-verified (code or live SQL) · ◻ = agent-verified with file:line/SQL, not re-checked by coordinator.

## Corrections to pass 1
- REFUTED: "weekly-recalc rewrites total_workouts_done every Sunday" — the function is deployed but has 0 cron jobs and 0 callers (✅ live cron.job). It is dead code, not a live second writer.
- CONFIRMED: coach completions skip bookkeeping; PR type filter; longest_gap_days never written (0 for every user live); current_streak_weeks never resets; last_streak_week not synced; ~11 age copies; nutrition fallbacks; water 3000 hardcode; Recents empty; meal_ templates never sync.
- UPGRADED: calorie double-count "likely" → proven live.

## P0 — wrong numbers / data loss / money in daily use
| # | Finding | Evidence | User sees |
|---|---|---|---|
| 1 | Launch-time pull stores cloud meals a 2nd time under a UUID key; 14 of 17 readers don't filter | ✅ live: snapshot yesterday = exactly 2× on 25 & 26 Sep (your account); 6/18 user-days | Calories/macros doubled after reopening app; coach + morning alert fed doubled numbers |
| 2 | Deleted/moved meals come back — no cloud delete exists; full restore every cold start re-adds | ✅ live: 23 Sep same 1,270 kcal meal in both snacks and dinner | Deleted meal reappears; moved meal counted twice |
| 3 | Same food+qty in same slot same day overwrites the first log (content-addressed key) | ◻ code (sync_write logMeal) | 2nd chai/roti "logged" but total doesn't change |
| 4 | Free vision quota enforced only on the phone; server cap 20, no tier | ✅ live function has no PRO branch | Free users get up to 20 scans/day by signing out/in |
| 5 | ai-proxy `prediction` path: no cap, no tier check, caller-supplied system prompt | ◻ ai-proxy/index.ts:700-757 | Unlimited free Gemini (cost + abuse) |
| 6 | Account deletion leaves avatar/banner photos in PUBLIC buckets | ✅ live: 12 orphan images of deleted users | DPDP erasure incomplete |

## P1 — wrong values in specific flows
**Nutrition**
- Coach sees every meal as "Unknown" (reads food_name, never written) ◻ live 100%
- Weekly chart merges Mon+Tue, shifts days, inflated average ◻
- Target flip-flops 2197/2165 — restore recompute is local-only (skipSync) ◻ live
- 2 of 5 recompose users have target = maintenance ◻ live
- Goal switch via coach / weight log / BF assessment / server AI extraction don't recompute targets ✅
- "Protein below target 90 days" to accounts with no logs ◻ live 10 users
- Morning alert "yesterday" = 2 days ago ◻
- Progress Comparison avg calories per MEAL not per day ◻ live 680 vs 1264
- Saved meals never sync (only live writer uses unsynced key) ✅ live 0 rows ever
- Water resets to first tap after reinstall ◻ code
- Weekly chart / saved-meals list stale after most log paths ◻
- 3 different nlog key formulas; migrator doubled 7 historical cloud meals ◻ live
**Training**
- Coach-completed workouts skip total/streak-weeks/badges/rank ✅
- Completed day can revert to "planned" on restore (completed_at never stamped) ◻ live 9/37 null
- Cloud duplicate rows: workout_logs 16 dup dates (name case), workout_log_exercises 54/200 stale (24% volume inflation, 29 fake PRs) ◻ live
- PR decided ~5 ways; first-ever attempt = "New PR!"; finish banner almost never fires ✅(banner)
- Schedule status has no owner: swap can move a completed day's credit; 9 different status lists ◻
- Deleted template resurrects on next launch ◻
- Week-1 repair can regenerate plan & move plan_start (custom templates) ◻
- Deployments earned without training (live PRO phase 3, 2 deployments, 0 workouts) ◻
- Profile shows 2 different lifetime volume + service-day numbers ◻
- Cardio/distance sets saved empty ◻
- Edit Profile → Reschedule puts Phase 2+ users on Phase-1 workouts (reads a field nobody writes) ◻
- streak-guardian "streak at risk" push fires on scheduled rest days ◻
- Promotion congrats never arrive (18 dispatched, 0 delivered, EF 500; telemetry can't record why) ◻
**Account / AI**
- Google sign-in users never linked to OneSignal → no server pushes (0/6) ◻ live
- Name edited in Profile reverts on next launch ◻
- "Renew" button/push in last 7 days → server refuses "already PRO"; renewals don't stack ◻
- Expired promo still honoured at order creation ◻ live
- daily-snapshot EF writes AI-guessed diet/lifestyle/injuries into the profile ◻ live 1/3 mismatch
- Onboarding flag in 4 places; 1 live user flagged done with no profile ◻
- AI memory: 852 of 1,028 embeddings are duplicates ✅ live (retrieval crowded, cost ×6)

## P2 (latent or narrower) — highlights
Coach snapshot reads subscription from old storage (PRO with null expiry); coach identity signals never run (reads userBox['user_id'], no writer); 5 free image analyses unreachable; chat "N left" per-device; snapshot_json 5 writers no lock; PRO rule copied ~13 EF + 5 SQL (shared helper unused); 9 different "on target" rules; weekly windows 7 vs 8 days; 5 device-local Monday calcs; training-day predicate 2 + 10 inline copies; "Chatted with AI" badge unlocks without chat; boot exlog healer every login can zero sets; custom exercise/food raw writes; 2 provider build() that write; streaks rows overwritten on restore; community approvals never reach library; inbox read state lost on reinstall; +2.5 kg suggestion during deload; active workout lost on app kill; coach meal log 2 paths (lunch→snacks, fiber 0).

## P3 — hygiene
Dead code (~25 methods incl. weekly-recalc, extend_subscription, rank_ladder table, ensureComputedTargets, HealthReadService.latestWeightKg unused while copies live); doc drift (train/nutrition CLAUDE.md, snapshot_contract.yaml); users.subscription_status stale & user-writable.

## Architecture-rule health
- SoT registry is NOT valid YAML; 96/149 concepts list >1 writer (registry accepts multi-owner).
- Unregistered: total_workouts_done, current_streak_weeks, last_workout_date, current weight, phase_started_at, current_plan, plan dates.
- Rule 5 (gate()): 44 inline PRO decisions in 28 UI files vs 13 gate() sites.
- Rule 4: 12 direct Hive writes + 7 direct Supabase calls from screens/widgets.
- Hive writes: 217 put / 66 delete / 74 MigratedKey — owner map in agent notes.

## Not covered
Telegram bot repo; device Hive inspection; plan_generator internals; deload internals; RLS policies; storage writers beyond avatars; EF deployed-vs-git parity; root cause of promotion EF 500.
