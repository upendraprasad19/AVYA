---
bug_id: a1d7c3
date: 2026-07-03
batch: audit-fixwave-2026-07-02
status: fixed
blast_radius: account
symptom: >
  Two defects in the AI-coach chat log flow, both from the coach rendering
  THREE parallel confirm systems (chat_area.dart:92 LogConfirmCard legacy
  instant-log; :98 WorkoutLogConfirmCard legacy workout draft; :108
  ToolConfirmCard typed tool-intent) and routing one AI response into BOTH the
  legacy `actions[]` path (ai_coach_provider.dart addActions, called at :592/
  :394/:649) AND the typed `tool_intents` path (addIntents at :599/:401/:652).
  (F1, P1 — double-log) "log 3 sets of bench" emitted a `confirm_workout_log`
  legacy action (→ workoutDraft → submitWorkoutDraft → WorkoutWriteService.
  logExercise+markCompleted) AND a `log_set` typed intent (→ ToolConfirmCard →
  _executeLogSet → logExercise). Both cards render; confirming both wrote the
  workout TWICE (live: workout_log_exercises 1→2, workout_log_sets 3→6). (F2,
  P2 — false success) the legacy food path _logFood (conversational_log_handler.
  dart:75-101) returned bare `true` after foodLogProvider.logFood(...) regardless
  of the write result — unlike siblings _logSleep (:141)/_logMeasurement (:161)
  which return result.success — so a failed food write (0 rows) still flipped
  LogConfirmCard to the green "LOGGED ✓" state, contradicting the error. A stale
  settled ToolConfirmCard could also linger (filterVisibleIntents kept executed
  intents; prune ran only on resume/add) and read as a false ✓ next to a new
  attempt.
concept: coach_log_confirm_routing
sot_registry_entry: >
  coach_log_confirm_routing — one AI response yields exactly ONE confirm
  affordance per log: addActions drops a legacy `actions[]` entry whose kind is
  covered by a typed tool intent in the same response (log_set↔confirm_workout_
  log, log_meal_by_text↔log_food). The legacy food handler honors the write
  result. Settled tool-intent cards drop from the visible thread once stale.
writers: >
  Workout: submitWorkoutDraft (conversational_log_handler.dart:211) and
  _executeLogSet (tool_dispatcher.dart:118) both call WorkoutWriteService.
  logExercise — pre-fix both ran when both cards were confirmed. Food:
  _logFood (conversational_log_handler.dart:75) → foodLogProvider.logFood
  (nutrition_provider.dart:992, returns ({bool success,...})) and
  _executeLogMealByText (tool_dispatcher.dart:151). Routing writer:
  PendingLogActionsNotifier.addActions (ai_coach_provider.dart) +
  coveredLegacyLogKinds helper.
readers: >
  chat_area.dart renders LogConfirmCard (:92), WorkoutLogConfirmCard (:98) and
  ToolConfirmCard (:108). AiCoachScreen.filterVisibleIntents (screen.dart:71)
  decides which typed cards show. LogConfirmCard's green "LOGGED" state
  (log_confirm_card.dart) is gated on ConversationalLogHandler.executeAction's
  bool result (now honest for food).
hive_key_prefix: "exlog_ / wlog_ (workout) + nlog_ (food) — via canonical writers"
hive_key_formula: "unchanged — WorkoutWriteService.exlogKey / NutritionWriteService.computeLogKey"
sync_methods: ["syncWorkoutData", "syncNutritionData", "pushSnapshot"]
restore_methods: ["n/a — this is a client-side confirm-routing fix, no restore change"]
cloud_table: "n/a (routing fix; underlying writes reach workout_log_* / nutrition_logs via the existing canonical writers)"
cloud_columns: ["n/a"]
contract_test_path: test/features/ai_coach/coach_single_confirm_per_log_intent_test.dart
ist_handling: >
  No date-key or timestamp semantics changed. The fix is purely about WHICH
  confirm affordance renders (dedup) and whether the legacy food card believes
  the write succeeded. Underlying writes keep their existing IST keys.
provider_invalidations:
  - "workoutDraftProvider (suppressed setDraft when a log_set intent covers the workout)"
  - "pendingLogActionsProvider (legacy food action suppressed when log_meal_by_text covers it)"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: true
forbidden_patterns_checked:
  - "One AI response routed into BOTH the legacy actions[] path AND the typed tool_intents path for the SAME log, rendering two confirm cards that each write (double-log). FIXED: addActions drops the legacy card of a kind covered by a typed intent in the same response; a source-grep gate (coach_no_dual_log_path_test.dart) requires every addActions call site to pass suppressLegacyKinds."
  - "A log handler that returns success unconditionally, ignoring the WriteResult, so a failed write shows a green success card. _logFood returned bare `true`; FIXED to return r.success like _logSleep/_logMeasurement."
proposed_fix: >
  F1 (primary, routing dedup): pass coveredLegacyLogKinds(response.toolIntents)
  into addActions; skip the legacy confirm_workout_log draft / log_food action
  when a matching typed intent (log_set / log_meal_by_text) is present in the
  same response, so exactly one (guarded typed) card renders. Solo legacy
  actions (no typed twin) and non-overlapping kinds (water/weight/sleep/
  measurement) are untouched. Kill-switch disable_coach_log_dedup (guarded
  configBox read; default fix-ON). F2: _logFood returns r.success; and
  filterVisibleIntents drops settled cards older than 2 min so a stale green
  card can't sit next to a fresh attempt. NOTE — the plan's v3 "content-keyed
  idempotency marker" (logcommit_<date>_<kind>_<hash>) was DELIBERATELY DROPPED
  during implementation: keyed per-day it would FALSE-SUPPRESS a legitimate
  identical same-day log (e.g. bench in a morning AND an evening session). The
  primary routing dedup (one card renders) plus the existing per-intent-id
  marker (tool_dispatcher.dart:101, intent_<id>_dispatched_at) close the
  double-log safely without that risk.
regression_test_planned: >
  coach_single_confirm_per_log_intent_test.dart (behavioral): addActions with a
  matching typed intent DROPS the legacy draft/food action; a solo legacy action
  is preserved; water is never suppressed; coveredLegacyLogKinds maps log_set→
  workout, log_meal_by_text→food and nothing else. dispatched_card_filter_test
  .dart: a 10-min-old executed card is dropped (F2 stale-pill). coach_no_dual_
  log_path_test.dart (comment-stripped source gate): every addActions call site
  passes suppressLegacyKinds; _logFood returns r.success not bare true. All fail
  on the pre-fix tree.
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — addActions dedup + coveredLegacyLogKinds (ai_coach_provider.dart); _logFood returns r.success (conversational_log_handler.dart); filterVisibleIntents stale-drop (screen.dart)."
  - "hive_local — status: verified — behavioral test: suppressed workout draft stays null; suppressed food action never enqueued; solo legacy preserved."
  - "client_to_server_contract — status: verified — underlying writes still route through the canonical WorkoutWriteService / NutritionWriteService (unchanged); only the number of confirm affordances + the food success signal changed."
impact_analysis: >
  F1 affects any user logging a workout (or meal) via the coach where the server
  emits both a legacy action and its typed intent — pre-fix a natural double-tap
  doubled the logged volume (a data-integrity defect). F2 affects any coach food
  log that fails — pre-fix it showed a false green ✓. Both are account-tier
  (one user's own data). No cloud contract or multi-user path changed. Fully
  feature-flagged (disable_coach_log_dedup) for rollback. The food re-test on
  a live session (F-retest) confirms the false-success is gone and a real log
  writes exactly once.
---

# a1d7c3 — coach dual-path double-log + food false-success

See YAML frontmatter for the full diagnosis. Surfaced live on test7 during the
2026-07-02 comprehensive audit (P1 double-log confirmed cloud-side: 3 sets →
6; P2 false-success confirmed with 0 nutrition rows). Fixed in the audit-fixwave
batch, Unit 1.

## Root cause (one line)
The coach renders three parallel confirm systems and routed one AI response into
both the legacy `actions[]` path and the typed `tool_intents` path, so a single
log produced two cards that each wrote; and the legacy food handler reported
success unconditionally, ignoring the write result.

## Fix
Primary: `addActions` drops a legacy card whose kind is covered by a typed
intent in the same response (one affordance, not two), flag-gated. `_logFood`
honors the `WriteResult`. Stale settled cards drop from the visible thread. The
v3 content-keyed marker was dropped as unsafe (would false-suppress legitimate
identical same-day logs); the routing dedup + existing per-intent-id marker
suffice.

## B-pass hardening (2026-07-03)
The adversarial B-pass caught two defects in the first cut; both fixed here:

1. **F1 over-suppression (P2, data-loss-adjacent).** `confirm_workout_log`
   carries an exercises[] ARRAY while `log_set` covers ONE exercise, so the
   coarse kind-based suppression dropped a WHOLE multi-exercise draft when a
   single-exercise `log_set` was present → the uncovered exercises were lost.
   **Fix:** exercise-NAME-aware dedup (`TypedLogCoverage` +
   `typedLogCoverage`): resolve each `log_set` `exerciseId`→name via the
   exercise library and suppress the draft ONLY when EVERY draft exercise is
   covered; a partially-covered draft is KEPT (a double-log of the overlap is
   recoverable; loss is not). Unresolvable → treated as uncovered → keep.

2. **F2 stale-drop keyed on the wrong timestamp (P2 regression).** The visible-
   thread staleness used `createdAt` (the AI-reply time), so a user who
   confirmed >2 min after reading the reply never saw the green "✓ Logged" pill.
   **Fix:** key the executed-pill staleness on the SETTLE marker
   (`intent_<id>_dispatched_at`), keeping the ✓ for 2 min after it settles;
   missing marker → keep (never hide a real success); rejected/expired always
   render.
