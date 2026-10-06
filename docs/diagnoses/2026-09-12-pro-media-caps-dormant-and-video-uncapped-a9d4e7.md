---
bug_id: a9d4e7
date: 2026-09-12
batch: oi153-pro-media-caps
status: fixed
blast_radius: platform
symptom: >
  ai-media-proxy's PRO daily image cap (H-23, 50/day) had NEVER FIRED: the
  gate counted ai_coach_interactions rows on channels pro_image_analysis /
  image_analysis, which nothing has ever written — 0 rows in the table's
  whole history (live census 2026-09-12) — so `used >= 50` was structurally
  false, and the reader was fail-OPEN (`return 0` on any error). Separately,
  PRO+video matched NEITHER tier branch (`isVideo && !isPro` paywall,
  `!isVideo && isPro` cap) and fell straight through to Gemini, uncapped. A
  third, pre-existing gap found by review round 2 and fixed here: the
  `subscriptions` read discarded its error, so a PostgREST fault on that
  table alone made `isPro=false` — a PAYING user's photo then took the FREE
  path, spent a lifetime free unit they do not own, and the reply ended in
  an upgrade CTA. Fifth and LAST instance of the pruned-log quota class
  (d3a7f1 / e7c4b2 slice 2, c4f9e2 slice 3b — same file — and f2c8d5 slice 4).
concept: pro_media_daily_caps
sot_registry_entry: pro_media_daily_caps
writers:
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "consume_quota(proQuotaKey) — ONE atomic call per PRO request, AFTER fetchImageAsBase64 and BEFORE geminiChat; quota_key pro_image_daily (cap 50) or pro_video_daily (cap 10) selected by isVideo; p_window_start = istDayStartIso()" }
  - { file: supabase/functions/_shared/coach_replies.ts, method: "proImageDailyCapReached(cap) / proVideoDailyCapReached(cap) / imageLedgerUnavailable / videoLedgerUnavailable — new copy; the three 'unlimited' promises reworded" }
  - { file: lib/features/ai_coach/copy/coach_replies.dart, method: "CoachReplies — byte-identical client mirror of every server key (fallback copy; nothing on the client reads the new keys today)" }
readers:
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "the RPC's own return value — proCount === -1 refuses with HTTP 200 gated:true, gate_reason pro_image_daily_limit_reached / pro_video_daily_limit_reached, resets_at; proConsumeError refuses with pro_quota_unavailable (fail CLOSED); subscriptionError refuses with tier_unavailable (fail CLOSED); a number becomes pro_daily_used on the success body" }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method: "sendWithMedia — renders aiResponse.reply as a coach bubble on any 200, unchanged; this is what makes the refusal visible on every installed APK without a client change" }
hive_key_prefix: "n/a — server-side gate, no Hive surface"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: usage_counters
cloud_columns: [user_id, quota_key, window_start, used, updated_at]
contract_test_path: test/contracts/pro_media_daily_caps_writer_to_reader_test.dart, test/contracts/usage_quota_ledger_writer_to_reader_test.dart, test/contracts/media_free_image_lifetime_gate_writer_to_reader_test.dart, test/contracts/coach_replies_test.dart, test/scripts/usage_counter_source_lib_test.dart, test/contracts/cap_triggers_use_usage_counters_test.dart
ist_handling: >
  IST, deliberately and per §4.5 — this is a user-visible daily reset
  ("midnight IST" is in the copy), unlike slice 4's sub-day UTC buckets.
  p_window_start = istDayStartIso() ('YYYY-MM-DDT00:00:00+05:30'), computed
  ONCE per request at function scope next to isVideo. It is the SAME instant
  migration 129's triggers store for chat_app (live rows sit at
  18:30:00+00), verified by query. resets_at = istDayStartIso(now + 24h) —
  IST has no DST, so +24h is always exactly one IST day.
provider_invalidations: "none — no client behaviour change. lib/ is touched only by the copy mirror (lib/features/ai_coach/copy/coach_replies.dart), which nothing reads for the new keys; the refusal reaches the user through the server's 200 reply, which sendWithMedia already renders as a coach bubble."
telemetry_op_types: >
  console.error on proConsumeError (fail-closed refusal, NEW), console.error
  on subscriptionError (fail-closed refusal, NEW — this path used to be
  silent and mis-served), console.warn on proCount === -1 (NEW — the only
  refusal telemetry, because -1 neither increments nor touches updated_at,
  so the ledger row cannot distinguish 51 refusals from 5,000). The client's
  existing ai_media_proxy_unknown_error telemetry is NOT fired by any of the
  three refusals, because they are 200s, not exceptions.
cross_account_guard: >
  p_user_id is the caller's OWN verified JWT subject
  (supabaseClient.auth.getUser(token)), never a request-body value, so a
  caller can only ever consume their own quota. consume_quota's EXECUTE is
  {postgres, service_role} since migration 130 and ai-media-proxy calls it
  through its service-role client — unchanged by this batch.
forbidden_patterns_checked: >
  No count(*)/count:"exact" read against ai_coach_interactions remains for
  any quota in ai-media-proxy (check_usage_counter_source.dart PASS with 0
  known EF counters; the allowlist entry ratcheted 1 -> 0). The deleted
  function name countProImageAnalysesToday appears in NO index.ts comment
  (the census mirror now reads comment-stripped source, but the name is kept
  out of the code entirely). No `.single()` on any ledger read. No 429 /
  RATE_LIMITED / Retry-After remains in the file. No "unlimited" survives in
  either copy-mirror file (all three occurrences reworded — the round-1
  hardened plan had reworded one; the author's pre-round-2 pass found the
  other two in freeImageCounter). Every gate_reason literal in the file is
  produced by exactly one branch (quota_unavailable is a SUBSTRING of
  pro_quota_unavailable, so the new one is checked as a quoted literal).
proposed_fix: >
  Delete the channel-counting gate, the 429 and its Retry-After. Add ONE
  atomic consume_quota call for PRO requests, placed after the Storage fetch
  (a 5 MB reject, an SSRF reject or a Storage-404 propagation race never
  spends a unit) and before the Gemini call (the spend is bounded even under
  concurrency — an advisory read lets N in-flight requests all reach
  Gemini; consume_quota increments only WHERE used < p_limit and returns -1
  past it). Gate on `if (isPro)` so video and image alike are capped, with
  the key AND the cap both selected by isVideo (two ternaries, pinned in
  ORDER — swapping either arm alone would leave video at 50). -1 -> HTTP 200
  gated:true with a rank-free Bridge reply that states the midnight-IST
  reset and carries the cap as a function ARGUMENT (the copy file cannot
  import the constant — ai-media-proxy imports coach_replies.ts, so a cycle).
  RPC error and subscriptions-read error both fail CLOSED with honest "not a
  limit" copy. Founder decisions 2026-09-12: 50/day images, 10/day videos,
  midnight IST, in-app message not the paywall, proposed wording accepted.
regression_test_planned: >
  T1 test/contracts/pro_media_daily_caps_writer_to_reader_test.dart (15
  assertions, green) — absent tokens, constants, both ternaries by order,
  the gate's inputs, consume position between `await fetchImageAsBase64(`
  and `await geminiChat(`, the free consume still after the log insert,
  every new gate_reason exactly once on a 200, associative spans per branch,
  the copy's shape. T2 the ledger census goes to ZERO (usage_quota_ledger_
  writer_to_reader_test.dart, 6 green) with the ai-media-proxy mirror over
  comment-stripped source. T3 the free-image test's two indexOf('consume_
  quota') lookups repointed to a KEY-based lookup of the free call (10
  green) and its ratchet 1 -> 0. T4 the source-lib tests repointed to an
  injected fixture allowlist (their firstWhere over the production map threw
  StateError once every entry was 0) plus a new all-zero assertion (18
  green). T10 coach_replies_test.dart: EVERY server key derived from the .ts
  object and compared byte-identical to its Dart twin via a quote-aware
  extractor, function twins rendered, "unlimited" absent (10 green). T11
  cap_triggers_use_usage_counters_test.dart repointed to per-trigger
  resolution (>=129) with the backfill pinned to 129 by name, so migration
  132 can redefine one trigger without erroring the whole file (18 green
  across its 3 consumer files). Mutation-proven per rule 21 — see the body.
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "lib/features/ai_coach/copy/coach_replies.dart mirrors every server key (T10 derives the key set from the .ts object; 10/10 green). sendWithMedia (ai_coach_provider.dart) renders any 200 reply as a coach bubble — traced; no lib/ behaviour change, no APK needed. flutter analyze on the touched lib/ file: clean." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "Server-side gate; no Hive surface. The client persists the refusal bubble exactly as it persists any coach reply (existing behaviour)." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "usage_counters.quota_key is unconstrained text (128) — the two new keys need no DDL. consume_quota's p_window_start is timestamptz (128:72); '+05:30' ISO strings cast cleanly (the free path already passes an ISO string). ai_coach_interactions.channel is nullable with default 'app' (information_schema, live) — the premise of migration 132 (Unit F, applied separately in this batch's apply commit)." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live 2026-09-12: 0 rows on pro_image_analysis / image_analysis in ai_coach_interactions' whole history (the cap had never fired); usage_counters holds rows for ONE key only (chat_app, 6 rows, window_start at 18:30:00+00 = IST midnight); 0 active PRO subscriptions and 0 photo analyses in the last 30 days — the cutover starts from empty and the caps count nothing until a PRO user sends a photo." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "This fix needs NO migration. Migrations 131 (digest cron) and 132 (vision-trigger NULL guard) belong to the same batch but to different concepts; they are applied and ledgered in the apply commit, each on the founder's go." }
  - { tier: 6, name: edge_function_deploy, status: fixed_in_this_batch, evidence: "ai-media-proxy source fixed in git (67ba6ba4); deno check (local Deno 2.9.6, --node-modules-dir=none) PASS on the whole tree. DEPLOYED as v24 on 2026-09-13 02:17Z (verify_jwt=true, unchanged) on the founder's 2026-09-12 pre-authorization, from the branch bytes BEFORE the merge (main's ai-media-proxy and _shared had not changed since the branch base, so the merge carries the same bytes): decoded multipart /body sha256 of index.ts (48549aa1…) and _shared/coach_replies.ts (0fea2a5a…) equal the git blobs (deploy-rollback skill 6.9); anon-Bearer probe → the module's own 401; a real-user-token smoke (QA account, body {}, session revoked) → the module's own 400 Missing message, never 401 (skill 6.7). Until then live was v23 (2026-09-10), the PRE-fix bundle — the B-pass caught this row claiming the deploy before it happened, and the Hermes pass (2026-09-13) caught the row still saying v23 after it had; both corrected here. Superseded the same day by v25 (~06:39Z) carrying the Hermes L23 fixes — the OI-28 guard over the RESOLVED URL (diagnose c7e2a4), the served-MIME cap key, the non-numeric RPC refusal — byte-identical by /body, real-user traversal probes → 403. Ledger: docs/audit/oi153-pro-media-caps.closure.yaml OI153-DEPLOY-1." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "ai-media-proxy is client-invoked. (The founder-digest cron is the sibling commit's concern.)" }
  - { tier: 8, name: rls_policies, status: verified, evidence: "usage_counters: RLS enabled, zero policies (unchanged); the service-role client bypasses it. subscriptions: read as service role, unchanged." }
  - { tier: 9, name: storage, status: verified, evidence: "The Storage fetch (fetchImageAsBase64, SSRF allowlist + user-scope assertion) runs BEFORE the consume — a rejected or racing upload never spends a unit (T1 pins the order). Untouched by THIS fix; hardened the next day by c7e2a4 (Hermes L23: the guard now reads the URL as fetch will request it)." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No new secret read by ai-media-proxy." }
  - { tier: 11, name: external_services, status: verified, evidence: "Gemini is called exactly as before; the only change is that a capped PRO request never reaches it. Cost stated: a Gemini timeout/5xx after a successful consume spends a daily unit (the client retries a 502 up to 3x)." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Success body gains pro_daily_used / pro_daily_limit (null/null for non-PRO); _buildResponse ignores unknown keys. Refusals are 200 gated:true with reply — the convention the file already used for video_pro_only / free_image_limit_reached / quota_unavailable, and the shape sendWithMedia already renders. The old 429 would have landed in sendWithMedia's catch as 'Sorry, I couldn't analyse that photo' (no RATE_LIMITED branch exists there) — the d8e5b3 shape." }
impact_analysis: >
  BEFORE: a PRO token had NO effective ceiling on Gemini Vision fan-out —
  the 50/day image cap was dormant (0 rows counted, ever) and video had no
  cap at all; a subscriptions-read fault silently downgraded paying users
  to the free path. AFTER: 50 images / 10 videos per IST day, enforced
  atomically before Gemini, with an honest in-app refusal at the ceiling and
  honest fail-closed refusals on a ledger or tier-read fault. Live blast
  radius of the cutover is zero, measured: 0 active PRO subscriptions and 0
  photo analyses in 30 days, so no user's counter starts anywhere but empty.
  Residuals, stated: up to 4 daily units can be spent by one photo during a
  Gemini outage (client 502 retries; no decrement RPC exists); the ledger
  cannot count refusals (only users at the ceiling); the video cap has no
  client UI to reach it from today (no video picker exists — it protects the
  API surface, the H-23 threat model).
---

# a9d4e7 — PRO media caps dormant (image) and absent (video)

OI-153 — the LAST of the ten quota readers that derived their count from the
pruned `ai_coach_interactions` log. OI-162 slices 1–4 moved the other nine; this
one waited on a product decision (activating a cap that had never fired), taken
by the founder on 2026-09-12: 50 images / 10 videos per IST day.

## Why this is a direct recurrence, and where it differs

Same class as `d3a7f1` / `e7c4b2` (slice 2), `c4f9e2` (slice 3b — the same
file's FREE meter) and `f2c8d5` (slice 4): a quota derived from counting rows
in `ai_coach_interactions`. Two differences worth recording:

1. **Nothing ever wrote the rows.** The other instances counted rows that
   existed and were pruned; this one counted channels
   (`pro_image_analysis` / `image_analysis`) that no writer has ever emitted.
   The cap was not "reset nightly" — it was never non-zero. The fail-open
   reader (`return 0` on error) made it doubly inert.
2. **A branch that matched nothing.** PRO+video satisfied neither
   `isVideo && !isPro` nor `!isVideo && isPro`. Not a counting bug — a
   guard-without-its-mirror: the cap was written for images and the video
   paywall for free users, and the fourth quadrant fell through.

## Consume-FIRST here, consume-AFTER for the free meter — both deliberate

Review round 1's P1: the first draft copied slice 3b's advisory-read →
deliver → consume shape. That shape cannot bound spend under concurrency: N
in-flight requests each read `used < 50`, all N reach Gemini, and
`consume_quota` merely returns `-1` to the late ones. A compromised token
defeats an advisory gate with parallelism alone — and bounding Gemini spend
from a stolen PRO token is the one thing H-23 exists to do. So the atomic
check-and-increment IS the gate, placed after the Storage fetch and before
Gemini. The free path keeps consume-after-delivery because its unit is
LIFETIME: an undelivered lifetime unit is unrecoverable, an undelivered daily
one is cheap.

## The tier-read gap (round 2, P2)

`:407-416` discarded the `subscriptions` read's error. `.maybeSingle()` returns
`data: null, error: null` for a user with NO row — a free user is never an
error — so `subscriptionError` means exactly "the tier is unknown". Treating
unknown as free mis-served every paying user during a partial outage (a
lifetime free unit spent, an upgrade CTA shown). It now refuses honestly for
either tier (`tier_unavailable`), with rank-free copy, because the rank is
exactly what is unknown.

## Mutation proof (rule 21)

Every mutation was applied by a script that asserted the substitution matched
exactly once, ran the target test, and restored the file byte-identically (the
restored control run is green). None produced a compile error — each mutated
file is valid TypeScript / Dart, semantically wrong.

| # | Mutation | Reddened |
|---|---|---|
| M1 | `if (isPro)` → `if (!isVideo && isPro)` (video uncapped again) | T1: 2 |
| M2 | swap the arms of the key ternary | T1: 1 |
| M2b | swap the arms of the cap ternary (the arrangement mirror on the SECOND ternary) | T1: 1 |
| M3 | move the PRO RPC block below `await geminiChat(` | T1: 1 |
| M3b | move it above `await fetchImageAsBase64(` (the other direction, which M3 alone never tests) | T1: 1 |
| M4 | the `proConsumeError` branch reports the cap reason instead of `pro_quota_unavailable` | T1: 2 |
| M4b | delete the `tier_unavailable` branch | T1: 2 |
| M8 | chain `.in("channel", ["pro_image_analysis", "image_analysis"])` onto `readFreeImageQuota`'s builder | T1: 1 (T2's mirror is the second net) |
| M9 | ratchet `usage_counter_source_lib.dart`'s ai-media-proxy entry back to 1 | T3: 1 |
| M10 | drift one CLIENT copy (`videoLedgerUnavailable`) by one character | T10: 1 |
| M10b | re-type "unlimited" into `freeImageCounter` on the SERVER only | T10: 2 |
| M10c | add a server key with no Dart twin | T10: 1 |
| M10d | drift a server METHOD return (the image cap copy) by one word | T10: 1 |
| M11 | `return defs.last;` → `return defs.first;` in `latestMigrationDefining` (earliest definer) | T11 + parity/food consumers: 5 |
| M14 | `count > allowed` → `count > allowed + 1` in `usage_counter_source_lib.dart` (the `else if` under the allowlist lookup) | T4: 2 |
| M6 | `founder-digest`: the windowed loop no longer skips `kind: "lifetime"` keys (a lifetime key rendered as a day total) | T6: 1 |
| M7 | `founder-digest`: the alert line drops `escapeHtml` on `severity`/`source` | T6: 1 |
| M7b | `founder-digest`: at-cap uses `used > cap` instead of `>=` | T6: 1 |
| M7c | `founder-digest`: the 4096-char truncation removed | T6: 1 |
| M13 | `founder-digest`: `if (!await isAuthorizedCronCall(req))` → `if (false)` (the auth gate gone) | T5 cron_auth_adoption: 1 |
| M13b | `founder-digest`: `logCronStart("founder-digest")` → `null` (telemetry gone) | T5 cron_telemetry_adoption: 1 |
| M7-T7a | misspell a `DIGEST_KEYS` key (`pro_vidio_daily`) | T7: 4 |
| M7-T7b | drift a `DIGEST_KEYS` cap (50 → 40) | T7: 2 |
| M7-T7c | file `free_image_analysis` as `kind: "daily"` | T7: 1 |
| M7-T7d | swap the arms of ai-media-proxy's KEY ternary only (association: video key now paired with the image cap) | T7: 1 |

M9, M14 and the founder-digest rows (M6, M7*, M13*, M7-T7*) were run in the
sibling `feat(founder-digest)` commit of the same branch; the table is the
batch's single ledger of what was mutated. T6 is the Deno file
`supabase/functions/founder-digest/index_test.ts` (19 tests, run with the
local Deno 2.9.6 — `--node-modules-dir=none`, see the EF CLAUDE.md); T7 is
`test/contracts/founder_digest_caps_mirror_test.dart` (6).

## What is NOT proven here

- Runtime behaviour of the Edge Function: source-greps + `deno check` +
  the deploy-time smoke. The live-ledger behaviour (1..cap then -1, key
  isolation) is `test/sql/oi153_pro_media_caps_live_verify.sql`, executed by
  hand inside `BEGIN … ROLLBACK` at the apply step.
- The 51st request against a real PRO account — not exercised live (0 PRO
  accounts exist); the deploy-time T9 sends ONE photo from a temp-PRO QA
  account and checks one `pro_image_daily` row with `used = 1`.
- Refusal COUNTS: the ledger cannot carry them (`-1` leaves the row
  untouched); the `console.warn` is the only trace.

## Related

- Plan + four review rounds: `docs/audit/oi153-plan.md`.
- Board: OI-153 (closed by this batch); OI-162 (the class, closed 2026-09-12).
- Prior instances: `d3a7f1`, `e7c4b2`, `c4f9e2`, `f2c8d5`.
- Review-found pre-existing defects filed separately (not this batch):
  `morning-alert:388` may log the bot token on a fetch error; the orphan-sync
  dedupe never matches a media turn (`[Photo]` vs `[Photo: image]`); Gate 31
  is blind to jobs whose migration carries a commented `cron.unschedule('…')`.
