---
bug_id: e3b9d7
date: 2026-08-09
batch: train-signout-notif-bugs
status: fixed
blast_radius: account
symptom: |
  TWO notification-cron defects reported by the founder from their own phone and
  account, 2026-08-05 / 2026-08-07.

  (1) STREAK-GUARDIAN SENT A SELF-CONTRADICTING PUSH. A single notification read
  "Don't break your 28-day streak" beside a streak of 0 days, and titled itself
  "You hit a PR recently!" about a PR set 75 days earlier.

  Root cause A — TWO-CACHE DISAGREEMENT. Eligibility selected and gated on
  `user_progress.current_streak_weeks` ONLY, while the message body quoted
  `current_streak_days` from the DAILY SNAPSHOT — a different cache, written by
  a different writer on a different schedule. The founder's row had
  current_streak_weeks = 4 (frozen; last workout 2026-05-22) and
  current_streak_days = 0. Nothing reconciled them, so the push contradicted
  itself within one notification.

  Root cause B — UNBOUNDED "RECENTLY". The `recent_pr_exercise` title branch had
  NO recency check at all. The field comes from
  ai_snapshot_builder._getPRTimelineSummary, which scans every exlog row ever
  with no date cutoff, so "recently" could mean months ago.

  (2) A PRO-ONLY PUSH WENT TO EVERY ACTIVE USER. `weekly-recap-ready` sends the
  Sunday Brief, a PRO deliverable, and had NO subscription check of ANY kind.
  `last_active_at >= cutoff` was its ONLY eligibility filter. Confirmed live on
  the founder's own account, whose PRO ended 2026-07-05 and which was still
  receiving it 33 days later.
concept: notification_cron_eligibility_and_pro_gate
sot_registry_entry: notification_cron_eligibility_and_pro_gate
writers:
  - { file: supabase/functions/streak-guardian/index.ts, method_or_widget: "eligibility select — now fetches current_streak_days alongside current_streak_weeks so one row supplies both the gate and the copy", line: 94 }
  - { file: supabase/functions/streak-guardian/index.ts, method_or_widget: "eligibility gate .gte(current_streak_days, 1) — a live-0 user is never told they have a streak to protect", line: 96 }
  - { file: supabase/functions/weekly-recap-ready/index.ts, method_or_widget: "proUserIds — fetched ONCE before the page loop; a full-table set, not per-page", line: 133 }
  - { file: supabase/functions/weekly-recap-ready/index.ts, method_or_widget: "proUsers — the per-page PRO filter applied before any send work", line: 179 }
  - { file: supabase/functions/_shared/subscription.ts, method_or_widget: "fetchProUserIds — the CANONICAL PRO predicate, shared with morning-alert / plateau-alert / protein-gap-alert", line: 59 }
readers:
  - { file: supabase/functions/streak-guardian/index.ts, method_or_widget: "streakDays — reads the user_progress row this user was SELECTED on, not the snapshot", line: 214 }
  - { file: supabase/functions/weekly-recap-ready/index.ts, method_or_widget: "skipped tally — counts filtered-out users so a cron that sends nothing does not report a silently clean run", line: 180 }
  - { file: supabase/functions/weekly-recap-ready/index.ts, method_or_widget: "concurrency loop — iterates proUsers, the last place the filter could be lost", line: 263 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: user_progress
cloud_columns: [user_id, current_streak_weeks, current_streak_days]
contract_test_path: test/contracts/streak_guardian_eligibility_test.dart
ist_handling:
  - "streak-guardian's getTodayIST() and its 20:00 IST cron schedule are UNCHANGED by this fix — the today-logs comparison still uses the existing IST date key. This fix changes WHICH users are selected and WHICH cached number the copy quotes, never how a date is formed."
  - "weekly-recap-ready: the 14-day last_active_at cutoff is unchanged; the PRO filter is applied on top of it and introduces no new date arithmetic."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  Not applicable in the client sense — both are service-role crons with no user
  JWT. The relevant server-side equivalent IS addressed: weekly-recap-ready now
  resolves entitlement from the `subscriptions` table via the shared helper
  rather than trusting a denormalized per-user mirror, so one user's stale
  column cannot grant another's tier. streak-guardian's per-user snapshot read
  remains scoped by `.eq("user_id", userId)`, unchanged.
forbidden_patterns_checked:
  - "Every column referenced (`user_id`, `current_streak_weeks`, `current_streak_days`) exists on user_progress — check_schema_column_refs.dart covers supabase/functions/ since the WI-1 server-seam extension, so a nonexistent column would hard-fail the gate."
  - "No `users.subscription_status` read — that denormalized mirror goes stale and is the reason the founder's expired account still qualified. Pinned by an isFalse assertion."
  - "PRO predicate is NOT re-implemented locally; the shared _shared/subscription.ts helper is imported. Pinned by an import-shape regex."
  - "Both functions keep their _shared/cron_telemetry.ts logCronStart/logCronEnd and _shared/cron_auth.ts gate — neither was touched, so the adoption gates stay green."
  - "No `?? streakWeeks * 7` fallback survives — it would be unreachable today but would silently restore the two-cache contradiction if the gate were ever loosened."
proposed_fix: |
  (1) STREAK-GUARDIAN. Select `current_streak_days` in the eligibility query AND
  gate on `.gte("current_streak_days", 1)`. Read `streakDays` from that row
  instead of the snapshot. Both numbers now originate in the SAME row, so they
  cannot disagree.

  Remove the `recent_pr_exercise` title branch entirely rather than date-bounding
  it: `pr-detection` is a separate cron with a correct 20-minute lookback that
  already owns "you just hit a PR" in real time, so a second, later surface
  celebrating the same event is redundant even when correctly bounded. Users who
  would have hit that branch fall through to the goal-weight / variant framings.

  Also remove `recent_pr_exercise` from the Gemini `userState`. This is the
  load-bearing second half: dropping it from the TITLE alone would not have been
  enough, because the model writes the body independently and would narrate the
  same unbounded PR into the copy. The model can only say what it is given.

  Drop the now-unreachable `?? streakWeeks * 7` fallback — `.gte(..., 1)` means
  SQL already excluded NULL, and leaving it would silently re-derive the exact
  contradiction if the gate were ever loosened. The guarantee lives in the query.

  (2) WEEKLY-RECAP-READY. Import `fetchProUserIds` from `_shared/subscription.ts`
  and call it ONCE before the page loop. Filter each page to `proUsers` before
  the snapshot/progress batch fetches and the concurrency loop. Keep pagination
  bookkeeping on the RAW page — `.range()` walked the raw page, so advancing the
  offset by the filtered count would SKIP users. Count the difference as
  `skipped`.
regression_test_planned: |
  test/contracts/streak_guardian_eligibility_test.dart — 9 tests.
  test/contracts/weekly_recap_pro_filter_test.dart — 13 tests.

  Both are source-grep contracts: these are Deno Edge Functions and cannot be
  executed by `flutter test`. Their SoT registry entry therefore carries
  `presence_only: true` with that justification, per rule 21 — NOT a fabricated
  behavioral_test_path.

  Comments are STRIPPED before every grep, and that is load-bearing rather than
  boilerplate here: the fixes' own comments deliberately name `recentPR`,
  `recent_pr_exercise` and `users.subscription_status` to explain what was
  removed and why. An un-stripped absent-grep would match the explanation and
  pass while the code was broken. Per feedback_source_grep_strip_comments_first.

  The weekly-recap tests assert ORDERING, not just presence — fetched before the
  loop, filtered before the concurrency loop, pagination still on the raw page —
  because a "fix" that imports the helper and wires it in the wrong place is the
  realistic failure mode.

  MUTATION-PROVEN: reverting the streak-days gate + snapshot read turns 3 red;
  reverting the concurrency loop to the raw page turns the ordering test red.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "Both fixes are server-side Deno; no Dart client code changed under e3b9d7." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive read or write in either cron." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "current_streak_days confirmed present on user_progress in backups/live_schema_columns.json, which is what check_schema_column_refs.dart validates the new .select()/.gte() refs against for supabase/functions/ (WI-1 server-seam extension)." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "The founder's own row is the reproducing case and is recorded in the symptom: current_streak_weeks=4 with current_streak_days=0, last workout 2026-05-22. The PRO leak was confirmed on the same account, PRO ended 2026-07-05, still receiving the Sunday Brief 2026-08-07." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration — both columns already exist." }
  - { tier: 6, name: edge_function_deploy, status: fixed_in_this_batch, evidence: "SOURCE is fixed and committed here. The live DEPLOY of both functions is NOT part of this commit — it requires its own explicit founder authorization per CLAUDE.md §4.3 (plan approval is not deploy approval). Until deployed, the live functions retain the old behaviour; this is stated rather than implied so nobody reads a green commit as a shipped fix." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "Neither cron's schedule, job name, nor auth gate changed. streak-guardian stays the 20:00 IST daily job; weekly-recap-ready's dispatch is untouched. Both keep _shared/cron_telemetry.ts, so the adoption gate stays green." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Both run service-role; no policy consulted or changed." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret added or rotated; both use the existing service-role env." }
  - { tier: 11, name: external_services, status: verified, evidence: "OneSignal send path is unchanged — the fix reduces WHO is sent to and WHAT the copy quotes, never how the push is delivered. Gemini is still called by streak-guardian, with one field removed from its userState." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "streak-guardian traced: user_progress row → eligibility gate → same row's current_streak_days → copy + Gemini userState. weekly-recap-ready traced: subscriptions → fetchProUserIds → per-page proUsers → batch fetches → concurrency loop → send. All writers and readers named by file:line above." }
impact_analysis: |
  BLAST RADIUS account — both defects are per-user entitlement/eligibility on an
  outbound channel the user cannot opt out of retroactively.

  (2) IS A REVENUE DEFECT, not just a correctness one: the Sunday Brief is a
  headline PRO deliverable and every active free user was receiving it. That
  removes a reason to subscribe and devalues the tier for people who paid.

  (1) IS A TRUST DEFECT: a push that contradicts itself in one sentence reads as
  a broken app, and it arrived on the founder's own phone.

  FAIL-SAFE DIRECTION, deliberately chosen: fetchProUserIds returns an EMPTY set
  on error and never throws, so a lookup failure sends the Sunday Brief to
  NOBODY rather than to everybody. For a paid-tier push that is the correct
  direction to fail, and the caller's `proUsers.length === 0` branch honours it
  by advancing the page instead of stalling.

  RISK OF FIX (1): `.gte("current_streak_days", 1)` genuinely NARROWS the
  audience — a user whose weeks counter is warm but whose days counter is 0 will
  no longer be nudged. That is intended: telling someone to protect a streak
  they have already lost is the bug. Users who lose the removed PR branch fall
  through to existing framings, so nobody loses a notification entirely.

  RISK OF FIX (2): if fetchProUserIds were ever wrong in the restrictive
  direction, PRO users would silently stop receiving the Brief. The `skipped`
  tally is what makes that observable rather than invisible.

  ⚠ NOT LIVE YET. Both functions still run their OLD code in production until
  the deploy is explicitly authorized. The fix is real in git and unproven in
  prod until then.

  NOT FIXED HERE: the underlying divergence between the two streak caches. This
  fix stops the crons from straddling them; it does not reconcile the writers.
  That is a separate concern with its own writers to name.
related_bugs: [b9f4d2, a7e2c4, d5b8c2]
recurrence: |
  (1) is writer/reader drift across two CACHES rather than two field names — the
  reader was correct about each source individually and wrong to mix them. New
  variant worth recording: when a query GATES on one cached number and the copy
  QUOTES another, they must come from the same row, or the notification can
  contradict itself. The fix pattern is "select what you quote".

  (2) is the "server-side entitlement never checked" class, and its shape
  matches b9f4d2 / d5b8c2 — a cron whose eligibility filter looked complete but
  omitted the one predicate that mattered, failing OPEN and silently. Same
  lesson as CLAUDE.md rule 19: PRO features verify from the server, and the
  canonical predicate is `status='active' AND end_date > now()`, never
  `status` alone and never the denormalized `users.subscription_status`. A
  lapsed row keeps `status='active'` until something rewrites it, which is
  exactly why the founder still qualified 33 days after expiry.
---

# Streak-guardian self-contradiction + Sunday Brief PRO leak

Full writer/reader map, the 12-tier check, and the reasoning are in the YAML.

## Why the PR branch was removed rather than date-bounded

Bounding it would have been defensible, but `pr-detection` already owns "you
just hit a PR" with a correct 20-minute lookback. A second surface celebrating
the same event hours or days later is redundant even when correct. Removing it
also removes a field whose only source scans all history with no cutoff, so the
unbounded value stops being reachable from this function at all.

## Why the field also had to leave the Gemini payload

The model writes the body independently of the title. Removing the title branch
while still handing it `recent_pr_exercise` would have left it free to narrate
the same months-old PR into the copy — which is how the contradiction reached
the founder's phone. The model can only say what it is given.

## Deploy status

The source fix is committed; the live deploy is a separate, explicitly
authorized action per §4.3. Until then production runs the old code.
