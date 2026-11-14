# Qualification Exam — Full Plan Review + Complete 3-Plan Arc

## Context

We brainstormed and specced a **qualification-exam** feature: consistency still promotes you, but each rank's vetted offline MCQ exam **confirms** it (brevet/"Acting" model). Spec: `docs/architecture/qualification-exam.md` (committed `7328c99`). I'd written **Plan 1 (engine)** only and recommended authoring Plans 2–3 after Plan 1 lands; you asked to (a) review Plan 1 for foolproofness from all angles, (b) explain why 2–3 weren't done, and (c) see the *entire* plan before deciding.

This document is that: a hardened review of Plan 1, the answer on 2–3, and the full task-level arc of all three plans. The detailed Plan 1 task doc lives at `docs/superpowers/plans/2026-06-04-qualification-exam-plan-1-brevet-engine.md`; the revisions below supersede it (I'll fold them in on approval).

**Why 2 & 3 weren't authored yet:** a deliberate sequencing call — author them against the engine's *real* seams (post-Plan-1) to avoid rework, not an oversight. Your instinct to see all three first was right: the review found a **Plan 1 ↔ Plan 2 coupling** (the clamp's "missing-content" rule needs Plan 2's bank data) that's only visible with the whole arc in view. It's now resolved below.

---

## Part A — Foolproofness review of Plan 1 (engine)

### What's verified solid (audited against source)
- **No writer bypasses the clamp.** Exhaustive grep: `current_rank_code` has exactly 4 writers — client `evaluateAndPromote` (cloud + Hive), the cron, and one-time migration 075. All are monotonic-guarded (`shouldPromote` / `winner.ordinal > currentOrdinal`). Only extra: a **dev-only** sim reset (`simulation_service.dart`) — acceptable.
- **Clamp insertion point is correct** — inside `evaluateAndPromote` after the behavioral ceiling resolves (`rank_service.dart:86-87`); it lowers the ceiling fed to the existing monotonic guard, so it can never demote. The cron mirror at `evaluate-rank-promotions/index.ts:132` is symmetric.
- **Plumbing confirmed:** `HiveService.instance.configBox` getter exists (and already backs kill-switches like `disable_phase_reconciler`); `istNow()` exists; `rank_ladder.ordinal` exists; `_restoreUserProfile` merges *all* non-null cloud columns so the new column round-trips with no restore edit.

### Gap 1 (SUBSTANTIVE) — clamp ignores the "missing-content" rule → "Acting SubLt" trap
Spec §4.2 says ranks **without published exam content are pass-through** (never gate). Plan 1's clamp was a pure `min(behavioral, passed+1)` — content-blind. With content only SD1–MCPO, a user who passes MCPO would clamp to **Acting SubLt forever** (no SubLt exam exists to confirm it). **Fix:** the clamp takes a **content-frontier** ordinal; above the frontier it's pass-through:
```
effective = passedOrdinal >= frontierOrdinal ? behavioral
                                             : ladder[min(behavioral.ordinal, passedOrdinal + 1)]
```
- **Plan 1** hard-codes `kHighestExamContentOrdinal = 5` (MCPO) as a constant and passes it to `clampToConfirmed` (client + server).
- **Plan 2** makes the frontier **data-driven** (derived from `exam_questions`), replacing the constant before rollout. This is the coupling that justified seeing the whole arc.

### Gap 2 (SUBSTANTIVE) — backfill goes stale between Plan 1 and rollout
Plan 1's migration backfilled `highest_passed = current−1` at *apply* time. But the flag stays OFF for weeks (until Plan 3), during which users keep climbing unclamped. At flag-flip the backfill is stale-low → clamp would cap far below their (monotonic, non-demoting) `current_rank_code` → user stuck "Acting <high>" needing many exams. **Fix:**
- **Plan 1 migration adds the columns only** (nullable, no backfill — the value is unused while the flag is off).
- **The §11 retroactivity backfill runs at ROLLOUT** (Plan 3, immediately before the flag flips), **monotonic-raise** (`SET highest_passed = GREATEST-equivalent of existing vs current−1`), re-derived from *then-current* ranks.
- The client **boot reconciler** (Plan 1) complements it per-user offline (also monotonic-raise from current−1).

### Gap 3 (SUBSTANTIVE for your OTA choice) — seed pattern is bundle-only, not OTA
You chose "OTA refresh — fix a wrong question without an app release." But `seed_service.dart` is **bundle + version-gated only** (re-seeds from the APK asset on version bump — i.e., needs an app release). exercise_library has **no cloud-pull**. **Fix:** Plan 2 adds a real cloud-pull (`SyncService.refreshExamBankIfStale()`) that fetches `exam_questions`/`exam_lessons` rows newer than the local version and upserts the box — the actual OTA capability, on top of the bundle seed for offline first-run.

### Minor gaps (fixed in the arc)
- **G4 — reconciler call-site** now pinned: wire `RankConfirmationReconciler.reconcile()` at `restoring_screen.dart:~333` (right after `PhaseProgressReconciler`, awaited, post-restore). Note: `evaluateAndPromote` also runs fire-and-forget at `splash_screen.dart:165` *before* restore — at most a one-cycle promotion delay on the first post-rollout boot; never a demotion (monotonic). Acceptable.
- **G5 — gate-coverage test:** `gate_coverage_test.dart` fails if a `feature*` key exists with no `gate()` callsite. So `featureRankExamGraded` is added in **Plan 3 only** (with its gate), never in Plan 1.
- **G6 — Acting not distinguished** in `getLadder` / `rank_chip_full_width` / cron ceremony text. Plan 3 adds the "ACTING" modifier; ceremony Acting-awareness is an optional Plan 3 polish.
- **G7 — attempts key:** `rank_exam_attempts` uses a **client-minted v4 UUID** per attempt (Hive key + cloud `id`, `onConflict: 'id'`) — append-only, no cross-user collision (the collision class that hit migrations 082/083 was *deterministic* ids; random ids are safe).
- **G8 — dev sim reset** writes `current_rank_code` directly (bypasses clamp) — dev-only, documented, acceptable.

---

## The entire plan (3 sequential plans)

### PLAN 1 — Brevet engine + state *(revised)*
Flag-gated (default OFF) so it's a no-op until rollout. Tasks (full code in the existing Plan 1 doc, with these revisions):
1. **Feature flag** `RankFeatureFlags.isExamGateEnabled` (configBox `exam_gate_enabled`, default off; `debugExamGateOverride` test seam) — mirrors existing kill-switch pattern.
2. **Migration 084 — columns only** (`user_profile.highest_passed_exam_code` FK `rank_ladder` + `highest_passed_exam_at`). *No backfill* (moved to rollout, Gap 2).
3. **Pure helpers** in `rank_service.dart`: `clampToConfirmed(behavioral, passedCode, frontierOrdinal)` *(now frontier-aware, Gap 1)* + `nextPassedExamCode` (monotonic). Const `kHighestExamContentOrdinal = 5` (MCPO).
4. **Wire clamp** into `evaluateAndPromote` (flag-gated; reads profile `highest_passed_exam_code`; passes `kHighestExamContentOrdinal`).
5. **`recordExamPass(rankCode)`** seam (monotonic; Hive-first → upward sync) + `highestPassedExamCode()` + `isCurrentRankActing()`. Add the two columns to `sync_profile.dart _syncUserProfile` payload (~:110).
6. **`RankConfirmationReconciler`** boot backfill (monotonic, flag-gated), wired at `restoring_screen.dart:~333` (Gap 4).
7. **Server clamp** — `clampToConfirmed` in `_shared/rank_engine.ts` (frontier-aware) + cron wiring (env `EXAM_GATE_ENABLED`, reads column); deploy host-shell, leave env unset; parity source-grep test.
8. **SoT** concept `rank_exam_confirmation_monotonic` + glossary.
9. **Verify** — analyze + rank test suite + confirm flag OFF.

New tests: `rank_exam_clamp_behavioral_test` (incl. frontier pass-through cases), `rank_exam_confirmation_writer_to_reader_test` (Hive), `rank_clamp_parity_test`.

### PLAN 2 — Question bank + sync (offline + OTA) + content seeding
1. **Migration 085** — `exam_questions` + `exam_lessons` (world-read RLS: `FOR SELECT USING(true)`, mirroring `008` for exercise_library) + `rank_exam_attempts` (user-scoped RLS: `FOR ALL USING(auth.uid()=user_id)`). Pair `applied_migrations.json`.
2. **Bundle seed** — convert `docs/content/qualification-exam/*.md` drafts → `assets/data/exam_questions.json` + `exam_lessons.json`; add `_seedExam()` + version const to `seed_service.dart` (mirror `_seedExercises`); add **shared** boxes `examQuestionsBox` + `examLessonsBox` to `hive_service.dart`.
3. **Seed cloud** — migration 086 seeds cloud bank from the same JSON, deterministic UUID v5 (mirror `074`), so cloud is the OTA + frontier source of truth.
4. **OTA cloud-pull** *(Gap 3)* — `SyncService.refreshExamBankIfStale()`: fetch `exam_questions`/`exam_lessons` where `version >` local, upsert boxes; call on boot/app-resume. A bad question is now fixable via a data update.
5. **Content-frontier data-driven** *(Gap 1)* — `ExamBankRepository.highestRankWithContentOrdinal()` from `examQuestionsBox`; replace Plan 1's `kHighestExamContentOrdinal` constant at the clamp call sites (client); server derives from an `exam_questions` count query. Update parity test.
6. **Attempts write+sync** — `RankExamWriteService` (client-minted UUID; Hive-first `examAttemptsBox` *(user-scoped)* → `unawaited(syncExamData())`) + `sync/sync_exam.dart` (`_syncExamAttempts` `onConflict:'id'` + `_restoreExamAttempts`); register restore in Step B (`sync_service.dart:1086`).
7. **SoT** concepts `exam_bank_sync` + `exam_attempt_log`; restore round-trip + writer→reader tests.

### PLAN 3 — Exam + Learn UI + gating + ROLLOUT
1. **Feature key + gate** `featureRankExamGraded` in `app_constants.dart` + the `gate()` callsite in the Take-Exam action (PO+), `onFree: showPaywallSheet` *(Gap 5)*.
2. **Profile entry** — `SectionHeader` + `ProfileRow` "Qualification Exam" in `profile_content.dart`; `GoRoute 'qualification-exam'` in `app_router.dart` (profile shell branch).
3. **`QualificationExamScreen`** — pill-toggle + `IndexedStack` (mirror `submissions_screen.dart`), tabs Take Exam / Learn.
4. **Take Exam** — `ExamBankRepository.draw(rankCode, ~10)` → MCQ flow → client grade → ≥80% calls `RankService.recordExamPass` (+ celebration); fail → explanations for misses + short cooldown (`examAttemptsBox` `last_failed_at`). Shows only `highest_passed+1`'s exam (gated). Wardroom primitives; loading/error/empty.
5. **Learn** — lessons reader + unlimited mock exams (free, all ranks, full reveal).
6. **Acting rendering** *(Gap 6)* — inject "ACTING" modifier in `rank_chip_full_width.dart`, `ward_rank_pill.dart`, `getLadder`/`RankLadderScreen` when `isCurrentRankActing()`.
7. **Notification nudge** — on a newly-Acting promotion, `NotificationInboxService.record(...)` "take the exam."
8. **ROLLOUT** *(Gap 2)* — migration 087: monotonic-raise backfill `highest_passed = max(existing, current−1)`; then flip flags together (client `configBox['exam_gate_enabled']=true` via dev panel/RemoteConfig + Edge secret `EXAM_GATE_ENABLED=true`). Add nested `lib/features/exam/CLAUDE.md`, link spec in root `CLAUDE.md §7`, update spec status.
9. **Verify** — full suite + the e2e-sim-testing flow (take an exam end-to-end on a temp-PRO account).

---

## Sequencing & rollout
Execute **1 → 2 → 3** with a review checkpoint between each (subagent-driven recommended). The gate stays **OFF** through Plans 1–2 and most of 3; the **only** moment behavior changes for real users is Plan 3 Task 8 (rollout), which you trigger after verifying on a test account. SubLt→Capt remain "coming soon" / pass-through until their content ships.

## Critical files (by plan)
- **P1:** `lib/core/services/rank_service.dart`, `rank_feature_flags.dart` (new), `rank_confirmation_reconciler.dart` (new), `_shared/rank_engine.ts`, `evaluate-rank-promotions/index.ts`, `sync/sync_profile.dart`, migration 084.
- **P2:** migrations 085/086, `seed_service.dart`, `hive_service.dart`, `sync_service.dart`, `sync/sync_exam.dart` (new), `rank_exam_write_service.dart` (new), `exam_bank_repository.dart` (new), `assets/data/exam_*.json` (new).
- **P3:** `profile_content.dart`, `app_router.dart`, `qualification_exam_screen.dart` (new), `app_constants.dart`, `rank_chip_full_width.dart`, `ward_rank_pill.dart`, `notification_inbox_service.dart`, migration 087, `lib/features/exam/CLAUDE.md` (new).

## Verification
- **Per plan:** `flutter analyze` clean; the new behavioral + contract + parity tests pass; pre-commit gates green.
- **Engine (P1):** clamp behavioral table (incl. frontier pass-through + test-ahead); confirmation monotonic round-trip (Hive); client≡server parity; existing rank tests unaffected (flag off).
- **Bank (P2):** restore round-trip for attempts; bundle-seed offline first-run; OTA pull updates a changed question without a rebuild; frontier derives correctly.
- **End-to-end (P3, e2e-sim-testing skill):** on a temp-PRO test account with the flag on — reach Acting LS, take + pass the LS exam, confirm it unlocks the next rung; fail path shows explanations + cooldown; Learn is free for all ranks; existing users see current rank → Acting after the rollout backfill.
- **Rollout safety:** confirm flag OFF end-to-end before Task 8; flip client + server together.
