---
bug_id: 280c4d
date: 2026-07-06
batch: coach-completion-tap-card (Unit 1)
status: fixed
blast_radius: platform
symptom: >
  A single coach `logSet` on a multi-exercise scheduled day silently flipped
  the WHOLE day to `status:'completed'`, inflating streak / rank / deployment.
  The coach dispatcher's derived-completion hook `_maybeCompleteScheduledDay`
  (tool_dispatcher.dart) had NO "all exercises logged" check — it called
  `WorkoutWriteService.markCompleted` as soon as ONE exercise was logged (only
  guarding rest-day + already-completed). Every coach write already requires an
  explicit APPLY tap; the whole-day completion was a HIDDEN side-effect riding
  that one tap. Founder live-tested (test7, PRO) and reported it. Because
  completion feeds the streak counter, the sequential-rank deployment ladder,
  and the home/calendar status, one logged set could earn a full day's credit
  for a workout that was 1-of-5 done.
concept: coach_derived_completion
sot_registry_entry: >
  coach_derived_completion — completion of a scheduled day DERIVES from logging
  (never AI-asserted, ADR-0012). Post-fix it derives via TWO paths: (1) the
  all-logged AUTO backstop — auto-`markCompleted(completedVia:'auto')` ONLY when
  every planned exercise in `schedule_<date>['exercises']` has a log today
  (swap-tolerant; warmup/cooldown/finisher optional; empty exercises[] ⇒
  vacuously complete); (2) the user-tapped completion-prompt card
  (`completedVia:'tap'`). A genuine partial stays `planned` and writes a
  date-scoped `completion_prompt_<date>` action row (LOCAL-ONLY, never synced).
writers: >
  Derived-completion decision — { file: lib/features/ai_coach/services/tool_dispatcher.dart, method: _maybeCompleteScheduledDay, line: 351 } (all-logged gate + partial→prompt), calling
  { file: lib/core/services/workout_write_service.dart, method: markCompleted, line: 399 } (now takes completedVia; idempotent status re-check under the per-date lock; stamps completed_via on schedule + wlog rows).
  Completion-prompt row writer — { file: lib/features/ai_coach/services/tool_dispatcher.dart, method: _writeCompletionPrompt, line: 424 } (date-scoped key, UPDATE-not-INSERT).
  Tap handler — { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method: completeWorkoutFromPrompt, line: 277 } (re-reads schedule, markCompleted completedVia:'tap', resolves the prompt).
readers: >
  Downstream status readers (unchanged) — home Today's Workout card + calendar +
  streak, train currentPlan day view, cloud scheduled_workouts.status. New
  readers of the prompt row + counts:
  { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method: ChatHistoryNotifier.build, line: 137 } (skips resolved prompts; emits a kind:'completion_prompt' ChatMessage for unresolved ones);
  { file: lib/features/ai_coach/screens/ai_coach/chat_area.dart, method: _buildChatArea, line: 48 } (renders CompletionPromptCard);
  { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method: _buildWorkoutSnapshotForDate, line: 1064 } (emits today_workout_completion counts so the coach narrates "3 of 5" and never nags).
hive_key_prefix: "completion_prompt_ (coachBox action row); schedule_ / exlog_ / wlog_ (workoutBox, unchanged)"
hive_key_formula: "'completion_prompt_${istDateStr(date)}' (date-scoped, one per day); exlog via WorkoutWriteService.exlogKey (unchanged); schedule via scheduleKey (unchanged)"
sync_methods: ["syncWorkoutData", "pushSnapshot"]
restore_methods: ["n/a — completion_prompt rows are LOCAL-ONLY (excluded from _syncCoachInteractions push at sync_coach.dart:89 and never returned by _restoreCoachInteractions); the underlying schedule_/wlog_ completion reaches the cloud via the existing scheduled_workouts / workout_logs sync (unchanged)"]
cloud_table: "scheduled_workouts (status) + workout_logs — via the existing canonical writers; completion_prompt rows have NO cloud table (local action rows)"
cloud_columns: ["scheduled_workouts.status (unchanged)", "n/a for completion_prompt"]
contract_test_path: test/contracts/coach_completion_prompt_test.dart
ist_handling: >
  The completion-prompt key is `completion_prompt_${istDateStr(date)}` (IST, per
  §4.5). The all-logged check + snapshot counts read exlog rows via
  `WorkoutWriteService.exlogKey`, which applies `istDateStr` internally — the
  dispatcher passes the SAME DateTime `logExercise` used so the keys align; the
  snapshot helper reconstructs a UTC-midnight DateTime from the IST date-string
  (DateTime.utc(y,m,d)) so exlogKey round-trips to the same date-string without
  the Test #11.1 double-shift (never `istDateOf(DateTime.parse(dateStr))`).
provider_invalidations:
  - "calendarWeekProvider (after a [Complete workout] tap — home calendar re-reads status)"
  - "todayWorkoutProvider (home Today's Workout card)"
  - "streakProvider (streak reflects the completion)"
  - "currentPlanProvider (train day view)"
  - "workoutStatsProvider (train stats)"
  - "chatHistoryProvider (rebuilt via refreshFromHive when a prompt is written/resolved)"
telemetry_op_types:
  success: []
  failure: ["tool_dispatch_derived_completion_failed (existing; the derived-completion hook stays best-effort and never throws into dispatch)"]
cross_account_guard: true
forbidden_patterns_checked:
  - "A single coach logSet auto-completing a multi-exercise day with NO all-logged check. FIXED: _maybeCompleteScheduledDay counts planned exercises[] and only auto-completes when EVERY one has a log today; otherwise it writes the tap-to-complete card. Pinned by coach_completion_prompt_test.dart test (a) (partial → planned + prompt)."
  - "markCompleted rewriting completed_at / completed_via on a re-call (double markCompleted from the auto-backstop racing a user tap). FIXED: an under-lock status re-check returns success WITHOUT rewriting when already 'completed'."
  - "A kind-tagged local action row leaking into ai_coach_interactions (would corrupt interaction analytics). FIXED: _syncCoachInteractions skips entry['kind'] != null (belt-and-braces atop the coach_ key-prefix guard); restore never re-hydrates them."
proposed_fix: >
  KEEP `_maybeCompleteScheduledDay` + its `markCompleted` call + the rest-guard
  (so derive_only_tool_surface_test stays green) but GATE the auto-completion on
  all-logged. After a coach `logSet`: count planned `exercises[]` (warmup/
  cooldown/finisher optional), swap-tolerant (a log under `exercise_name` OR
  `swapped_from` counts), empty exercises[] ⇒ vacuously complete. If all logged
  → auto-`markCompleted(completedVia:'auto')` AND resolve any earlier partial
  prompt. If NOT all logged → write/update the date-scoped `completion_prompt_
  <date>` coachBox row (kind:'completion_prompt', planned/logged counts,
  resolved_at:null). ChatHistoryNotifier renders unresolved prompts as a
  two-button coach tile (WardButton, Campaign-Gold, DM Sans): "Recruit — log
  more exercises? [Log more] · [Complete workout]". [Complete workout] re-reads
  the schedule and markCompleted(completedVia:'tap'); [Log more] resolves the
  card + focuses the composer. markCompleted gains an optional completedVia
  (default 'app') + an idempotent under-lock status re-check + stamps
  completed_via on schedule + wlog. The snapshot's today_workout carries
  today_workout_completion:{total_planned,total_logged,all_logged}. The prompt
  row is LOCAL-ONLY (sync push skips kind-tagged rows; restore never returns
  them). No EF change (client-only).
regression_test_planned: >
  test/contracts/coach_completion_prompt_test.dart (behavioral, pure-Hive):
  (a) 1-of-3 coach log → status STAYS 'planned' + a completion_prompt row with
  planned_count:3/logged_count:1/resolved_at:null; (b) log ALL planned →
  'completed' with completed_via:'auto' (+ the earlier partial prompt resolved);
  (c) [Complete workout] tap on a partial → 'completed' with completed_via:'tap'
  + resolved_at set; (d) a log under the swapped_from name completes a
  single-exercise swapped day (swap-tolerant); (e) the prompt row is deduped —
  ONE date-scoped key, superseded (logged_count refreshed, created_at
  preserved); plus the snapshot carries today_workout_completion counts, and
  ChatHistoryNotifier renders an unresolved prompt / skips a resolved one. Each
  fails against the pre-fix tree (which flipped to completed on the first log
  with no prompt row, and had no completedVia / tap-complete API).
  derive_only_tool_surface_test.dart + coach_derived_pr_and_completion_test.dart
  stay GREEN (method + markCompleted + rest-guard kept).
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — all-logged gate + tap-card + snapshot counts + sync-isolation guard + markCompleted completedVia/idempotency (tool_dispatcher.dart, ai_coach_provider.dart, completion_prompt_card.dart, chat_area.dart, screen.dart, ai_snapshot_builder.dart, workout_write_service.dart, sync_coach.dart). flutter analyze clean on the changed area."
  - "hive_local — status: fixed_in_this_batch — behavioral test coach_completion_prompt_test.dart: partial stays planned + writes completion_prompt_<date>; all-logged → completed(completed_via:auto); tap → completed(completed_via:tap); swapped counts; prompt deduped. 7/7 pass."
  - "client_to_server_contract — status: verified — completion still reaches scheduled_workouts.status + workout_logs via the unchanged canonical markCompleted/syncWorkoutData path; the completion_prompt row is LOCAL-ONLY (excluded from _syncCoachInteractions push AND restore) so it can never corrupt ai_coach_interactions."
  - "postgres_schema — status: not_applicable — no schema change; scheduled_workouts.status legal values unchanged; completed_via is a Hive-local attribution field (not a new cloud column this batch)."
  - "postgres_data — status: not_applicable — no migration; no data backfill."
  - "migrations_applied — status: not_applicable — client-only batch, no migration."
  - "edge_function_code_vs_deploy — status: not_applicable — NO EF change (client-only); snapshot passthrough unchanged (today_workout is prompt_passthrough)."
  - "rls_policies — status: not_applicable — no RLS-touching change."
impact_analysis: >
  Platform blast radius: completion feeds streak, the sequential-rank deployment
  ladder, and the home/calendar/snapshot status — every coach user who logs a
  partial workout via chat was affected pre-fix (a single set earned a full
  day's completion credit → inflated streak/rank). Post-fix a partial stays
  correctly "in progress" and the user explicitly completes (tap) or the day
  auto-completes only when genuinely all-logged (no lost-streak footgun for a
  fully coach-logged workout). The completion-prompt row is LOCAL-ONLY, so no
  cloud contract or multi-user surface changed; the fix is fully client-side
  (no EF deploy). Idempotency (auto-backstop racing a tap) is safe via the
  per-date lock + the under-lock status re-check. derive_only_tool_surface_test
  stays green because the method + markCompleted + rest-guard are all kept.
---

# 280c4d — coach logSet prematurely auto-completed the whole scheduled day

See YAML frontmatter for the full diagnosis. Founder-reported live on test7 (PRO,
2026-07-06): one coach `logSet` flipped a multi-exercise day to `completed`,
inflating streak / rank / deployment.

## Root cause (one line)
`_maybeCompleteScheduledDay` (tool_dispatcher.dart) auto-called `markCompleted`
after ANY single coach `logSet` on a scheduled day — it guarded only rest-day +
already-completed, never "are all planned exercises logged?" — so one set earned
a full day's completion credit.

## Fix
The method + its `markCompleted` call + the rest-guard are KEPT (derive-only
invariant, ADR-0012 — completion still derives from logging, never AI-asserted;
`derive_only_tool_surface_test` stays green). The auto-completion is now GATED on
**all-logged**: it fires only when every planned `exercises[]` entry has a log
today (swap-tolerant via `swapped_from`; warmup/cooldown/finisher optional; an
empty `exercises[]` ad-hoc day is vacuously complete). A genuine partial writes a
date-scoped `completion_prompt_<date>` coachBox action row that the chat renders
as a two-button tile — **"Recruit — log more exercises? [Log more] · [Complete
workout]"** — so the user decides. `[Complete workout]` derives completion via
the same canonical `markCompleted` (`completed_via:'tap'`); the all-logged
backstop uses `completed_via:'auto'`. `markCompleted` gained an idempotent
under-lock status re-check so the auto-backstop and a user tap can't double-stamp.
The prompt row is **LOCAL-ONLY** (sync push skips `kind`-tagged rows; restore
never returns them) so it can never corrupt `ai_coach_interactions`. The snapshot
carries `today_workout_completion:{total_planned,total_logged,all_logged}` so the
coach narrates "3 of 5 down" and never nags a legitimately in-progress day.

## Why not "pure explicit with NO backstop"?
Founder direction (2026-07-06): keep the all-logged backstop — a FULLY
coach-logged workout should still auto-complete so there is no lost-streak
footgun. The `[Complete workout]` tap is the reliable fallback for any partial
or any case a name mismatch / post-hoc edit makes the auto-check miss.

## Contracts + brand
`coach_derived_completion` SoT updated (all-logged auto OR user-tapped card;
model never asserts completion). `lib/features/ai_coach/CLAUDE.md` SoT table
updated. ADR-0012 extended with a completion-tap-card note. The card widget uses
WardButton primitives + Campaign-Gold + DM Sans per the Wardroom brand soul.
