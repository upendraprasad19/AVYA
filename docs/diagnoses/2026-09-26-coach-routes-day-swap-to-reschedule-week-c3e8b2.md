---
bug_id: c3e8b2
date: 2026-09-26
batch: day-swapper-sync-load
status: in_progress
blast_radius: platform
symptom: |
  Asking the AI coach to "shift today's workout to tomorrow and tomorrow's workout to today" (the
  APK observation that triggered this whole batch, spec §1.1: Fri 25 Pull+Core <-> Sat 26 Legs+Core)
  makes the coach emit `reschedule_week` with `daysAvailable=[Fri, Sat]`, which APPLY then shows as
  "6 keep - 0 move - 0 drop": a silent no-op. There is no day-swap coach tool at all, and two prompt
  sites actively steer a two-day exchange toward the wrong tool: the Captain Manual's own worked
  multi-intent example sends "move Friday's pull workout to today and today's pull to Friday" to
  `rescheduleWeek` (supabase/functions/_shared/captain_manual.ts:386-390), and
  `rescheduleWeek`'s own `selectionHints` (supabase/functions/_shared/tools/workout/rescheduleWeek.ts:25-26)
  claim "move Friday's pull to today" as an example of when to use it. `rescheduleWeek`'s tool
  description says it reshuffles a WEEK to a new set of AVAILABLE days and drops what doesn't fit
  (`rescheduleWeek.ts:23`) — a two-day exchange has no "unavailable" day, so every day stays available
  and the move planner produces zero moves, matching the observed 6/0/0 result exactly.
concept: day_swap_engine
sot_registry_entry: scheduled_workouts_mutations (interim until Task 29 registers day_swap_engine; Task 31 re-points this line to it — see docs/sot_registry.yaml; this concept's coach-facing
  half is the new swapWorkoutDays tool plus the manual's routing rule that sends a two-day exchange
  to it instead of rescheduleWeek)
writers:
  - { file: supabase/functions/_shared/captain_manual.ts, method: "multi-intent worked example", line: 386 }
  - { file: supabase/functions/_shared/tools/workout/rescheduleWeek.ts, method: selectionHints, line: 25 }
readers:
  - { file: supabase/functions/_shared/tool-loop.ts, method: "visibleTools = allTools(opts.ctx.isPro).map(toolToFunctionDeclaration)", line: 265 }
  - { file: supabase/functions/_shared/tools/registry.ts, method: allTools, line: 71 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method: "intent-type switch default branch", line: 160 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: not_applicable — this bug is a prompt/tool-selection defect; no sync method is involved.
restore_methods: not_applicable — no restore path is involved.
cloud_table: null
cloud_columns: []
contract_test_path: "must add: supabase/functions/_shared/tools/workout/__tests__/swapWorkoutDays_test.ts
  (tool definition: PRO, reviewable, intent type) plus a Deno test asserting rescheduleWeek.ts's
  selectionHints no longer contain swap phrasing (spec §9 test-layer table, 'Deno' bullet)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: [day_swap_done]
  failure: [day_swap_refused, day_swap_failed]
cross_account_guard: n/a — the fix is prompt content and tool registration; it introduces no new
  data read across accounts.
forbidden_patterns_checked:
  - { pattern: "Fixing this by widening rescheduleWeek's move planner to also handle the two-day case", absent: true }
  - { pattern: "Leaving the misleading rescheduleWeek.ts selectionHints text in place while only adding the new tool", absent: true }
proposed_fix: |
  Add a dedicated coach tool `swapWorkoutDays` (supabase/functions/_shared/tools/workout/swapWorkoutDays.ts,
  name `swapWorkoutDays`, intent type `swap_workout_days`, tier `pro`, `confirmationClass: reviewable`,
  params `{dateA, dateB}` as plain Zod strings) registered in `ALL_TOOLS`
  (supabase/functions/_shared/tools/registry.ts:31). Rewrite `rescheduleWeek.ts`'s selectionHints to
  "I'm only free on these days / reshape my week around availability" and drop the "move Friday's
  pull" phrasing entirely, so the two tools' hints no longer overlap. Fix `captain_manual.ts:386`'s
  worked example to route a two-day exchange to `swapWorkoutDays`, and add an explicit routing rule:
  swap or move-within-week -> `swapWorkoutDays` (PRO, capable client); free user -> the fallback line;
  PRO user whose client did not declare the `swap_workout_days` capability -> the "update the app"
  line. A new `client_capabilities` request field (spec §5.8) lets `tool-loop.ts:265`'s tier-filtered
  tool list exclude the new tool from clients that have not declared the capability, so an old app
  version gets the fallback line instead of a tool call it cannot execute. A new
  `swap_workout_days` case is added to `tool_dispatcher.dart`'s intent-type switch (its default
  branch is at :160), which calls the rebuilt day-swap engine with `origin: coach`.
regression_test_planned: |
  Deno: tool definition asserts PRO/reviewable/`swap_workout_days` (registry_test-style); a hints
  test asserts `rescheduleWeek.ts`'s selectionHints string does not match any of the phrases this bug
  reported ("move Friday's pull", "move ... to today"); a manual-routing test in the style of the
  existing `captain_manual_*_test.ts` files asserts the multi-intent worked example resolves to
  `swapWorkoutDays` for a same-week two-day exchange. Dart: a `tool_dispatcher_test.dart` case drives
  a fixture `swap_workout_days` intent through the dispatcher and asserts it calls the engine, not the
  unknown-intent-type failure path. `check_ai_tool_dispatcher_coverage.dart` is extended to require
  every tool declaring `requiresCapability` to have a matching dispatcher case AND a capability
  present in the client's const (spec §5.8) — mutation proof planned: remove the new dispatcher case
  and confirm the extended gate fails.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "New swap_workout_days case in tool_dispatcher.dart's intent-type switch (Task 27, U6), calling the day-swap engine with origin: coach." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No new Hive key is introduced by the routing fix itself." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL is involved in tool routing." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud data read or write is involved in tool selection." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration is needed for this bug." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "captain_manual.ts, rescheduleWeek.ts and registry.ts all ship in the ai-proxy Edge Function deploy (spec §11 rollout step 2)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job is involved in coach tool routing." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No RLS-governed table is touched by this fix." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No Storage bucket or object is involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret is involved." }
  - { tier: 11, name: external_services, status: verified, evidence: "The symptom itself is a live Gemini tool-call observation cited in spec §1.1: the coach emitted reschedule_week with daysAvailable=[Fri, Sat] and APPLY showed '6 keep - 0 move - 0 drop' for the founder's actual request. This drafting pass did not re-query Gemini; the evidence is the spec's own recorded observation." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "The client_capabilities request field (spec §5.8) and the server's capability-filtered tool list are the contract that lets an old client keep getting the fallback line instead of a tool call it cannot execute." }
impact_analysis: |
  Severity: P2. Every PRO user who asks the coach to swap or exchange two days' workouts gets a
  silent no-op today (APPLY shows 6 keep / 0 move / 0 drop with no explanation), which reads as the
  coach ignoring the request rather than as an unsupported feature. This is the triggering observation
  for the whole batch (spec §1.1) and is fixed as a side effect of shipping the day-swap engine and
  its coach tool — it is not a standalone smaller fix, because the correct behavior requires the new
  tool to exist.
---

# The coach routes a two-day workout exchange to rescheduleWeek instead of swapping (spec §1.1, §5.8)

## Why this is not a recurrence

`docs/diagnoses/INDEX.md` was grepped for `swap`, `reschedule`, `day_swap`. The only prior tool-routing
diagnose is `e8f4a3` (2026-09-18, tool-integrity audit), which fixed `_executeRescheduleWeek`'s MOVE
path raw-deleting the source row's terminal status — a different defect in the same tool, not a
misrouting bug. There is no prior diagnose for the coach sending a swap request to the wrong tool, so
this is filed as new (spec §1.2's bug-history check reaches the same conclusion).

## Fix ownership in the plan

- The new tool file, its registration, the dispatcher case and the tool-count pin: Task 27 (U6, Wave
  2) — deliberately held to Wave 2 because `check_ai_tool_dispatcher_coverage.dart` requires the
  dispatcher case to exist in the same commit as the tool file, and the dispatcher case needs U4's
  engine (integrated by then).
- The capability plumbing (`client_capabilities` request field, server-side filter,
  `_shared/client_capabilities.ts`, `_shared/day_swap_routing.ts`): Task 9 (U3, Wave 1).
- The manual amendment and hints rewrite: also Task 9 (U3), landing with the capability plumbing since
  both touch `captain_manual.ts` / `rescheduleWeek.ts`.

## Mutation evidence

Recorded at Task 31: each mutation, the grep that confirmed it applied, and the red count.
