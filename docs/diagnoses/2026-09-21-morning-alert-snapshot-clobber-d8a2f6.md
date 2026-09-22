---
bug_id: d8a2f6
date: 2026-09-21
batch: food-logging-observations
status: fixed
blast_radius: platform
symptom: >
  Founder (PRO) reported never receiving a morning brief push notification. Live-verified via
  the app's own "hi" chat reply, which read the same broken data: "Your last proactive nudge
  was a morning brief today" alongside a snapshot that in fact carries no such alert.
  `cron_call_log` shows `morning-alert` ran successfully (HTTP 200) five times on 2026-09-21.
  But `user_daily_snapshots.snapshot_json->>'morning_alert'` was NULL for this user on BOTH
  2026-09-21 and 2026-09-20. `morning-alert`'s deliver mode does `if (!alertMsg) return;` with
  no log line and no error on a null alert — a fully silent skip. Sampled system-wide for
  2026-09-21: 2 of 7 users had a null `morning_alert`, so this is live and ongoing, not isolated
  to one account.
concept: daily_snapshot_server_key_preservation
sot_registry_entry: daily_snapshot_server_key_preservation
writers:
  - { file: supabase/functions/_shared/snapshot_merge.ts, method: "mergeSnapshotJson — pure merge, existing row spread first, incoming client payload layered on top", line: 23 }
  - { file: supabase/functions/daily-snapshot/index.ts, method: "serve handler — reads existing row via .maybeSingle() (:363), merges via mergeSnapshotJson (:384), upserts the MERGED result (:397) instead of the raw request body; gated behind DISABLE_SNAPSHOT_MERGE_SAFE_UPSERT (:357, added in code-review remediation). Line numbers shifted +1 by the observation-batch-and-digest-redesign merge (PR #32, 2026-09-22) inserting one unrelated line earlier in the same file (extractCoachingNotes' retries: 2) — re-verify by grep, not by citation, per this repo's own common-pitfalls row on line-count drift.", line_range: "340-398" }
  - { file: supabase/functions/morning-alert/index.ts, method: "generate mode — already correct: reads existing row, spreads it, layers morning_alert/morning_alert_type/morning_alert_generated_at on top", line: 286 }
readers:
  - { file: supabase/functions/morning-alert/index.ts, method_or_widget: "deliver mode — const alertMsg = snap.snapshot_json?.morning_alert; if (!alertMsg) return;", line: 413 }
hive_key_prefix: not_applicable — entirely server-side (Edge Function to Postgres), no Hive box involved.
hive_key_formula: not_applicable — see hive_key_prefix.
sync_methods: >
  not_applicable in the WriteService sense — the client-side call site is sync_service.dart's
  pushSnapshot/pushSnapshotNow (registered under the existing ai_snapshot_building concept),
  which is unchanged by this fix. The fix is entirely inside the Edge Function that receives
  that push.
restore_methods: >
  not_applicable — no Hive restore path is involved. This is a cloud-side write-collision
  between the client's daily-snapshot push and server crons, not a client restore concept.
cloud_table: user_daily_snapshots
cloud_columns: [user_id, snapshot_date, snapshot_json]
contract_test_path: supabase/functions/_shared/snapshot_merge_test.ts
ist_handling:
  - { file: supabase/functions/daily-snapshot/index.ts, line: 340, fn: "getTodayIST — unchanged; snapshotDate is the same IST-day key already used by the pre-fix upsert, now reused to scope the new pre-read. (This citation was already off by one pre-merge — corrected here to the call site's actual current line, not just shifted.)" }
provider_invalidations: >
  None — no Riverpod provider is touched. This is a server-side Edge Function fix; the client
  is unmodified.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  No new cross-account surface. The new SELECT reuses the EXACT SAME `userId` (from the
  already-verified JWT, supabaseClient.auth.getUser(token) at line 313) and `snapshotDate`
  that the pre-fix code already used to scope the upsert — it is strictly a read added before
  a write that was already correctly user-scoped.
forbidden_patterns_checked: >
  No istDateStr(istNow(...)) double-shift pattern introduced (no new date arithmetic — reuses
  the existing snapshotDate). No .single() used for the new read (would throw on a legitimate
  first-snapshot-of-the-day absence) — .maybeSingle() used instead, matching the pattern this
  repo's own supabase/functions/CLAUDE.md documents for weekly_report_free_gate /
  media_free_image_lifetime_gate (absent row = legitimate empty state, only a populated `error`
  should fail closed).
proposed_fix: >
  Extract a pure mergeSnapshotJson(existing, incoming) helper into _shared/ (existing spread
  first, incoming layered on top, so the client stays authoritative for everything it knows
  about while any key it has never heard of — morning_alert, and by the same shape
  future_prediction / beat_my_coach's fields — survives). Wire daily-snapshot/index.ts's upsert
  to read the existing row first (.maybeSingle()) and upsert the merged result instead of the
  raw request body. This mirrors the read-modify-write pattern morning-alert's OWN generate
  mode already uses correctly (line 286) — daily-snapshot was the ONE writer among the four
  that still did a blind wholesale replace.
regression_test_planned:
  - supabase/functions/_shared/snapshot_merge_test.ts
  - supabase/functions/daily-snapshot/index_test.ts
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No client (lib/) file touched — the bug and the fix are both entirely server-side." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive box involved in this concept." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No column/table added, dropped, or renamed. user_daily_snapshots.snapshot_json already existed and is unchanged in shape." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live query 2026-09-21: 2 of 7 user_daily_snapshots rows dated 2026-09-21 have snapshot_json->>'morning_alert' IS NULL; founder's own row confirmed NULL on both 2026-09-21 and 2026-09-20, and its created_at changed between two reads 13 minutes apart during this same investigation — direct evidence of an in-flight overwrite." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this fix." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "daily-snapshot/index.ts fixed locally; deno check passes clean; NOT YET DEPLOYED — live Edge Function deploy requires its own explicit founder authorization per CLAUDE.md §4.3, separate from this batch's code changes." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "cron.job: morning_alert_generate (jobid 5, schedule 30 20 * * * UTC = 02:00 IST, mode=generate) and morning_alert_deliver_early/late (jobid 17/16, */15 0-6 and */15 22-23 UTC, mode=deliver) all active. cron_call_log confirms morning-alert ran 5x today, all status=success — the cron infrastructure was never the problem." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "daily-snapshot already used a service-role client scoped by the JWT-verified userId before this fix; the new read uses the identical scoping, no policy surface changed." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret added, read, or rotated." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "OneSignal delivery is downstream of the send/don't-send decision this fix protects the INPUT to; the OneSignal call itself is unchanged." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "The request/response shape of the daily-snapshot Edge Function is unchanged — same body in, same 200/error shape out. Only the server-side persistence behavior changed." }
impact_analysis: >
  Every user whose account has ever had a cron write a key into snapshot_json (morning_alert
  today; future_prediction / beat_my_coach / rolling-context's fields by the same mechanism) is
  exposed the moment they use the app again before that cron's next run overwrites it fresh.
  The failure is silent by construction on both ends: daily-snapshot's upsert never errors (it
  succeeds at replacing the row), and morning-alert's deliver mode never errors either (a null
  alertMsg is treated as "nothing to send today", not a fault) — so nothing in the current
  telemetry would ever have surfaced this without a live data cross-check. Recurrence,
  explicitly: this is the same mechanism as diagnose e4a1b7/OI-98
  (docs/diagnoses/2026-08-26-notification-prefs-push-only-e4a1b7.md), which named the general
  shape ("snapshot_json is a materialised read model... replaced wholesale on write... correct
  for disposable, regenerable data") but scoped its actual fix to ONE key
  (notification_preferences, moved to its own table). This diagnose-doc closes the same class
  for daily-snapshot's write path in general, rather than moving morning_alert to its own table
  the way e4a1b7 did for notification_preferences — because morning_alert (and its cron
  siblings) are legitimately snapshot-scoped, cron-owned, single-key data with no independent
  restore/merge requirement the way user-intent preferences have; the fix that fits is making
  the ONE careless writer merge-safe, not relocating every careful writer's data.

  Explicitly out of scope, stated rather than silently left: this fix does not make the four
  snapshot_json writers (daily-snapshot, morning-alert, rolling-context, future-prediction,
  beat-my-coach) atomic against EACH OTHER. Each still does its own application-level
  read-modify-write, so two of them racing the exact same row at the exact same instant could
  still lose an update to each other — a Postgres RPC doing an atomic `snapshot_json ||
  $delta` (the approach e4a1b7's own final fix used for notification_preferences) would close
  that residual race fully, but requires a migration touching a table four live Edge Functions
  read/write, which is disproportionate to the actual reported symptom: the GUARANTEED clobber
  from ANY client sync after a cron write, which this fix closes completely. Worth its own OI
  if the founder wants the race closed too.
---

# d8a2f6 — daily-snapshot's wholesale upsert silently destroyed the day's morning brief

## What a user experiences

You never get your morning push notification. Nothing in the app or its logs tells you why —
the cron ran, reported success, and the AI coach even claims (from stale, unrelated
`coach_memory` state) that you got one "today."

## The mechanism

`morning-alert`'s generate step (02:00 IST) correctly writes `morning_alert` into today's
`user_daily_snapshots` row via a read-modify-write. Any time after that — in practice, the next
time you open the app and it syncs — `daily-snapshot` fires and REPLACES the entire row with a
freshly Hive-rebuilt payload that has never heard of `morning_alert`, because that field isn't
client-observable data. The delivery poller (running every 15 minutes for hours) then finds
`snapshot_json.morning_alert` null and silently returns, having nothing to send.

Caught live during this investigation: the founder's own snapshot row's `created_at` changed
between two reads 13 minutes apart — direct proof of an overwrite happening in real time.

## Why this is a recurrence, not a new class

`docs/diagnoses/2026-08-26-notification-prefs-push-only-e4a1b7.md` (OI-98) diagnosed the exact
same container problem on `notification_preferences` and fixed it by moving that ONE field out
of the blob entirely. Its own `concept:` field said the plainly: the blob is "correct for
disposable, regenerable data — which is every other key it carries." That sentence was an
assumption, not a verified claim, about every OTHER key — `morning_alert` is exactly one of
those "every other key"s, and it was not actually safe.

## The fix

`daily-snapshot/index.ts` was the one writer among four that did a blind replace. It now reads
the existing row first and merges — mirroring the read-modify-write pattern its three sibling
writers (`morning-alert`, and by the same shape `rolling-context` / `future-prediction` /
`beat-my-coach`) already used correctly. Extracted as a pure `mergeSnapshotJson` helper so it's
testable without booting a server or touching a real database.

## Deploy status

Code changes are local and tested (`deno check` clean, 7/7 tests green, mutation-proven). **Not
deployed.** Per CLAUDE.md §4.3, a live Edge Function deploy needs its own explicit
authorization separate from landing the code.
