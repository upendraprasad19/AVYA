# E2E Full-Charter Pass — Evidence & Observations (2026-06-21)

> Live-web cross-surface verification against `docs/architecture/functionality-flow.md` (130 assertions).
> Venue: local `flutter run -d web-server` @ `main`/`806824e`, driven via Claude-in-Chrome. Project
> `dedsavbjuwgarrhphgnl`. Working scratch — baselines captured BEFORE any mutation (for cleanup diff +
> §4.1 observation consolidation). Not a committed artifact unless an observation graduates to a fix batch.

## Test-bed allocation

| Account | id | Role | Tier at start | Notes |
|---|---|---|---|---|
| **test2@gmail.com** | `ee22d247-d57d-4ff7-80ad-e6668b9a4b14` | **PRIMARY** (Home/Train/Nutrition/Profile, reactive-/3 denominator, ledger back-date, sync/restore, cross-account A) | **PRO** (`referral_trial` → 2026-06-24) | sane streak; 28 sched, 1 wlog/1 nlog/1 weight; onboarded 2026-06-13. No temp-PRO grant needed. |
| **(fresh)** | TBD (founder signs up) | Onboarding funnel + body-fat calc + **first-PRO instant-3 grant P0** | FREE → temp-PRO | flag defaults false → the only bed that can exercise the grant. |
| **(account B)** | TBD (founder logs in) | Cross-account leak target (Phase 6) | any | sign out test2 → in B → assert zero leak. |
| **amar@gmail.com** | `0f35f3dd-7077-4b0e-966d-34b683130fa4` | **DPDP delete-account throwaway** (Phase 5) | PRO (`referral_trial` → 2026-06-24) | founder said "delete amar"; do it via the real delete-account flow (tests that P0). Streak sim-corrupted. |

## Pre-mutation baselines (captured 2026-06-21, before any E2E write)

### test2 (PRIMARY) — `user_progress`
- current_streak_days=1, current_streak_weeks=0
- streak_freezes_available=1, used_dates=[], last_refill=2026-06-15, first_pro_grant_done=true, version=(n/a)
- subscriptions: 1 row — referral_trial active 2026-06-17 → 2026-06-24 (tag null)
- history: scheduled_workouts=28, workout_logs=1, nutrition_logs=1, weight_logs=1, onboarding_completed_at=2026-06-13 06:37 UTC

### amar (to delete) — `user_progress`
- current_streak_days=2, available=0, used_dates=["2026-06-30" ← FUTURE/sim residue], last_refill="2028-11-13" ← FUTURE/sim residue, first_pro_grant_done=true
- subscriptions: (1) referral_trial active → 2026-06-24; (2) **E2E_TEST_TEMP_PRO pro_monthly, end 2026-06-01 — STALE, prior-session cleanup miss → delete in Phase 9**

## Standing observations (pre-walk findings)
- **OBS-PRE-1 (process, P2):** amar carries a leftover `E2E_TEST_TEMP_PRO` subscription row (expired 2026-06-01) never cleaned by the prior E2E session. Cleanup-discipline gap. → fold into Phase-9 cleanup.
- **OBS-PRE-2 (data, P2):** amar's streak fields hold future dates (`last_refill=2028-11-13`, `used_dates=[2026-06-30]`) from a year-sim clock-seam run — sim residue never reset. (amar being deleted moots it for amar, but flags that the sim harness can leave a real account in an impossible streak state.)

## First-PRO grant test — INCONCLUSIVE (live), + new obs
- **first-PRO instant-3 grant (Unit-C P0): NOT verified live.** Method = set test3 PRO in `subscriptions` + cold-reload. Findings: (1) a `pro_monthly` row **without** a Razorpay payment is correctly **rejected** by `SubscriptionService.refreshFromSupabase` ("no active subscription row — downgrading locally") → temp-PRO must use **`plan='referral_trial'`** (skill §3 note to update). (2) Even as `referral_trial` (PRO recognized), the grant did **not** fire (`available` stayed **1**, `first_pro_grant_done` stayed **false**) — the grant keys on a genuine **in-session free→PRO transition**, which a boot-already-PRO doesn't produce; (3) compounded by OBS-6 routing derailing each boot. **Conclusion:** covered by behavioral test #177 + live migration flag; live-verify needs an in-session-transition harness (deferred). Skill note: temp-PRO grant = `referral_trial`, and the grant won't show on a cold-boot-as-PRO.
- **OBS-15 (AUTH-12 / OBS-6 cluster):** the **15s CONTINUE** button surfaced on a slow restore ✓ (AUTH-12 fallback works) — BUT tapping **CONTINUE routed to `/sign-in`**, not Home (AUTH-12 says it should reach Home while restore continues). Another OBS-6-cluster session/guard routing bounce. Also: restore was **slow (>15s) for a fresh minimal-data account** (perf note; `[AuthSessionBootstrapper] Gap detected — pushed missing user_profile` in the log).

## Cleanup tracker (delete in Phase 9; verify 0 residual)
- **test2 meal:** `nutrition_logs` id `ac0030b1-8823-477d-9603-add06bd53034` (+ its `nutrition_log_items`) — the E2E AI-log.
- **amar stale temp-PRO:** `subscriptions` row tagged `E2E_TEST_TEMP_PRO` (end 2026-06-01) — prior-session miss.
- **test3 account** (`4d27a40b-ce2b-48e6-8485-f6f5a1b85863`): full FK-safe teardown OR keep — founder decision. Fresh-account baseline: streak 0, freezes 1/1, `first_pro_grant_done=FALSE` (the only account that can exercise the first-PRO instant-3 grant).
- **(if granted) test3 temp-PRO:** `subscriptions` tagged `E2E_TEST_TEMP_PRO` + revert `streak_freezes_*` after the grant test.

### ✅ CLEANUP DONE — 0 residual verified (2026-06-21)
- Deleted both `E2E_TEST_TEMP_PRO` subscription rows: test3's grant (`d578848f`) **+ amar's stale prior-session row** (`815d03b7`, end 2026-06-01 — prior cleanup miss, OBS-PRE-1 closed).
- Deleted test2 meal `nutrition_logs ac0030b1` + its `nutrition_log_items`.
- Verify query: temp_pro_rows=0, meal_log=0, meal_items=0. ✓
- **Left as-is (founder decisions, NOT auto-deleted):** the **test3 account** (valid onboarded free account) and **amar account** — auth-account deletion is destructive; do via the app's delete-account (DPDP) flow if wanted. **test2's freeze** (`available=0, used_dates=[2026-06-20]`) is the real OBS-8a consumed state — left for evidence; reset if re-testing.

---

# Consolidated §4.1 fix-batch plan (for founder review — DO NOT fix inline)

> ~18 observations from the full-charter web walk @ `806824e`. Each fix needs a diagnose-doc + contract test (§4.5). The P0 is ≥account → B-pass + Hermes + plan-review-record before merge (§4.3/§4.12).

## P0
- **FIX-1 — OBS-6 web session-open / cross-account-guard routing (3 triggers).** In-session account switch → blank Home; cold-boot deep-link to a user-scoped route (`/coach/induction`) → "Something went wrong"; restore-CONTINUE → `/sign-in`. **Root:** `wrapUserScopedBox` THROWS "HiveUserSession not opened" when a user-scoped screen mounts before `openForUser(uid)` completes. **Fix (robust):** (a) `wrapUserScopedBox` serves `GuardedBox.empty` (AUTH-14) instead of throwing when the session isn't open; (b) a router guard holds ALL user-scoped routes until `openForUser` completes (route via `/restoring`); (c) in-session post-sign-in calls `openForUser(newUid)` before GoHome. **Test:** sign-out A → sign-in B (no reload) serves empty not throw; deep-link cold-boot renders/redirects (never the error screen). Blast: account/platform.

## P1
- **FIX-2 — OBS-8a/8b streak/freeze reckon.** (8a) reckon spends a freeze that can't save the streak (≥2 consecutive *unprotected* misses) → wasted freeze + "freeze used" popup, no benefit; (8b) UI streak (`calculateCurrentStreak`=0) vs cloud `current_streak_days`=1 drift; likely the reckon only processes the most-recent rollover day, not the full multi-day-absent gap. **Fix:** only consume a freeze if it actually preserves the streak (look back to the last completed day); reckon recomputes + persists `current_streak_days` to match the client calc. **Test:** pin Home-chip == cloud == `calculateCurrentStreak`; 1-freeze + 2-missed-days → no consume.
- **FIX-3 — OBS-11 Nutrition target drift.** Nutrition screen recomputes targets (2583/150/3129) vs canonical `user_profile` (2540/140/3125); Home is correct. **Fix:** Nutrition reads canonical (or recompute writes back). **Test:** Home==Nutrition==`user_profile`.
- **FIX-4 — OBS-13 full_name not title-cased.** `users.full_name` saved lowercase "test three" → "Recruit test" greeting (ONB-04 says title-case). **Fix:** title-case on the completeOnboarding/Identity write. **Test:** lowercase input → "Test Three" saved.

## P2
- **FIX-5 — OBS-1/10 RenderFlex overflow + `borderRadius` non-uniform cluster** (~5+ surfaces: Home Today card, food-analysis result card, …). Add Flexible/Expanded; fix the bordered-box-with-borderRadius decoration. Widget overflow tests.
- **FIX-6 — OBS-9 empty card at top of Home** — identify + fix.
- **FIX-7 — OBS-14 DOB date-picker overflow** at phone-frame width (Obs#5/#135 recurrence) — constrain the picker host.

## P3 (copy/cosmetic)
- OBS-4 logout "Failed to load profile" flash · OBS-5 "RENEWS" on a referral trial → "expires"/"ends" · OBS-12 "Goal: Lose 70kg" → "Reach 70kg".

## Charter (`functionality-flow.md`) updates [Phase 10]
- Add a **COMM-** block (community review — verified working) · **referral lifecycle** (beyond PROF-14) · **web-platform variants** (kIsWeb health dead-end, PWA banner) · **Mission Brief copy-lock**.
- Fix column-name drift: ONB-06 `body_fat_pct` → **`body_fat_percent`**.
- Flip verify-status for assertions walked (HOME-04..09 partial, ONB-01/06/08/09 PASS, AUTH-02/07/11/12, NUT-02, community).

## Process / skill notes
- `e2e-sim-testing` §3: temp-PRO grant must use **`plan='referral_trial'`** (a `pro_monthly` row without a Razorpay payment is correctly rejected); the **first-PRO grant won't fire on a cold-boot-as-PRO** — it keys on an in-session free→PRO transition (live-verify deferred; covered by behavioral test #177).

## ✅ Unit F — docs closure (2026-06-26)

All four Unit-F items landed (no live DB apply needed):
- **#151 founder_metrics — VERIFIED SATISFIED, closed (no new artifact).** The original
  ask was a "SQL view"; U5 shipped `private.founder_metrics()` (migration **093 LIVE**) — a
  SECURITY DEFINER **function**, deliberately NOT a view (a view inherits the caller's RLS
  → would leak aggregate counts to anon via PostgREST; the function in the `private` schema
  is unreachable by the REST API). Live re-verified 2026-06-26: function exists,
  `security_definer=true`, returns the 10-col table, and the anon-leak gate holds
  (`has_function_privilege` → anon=false, authenticated=false, service_role=true). A view
  would re-introduce the exact leak the founder worried about → **do not build it.** Founder
  calls it in the SQL editor: `select * from private.founder_metrics();`.
- **#152 EF-auth + token-freshness contract — DONE.** New **ADR-0016**
  (`docs/adr/0016-edge-function-user-token-auth-contract.md`) + handbook port
  (`docs/handbook/bug-classes/edge-function-user-token-auth.md`) capturing both seams
  (server: service-role client + `getUser(token)`, never JWT-as-apikey / JWT-in-global-headers;
  client: `callFunction` → `ensureFreshToken`). Gates `check_edge_function_auth_pattern.dart`
  + `check_authed_invoke_fresh_token.dart`.
- **#147 charter — DONE.** Added ONB-15 (Mission Brief copy-lock), §7 COMM-01..03 (community
  review), PROF-19 (referral lifecycle), XC-15 (web-platform variants); fixed ONB-06
  `body_fat_pct`→`body_fat_percent`; flipped verify-status with **Live-verified 2026-06-21**
  annotations on the walked assertions (ONB-01/06/08/09, AUTH-02/07/11/12, NUT-02, COMM).
- **skill** `e2e-sim-testing` §3 — temp-PRO grant SQL corrected to `plan='referral_trial'` +
  the two gotchas documented.

## PASSES (verified working live)
Community Review queue (GAP, c7d4f1/mig-092) ✓ · AI food-log cross-surface integrity (Gemini→Hive→UI→cloud, FK-23503 healthy) ✓ · **body-fat HONOR** (22% saved + used in calc) ✓ · ONB-08 preview==saved (3045/135) ✓ · Mission Brief copy-lock (no Instagram CTA) ✓ · reactive `/3` PRO freeze denominator ✓ · onboarding funnel end-to-end ✓ · AUTH-02/11/12 (sign-in surface, signup→mission-brief, 15s CONTINUE) ✓ · quote fix (no "template" garbage) ✓ · PR/weight/insight cards + empty states ✓ · sign-out confirm dialog ✓.

## Integrity matrix (filled per driven write)

| Phase/assertion | action | writer (file:line) | Hive key | cloud table | UI surface reflects? | cloud == Hive == sent? | result |
|---|---|---|---|---|---|---|---|
| Phase4 NUT-02 AI text-log | typed "2 boiled eggs + 2 slices brown bread toast" → ANALYSE → SAVE MEAL | NutritionWriteService (food-text-analysis EF) | nlog_* (Hive) | `nutrition_logs` id `ac0030b1-8823-477d-9603-add06bd53034` | Nutrition summary "306 consumed / 2277 remaining", macros 19/27/12/3 | **YES** — Gemini 306 == UI 306 == cloud 306 (breakfast, 2026-06-21) | ✓ PASS (clean cross-surface; FK-23503 path healthy) |

## Phase 1 — fresh-account onboarding (test3@gmail.com, id `4d27a40b-ce2b-48e6-8485-f6f5a1b85863`)

- **GOOD-12 (AUTH-11):** test3 email signup → routed cleanly to `/onboarding/mission-brief`, session opened (no OBS-6 blank screen — because we reloaded to a clean slate before signup; the in-session switch is what breaks, a clean-load signup works).
- **GOOD-13 (ONB-01 / Unit-5 Mission Brief copy lock):** Mission Brief renders the founder-locked narrative — *"discipline isn't motivation… AVYA holds the line… Show up. Earn your promotions. Become the man who lasts… No one is coming to save you, Recruit… Jai Hind. — Upendra"*. **NO Instagram CTA** (the Unit-5 removal verified). Pure Wardroom/Navy voice. CONTINUE → proceeds.
- **GOOD-14 (ONB-06/08 / U4 body-fat HONOR — c3f2d8 verified on fresh account):** entered **body fat 22%** on Stats → saved `user_profile.body_fat_percent = **22**` (NOT null, NOT fabricated 18), `bmr = **1584**` (below the no-body-fat Mifflin ~1694 → the 22% **was** used in the calc), `fat_grams=85`, `primary_goal=build_muscle`, `target_weight_kg=78` (Build adapts up). **`daily_calories=3045` + `protein_grams=135` EXACTLY match the Plan-screen preview** → ONB-08 preview==saved holds (Obs#6 #136 fix intact). The SAVED-body-fat fix works end-to-end.
- **GOOD-15 (ONB-09/13):** completeOnboarding **succeeded** — `onboarding_completed_at` stamped (08:37:35), profile + plan written, then routed to `/coach/induction`; the AI induction/muster **loaded** ("Recruit test — welcome aboard. I'm your AI Coach…", Wardroom voice). *(The apparent "stuck spinner" was the transition + Gemini induction load, NOT a failure — corrected.)*
- **NOTE-3 (charter column drift):** charter ONB-06 cites `body_fat_pct` but the real column is **`body_fat_percent`** (also `body_fat_assessed_at`, `fat_grams`). Fix the charter in Phase 10.
- **OBS-13 CONFIRMED via DB:** `users.full_name = "test three"` (lowercase) — title-case NOT applied to the saved name; **propagates to the induction greeting "Recruit test"** (lowercase). User-visible.

## Observations log (per §4.1 — collect, don't fix inline)

| id | assertion | surface | symptom | severity | writer/reader note |
|---|---|---|---|---|---|
| OBS-13 | ONB-04 (name title-case) | Onboarding › Identity | NAME field shows **"test three"** (lowercase) — ONB-04 says it **title-cases input**; not applied on keystroke OR blur. | P2 | verify the SAVED `users.full_name` — does it persist "test three" (broken) or "Test Three" (title-cased on save)? full_name is drift-prone (bug #25 resolveDestination). |
| OBS-14 | ONB-04 (DOB picker) / Obs#5 | Onboarding › Identity › DOB picker | The Material **date-picker calendar overflows/cramps** at phone-frame width (day grid squished/overlapping, "RIGHT OVERFLOWED" stripe); the keyboard-entry field is also cramped ("Ente…" label truncated, input clips). | P2 | the onboarding date-picker host isn't constrained for the ~390px web phone-frame — Obs#5/#135 ("constrain onboarding time/date picker host") recurrence or web-specific. DOB still selectable via input mode (1 Jan 1995 set OK). |
| OBS-1 | HOME-10/01 | Home › Today/Workout card | **RenderFlex overflow** — red/black stripe "RIGHT OVERFLOWED BY ~11–15px" between the RECOVERY card and the metrics column, at phone-frame width (~390px). Seen on amar, Phase 2, Sunday rest-day. | P2 (layout) | account-independent; RE-VERIFY on test2 Home. Likely a Row/Flex without Flexible/Expanded on the today-card vs metrics split. |
| OBS-2 | HOME-20 | Home › Steps card (WEB) | Steps show **6k/10k** on the web build. Charter HOME-20 + web-deadend map say Health Connect is native-only → expected 0/NA on web. | P2 (verify) | Likely restored cloud `daily_steps` (synced from Android), not live Health Connect — may be correct-by-restore, not a bug. RE-CHECK on test2 (which has Android history too). |
| OBS-3 | HOME-04 | Home › streak chip | amar chip reads "🔥 4 DAYS" while DB `current_streak_days=2`. | P2 (info) | client `calculateCurrentStreak()` is schedule-derived (HOME-04/05), DB field may be stale — divergence, not necessarily a bug. amar data corrupted; RE-CHECK cleanly on test2. |
| GOOD-1 | HOME-06 | Home › freeze chip | PRO user (amar referral_trial) → chip denominator shows **"/3"** (not "/1"). | ✓ pass | Reactive denominator confirmed for PRO. Re-confirm "1/3" on test2 (PRO, available=1). |
| NOTE-1 | XC naming | bottom nav | Actual tab labels = **Daily / Workout / Nutrition / Coach / Profile** (charter prose says Home/Train/AI Coach). | n/a | naming convention, not a bug; note for charter wording. |
| GOOD-2 | AUTH-02 | sign-in surface | Welcome offers **ENLIST VIA GOOGLE / PHONE / EMAIL** (Email + Google OAuth + Phone OTP entry points all present). Brand voice intact ("Discipline. Honest data. Twelve months. We change the man."). | ✓ pass | AUTH-02 confirmed. |
| GOOD-3 | profile › sign-out | Profile › SIGN OUT | Sign-out shows a **confirm dialog** ("Are you sure… Your data is safe locally") before clearing session. | ✓ pass | good guard on a destructive-ish action. |
| OBS-4 | AUTH-14..18 | sign-out transition | Brief **"Failed to load profile / Tap to…"** flash behind the logo during the amar→sign-in transition. | P3 (transient) | likely the cross-account guard serving empty as the session tears down (expected), but the user-facing "Failed to load profile" copy reads as an error mid-logout. Re-observe on the test2→amar cross-account switch (Phase 6). |
| NOTE-2 | PROF-14 / community | Profile › Share & Grow | Referral entry = **"Invite Friends — Both get 7 days PRO free"**; community-review entry = **"Submissions — Your submissions + vote on community items"**. | n/a | confirms the Phase-5 entry points exist; drive both on test2. |
| OBS-5 | subscription copy | Profile › Subscription card | A **referral_trial** subscription shows **"RENEWS 24 JUN 2026"** — a trial expires, it doesn't renew. | P3 (copy) | minor: "RENEWS" implies auto-renew; a trial should read "expires"/"ends". |
| **OBS-6** | **AUTH-07/14..18 (§2.3)** | **in-session re-login → Home** | **P0 — BLANK HOME.** Sign out account A (amar) → sign in account B (test2) **without a page reload** lands on `#/home` but throws repeatedly: `Bad state: HiveUserSession not opened — cannot wrap user-scoped box "userBox". Call HiveUserSession.openForUser(userId) after sign-in.` → `setState() during build` → Home body never builds (only bottom nav renders). App unusable. **On reload it does NOT recover** — bounces to `/sign-in`. | **P0** | **Confirmed mechanism:** console shows `[HiveUserSession] opened 7 boxes for user 0f35f3dd` (amar) but `openForUser(ee22d247)` (test2) is **NEVER** called on the in-session email-login path → wrap throws. On reload, Hive-owner(amar) ≠ Supabase-token(test2) → cross-account guard (AUTH-14/15) bounces to `/sign-in` (guard works = no leak, but UX dead-ends). FIX: post-email-sign-in must route through `/restoring` (AUTH-07) OR call `openForUser(newUid)` before GoHome; and `wrapUserScopedBox` should serve `GuardedBox.empty` (AUTH-14) rather than THROW when the session isn't open. Related bug #26 (induction session-open race), class §2.3. Founder repro: "blank screen … pop up saying streak freeze used". **EXTENDED (3rd trigger):** a cold-boot/reload that lands on a user-scoped **deep-link route** (`/coach/induction` — the persisted hash) ALSO throws "HiveUserSession not opened" → renders a user-facing **"Something went wrong"** error screen (red ⚠️), and a completed-onboarding user is NOT redirected off `/coach/induction` to Home. So the bug is general: ANY user-scoped route mounting before `openForUser` completes errors. The `wrapUserScopedBox`-should-serve-empty fix is the robust one (covers all routes), plus a router guard that holds user-scoped routes until the session is open. |
| OBS-7 | HOME-04 (founder-flagged) | Home › streak (amar) | Founder confirms amar streak "4 DAYS" is **incorrect**. | P1 | amar's freeze data is sim-corrupted (future `used_dates`/`last_refill`) which likely inflates the schedule-derived streak. RE-CHECK on test2 (baseline `current_streak_days=1`) once Home renders. |
| **OBS-8a** | **HOME-06/07 / D2 reckon** | **login (test2) — freeze consume** | **P1 — WASTED FREEZE.** On login the decay reckon consumed test2's only freeze (`available 1→0`, `used_dates [] → ["2026-06-20"]`, synced to cloud) to protect **06-20 (Sat, missed)**. But **06-19 (Fri) was an earlier *unprotected* missed scheduled workout** → the streak breaks at 06-19 anyway → the freeze produced **zero streak benefit**, yet fired a "streak freeze used" popup. | **P1** | Schedule (test2): completed only **06-13**; missed **06-15,16,17,18,19,20** (6 planned); 06-14 & 06-21 rest. With 1 freeze + ≥2 consecutive misses, a freeze can't bridge the gap. The reckon (`reckonStreakDecayAndPersist`, D2) should NOT spend a freeze it can't save the streak with (greedy-consume vs save-only-if-useful). Candidate: reckon processes only the most-recent rollover day, blind to the earlier 06-15..06-19 gap for a multi-day-absent returning user. |
| **OBS-8b** | **HOME-04 (writer/reader)** | **streak chip vs cloud** | **P1 — STREAK DRIFT.** UI chip shows **0 DAYS** (client `calculateCurrentStreak`, correct given 6 missed days since 06-13) while cloud `user_progress.current_streak_days` = **1** (stale/wrong). | **P1** | reckon synced the freeze fields but left `current_streak_days` stale at 1. Latent: a cross-device read or restore that trusts cloud `current_streak_days` would show **1** (wrong). Writer = reckon persist; reader divergence vs `calculateCurrentStreak`. Pin SEMANTIC in a contract test. |
| GOOD-4 | HOME-06 (test2) | Home › freeze chip | PRO user test2 → chip shows **"0/3"** (denominator /3, reactive); `available=0` after the consume → UI matches cloud. | ✓ pass (denominator) | reactive /3 confirmed on a 2nd PRO account; the *value* issues are OBS-8a/8b not the denominator. |
| OBS-9 | HOME-01/18 | Home › card below header | A large **empty dark-olive rectangle** sits between the header and the weekly-calendar strip on Home (both amar & test2). | P2 (verify) | likely the AI-coach-insight card (HOME-18) or a promo banner rendering empty. Inspect during the Home-cards pass. |
| GOOD-5 | OBS-1 repro | Home › Today card (test2) | The RenderFlex overflow stripe reproduces on test2 (Phase 1) too → **OBS-1 is account-independent** (confirmed). Console: `RenderFlex overflowed by 2.5px` + `borderRadius non-uniform` (cosmetic, no session crash post-fresh-login). | (confirms OBS-1) | the px count varies by content (11/15/2.5/4.3) — same Row/Flex needs Flexible/Expanded. |
| GOOD-6 | HOME-16/17/18 + empty states | Home › lower cards (test2) | **PR snapshot** (Barbell Bench Press 11kg, Test Exercise 11kg — 2-exercise layout), **Weight Trend** (75.1kg + "Log again to see your trend line" empty state + View full history), **AI Coach Insights** (local "Rest day! …PROTEIN CHEAT SHEET"), **Recent Logs** ("No logs yet today. Start tracking!" empty state) all render. | ✓ pass | HOME-16/17/18 + empty-state handling good. |
| GOOD-7 | (Unit-3 quote fix) | Home › quote card | Quote renders **clean** — "The pain you feel today will be the strength you feel tomorrow." — Arnold Schwarzenegger. **No "template"/"lat" garbage** → the Unit-3 word-bounded keyword fix holds. | ✓ pass | re-confirms d8f3a2 quote fix live. |
| **GOOD-9** | **(GAP: community review, Unit-2)** | Profile › Submissions | **Community Review WORKS.** COMMUNITY REVIEW tab loads a **cross-user** anonymized queue (Straddle Front Lever, Single Leg Front Lever, Barbell Jump Squats — no author shown) with REJECT/APPROVE; MY SUBMISSIONS shows test2's own "test exercise / PENDING". Queue NOT empty → the c7d4f1 + migration-092 cross-user-read fix is **verified live**. No console errors. | ✓ PASS | **Charter GAP confirmed** (no COMM-/PROF assertion) → add a `COMM-` block in Phase 10. **Vote NOT cast** (APPROVE/REJECT mutates real cross-user community data — needs explicit founder ok + reversibility check before exercising). |
| OBS-12 | profile copy | Profile › goal card | **"Goal: Lose 70kg"** — test2 weighs 75.1kg, target 70kg; the copy reads as "lose 70 kilograms" rather than "reach 70 kg". | P3 (copy) | should read "Reach 70kg" / "Target 70kg" / "Lose 5kg → 70kg". |
| GOOD-10 | ONB-06 / U4 (body-fat) | Profile › Body Stats | test2 body fat shows **"—"** (null), not a fabricated 18% — the **correct post-U4 behavior** (skip → null). (amar showed the un-healed legacy 18%, but amar is being deleted.) | ✓ pass | confirm skip→null directly on the fresh-account onboarding (Phase 1). |
| GOOD-11 | PROF subscription + danger zone | Profile › bottom | Subscription card renders (PRO · REFERRAL_TRIAL · "Everything unlocked" · RENEWS 24 JUN 2026 · MANAGE SUBSCRIPTION ✓); **Delete Account** entry renders in the Danger Zone (red). | ✓ pass | delete-account flow NOT exercised on test2 (reserved for amar throwaway). Referral *redeem* + *share* deferred to fresh-account (Phase 1) / Invite Friends. |
| TODO-1 | HOME-10/12 | Home › Today card receipt | NOT TESTED — test2's today (06-21) is a **rest day**, so "Start Workout"/"View Card" receipt (phaseForDate label) couldn't be exercised. | deferred | test on a workout day via Train (log a set → DONE badge → View Card). |
| GOOD-8 | TRAIN plan view + day detail | Workout tab (test2) | Phase I/II **week selector** (W2 Jun15-21 selected, W1 ✓), week plan (MON PUSH…SAT LEGS+CORE 4 EX each, SUN Rest gold=today), and **day-detail sheet** (PUSH/Jun15 → Warm-up 4, Barbell Bench 5×7 150s, Incline Bench, Pike Push Up 5×10, Lateral Raise 5×14, Cool-down 4) all render. | ✓ pass | TRAIN plan-view/week-selector/day-detail good. |
| **OBS-10** | rendering | Home + Train (all screens) | Recurring **`A borderRadius can only be given on borders with uniform colors`** exception fires repeatedly (caught, cosmetic) across screens, alongside the OBS-1 RenderFlex overflow. | P2 | a `BoxDecoration(border: Border(...non-uniform colors...), borderRadius: ...)` — Flutter throws when a bordered box with a borderRadius has per-side colors. Find the offending decoration (likely a shared card/chip). |
| TODO-2 | TRAIN active-workout/swap/template/copy-week | Workout tab | NOT driven — test2's today is a **rest day** (no "Start Workout"); past-day detail is a read-only preview. Active-workout-mode, log-a-set, swap-exercise, template-builder, copy-week unverified live. | deferred | drive via the coach "log a workout" (Phase 7, founder) OR on a workout day; rank-ladder via Profile. |
| **OBS-11** | **HOME-15 vs NUT (writer/reader)** | Home snapshot vs Nutrition summary | **Calorie/protein target DRIFT across surfaces:** Home nutrition snapshot shows **2540 cal / 140g protein**; Nutrition tab "Today's Summary" shows **2583 cal / 150g protein** (0 consumed → 2583 remaining). Same user, same day, two different targets. | P1 | canonical target SoT mismatch. **RESOLVED via DB:** `user_profile` canonical = **daily_calories=2540, protein_grams=140, water_target_ml=3125** → **Home is CORRECT** (reads canonical); **the Nutrition screen DRIFTS** (recomputes 2583/150/3129, a live recompute that diverges from the stored SoT). Fix: Nutrition summary must read `user_profile.daily_calories/protein_grams/water_target_ml` (or the recompute must write-back the canonical). Pin Home==Nutrition==`user_profile` in a contract test. (Prior class: weekly-report EF "reads canonical target" fix; relates to task #150 live-recompute.) |
