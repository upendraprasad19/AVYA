---
hermes_pass_id: 2026-06-05-hermes-apk-obs
ran_at: 2026-06-05T14:05:00+05:30
batch_scope: >
  working tree (uncommitted) on branch `qualification-exam` — the APK-obs-2026-06-05
  batch ONLY (7 items: Obs 1/2/3a/3b/4/5 + follow-ups F-A/F-B). Explicitly EXCLUDES
  the already-committed qualification-exam spec (commit 7328c99) and the stray
  untracked plan file docs/superpowers/plans/2026-06-04-qualification-exam-plan-1-brevet-engine.md,
  which belong to the separate in-flight qualification-exam workstream.
lens_set: [L1, L11, L15, L16, L27, L34, L37]
agents_dispatched: 7
findings_total: 10
findings_by_severity: { P0: 0, P1: 0, P2: 4, accepted_as_is: 6, false_alarm: 0 }
verdict: accepted
---

# Hermes Pass — APK obs batch 2026-06-05

Per-batch deep multi-lens review (E-pass). Triggered because the batch's max
blast-radius is **account/platform** (Obs 4 rewrites the cold-start restore path;
F-B feeds the rank/phase reconciler). 7 parallel Opus lenses, consolidated below.

## Summary

- **0 P0. 0 P1.** No data-loss, no cross-account leak, no writer/reader drift,
  no crashes. The batch is **ship-safe**.
- **4 findings fixed in this batch** (all P2 — observability gap, latent null-shape
  reader, a rule-21 behavioral-test gap, and doc/prose drift).
- **6 findings accepted-as-is** — each is low-severity, self-healing, AND/OR sits
  behind the default-OFF `bg_restore_enabled` flag; documented below so a future
  reader doesn't re-discover them cold.
- The two highest-fear surfaces going in — (a) does the flagged background-restore
  open a cross-account or data-loss hole, and (b) does the phase-identity bucketing
  over/under-count — both came back **clean** (L15/L16 ownership preserved; L1
  confirmed `SwapService`/`markCompleted` preserve the stamped phase).

## Findings by lens

### L1 — Writer/reader drift
**1 fixed (P2) · 1 accepted**

- **[FIXED] `completedWeekNumbers` had only a source-grep test (rule-21 gap).**
  The Obs-3a current-phase week-check reader was pinned only by a brittle
  source-grep assertion (`svc.contains("sched['status'] == 'completed'")`) — no
  behavioral coverage, and rule 21 requires `behavioral_test_path:` for any SoT
  reader. **Fix:** extracted the pure decision into
  `WorkoutScheduleReadService.completedWeekNumbersFrom(planStart, isCompletedOn, {maxWeek})`
  (no Hive — takes a predicate) + 4 behavioral tests (any-completed-day marks the
  week / empty week excluded / null planStart → empty / maxWeek bounds the scan).
  Repinned the source-grep assertion to the **delegation + `== 'completed'`
  semantic** instead of the inlined `sched` local (the refactor inlined it, which
  is precisely why the old literal assertion was fragile).
  - file: `lib/core/services/workout_schedule_read_service.dart` (completedWeekNumbersFrom)
  - test: `test/contracts/week_completion_check_test.dart` (group "Obs 3a — completedWeekNumbersFrom (behavioral, pure)")
- **[ACCEPTED] `phaseForDatePure` assumes monotonic-ascending block starts.**
  True for every real plan (blocks are generated forward-only; the reconciler is
  monotonic). A non-monotonic block list is unreachable without a separate
  reconciler bug, which is independently clamped. Documented; no change.

### L11 — Restore-completeness sync
**1 fixed (P2) · 1 accepted**

- **[FIXED] F-B carry-forward prose drift (the doc said "ALL", the code does "ANY").**
  After the B-pass F-2 fix, `bucketPastRows` groups by phase identity via
  **carry-forward** — it triggers when **ANY** past row is stamped (unstamped rows
  inherit the nearest preceding stamped phase), not when *every* row is stamped.
  Three artifacts still carried the stale all-or-nothing "EVERY/ALL" description:
  the F-B diagnose-doc (`7d2e6b`, 4 spots), the `bucketPastRows` source doc-comment,
  and the test-file header. **Fix:** corrected all three to the carry-forward
  description; the diagnose-doc re-passes `validate_diagnose_doc.dart`. (Test
  *bodies* were already correct — the B-pass F-2 test asserts an unstamped row
  inherits the surrounding phase — so this is prose-only, no behavior change.)
- **[ACCEPTED] Fail-path heal asymmetry on the flag-ON path.**
  When `bg_restore_enabled` is ON and the background `restoreFuture` **fails**, the
  post-restore heals don't run (they're attached via `.then` on success only),
  whereas the default (flag-OFF) path's foreground heals always run before nav.
  Acceptable: the flag is default-OFF, so today every boot uses the always-heal
  foreground path; and when the restore future fails there is, by definition,
  nothing newly-restored to heal — the next boot retries restore + heal. Documented
  as a roll-the-flag caveat.

### L15 — Cross-account session ownership (Hive)
**Clean.** The background-restore path keeps the ownership gate
(`HiveUserSession.openForUser`) **BLOCKING before navigation** — verified by
`background_restore_test` ("ownership (openForUser) completes BEFORE navigation in
the bg path"). No user-scoped read was moved outside `wrapUserScopedBox`. A user-B
sign-in cannot reach home on user-A's boxes.

### L16 — Riverpod auth-token watch
**Clean.** No provider lost its `authUserIdTokenProvider` watch. The new
cold-start refresh bridge (`restoreCompletedTick` → `home_screen` listener →
`invalidateOnRetry`) re-runs the home providers' `build()` after the bg heal — it
*adds* an invalidation signal, it does not bypass the auth-token gate. The tick is
a monotonic `ValueNotifier<int>`, single-writer (`bumpRestoreCompleted`).

### L27 — Concurrency on shared state
**2 accepted (both self-healing + flag-gated)**

- **[ACCEPTED] F-1: migrator-vs-foreground-write index lag.** In the bg path the
  once-per-device key migrators run inside the background heal while the foreground
  may issue a write; a Hive index can lag by one frame. Self-heals on the next
  read/invalidate (the heal bumps `restoreCompletedTick`, which invalidates the
  readers). No lost write — migrators merge (put-before-delete). Flag-OFF by default.
- **[ACCEPTED] F-5: Train tab one-tick-stale week strip.** Same window — the Train
  strip can render one tick stale until the restore tick invalidates. Cosmetic,
  self-healing, flag-gated. (The L34 fix below makes any migrator failure in this
  window observable rather than silent.)

### L34 — Telemetry coverage on async failure legs
**1 fixed (P2)**

- **[FIXED] bg-heal silent-catch gap.** `_healAfterRestoreInBackground()` ran the
  Exlog/Nlog/SavedMeal migrators + `PhaseProgressReconciler.reconcile` +
  `refillIfNewWeek` each inside a bare `catch (_) {}` — a background heal failure
  was invisible (the exact silent-observability-loss class from Test #16.1 D /
  `feedback_observability_silent_drop.md`). **Fix:** each catch now
  `unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'bg_heal_<step>'))`
  (`bg_heal_exlog` / `_nlog` / `_saved_meal` / `_phase_reconcile` / `_refill`),
  mirroring the foreground twin `_ensureOwnershipBeforeHome`. This also makes the
  L27 race observable if it ever bites.
  - file: `lib/features/auth/screens/restoring_screen.dart`

### L37 — Empty-state / null-shape readers
**1 fixed (P2) · 1 accepted**

- **[FIXED] Home "Recent Logs" saved-meal leak (latent).** The home recent-logs
  loop iterates `nutritionBox.values` and filters by `date == todayStr`. A
  saved-meal *template* (`is_saved_meal == true`) currently carries no `date`, so
  it's filtered out today — but a future writer that stamps `date` on a template
  would leak it into "Recent Logs". **Fix:** explicit defensive guard
  `if (log['is_saved_meal'] == true) continue;` before the date check.
  - file: `lib/features/home/providers/home_provider.dart`
- **[ACCEPTED] `completedWeekNumbers` maxWeek=12 cap.** A phase with >12 weeks
  wouldn't mark weeks 13+. Real phases are ≤12 weeks; post-phase-12 deployment
  cycles render via a different path. Documented; no change.

## Founder triage

All 4 P2 findings **fixed in-batch** (per `feedback_no_deferrals.md` — no deferral).
All 6 accepted-as-is findings **documented** above with the reason each is safe to
leave (low-severity + self-healing + flag-gated). No P0/P1 → **verdict: accepted**,
batch is ship-safe pending the founder's explicit "commit".

## Action items

- [x] L34 — bg-heal telemetry on every heal-step catch (restoring_screen.dart)
- [x] L37 — `is_saved_meal` guard on home recent-logs (home_provider.dart)
- [x] L1/L37 — pure `completedWeekNumbersFrom` + 4 behavioral tests + repin source-grep
- [x] L11-F5 — carry-forward prose corrected in diagnose-doc + source comment + test header
- [ ] (founder, at commit time) Stage ONLY the APK-obs batch; EXCLUDE the untracked
      `docs/superpowers/plans/2026-06-04-qualification-exam-plan-1-brevet-engine.md`
      (separate qualification-exam workstream sharing this branch).
- [ ] (founder, on roll) When flipping `bg_restore_enabled` ON after device verify,
      note the L11-accepted fail-path heal asymmetry — a failed restore defers heal
      to next boot (acceptable, documented).

## Self-evolution

- date: 2026-06-05 · batch: apk-obs-2026-06-05 · lenses: L1,L11,L15,L16,L27,L34,L37
  · findings: 4 P2 fixed + 6 accepted + 0 false-alarm · 7 parallel Opus agents.
- Signal: **L34 and L37 were the highest-value lenses** this batch — both caught
  real (if latent/flag-gated) gaps in *new* code that the per-commit B-pass + 5
  other lenses missed. L34 (telemetry on async failure legs) is now a must-run on
  any batch that adds a background async pipeline. L37 (null-shape readers) earns
  its place on any batch that adds a new consumer over a heterogeneous Hive box
  (templates + logs share `nutritionBox`).
- New lesson for the hermes-pass skill history: when a batch's B-pass already
  applied a fix (here B-pass F-2 carry-forward), **re-grep the prose/doc-comments
  for the pre-fix description** — code can be corrected while three layers of prose
  keep describing the old all-or-nothing behavior (L11-F5). Mirrors
  `feedback_source_grep_strip_comments_first.md` at the doc layer.
