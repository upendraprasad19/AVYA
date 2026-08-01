---
bug_id: d3f7b2
date: 2026-08-01
batch: oi79-paged-cron-reads (Unit 9 of the OI-25/44/45/46/48/50 batch)
status: fixed
blast_radius: platform
symptom: >
  Every fan-out read in the cron Edge Function fleet silently stopped at 1000
  rows. PostgREST caps an un-ranged response at db-max-rows and returns HTTP
  200 with error===null, so a truncated candidate set was indistinguishable
  from a small one. On five reads the truncation did not merely skip users, it
  INVERTED their classification and produced a factually wrong push
  notification.
concept: unbounded_postgrest_reads_in_cron
sot_registry_entry: n/a — no Hive/cloud writer contract changed; this is a
  read-completeness fix on the server side only.
writers: >
  n/a for the bug itself (no writer changed). The reads fixed are:
  protein-gap-alert/index.ts:101,142,172,181 ·
  workout-window-closing/index.ts:90,129,186,191 ·
  streak-guardian/index.ts:73,110 · plateau-alert/index.ts:99,136 ·
  evaluate-rank-promotions/index.ts:138,+fetchInChunks:71-101 ·
  re-engagement/index.ts:141,216 · expiry-reminder/index.ts:60 ·
  pr-detection/index.ts:87 · rolling-context/index.ts:143,172,253 ·
  compute-coach-signals/index.ts:67 · clean-orphan-media/index.ts:69 ·
  promote-community-item/index.ts:264 · weekly-recap-ready/index.ts:169,178 ·
  _shared/notification_prefs.ts:80 · _shared/subscription.ts:64
readers: >
  The candidate/exclusion sets each read feeds:
  proteinByUser (protein-gap-alert), loggedUserIds (workout-window-closing,
  streak-guardian), proSet (plateau-alert), ranksBatch (evaluate-rank-promotions),
  candidatesFromMemory + fallbackCandidates (re-engagement), prefs map
  (_shared/notification_prefs.ts → isNotificationEnabled at every caller).
hive_key_prefix: n/a — server-side only, no Hive involvement.
hive_key_formula: n/a — server-side only, no Hive involvement.
sync_methods: n/a — cron Edge Functions do not participate in client sync.
restore_methods: n/a — no restore path touched.
cloud_table: >
  users, coach_memory, subscriptions, nutrition_logs, workout_logs,
  scheduled_workouts, workout_templates, user_profile, user_daily_snapshots,
  user_progress, rank_promotions, workout_log_exercises, ai_coach_interactions,
  community_reviews, memory_embeddings
cloud_columns: >
  No column added, dropped or renamed — reads only. Sort keys used for paging
  were verified against live PK metadata (pg_constraint): every table above is
  keyed on `id` EXCEPT coach_memory, whose PK is `user_id` (it has no `id`
  column at all). RPC sort columns verified against live pg_get_function_result:
  find_orphan_chat_media(user_id, path), active_users_for_signals(user_id),
  find_reengagement_silent_candidates(user_id, full_name),
  get_users_with_message_count(user_id, msg_count).
contract_test_path: supabase/functions/_shared/paged_fetch_test.ts
ist_handling: >
  not_applicable — no date-key or counter-reset logic changed. The IST date
  helpers already in these functions (getTodayIST) are untouched and still feed
  the same .eq("date", todayIST) filters; only the row-count bound changed.
provider_invalidations: n/a — no client Riverpod provider touched.
telemetry_op_types: >
  No new telemetry op_type. Existing cron_call_log telemetry is preserved and in
  three places made MORE truthful: streak-guardian and expiry-reminder used to
  report a failed read as cron status "success" with users_checked=0, and
  _shared/subscription.ts carried a saturation canary that could never fire.
cross_account_guard: >
  not_applicable — every read fixed is either service-role fleet-wide (already
  cross-user by design, running in a cron context with no end-user session) or
  already scoped by an explicit .eq("user_id", …). No read had its user scoping
  widened or narrowed; only its row count changed.
forbidden_patterns_checked: >
  - Container(color:+decoration:) — n/a, no Flutter widget touched.
  - unawaited() without an error sink — none introduced; every new call site is
    awaited inside an existing try/catch.
  - .functions.invoke without FunctionException handling — n/a, no client invoke.
  - Bare String(err) on a PostgrestError — preserved the existing
    .message-unwrapping at both re-engagement path tags; introduced none.
  - Source-grep without stripping comments — CAUGHT IN THIS BATCH, see
    "The gate's own bug" below.
proposed_fix: >
  A shared _shared/paged_fetch.ts exposing fetchAllPages (required orderBy, no
  default) and fetchAllByIds (chunks the .in() list AND pages within each
  chunk), route every unbounded cron read through it, and add
  scripts/check_unbounded_cron_reads.dart so a new one cannot ship.
regression_test_planned: >
  supabase/functions/_shared/paged_fetch_test.ts — 18 Deno tests including an
  explicit NEGATIVE CONTROL that pins the pre-fix behaviour (a single un-ranged
  read returns 1000 of 1431 with error===null), so the paging test next to it is
  demonstrably a regression test rather than an assertion about the helper.
  Plus scripts/check_unbounded_cron_reads.dart, verified to exit 1 on an
  injected unbounded read and 0 when clean.
touched_layers_checked:
  - { tier: 1_client_code, status: verified, evidence: "Zero files under lib/ changed — no client runtime code is touched. The staged set is scripts/ + supabase/functions/ + docs/ + two test/contracts/*.dart files, so flutter analyze IS in scope (it covers test/) and is clean. deno check across supabase/functions/ exits 0 and the 316-test deno suite passes (re-measured on the merged tree 2026-08-01: ok | 316 passed | 0 failed. This line said 315, which was true when written and went stale within the same batch once the 'server cap BELOW pageSize' regression test was added — a count asserted mid-batch and never re-measured at merge). The two .dart edits are assertion fixes, not production code: F21/F22 in the closure ledger." }
  - { tier: 2_hive, status: not_applicable, evidence: "No Hive box, key or adapter touched. Every read fixed is a server-side PostgREST call inside a cron Edge Function." }
  - { tier: 3_postgres_schema, status: verified, evidence: "No DDL in this batch. Every pagination sort key was validated against live catalog metadata before use: pg_constraint PK lookup for the 15 tables (all keyed on `id` EXCEPT coach_memory, whose PK is user_id and which has no id column — assuming id would have thrown 42703 at runtime), and pg_get_function_result for the 4 RPCs paged here (find_orphan_chat_media(user_id,path), active_users_for_signals(user_id), find_reengagement_silent_candidates(user_id,full_name), get_users_with_message_count(user_id,msg_count))." }
  - { tier: 4_postgres_data, status: verified, evidence: "Live row counts queried 2026-08-01 against dedsavbjuwgarrhphgnl to size the exposure: 18 users; scheduled_workouts 565 (largest per-user table); nutrition_logs max 4 rows/user/day; user_daily_snapshots 97 rows across 17 users (~5.7 each); rank_promotions 19/18. Confirms NOTHING truncates at today's scale — this is a latent correctness fix, not a live outage, and the diagnose-doc says so rather than overclaiming." }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "This batch adds no migration; backups/applied_migrations.json is unchanged and no apply_migration call was made." }
  - { tier: 6_edge_function_code_vs_deploy, status: verified, evidence: "DEPLOYED 2026-08-01, after this doc was first written — git and the live fleet now AGREE. All 16 versions read back from the Management API (GET /functions/<slug>), not from the deploy tool's own output: protein-gap-alert v11, workout-window-closing v10, streak-guardian v21, plateau-alert v10, evaluate-rank-promotions v15, weekly-recap-ready v19, proactive-coach-promotion v10, re-engagement v12, expiry-reminder v18, pr-detection v12, compute-coach-signals v12, clean-orphan-media v9, rolling-context v18, promote-community-item v13, morning-alert v31, weekly-recalc v21. Every verify_jwt=false preserved. DEPLOY SET IS 16, DERIVED NOT ASSUMED: the 15 Edge Function directories changed in the diff, PLUS proactive-coach-promotion, which changes no file of its own but imports _shared/notification_prefs.ts — a real code change (the paged fetchAllByIds fix) that it consumes. A deploy plan keyed on changed directories would have silently skipped it. EXCLUDED, deliberately: ai-proxy also imports a changed _shared file, but its ONLY changed dependency is memory_retrieval.ts whose entire diff is three COMMENT lines, so it is functionally byte-identical — redeploying the highest-traffic client-facing function for a comment would be risk with no fix; it stays at v79. Per CLAUDE.md 4.3 the wave took its own explicit authorization beyond plan approval. No migration dependency, so no ordering constraint; deployed by severity, Class 1 first, each boot-verified (HTTP 401 per function, which for a verify_jwt=false function means the module booted and its own cron gate rejected the probe). History, kept because the reasoning is the durable part: this tier read 'pending_explicit_authorization' until the B-pass correctly flagged it as outside the CLAUDE.md 6 enum — verified/fixed_in_this_batch/not_applicable/deferred — and then read as a verified DELTA (git differs from the deployed fleet) for the window between the merge and the deploy wave. Each was true when written; both are superseded by this line." }
  - { tier: 7_cron_jobs, status: verified, evidence: "Roster of 16 cron-dispatched functions read from docs/operations/CRON_REGISTRY.md; the new gate derives its scan set from that same file so it cannot drift from the real fleet, and fails closed if that table ever parses to zero. No cron schedule, job name or auth gate changed." }
  - { tier: 8_rls_policies, status: verified, evidence: "No RLS policy changed. Incidentally confirmed live that the 3 anon-executable set-returning RPCs (get_users_with_message_count, match_memories, morning_alert_pick_quarter) are NOT SECURITY DEFINER — an anon call returns 0 rows because RLS applies with the caller's own privileges. That independently corroborates OI-78's 'unwanted attack surface, not a confirmed live leak' classification, and is also why the RPC row-cap probe via anon was inconclusive." }
  - { tier: 9_storage, status: verified, evidence: "clean-orphan-media's candidate read is now paged, but its storage.remove() loop is unchanged and still runs AFTER the full candidate set is collected — so no delete interleaves with pagination and the paged set cannot shift underneath the loop. No bucket or object touched otherwise." }
  - { tier: 10_secrets, status: not_applicable, evidence: "No secret read, written or rotated. The live empirical measurements used the gitignored SUPABASE_ANON_KEY from the worktree .env and no key value appears in any committed file." }
  - { tier: 11_external_services, status: not_applicable, evidence: "OneSignal / Gemini / Razorpay call sites untouched. Push volume may RISE once deployed because more candidates are found per tick — that is the intended effect of the fix, not a regression." }
  - { tier: 12_client_server_contract, status: verified, evidence: "No client-facing contract changed: all 15 CHANGED functions are cron-triggered (16 were deployed — see tier 6 for why the deploy set is one larger than the changed set) and return only status JSON to pg_cron, and every response key set is byte-identical (the re-engagement key-set parity test from Unit 5 still passes). The 9 re-engagement index_test.ts tests, including the Hermes L34 path-tag test, pass unchanged after the Path A/B rewrite." }
impact_analysis: >
  Nothing is truncating today at 18 users, so no user has yet received a wrong
  push from this. The value is that five reads whose failure mode is a WRONG
  notification (not a missing one) are now bounded before the user base reaches
  the threshold — the nearest of which, protein-gap-alert's nutrition_logs read,
  bites at roughly 250 active PRO users. Two more shipped guards that could
  never fire (a 5000-row canary behind a 1000-row cap) are now genuinely
  reachable. Cost is one extra round-trip per read only when a result actually
  fills a page; at current scale every read still completes in a single request.
---

# d3f7b2 — Unbounded PostgREST reads across the cron Edge Function fleet

Closes **OI-79**. Unit 9 of the OI-25/44/45/46/48/50 batch.

## What was actually wrong

OI-79 was filed off a Hermes L31 finding during Unit 5 and described the
truncation as observable via `HTTP 206 Partial Content`. **That is wrong in the
shape our code uses**, and the correction matters because anyone hunting this by
looking for a 206 would find nothing. Measured live 2026-08-01 against
`food_database` (1431 rows):

| request | status | `Content-Range` | rows |
|---|---|---|---|
| `?select=id` — what supabase-js `.select()` sends | **200 OK** | `0-999/*` | 1000 |
| `Range: 0-1499` | 200 OK | `0-999/*` | 1000 |
| `Range: 1000-1999` | 200 OK | `1000-1430/*` | 431 |
| `Prefer: count=exact` | 206 | `0-999/1431` | 1000 |

Three consequences, each load-bearing:

1. **It is a 200.** The 206 only appears when the caller requests a count, which
   no cron function does. `error` is null, the body is just short, and the total
   is `*` — the response does not even carry the information needed to detect
   the loss. The only signal available is `rows.length === pageSize`.
2. **`.range()` cannot raise the cap.** Asking for 0-1499 still yields 1000. So
   a page size above the cap does not fetch more — it makes the first full page
   look short and silently ends the loop.
3. **Paging past it works**, so a `.range()` loop is a real fix.

No per-role `pgrst.db_max_rows` override exists (`pg_db_role_setting` → 0 rows),
so the cap applies to `service_role` — which is what every cron function uses.

## Four classes, one of them worse than OI-79 described

OI-79 named only the two `re-engagement` candidate scans. Re-running the lens
across all 16 cron functions found:

**Class 1 — silently WRONG.** Follow-up `.in(userIds)` joins that decide who is
EXCLUDED. Truncation here does not skip a user, it misclassifies them:

| site | table | failure | bites at |
|---|---|---|---|
| `protein-gap-alert:142` | nutrition_logs | partial protein sums → **false "you're short on protein" push to someone who hit target** | **~250 active-PRO users** |
| `workout-window-closing:129` | workout_logs | user who DID train is told their window is closing | ~1000 |
| `streak-guardian:110` | workout_logs | same shape | ~1000 |
| `plateau-alert:136` | subscriptions | PRO read as free → alert suppressed | ~1000 |
| `evaluate-rank-promotions` `fetchInChunks` | rank_promotions | missing rank history → **duplicate promotion ceremony** | ~10 ranks/user |
| `_shared/notification_prefs.ts:80` | user_daily_snapshots | **every notification toggle silently ignored** | **~175 users** |

`evaluate-rank-promotions` deserves its own note: it already had a
`fetchInChunks` helper (`BATCH_SIZE = 100`) that *looks* like the mitigation.
**It bounds the input array, not the output rows.** A 100-id chunk against a
multi-row-per-user table returns 100×N rows. An existing helper that appears to
solve the problem and does not is worth naming explicitly.

`_shared/notification_prefs.ts` is the sharpest one. It reads
`user_daily_snapshots` (~5.7 rows/user) ordered `snapshot_date DESC` and keeps
the first row per user. Truncation removes the TAIL — exactly the users whose
newest snapshot is oldest — and under that file's own documented `ABSENT ⇒ SEND`
rule those users' preferences then read as absent. That is precisely the failure
its header was written to prevent ("the toggles would still do nothing, while
looking implemented"), arriving by a different route.

**Class 2 — under-coverage.** ~14 un-ranged candidate scans; the failure is a
missed nudge rather than a wrong one.

**Class 3 — unreachable limits.** Code asserting a ceiling that cannot hold:
`rolling-context:155` `.limit(10000)`; `active_users_for_signals()`'s internal
`limit 5000` (making `compute-coach-signals`'s "worst-case is 5000" header
comment false); and `_shared/subscription.ts` `.limit(5000)` — which also had a
`rows.length >= 5000` saturation canary that **could never fire**, because the
truncation it existed to announce happened 4000 rows below its threshold. A
detector that is structurally always false is worse than none: it reads as "we
would have been told". Same shape as the `mark_failures` counter Hermes refuted
in Unit 5.

**Class 4 — unstable pagination in the loops that already existed.** Not in
OI-79 at all. `.range()` without `.order()` has no cross-page row-order
guarantee, so pages can skip or duplicate rows: `morning-alert:801`,
`weekly-recap-ready:134`, `weekly-recalc:133`. `i-see-you-callout:101` does it
right. So `i-see-you-callout` is the precedent to mirror, not `morning-alert` as
OI-79 suggested — and OI-79's other citation is off too: `morning-alert:578-594`
is not a `.range()` loop but a `p_offset`/`p_limit` RPC, which is the better
pattern.

## The fix

`supabase/functions/_shared/paged_fetch.ts`:

- `fetchAllPages(makeQuery, {orderBy, …})` — `orderBy` is **required with no
  default**, because a pagination loop without a stable sort key IS the Class 4
  bug and should be unconstructible. Accepts a compound key so
  `notification_prefs`' `snapshot_date DESC` semantics survive paging with `id`
  as the unique tiebreaker.
- `fetchAllByIds(makeQuery, ids, …)` — chunks the `.in()` list AND pages within
  each chunk. Replaces `fetchInChunks`.
- Rejects `pageSize > 1000` with an explanatory error rather than silently
  truncating.
- Throws on a page error instead of returning partial rows: proceeding with an
  incomplete candidate set is the exact failure this module exists to prevent.

Class 4 sites got a one-line `.order()` rather than being rewritten through the
helper — they already paginate correctly apart from ordering, and rewriting them
would have changed `morning-alert`'s partial-failure semantics for no benefit.

## Two pre-existing swallow-the-error bugs fixed in passing

Both are the `a7e2c4` class (an Edge Function read coercing a failure into empty
data), found while touching the same lines:

- `streak-guardian:106` did not destructure `error` at all, so a failed
  "who trained today" read coerced to `?? []` = "nobody trained" = alert
  everyone. That site was missed by the a7e2c4 sweep.
- `streak-guardian` and `expiry-reminder` both had `if (err || !rows || length
  === 0)` guards that reported a FAILED read as cron status `success`. A broken
  query looked like a healthy tick while nobody got guarded or reminded.

## The gate

`scripts/check_unbounded_cron_reads.dart` — auto-wired by pre-commit's
`scripts/check_*.dart` glob. Derives its cron roster from `CRON_REGISTRY.md` so
it cannot drift, and **fails closed** if that table ever parses to zero
functions rather than reporting a vacuous pass. Bounded = routed through
`paged_fetch`, `.single()`/`.maybeSingle()`, a head-count, a `.limit(n≤1000)`, a
`.range()` loop, or `p_offset`+`p_limit` RPC args. An `// oi79-ok: <reason>`
waiver covers genuinely per-entity reads; there are 5, each with a written
justification, and the count is printed on every clean run so they stay visible.

Verified non-vacuous: injecting `supabase.from("users").select("id")` into
`expiry-reminder` makes it exit 1 and name the line; removing it returns exit 0.

### The gate's own bug, worth recording

The first run reported 51 violations, of which 3 classes were the gate's fault:
`fetchAllPages<Record<string, unknown>>(` has a generic parameter my
helper-detection regex did not allow; `.insert(` chains are not reads; and
`morning-alert`'s `p_offset`/`p_limit` RPC is bounded. A fourth was worse — it
flagged `re-engagement:184`, which is **prose inside a comment** describing what
the old code did. That is a direct recurrence of
`feedback_source_grep_strip_comments_first.md`: strip comments BEFORE any
source-pattern scan. The gate now blanks comment bodies (preserving offsets so
line numbers stay right) and matches waivers against the raw text.

Two of the 51 were real findings the manual sweep had missed —
`weekly-recap-ready:169/174` — which is the argument for the gate existing.

## Recurrence

Not a recurrence of a truncation bug; `docs/diagnoses/INDEX.md` has none. It IS
the third instance of the broader family *a server read silently yields
incomplete data and the code cannot tell*:

- `a7e2c4` (2026-07-08) — 12 EF reads destructuring `.data` without `.error`.
- `b9f4d2` / `d7c3f1` — EF selects a nonexistent column → 400 → null → defaults
  → silently inert.
- `d3f7b2` (this) — EF read truncated by the platform → short array → wrong set.

The through-line: **a read that returns fewer rows than it should, without
erroring, is invisible to every caller.** The first two were fixed per-site; this
one ships a structural gate because that is the third time.

## Residuals, stated

- **Deployed 2026-08-01.** 15 Edge Function directories changed, but the deploy
  set is **16** — `proactive-coach-promotion` consumes the changed
  `_shared/notification_prefs.ts` without a diff of its own — and all 16 are live
  with their versions read back from the Management API (tier 6 above).
  `ai-proxy` is deliberately excluded and stays at v79. This bullet read *"Not
  deployed — the live fleet still truncates until each is deployed"* (and said
  15, not 16) until the wave ran; corrected here rather than silently rewritten,
  because a residual that outlives its own truth is how a doc starts lying.
- **`community_votes_summary` does not exist** in any schema (verified live
  across all of `pg_proc`). `promote-community-item`'s `.rpc()` therefore errors
  on every tick and the "fallback" count is the only live path. Its read is
  fixed here; the missing RPC is a separate defect and is filed rather than
  fixed, because inventing the aggregate's semantics is a product decision.
- **10 per-user reads still destructure `.data` without `.error`** in
  `morning-alert` (4), `i-see-you-callout` (4), `rolling-context` (1),
  `weekly-recalc` (1). Same a7e2c4 class, but per-user degradation of AI prompt
  context rather than a fleet-wide wrong push, and in four functions this batch
  otherwise does not touch. Filed, not folded in.
- **RPC cap unproven.** Whether `db-max-rows` also caps `/rpc/` responses could
  not be settled from here: the only anon-executable set-returning functions are
  not SECURITY DEFINER, so RLS returns 0 rows to anon and the probe is
  inconclusive. It does not affect correctness — the helpers page
  unconditionally, which is right either way. **Still unsettled after the deploy
  wave**: this bullet originally said the deploy-time behavioural check would
  settle it against a service-role path, and it did not. The wave boot-verified
  each function (HTTP 401 per `verify_jwt=false` function) but ran no row-count
  probe, and at 18 live users no RPC returns anything near 1000 rows, so there is
  nothing to observe from production either. Settling it needs a service-role
  request to `/rest/v1/rpc/<fn>` against a function that genuinely returns >1000
  rows — which today means creating one. Recorded as measured-not-yet, not as
  answered.
