---
bug_id: d7b1f8
date: 2026-08-13
batch: backend-cpu-starvation
status: fixed
blast_radius: account
symptom: |
  During the 2026-08-13 23:03-23:19 IST backend outage, the app issued auth
  requests that piled up rather than queueing behind one another, and every one
  of them sat holding a connection for 10-36 seconds against an already
  CPU-starved database.

  The tell is the recovery instant. At 17:49:45 UTC, edge_logs records roughly
  FIFTEEN GET /auth/v1/user requests all returning 200 within the same 400ms
  window (17:49:45.375 through 17:49:45.502), immediately followed by
  /rest/v1/weight_logs and /rest/v1/body_measurements 200s. Fifteen requests
  do not complete simultaneously because fifteen things were needed — they
  complete simultaneously because fifteen INDEPENDENT in-flight requests had
  each been blocked on the same unavailable backend and were released at once.

  Throughout the outage the same shape repeats: /auth/v1/user 504 at 17:34:11
  and 17:34:21, again at 17:35:59 and 17:36:01, again 17:36:55, 17:38:13,
  17:43:42 (x2), 17:44:34, 17:45:43 — sustained for sixteen minutes, from a
  client that had no chance of succeeding and no awareness that its siblings
  were failing identically.

  Verified root cause: SupabaseService.ensureFreshToken (supabase_service.dart:
  176-206) holds NO in-flight future. Every caller that finds the token inside
  the 5-minute expiry buffer independently calls client.auth.refreshSession().
  N concurrent callers produce N concurrent refreshes. There is no join.

  The codebase already solved this exact problem next door: AuthNotifier.signOut
  keeps _inFlightSignOut and returns the existing future so a second caller
  JOINS instead of racing (auth_provider.dart:471-479), added after review found
  overlapping teardowns. SyncCoalescer does the same for the write fan-out after
  the free-tier collapse (c4f8d2). Auth token freshness got neither.
concept: edge_function_token_freshness
sot_registry_entry: edge_function_token_freshness
writers:
  - { file: lib/core/services/supabase_service.dart, method_or_widget: "ensureFreshToken — no in-flight join; each caller independently awaits client.auth.refreshSession()", line: 176 }
  - { file: lib/core/services/supabase_service.dart, method_or_widget: "ensureFreshToken — the unguarded refreshSession() call itself", line: 189 }
  - { file: lib/core/services/supabase_service.dart, method_or_widget: "callFunction — awaits ensureFreshToken before every authed Edge Function invoke", line: 238 }
  - { file: lib/core/services/supabase_service.dart, method_or_widget: "retryColdStart — retries 502/503/504 on the [2000, 6000, 12000] schedule; per-call, unaware of concurrent siblings", line: 290 }
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "signOut / _inFlightSignOut — THE PRECEDENT: join-don't-race, already implemented for teardown", line: 471 }
readers:
  - { file: lib/core/services/sync/sync_realtime.dart, method_or_widget: "subscribeToRealtimeSync — refreshes the session before attaching the channel", line: 20 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "restoreFromCloudForUser — the restore fan-out, whose per-domain steps each touch the authed path", line: 454 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_kickoffRestore — runs resolveDestination and restoreFromCloudForUser in parallel, each with its own token needs", line: 99 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "resolveDestination — calls ensureFreshToken then one hard-refresh retry (c2e9f4)", line: 150 }
hive_key_prefix: "n/a — token freshness is session state, not a Hive-keyed concept"
hive_key_formula: "unchanged; no Hive key is read or written by this fix"
sync_methods: [restoreFromCloudForUser, callFunction]
restore_methods: [restoreFromCloudForUser]
cloud_table: users
cloud_columns: [id]
contract_test_path: test/contracts/token_refresh_join_behavioral_test.dart
ist_handling:
  - "Not applicable in the IST sense — the only time arithmetic is the existing UTC epoch expiry comparison (session.expiresAt), which is a timestamp, not a date key. Per docs/architecture/sync.md the IST contract governs date-keys and counter resets only."
provider_invalidations: []
telemetry_op_types:
  success: [auth_token_refresh_joined_inflight]
  failure: [supabase_service_ensure_fresh_token_refresh, edge_function_cold_start_retry]
cross_account_guard: |
  Requires care, and this is the one place the fix could go wrong. A shared
  in-flight future MUST be keyed to, or invalidated on, the current user id.
  If user A's refresh is in flight when an account swap lands, user B must NOT
  join A's future and receive A's token — that would be a cross-account
  credential handover, strictly worse than the pile-up being fixed.

  This is the same shape as diagnose e7c1a9 (bug-class 2.44): an in-flight
  async op resuming after a swap and writing under the wrong identity. The
  remedy there applies here — capture the user id at entry, re-check it
  synchronously against SupabaseService.currentUser?.id before RETURNING the
  joined token, with no await between the check and the return. On mismatch,
  discard the joined future and start a fresh refresh for the new owner.
  The existing _onUserChanged handler must also clear the in-flight holder,
  exactly as it already reassigns all three SyncCoalescers.
forbidden_patterns_checked:
  - { pattern: "two concurrent callers of ensureFreshToken each issuing their own refreshSession()", absent: true, after_fix: true }
  - { pattern: "a shared in-flight token future returned to a caller whose user id no longer matches the session that started it", absent: true, after_fix: true }
  - { pattern: "the in-flight holder surviving an account swap in _onUserChanged", absent: true, after_fix: true }
proposed_fix: |
  JOIN, DON'T RACE — the pattern signOut already uses, applied to token freshness.

  1. supabase_service.dart — add a private in-flight holder alongside the
     existing state, and have ensureFreshToken return the existing future when
     one is live, mirroring AuthNotifier.signOut's shape (auth_provider.dart:
     473-479):
       - if a refresh is already in flight for THIS user id, return it;
       - otherwise start one, store it, and clear it in whenComplete.
     Emit auth_token_refresh_joined_inflight when a caller joins, so the
     collapse is measurable rather than assumed.

  2. Guard the join on identity per cross_account_guard: capture the user id
     when the refresh starts; before returning a joined token, synchronously
     compare against SupabaseService.currentUser?.id with no intervening await.
     On mismatch, do not return the joined future.

  3. Clear the holder in the user-swap handler, alongside the existing
     SyncCoalescer reassignments.

  4. Kill-switch configBox['disable_token_refresh_join'] restores verbatim
     pre-fix behaviour (§4.6).

  EXPLICITLY OUT OF SCOPE, and NOT a deferral — a different fix for a different
  defect, which should be scoped on its own evidence rather than bundled here
  on a hunch: adding a circuit breaker so the restore fan-out stops retrying
  after N consecutive backend failures. The 16 minutes of doomed retries are
  real and visible in the logs above, but "how long should a client keep trying
  a dead backend" is a product/UX decision with its own failure modes
  (a breaker that trips too eagerly turns a 5-second blip into a manual
  reload). Landing the join first also shrinks the problem it would address,
  which changes the evidence any breaker should be designed against. Filed as
  its own item rather than smuggled into this one.
regression_test_planned: |
  test/contracts/token_refresh_join_behavioral_test.dart — behavioral.

  Cases:
  1. N=10 concurrent ensureFreshToken() calls against a seeded near-expiry
     session with an instrumented refresh → refresh invoked EXACTLY ONCE, all
     10 receive the same token. FAILS on main (pre-fix: 10 invocations).
  2. Sequential calls after the first completes → a second refresh does occur
     when the buffer is re-entered. Pins that the holder is cleared and this is
     not a permanent cache.
  3. Account swap mid-flight: start a refresh as user A, swap currentUser to B,
     then have B call → B does NOT receive A's token. This is the mirror test
     for cross_account_guard; without it the fix could ship a credential leak
     and every other case would still pass green.
  4. Refresh throws → all joined callers observe the existing failure semantics
     (existing token if unexpired, null if past expiry), and the holder is
     cleared so the next call retries rather than joining a dead future.
  5. Kill-switch ON → N calls produce N refreshes (verbatim pre-fix).

  MUTATION PROOF: deleting the in-flight holder must redden case 1; deleting
  the identity re-check must redden case 3; failing to clear in whenComplete
  must redden cases 2 and 4. Record all four counts — per
  feedback_mistake_guard_without_its_mirror, a guard whose removal reddens
  nothing is not a guard.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "supabase_service.dart:176-206 read in full — confirmed no in-flight holder, no join, unguarded refreshSession() at :189. auth_provider.dart:471-479 read and confirmed as the in-repo join-don't-race precedent." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive read or write. Token freshness is Supabase session state." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "edge_logs: ~15 GET /auth/v1/user 200s within 17:49:45.375-.502 UTC; sustained 504s on the same path 17:34:11 through 17:45:43. auth_logs give per-request durations of 9.3s to 35.9s with error 'context deadline exceeded'." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Client-only; the Edge Functions themselves are unchanged." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "cron.job enumerated (24 active). The /auth/v1/user burst is attributable to app clients, not cron: cron dispatch goes through net.http_post with the vault service key, which does not hit /auth/v1/user." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Unchanged." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage involvement." }
  - { tier: 10, name: secrets, status: verified, evidence: "The fix shares an access token between in-process callers that would each have fetched an equivalent token; it neither persists nor widens the scope of any credential. The identity re-check is what keeps that true across an account swap." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No third-party service involved in token refresh." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The ~15-in-400ms recovery burst is the direct observable of the missing join and is what the N=1 assertion in regression case 1 pins." }
impact_analysis: |
  WHAT IT COSTS. Two compounding effects, both worst exactly when the backend
  is least able to absorb them:

  (a) LOAD AMPLIFICATION AT THE WORST MOMENT. Each pending request holds a
  connection and a GoTrue worker for 10-36 seconds. During CPU starvation
  (e4a7c9) this is load added to a system already failing to keep up — the
  classic degradation-into-collapse loop that bug-class 2.43 documents for the
  write fan-out and that SyncCoalescer was built to break. The read/auth path
  never got the same treatment.

  (b) RECOVERY THUNDERING HERD. When the backend recovers, every queued request
  fires at once — the fifteen simultaneous 200s at 17:49:45 are exactly this.
  On a burstable instance that has just clawed back a small credit balance, a
  synchronised burst is a good way to spend it immediately and re-enter
  throttling. This outage recovered; a larger user base making the same burst
  might not.

  HONEST SCOPE LIMIT. What is VERIFIED by reading the code is that
  ensureFreshToken has no in-flight join and that N concurrent callers produce
  N refreshes. What is INFERRED, not proven, is that this specific mechanism
  produced that specific fifteen-request burst — /auth/v1/user is getUser, not
  the refresh endpoint, so some of those calls come from other callers on the
  same degraded path. I am not claiming a one-to-one attribution. The join is
  correct on its own merits regardless of how many of the fifteen it would
  have collapsed, and instrumenting auth_token_refresh_joined_inflight is what
  converts the inference into a measurement after landing.

  RELATION TO THE BATCH. e4a7c9 reduces how often the backend degrades;
  a9c4e2 makes degradation survivable from the user's seat; this one stops the
  client making degradation worse. Independent, complementary, all three worth
  landing.
related_bugs: [2026-06-27-sync-fanout-collapse-c4f8d2, 2026-06-09-edge-function-token-freshness-d3a1c7, 2026-06-13-authed-invoke-fresh-token-c4f1a7, 2026-06-28-pushsnapshot-crossaccount-mirror-e7c1a9]
self_review_findings: |
  WHY THIS ONE IS RANKED LAST OF THE THREE. It is the weakest-evidenced of the
  batch and I would rather say so than pad it. e4a7c9 rests on a direct
  pg_stat_statements measurement and a file read that proves the missing gate.
  a9c4e2 rests on a traced call chain with a matching live log timeline. This
  one rests on a proven code-level absence (no in-flight join) plus an
  INFERRED connection to an observed burst. That inference is stated as such in
  impact_analysis rather than dressed up.

  THE FAILURE MODE I WATCHED FOR. It would be easy to point at fifteen
  simultaneous requests and declare the cause, because the number is vivid and
  the story is tidy. /auth/v1/user is getUser rather than the refresh endpoint,
  so at least some of those calls originate elsewhere on the same path. The
  claim is therefore narrowed to what the code actually proves.

  BIGGEST RISK IN THE FIX ITSELF. The identity guard. A shared token future is
  a credential-sharing primitive, and getting the account-swap case wrong turns
  a performance fix into a cross-account credential handover — a materially
  worse bug than the one being fixed. This is why regression case 3 exists and
  why cross_account_guard specifies a SYNCHRONOUS re-check with no await
  between the check and the return: an await there re-opens exactly the window
  e7c1a9 closed for the coach_memory mirror.
---

# ensureFreshToken has no in-flight join: N callers, N refreshes

See frontmatter for the full analysis. One-line summary:
`SupabaseService.ensureFreshToken` holds no in-flight future, so every
concurrent caller inside the 5-minute expiry buffer independently calls
`refreshSession()`. During the 2026-08-13 outage this added load to an already
CPU-starved backend for sixteen minutes and released as a synchronised burst on
recovery (~15 `/auth/v1/user` 200s inside 400ms).

`AuthNotifier.signOut` already implements join-don't-race via `_inFlightSignOut`;
`SyncCoalescer` does it for the write fan-out. The auth path never got it.

The fix is a shared in-flight future GUARDED ON USER IDENTITY — without that
guard it is a cross-account credential leak, which is worse than the bug.
