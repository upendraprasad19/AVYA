---
bug_id: b6e4f2
date: 2026-08-06
batch: post38-auth-fixes (Unit 3 — every signed-out failure was structurally unloggable)
status: fixed
blast_radius: platform
symptom: >
  Founder hits "Could not send reset link. Try again." on the web app. The code
  that produced that message also calls
  ErrorTelemetry.logEvent('auth_forgot_password_send_failed'), so there should
  have been a row explaining what threw. There was not — and there never had
  been. That op_type had ZERO rows in the entire history of client_errors,
  leaving no evidence whatsoever of a founder-reported production failure.
concept: preauth_error_telemetry
sot_registry_entry: log_client_error_payload
writers: >
  lib/core/services/error_telemetry.dart:280-312 logEvent -> previously ALWAYS
  SupabaseService.callFunction. lib/features/auth/widgets/forgot_password_sheet
  .dart:79-88 is the reporting callsite that motivated this.
  supabase/functions/log-client-error/index.ts is the server-side writer into
  public.client_errors.
readers: >
  public.client_errors rows — read by the alert_client_errors_spike pg_cron job
  (current definition: migration 087) and by ad-hoc audit queries during
  debugging. The alert has NO user_id predicate and 087 deliberately
  RE-INCLUDES breadcrumb-coded rows whose op_type is failure-shaped, so
  pre-auth failures now reach it (every PRE_AUTH_OP_TYPES entry ends in _failed).
hive_key_prefix: "not_applicable — telemetry is cloud-only; no Hive key involved"
hive_key_formula: >
  not_applicable. The only Hive-adjacent state is ErrorTelemetry's in-memory
  cooldown, which is unchanged by this fix.
sync_methods: >
  None. This is the telemetry sink, not a domain sync fan-out. logEvent stays
  fire-and-forget and still swallows its own failure so it can never break a
  host flow.
restore_methods: >
  not_applicable — client_errors is write-only from the client; nothing restores it.
cloud_table: client_errors
cloud_columns: >
  user_id (uuid, NOT NULL -> NULLABLE by migration 119; FK to auth.users(id) ON
  DELETE CASCADE deliberately RETAINED — SQL foreign keys do not constrain NULL),
  error_code, error_message, op_type, retry_count, client_version, platform,
  created_at.
contract_test_path: test/contracts/error_telemetry_payload_contract_test.dart
ist_handling: >
  not_applicable for the fix. The lane's 24h budget uses a rolling
  now()-24h window, matching the pre-existing per-user budget — it is a rate
  limit, not an IST day-boundary counter, so no ist_date helper applies.
provider_invalidations: >
  None. Telemetry writes no app state and invalidates no provider.
telemetry_op_types: >
  New server-side allow-list PRE_AUTH_OP_TYPES, SIX entries:
  auth_forgot_password_send_failed, auth_password_recovery_verify_failed,
  auth_sign_in_failed, auth_sign_up_failed, auth_oauth_launch_failed,
  auth_send_phone_otp_failed. New response value priority_lane: "pre_auth".
  ⚠ CORRECTED 2026-08-08: this field listed FIVE, omitting
  auth_send_phone_otp_failed. Round-1 review added that sixth entry (it is the
  one op_type that was already emitted signed-out and therefore still 401'd),
  and the correction never reached this doc. All six now have a real emitter in
  lib/ — verified by grep, not from the code comment's claim.
  NOTE the anon lane is FORCED non-high-priority regardless of op_type: the
  HIGH_PRIORITY bypass exists to preserve a trusted user's P0 signals, and
  granting it to an unauthenticated caller would hand them an unbounded write.
  Today no allow-listed op_type matches a HIGH_PRIORITY prefix; the code makes
  that safe by construction rather than by coincidence.
cross_account_guard: >
  Strengthened, not weakened. The authenticated RLS INSERT policy
  ((SELECT auth.uid()) = user_id) is UNCHANGED and still rejects a NULL user_id,
  because NULL equals nothing in SQL — so a signed-in client cannot forge an
  anonymous row. The only path to a NULL row is the Edge Function's SERVICE_ROLE
  client, gated by the op_type allow-list and one global 200/day budget.
forbidden_patterns_checked: >
  No raw Hive.box; no setState; no inline isPro; no secrets in the diff; no
  Container(color:+decoration:). The direct functions.invoke added for the
  signed-out path is deliberate and documented — the fresh-token
  callFunction contract (rule 9) still governs every AUTHENTICATED event, and is
  untouched; the pre-auth branch is taken only when currentUser == null, where
  there is no token to refresh.
proposed_fix: >
  Remove all FOUR barriers, since any one left standing keeps the row unwritable.
  (1) client: logEvent routes a signed-out caller through a direct
  client.functions.invoke (which sends the anon key) instead of callFunction,
  which refreshes the session first and THROWS 'No active session. Please sign in
  again.' (supabase_service.dart:246-250) before the network.
  (2) function: a token resolving to no user is no longer an automatic 401 — the
  401 moves BELOW the body parse, to a gate that admits only an allow-listed
  pre-auth op_type and rejects everything else exactly as before.
  (3) column: migration 119 drops NOT NULL on client_errors.user_id.
  (4) RLS: deliberately LEFT IN PLACE, see cross_account_guard.
  Plus rule-17 surfacing at the forgot-password callsite: real error text in
  debug, unchanged generic line in release.
  REJECTED alternative — a sentinel "anonymous user" uuid: blocked by the FK
  (would require a fake auth.users row) and it corrupts reporting, since every
  per-user report would grow a phantom user with hundreds of errors. NULL is
  honest about not knowing; a sentinel is a lie shaped like a fact.
  REJECTED alternative — a separate table: doubles the query surface for every
  alert and every debugging session, when the whole value is seeing pre-auth and
  post-auth failures on ONE timeline.
regression_test_planned: >
  Verified end-to-end against LIVE production rather than only in test: an
  anon-bearer POST with an allow-listed op_type returned
  200 {"ok":true,"priority_lane":"pre_auth"} and the row LANDED —
  client_errors id b3fb0885-12b8-4633-b25a-2c3d670d08f2, user_id NULL,
  op_type auth_forgot_password_send_failed. A non-allow-listed op_type returned
  401. This is a write->read chain check, not an HTTP-shape check.
  test/contracts/error_telemetry_payload_contract_test.dart continues to pin the
  client/server payload-field parity that this change must not break.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ -> 0 errors, 0 warnings; error_telemetry.dart branches on currentUser == null" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "telemetry is cloud-only" }
  - { tier: 3, name: postgres_schema, status: fixed_in_this_batch, evidence: "migration 119 applied; verified live pg_attribute.attnotnull = false for client_errors.user_id" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "row b3fb0885 exists with user_id NULL and op_type auth_forgot_password_send_failed — an op_type with zero rows in the table's entire prior history" }
  - { tier: 5, name: migrations_applied, status: verified, evidence: "backups/applied_migrations.json entry 119 added. ⚠ supabase_migrations.schema_migrations has NO row for 119 — the founder ran the DDL by hand in the SQL editor after the auto-mode classifier refused apply_migration twice. list_migrations vs the manifest WILL show 119 absent server-side; that is expected, not drift. Do not re-apply." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "log-client-error deployed v11 -> v12, status ACTIVE (re-confirmed live 2026-08-08 via list_edge_functions: version 12). Boot-verified with an anon-key Bearer: returns the module's OWN 400 'Missing error_code' (a 503 would mean boot-broken). ⚠ SIGNATURE CHANGE: v11 returned the module's 401 'Invalid or expired token' on that same probe; v12 returns 400 because the 401 moved below the body parse. The deploy-skill rule (module's own 4xx = booted) still holds — the code it produces changed." }
  - { tier: 6, name: edge_function_repo_vs_deploy_drift, status: verified, evidence: "⚠ CORRECTED 2026-08-08. This row previously claimed the deploy was 'byte-identical' at 21976 bytes. That was true AT DEPLOY TIME and is NOT true now: round-1 review then added the sixth allow-list entry to the repo source, which was never redeployed. Measured by decoding .claude/_payload_log-client-error.json as UTF-8 and diffing against the worktree file — deployed 18334 chars vs source 19253, and the SOLE difference is the PRE_AUTH_OP_TYPES block (5 entries live, 6 in source). Prod is therefore one entry behind pending a v13 redeploy. Latent, not live-broken: _kEnablePhoneEnlist = false (lib/features/auth/screens/sign_in_screen.dart:27) makes signInWithPhone unreachable, so nothing emits auth_send_phone_otp_failed today. This is a fresh instance of OI-93's mechanism (a deployed EF lagging the repo undetected), not a new discovery." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "alert_client_errors_spike (migration 087) counts client_errors over 1h with NO user_id predicate and re-includes failure-shaped breadcrumb rows, so pre-auth failures reach the alert. Intended; bounded by the lane's 200/day cap." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "pg_policies client_errors INSERT with_check still ((SELECT auth.uid()) = user_id) after the migration — unchanged, and it still rejects NULL" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: verified, evidence: "no new secret; the lane uses the existing SUPABASE_SERVICE_ROLE_KEY already required by this function. Anon key is public by design (it ships in the web bundle) and is NOT the security boundary — the op_type allow-list and the global cap are." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no third-party service in this path" }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "full chain exercised live: client-shaped anon POST -> EF pre-auth lane -> migration-permitted NULL -> row readable in Postgres" }
impact_analysis: >
  The blast radius is diagnostic capability, not user-facing behaviour: no user
  ever saw a symptom from this, which is exactly why it survived so long. The
  cost was paid every time something broke before sign-in — we lost the evidence
  and had to guess. It made the Unit-4 intermittent send failure undiagnosable
  in principle: transient, self-healing, and unloggable is an unsolvable
  combination.
  The Edge Function's own header calls auth failures signals "we must never
  lose" and gives auth_failure_ a HIGH-priority lane; half of those — every
  signed-out one — could never reach it. The gap was not an oversight in one
  place but four independent mechanisms agreeing, which is why a partial fix
  would have looked correct and changed nothing.
  ACCEPTED RISK, stated plainly: this opens a narrow write path reachable by
  anyone holding the project's anon key, which is public by construction. It is
  bounded by an op_type allow-list and ONE global 200-row/24h budget, so the
  worst case is 200 junk rows per day and a spike alert firing — noisy, capped,
  and self-announcing. That is a deliberate trade against permanent blindness.
related_bugs: e9f2a4, c8f1d3, d3a7c9
recurrence: >
  Same family as c4f8d2 (backend collapse drops the telemetry that would explain
  it) and the observability_silent_drop class: the sink that would have recorded
  the incident was itself disabled by the incident's own conditions. The
  generalisable rule — when you add telemetry to a code path, ask what auth
  state that path runs in, and whether the sink accepts writes in that state.
---

# Every signed-out failure was structurally unloggable (b6e4f2)

## Four barriers, all load-bearing

Any ONE of these would have been enough to lose the row. All four were present,
so any partial fix would have looked right and changed nothing:

1. **Client** — `callFunction` refreshes the session first and throws
   `No active session. Please sign in again.` (`supabase_service.dart:246-250`).
   The event died before the network.
2. **Function** — `index.ts` returned 401 for any token resolving to no user, and
   stamped `user_id: user.id` from the verified token.
3. **Column** — `client_errors.user_id` was `NOT NULL`.
4. **RLS** — INSERT policy `(SELECT auth.uid()) = user_id`.

## Why barrier 4 stays

It is the thing that keeps the new lane narrow. With the column now nullable, an
authenticated client still cannot insert a NULL row, because `NULL = anything` is
never true in SQL. Only the service-role function can, and only for an
allow-listed op_type under the global cap.

## Proof, end to end

| Probe | Result |
|---|---|
| anon bearer, invalid body | `400 {"error":"Missing error_code"}` — module's own error, so it booted |
| anon bearer, allow-listed op_type | `200 {"ok":true,"priority_lane":"pre_auth"}` |
| anon bearer, non-allow-listed op_type | `401 {"error":"Invalid or expired token"}` |
| Postgres | row `b3fb0885`, `user_id NULL`, `op_type auth_forgot_password_send_failed` |
