---
bug_id: e4a7c9
date: 2026-08-13
batch: backend-cpu-starvation
status: proposed
blast_radius: platform
symptom: |
  Live pg_stat_statements (143-day window since project creation, never reset)
  shows realtime.list_changes() — the Supabase Realtime WAL poller, run as
  supabase_admin — is the single largest CPU consumer on the database:
  6,463 seconds of 18,279 total (35.4%) across 900,823 calls, spread over three
  query-shape variants (4,094s/446,937 calls + 2,026s/358,750 + 343s/95,136).

  The supabase_realtime publication contains exactly ONE table: weight_logs.
  That stream exists to serve a single PRO-only feature — Telegram-logged
  weight appearing in-app without waiting for the 24h batch pull
  (sync_realtime.dart:10-12 documents it as "PRO only").

  Root cause: the PRO gate exists at one of the two call sites and not the
  other. sync_service.dart:789 wraps the call in
  `if (SubscriptionService.instance.isPro())`. day_rollover_service.dart:65
  does NOT — its comment claims "Re-subscribe to realtime sync if PRO (was
  paused on background)" but the line beneath is an unconditional
  `unawaited(SyncService.instance.subscribeToRealtimeSync())`. The callee
  guards only re-entrancy (`if (_realtimeSubscription != null) return`), never
  entitlement. Every AppLifecycleState.resumed therefore attaches the WAL
  stream for EVERY user, free or PRO — and resume fires on every app foreground,
  every tab refocus on web.

  Discovered while investigating a 16-minute total backend outage on
  2026-08-13 23:03-23:19 IST (CPU throttling on burstable compute; see
  impact_analysis). Not the proximate trigger of that outage, but the largest
  standing draw on the CPU budget whose exhaustion caused it.
concept: sync_realtime_subscription
sot_registry_entry: sync_realtime_subscription
writers:
  - { file: lib/core/services/sync/sync_realtime.dart, method_or_widget: "subscribeToRealtimeSync — attaches the weight_logs stream; guards re-entrancy only, no entitlement check (THE SINK, where the guard belongs)", line: 13 }
  - { file: lib/core/services/sync/sync_realtime.dart, method_or_widget: "_attachRealtimeStream — opens .from('weight_logs').stream(primaryKey: ['id'])", line: 42 }
  - { file: lib/core/services/day_rollover_service.dart, method_or_widget: "didChangeAppLifecycleState resumed branch — UNGATED call; comment claims 'if PRO', code does not check", line: 65 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "checkAndSync — the ONE correctly-gated call site (isPro() wrapper)", line: 789 }
readers:
  - { file: lib/core/services/sync/sync_realtime.dart, method_or_widget: "the stream handler — merges inbound weight_logs rows into Hive", line: 62 }
  - { file: lib/core/services/day_rollover_service.dart, method_or_widget: "didChangeAppLifecycleState paused branch — unsubscribeRealtime (correctly unconditional; tearing down a non-existent subscription is a no-op)", line: 68 }
  - { file: lib/app.dart, method_or_widget: "dispose — unsubscribeRealtime", line: 88 }
hive_key_prefix: "n/a — realtime inbound rows land under the existing weight-log keys written by HealthWriteService"
hive_key_formula: "unchanged by this fix; the inbound handler routes through the existing weight-log write path"
sync_methods: [subscribeToRealtimeSync, unsubscribeRealtime, checkAndSync]
restore_methods: [_restoreWeightLogs]
cloud_table: weight_logs
cloud_columns: [id, user_id, weight_kg, logged_at]
contract_test_path: test/contracts/realtime_subscription_pro_gated_test.dart
ist_handling:
  - "Not applicable — this is an entitlement gate on a subscription lifecycle. No date-key derivation, no counter reset, no timestamp comparison is introduced or changed."
provider_invalidations: []
telemetry_op_types:
  success: [realtime_subscribe_skipped_free_tier]
  failure: [realtime_stream_weight_logs, realtime_handler_weight_logs]
cross_account_guard: |
  Unaffected and slightly strengthened. The fix adds an entitlement check at
  the sink; it removes no ownership check. subscribeToRealtimeSync already
  reads the live session for its user id, and unsubscribeRealtime is already
  called from the user-swap path via app.dart:88 / the paused branch. Gating
  MORE users out of the subscription strictly reduces the surface on which an
  inbound cross-account row could be handled: a free-tier user who currently
  attaches the stream and then swaps accounts is a window the fix closes
  entirely.
forbidden_patterns_checked:
  - { pattern: "a call to subscribeToRealtimeSync that is not preceded or backed by an isPro/proStateSnapshot check", absent: true, after_fix: true }
  - { pattern: "a comment claiming an entitlement gate on a line that does not perform one", absent: true, after_fix: true }
  - { pattern: "a table in the supabase_realtime publication with no PRO-gated consumer", absent: true, after_fix: true }
proposed_fix: |
  GUARD THE SINK, NOT THE ENTRY (debugging skill bug-class 2.25). The defect
  is precisely that the guard sits at one entry point while a second entry
  bypasses it. Moving the check inside subscribeToRealtimeSync makes it
  unbypassable by construction and covers call sites nobody has written yet.

  1. lib/core/services/sync/sync_realtime.dart — subscribeToRealtimeSync():
     after the existing re-entrancy guard and before any network work, return
     early when the user is not entitled. Use
     SubscriptionService.instance.proStateSnapshot() — the PURE read — NOT
     isPro(), which is the DECISION path and may WRITE (lib/core/services/
     CLAUDE.md, OI-44 Unit 6, diagnose a9c4e1). Emit
     ErrorTelemetry.logEvent('realtime_subscribe_skipped_free_tier') once per
     transition, not per resume, so this does not become its own telemetry
     flood (bug-class 2.13).

  2. THE SECOND HALF — TEARDOWN ON DOWNGRADE (added after plan-review round 1;
     the fix was incomplete without it). Gating the subscribe covers only the
     OPEN direction. subscribeToRealtimeSync's FIRST line is
     `if (_realtimeSubscription != null) return;`, so an already-attached
     channel never re-enters the guard — and nothing tears realtime down when
     entitlement lapses: _downgradeLocally never touches _realtimeSubscription
     and neither does SubscriptionService._onUserChanged. A PRO user who lapses
     mid-session keeps a live PRO channel until app background or dispose.
     Add the teardown to _downgradeLocally (subscription_service.dart:1152) —
     the single sink all EIGHT downgrade call sites funnel through: 439, 461
     (_enforceEntitlementInvariants), 579, 599 (legacy inline path), 890, 900,
     908 (refreshFromSupabase's no-row / null-response branches — the most
     likely real-world lapse) and 1066.

  3. lib/core/services/sync_service.dart:159-166 — _onUserChanged INLINES the
     realtime cancel instead of calling unsubscribeRealtime(). Collapse it to a
     call so a single teardown site carries any future bookkeeping; today the
     two are equivalent, which is exactly why the drift is easy to miss.

  4. lib/core/services/day_rollover_service.dart:64-65 — correct the comment to
     describe what the line does. Leave the call itself in place: with the sink
     guarded it is now correct, and it becomes the legitimate free→PRO
     re-subscribe path (a newly-PRO user attaches on the next resume).

  5. Kill-switch per §4.6: configBox['disable_realtime_pro_gate'] restores the
     verbatim pre-fix behaviour (subscribe unconditionally). Default OFF = fix
     ON. This is platform-tier, so the flag is mandatory, not optional.

  NOT part of this fix, deliberately: dropping weight_logs from the
  supabase_realtime publication. That would disable the feature for PRO users
  too and is a product decision, not a bug fix. Migration 079 added it for a
  real reason (diagnose e3f1a7 — the stream was channelError-ing 156 times
  because the publication was empty).

  ALSO NOT DOING, and this is a REVERSAL of a round-1 hardening decision that
  round 2 overturned: an entitlement-arrival re-subscribe. proStateSnapshot()
  reads local Hive while refreshFromSupabase() is fired unawaited, so a genuine
  PRO user on a fresh install can be gated off. But sync_service.dart:789
  already gates on isPro() TODAY, so that denial is PRE-EXISTING and not
  created by this fix; recovery is the next AppLifecycleState.resumed via
  day_rollover_service.dart:65, not "the whole session"; and the remedy would
  add a POST /token to a method fired unawaited from splash and 3x from
  Razorpay — in a batch whose entire thesis is REDUCING auth load during
  degradation. In the degraded case the .select() throws and the success path
  never fires anyway, so the remedy would not even work when it matters.
regression_test_planned: |
  test/contracts/realtime_subscription_pro_gated_test.dart — behavioral, not
  source-grep (rule 21; source-grep would pass on the pre-fix code too, since
  the string "isPro" already appears at the OTHER call site — this is exactly
  the false-confidence shape feedback_source_grep_false_confidence.md warns
  about).

  Cases:
  1. Free-tier snapshot + resume-equivalent call to subscribeToRealtimeSync →
     no stream attached, _realtimeSubscription stays null. FAILS on main
     (pre-fix it attaches).
  2. PRO snapshot → stream attaches. Pins that the fix does not break the
     feature it is gating.
  3. Kill-switch ON + free tier → attaches (verbatim pre-fix behaviour).
  4. Re-entrancy preserved: PRO, two calls → one attach.

  MUTATION PROOF (rule 24 discipline, and the lesson of
  feedback_mistake_guard_without_its_mirror): deleting the new early-return
  must redden case 1. Run it and record the count in self_review_findings —
  a guard whose removal reddens zero tests is not protected, and this batch's
  sibling c2e9f4 shipped exactly that mistake twice before catching it.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "day_rollover_service.dart:65 read directly (not grep context); confirmed the unconditional call and the contradicting comment. sync_service.dart:789 confirmed as the only gated caller via grep -rn over lib/." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive contract changes. Inbound rows continue through the existing weight-log write path." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "pg_publication_tables where pubname='supabase_realtime' returns exactly one row: weight_logs. No schema change proposed." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "pg_stat_statements joined to pg_roles: realtime.list_changes runs as supabase_admin, 900,823 calls / 6,463s / 35.4% of 18,279s total, window 143 days since 2026-03-23 08:18 UTC (stats never reset)." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration. Migration 079 (which added weight_logs to the publication) stays as-is — see proposed_fix." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Client-only change; no Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "cron.job enumerated: 24 active jobs, 4 on a */15 schedule. None subscribe to realtime; ruled out as the source of the list_changes calls." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "Unchanged. realtime.list_changes applies RLS per subscription; gating fewer subscribers cannot widen access." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage involvement." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret or key touched." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Telegram bot is a separate project and is the PRODUCER of the weight rows; its behaviour is unchanged by gating the app-side consumer." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Live: 0 rows in realtime.subscription and 0 pg_replication_slots at the time of measurement, confirming the poller is idle when nothing is attached — i.e. the 900k calls are attributable to attached client subscriptions, not to a standing server-side process." }
impact_analysis: |
  WHAT THIS COSTS TODAY. 35.4% of all database CPU since project creation, to
  serve a feature gated to PRO, on a project whose PRO population is
  approximately nobody (pre-launch, test accounts only). The instance is
  burstable: CPU credits accrue at a fixed rate and deplete under load, and
  when they hit zero the instance is throttled to its baseline share. On
  2026-08-13 that produced a 16-minute total outage (23:03-23:19 IST) in which
  /auth/v1/token and /auth/v1/user returned 504 with "context deadline
  exceeded" for 9-36s each, /rest/v1/* returned 503, and Postgres logged
  continuous "canceling statement due to statement timeout". Dashboard read
  CPU 87%, Memory 47%, Disk IO 2% — CPU-bound, conclusively.

  SCOPE LIMIT, STATED PLAINLY. pg_stat_statements is a 143-day CUMULATIVE
  view and was never reset, so it establishes WHERE the CPU budget goes in
  aggregate. It does NOT attribute the specific 16-minute spike, and I am not
  claiming it does — per-window attribution would need a reset-and-observe
  cycle that nobody ran. What it does establish is that the largest standing
  draw on a credit budget whose exhaustion caused the outage is a feature
  running for users not entitled to it. Reducing the baseline extends
  time-to-throttle proportionally; it does not by itself prove the next
  incident is prevented.

  WHY IT WILL GET WORSE, NOT BETTER. Cost here scales with CONNECTED CLIENTS,
  not with PRO subscribers, because the gate that was supposed to bound it is
  bypassed. Every free user the app acquires adds a WAL poller. At launch this
  is the load curve that breaks first, and it breaks as a total auth outage —
  the least debuggable symptom, because the telemetry sink goes down with it
  (feedback_backend_collapse_blinds_telemetry).

  RELATION TO THE OTHER TWO FIXES IN THIS BATCH. a9c4e2 (sign-in has no
  timeout) and d7b1f8 (un-coalesced auth retry pile-up) determine how badly
  the app BEHAVES when the backend degrades. This one reduces how often it
  degrades at all. They are independent and all three are worth landing;
  neither of the other two would have prevented the outage, and this one
  would not have made the spinner recoverable.
related_bugs: [2026-05-30-realtime-channelerror-publication-e3f1a7, 2026-06-27-sync-fanout-collapse-c4f8d2, 2026-05-31-pause-flag-guard-the-sink-c7e1a4]
self_review_findings: |
  CLASS IDENTIFICATION. Two known classes, both already in the debugging skill:

  2.25 (guard the SINK, not the ENTRY) — the exact structural shape. There the
  pause flag was checked at an async function's entry and an in-flight call
  slipped past it; here the entitlement check sits at one entry and a second
  entry has none. Same remedy: move the guard to the single point every path
  funnels through.

  2.48 (a claim in a comment trusted rather than verified) — "Re-subscribe to
  realtime sync if PRO" is a claim, and the line under it does not implement
  it. Anyone reading that call site sees a gate that is not there. This is why
  the fix corrects the comment as well as the code.

  WHAT I CHECKED BEFORE CLAIMING THE GAP. grep -rn over lib/ for both
  subscribeToRealtimeSync and unsubscribeRealtime returned every call site
  (4 total); day_rollover_service.dart:65 was then READ directly rather than
  trusted from grep context, per §2.9 — structural absence claims ("nothing
  gates this") are the dangerous kind and one file read refutes or confirms
  them in seconds.

  WHAT I HAVE NOT ESTABLISHED. Whether PRO users on the resume path were ever
  correctly served — i.e. whether the ungated call site was masking a bug where
  the gated one never fires on resume. The fix preserves the call, so this
  cannot regress, but it means "the resume path works for PRO" is currently
  untested in either direction. Test case 2 above closes that.

  WHAT THE TWO PLAN-REVIEW ROUNDS CHANGED (§4.12). Round 1 found this fix was
  HALF A FIX: the original proposed_fix gated the subscribe entry and stopped,
  which leaves an already-attached channel alive through a downgrade because
  the re-entrancy early-return means the guard is never re-evaluated. That is
  the teardown half now in step 2, and without it the entitlement invariant
  simply does not hold. Round 1 also corrected the _downgradeLocally call-site
  enumeration from 4 to 8 — the four I missed (890/900/908/1066) include
  refreshFromSupabase's branches, which are the most likely real lapse path.

  Round 2 then OVERTURNED one of round 1's own additions (the
  entitlement-arrival re-subscribe) on the reasoning now recorded at the end of
  proposed_fix. Worth stating plainly because it is the point of running two
  rounds: round 1's correction was not wrong about the RACE existing, it was
  wrong that this fix creates it or should carry the remedy.

  TWO TRAPS FOR THE IMPLEMENTER, both verified, neither obvious from the diff:
  (a) test/contracts/sync_service_public_api_snapshot_test.dart pins the set of
  PUBLIC Future/Stream/void members of SyncService and its part files against a
  hard-coded 100-name literal — so the teardown must NOT add a new public
  member, or that literal must move in the same commit. Private members and
  `bool get` kill-switches are invisible to it.
  (b) The dev panel's "revoke PRO" (dev_panel_screen.dart:221) and
  simulation_service.dart:138 reach writeSubscriptionState directly and NEVER
  call _downgradeLocally — so manually QA-ing the teardown through the dev
  panel produces a FALSE NEGATIVE. Verify via a real expiry instead.
---

# Realtime WAL subscription is not PRO-gated at the resume call site

See frontmatter for the full analysis. One-line summary: the `weight_logs`
Realtime stream is documented and intended as PRO-only, is gated at
`sync_service.dart:789`, and is attached unconditionally for every user on
every app resume by `day_rollover_service.dart:65` — whose own comment claims
the gate it does not perform. The resulting WAL polling is 35.4% of all
database CPU since project creation.

The fix moves the entitlement check into `subscribeToRealtimeSync` itself, so
no call site can bypass it.
