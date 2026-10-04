# OI-153 — PRO media caps on `usage_counters` + founder daily digest

**Branch:** `oi153-pro-media-caps` · **Tier:** platform (B-pass required; no Hermes — nothing
catastrophic by path or by content, see "Blast radius") · **Status:** spec, reviewed ×4 and CONVERGED (see
"Rounds"). **EXECUTED 2026-09-12/13** on the founder's go (execute + merge + EF deploys + migrations
authorized in one message, 2026-09-12): commit 1 `67ba6ba4` (Units A/B/C), commit 2 `f15fad75`
(Unit D), commit 3 (this file + the record + the B-pass remediation), then the apply commit
(Units E/F: migrations 131 + 132, the cron snapshot, the registry row). The record is
`docs/plan-reviews/oi153-pro-media-caps.md`; execution results live in the closure ledger
`docs/audit/oi153-pro-media-caps.closure.yaml` and diagnose `a9d4e7`, not in this spec — the text
below is the plan as reviewed, kept verbatim as the record of what was agreed. Two deviations,
both in the executed code's favour: (i) the digest's three reads were extracted into an exported
`readDigestSections` driven by a recording fake (B-pass finding 3 — the inline reads were
unreachable by any test); (ii) T1 gained a literal-independent guard assertion (B-pass finding 5).

Locked founder decisions (2026-09-12, not re-opened here): PRO image analysis **50/day**, PRO
video analysis **10/day**, reset at **midnight IST**, the capped-PRO message is an **in-app coach
message, not the paywall**, and a **daily Telegram digest** to the founder at **08:00 IST** via
`@IcanbefitterBot` using the Edge Function secrets `TELEGRAM_BOT_TOKEN` +
`FOUNDER_TELEGRAM_CHAT_ID` (Deno env, the same mechanism `morning-alert:111` reads; both stored
2026-09-12 and proven by a delivered message — they are NOT Vault rows, which hold only
`cron_secret` and three unrelated names). Free tier unchanged.

## Scope

1. **Unit A — PRO image cap actually fires.** `ai-media-proxy` counts a channel nothing writes
   (OI-153 CODE-1). Move the gate onto `usage_counters` via `consume_quota`, quota_key
   `pro_image_daily`, IST-day window.
2. **Unit B — PRO video cap exists.** PRO+video matches neither existing branch (CODE-2) and is
   uncapped. Same mechanism, quota_key `pro_video_daily`, cap 10.
3. **Unit C — capped-PRO reply** in the coach's voice, stating the midnight-IST reset, with no
   client BEHAVIOUR change (see "Response shape" — this is what makes the batch APK-free; the
   client copy mirror file is edited for parity only).
4. **Unit D — `founder-digest` Edge Function** (new, cron-dispatched, read-only) + migration 131
   scheduling it at `30 2 * * *` UTC (08:00 IST).
5. **Unit E — tests, census, ratchet, registry, docs** in the SAME commits as the code they pin.
6. **Unit F — `enforce_vision_analysis_daily_limit` NULL-channel guard** (migration 132, 3
   lines): the trigger's `NEW.channel NOT IN (...)` is NULL-blind while both siblings use
   `IS DISTINCT FROM` (`129:99`, `:149`, `:183`); `channel` is nullable with default `'app'` (live),
   so an explicit `channel: null` insert consumes a `vision_analysis` unit for its own user.
   Slice 4's residue parked this "with OI-153's channel work"; it is fixed here rather than left on
   a CLOSED entry (§4.2 — a closed entry cannot carry an open item). Independent of A–E: the
   founder may strike it as a scope decision without affecting the rest. **Reachability, so the
   decision is made on the fact (round 3):** live 2026-09-12 there are 0 NULL-channel rows; every
   one of the 12 `ai_coach_interactions` writers passes a literal or guarded channel; and an
   AUTHENTICATED direct insert with `channel = NULL` (RLS `insert_own` allows it) fails with
   `42501` inside the trigger — 130 revoked `consume_quota` from `authenticated` — so the insert
   itself fails and no unit is consumed. Only a future service-role writer passing NULL would
   consume. Unit F is a latent-guard fix, kept because it is 3 lines, applies in the SAME go as
   131, and gives the vision trigger the `IS DISTINCT FROM`-equivalent shape its two siblings have.

Not in scope (each is a separate concept with its own owner, stated so nobody reads silence as
an omission):
- A client-side video upload path. **None exists**: `grep -rn "pickVideo\|'video'" lib/` is empty
  and `media_picker.dart:281-288` is the only `sendWithMedia` call site, always
  `mediaType: 'image'`. Unit B protects the API surface (a PRO token used outside the app), which
  is exactly the H-23 threat model the 50/day cap was written for. Say this plainly to the founder:
  the video cap has no UI to hit it from today.
- A PRO "X of 50 left" counter line. Free users get one; PRO users get the reply only.
- Rotating `cron_secret` (live length **20** chars; `_shared/cron_auth.ts`'s own header asks for
  `openssl rand -hex 32` = 64). Founder action, flagged in the report.
- Two pre-existing defects FOUND by this review and to be FILED on the board by the main session
  (they are in files this batch does not deploy, and are not caused or exposed by it):
  (i) `morning-alert/index.ts:388` `console.error(..., err)` on a Telegram fetch failure — a Deno
  fetch error embeds the request URL, i.e. `api.telegram.org/bot<TOKEN>/…`, so the bot token can
  reach the function logs; latent today (`telegram_connections` has 0 rows), but the token now
  exists in the environment. (ii) The client's orphan-sync dedupe never matches a media turn:
  `ai_coach_provider.dart:625` persists `[Photo] <caption>` while the server logs
  `[Photo: image] <caption>` (`index.ts:766`), so `sync_coach.dart:120-128`'s `user_message`
  equality misses and every delivered analysis lands twice (server `app` row + client
  `in_app_orphan`). Live: 58 `in_app_orphan` rows exist; 0 photo rows survive, so the media case
  is source-verified only. (iii) Round 3: `scripts/check_cron_registry.dart:82-101` reads
  migration text RAW, so a COMMENTED inline-rollback `cron.unschedule('<name>')` (the convention
  ten migrations follow) removes that job from the gate's input A — the registry row for such a
  job is required only if the live snapshot (input B) happens to carry it. (iv) Verified live
  2026-09-12 while reviewing: `compute_admin_metrics_daily` (jobid 30) dispatched "succeeded / 1
  row" at 2026-09-11 18:15Z with ZERO `cron_call_log` rows, while the two prior days logged one
  each and 27 other cron calls that evening logged normally; `net._http_response` retention no
  longer holds the HTTP status. One silent miss of the admin snapshot — the exact class the
  digest's daily liveness rationale cites, and below `alert_cron_function_dead`'s 8-day window.

## Ground truth (live 2026-09-12, project `dedsavbjuwgarrhphgnl`; re-verify before executing)

| Claim | Evidence |
|---|---|
| The PRO cap has never fired | `ai_coach_interactions` holds **0** rows on `pro_image_analysis` / `image_analysis`; the only insert writes `free_image_analysis` or `app` (`index.ts:751-754`). `countProImageAnalysesToday` (`:133-149`) is fail-open (`return 0` on error) |
| PRO video is uncapped | `:477` `isVideo && !isPro` (paywall) and `:587` `!isVideo && isPro` (cap) — PRO+video falls through to `fetchImageAsBase64` (`:690`, 5 MB limit) and Gemini with a `video/*` mime |
| `usage_counters` today | rows for ONE key only: `chat_app` (6 rows, `window_start` = `…18:30:00+00` = IST midnight). No media, weekly-report, delete-account or verify-payment rows yet |
| Active PRO subscriptions | **0**. Photo analyses in the last 30 days: **0** (0 users). The caps will count nothing until a PRO user sends a photo — the digest will say so honestly rather than print zeros for unread sections |
| `consume_quota` ACL | `{postgres, service_role}` since migration 130; `ai-media-proxy` uses a service_role client (`:385`) — unaffected |
| `ai_coach_interactions.channel` | nullable, default `'app'` (information_schema) — the Unit F premise |
| `cron.job` | **29** live jobs; `backups/live_cron_jobs.json` has **28** — `usage_counters_retention_daily` (jobid 37, migration 128) was never added to the snapshot. **Corrected by round 3:** Gate 31 never REQUIRED that registry row at all — `check_cron_registry.dart:82-101` scans migration text RAW, so 128's commented inline rollback `-- SELECT cron.unschedule('usage_counters_retention_daily');` (`128:161`) puts the job in the gate's `unscheduled` set and drops it from input A; input B (the snapshot) lacked jobid 37. The row is listed by convention only. **Ten** migrations carry a commented `cron.unschedule('<name>')` line (`grep -ln "^\s*--.*cron\.unschedule" supabase/migrations/*.sql`: 069 076 077 086 087 102 109 110 121 128), so every job they schedule is invisible to input A — a pre-existing gate blind spot, FILED for the board (third filing, see Scope). 131 phrases its rollback without a quoted job name so it does not join them; the regenerated snapshot in the apply commit makes input B require both `usage_counters_retention_daily` and `founder_digest_daily` |
| Vault | `cron_secret` present (20 chars); **no `project_url` row** — every `private.*_function_url()` helper already resolves to its hardcoded `https://dedsavbjuwgarrhphgnl.supabase.co` fallback, and 10 live jobs (031/040/043/047/061) hardcode the URL outright |
| Client 429 handling | `sendWithMedia`'s catch (`ai_coach_provider.dart:711-755`) has NO 429 / `RATE_LIMITED` branch; a 429 from the media proxy renders *"Sorry, I couldn't analyse that photo. Please try again."* and fires `ai_media_proxy_unknown_error` telemetry — the same swallowed-refusal shape delete-account had before slice 4. `chatWithMedia`'s `if (response.status != 200)` (`ai_service.dart:599`) is unreachable: `functions.invoke` throws `FunctionsHttpException` on every non-2xx (functions_client 2.7.1, tail of `invoke` in `functions_client.dart`) |
| Client retry budget | `_coldStartBackoffsMs = [2000, 6000, 12000]` (`supabase_service.dart:381`) — a 502 is retried up to 3 times, so one photo can make up to 4 server calls during a Gemini outage |
| Bug history (§4.1.5) | **Recurrence** — 5th slice of the counter-in-a-pruned-table class: `d3a7f1` (the nine readers), `e7c4b2` (slice 2), `c4f9e2` (slice 3b, same file), `f2c8d5` (slice 4). Also `d8e5b3` (the media proxy's generic apology fires silently) and `c3f8a1` (cron 401 class — why the digest uses `cron_auth.ts`) |

Writers and readers named (§4.1):
- **Writer today (dormant):** none — nothing writes `pro_image_analysis` / `image_analysis`.
- **Reader today:** `ai-media-proxy/index.ts:133` `countProImageAnalysesToday` → `:588-592`.
- **Writer after:** `ai-media-proxy/index.ts` `consume_quota('pro_image_daily' | 'pro_video_daily',
  <IST day>, 50 | 10)`, called once per request after the Storage fetch succeeds and before
  Gemini (see Unit A/B).
- **Readers after:** the same RPC's return value (`-1` is the refusal — no separate advisory read)
  and `founder-digest` (yesterday's rows, read-only).

## Design

### Window and key

`window_start` = IST midnight of the current IST day: `istDayStartIso()` from
`_shared/ist_date.ts` (`YYYY-MM-DDT00:00:00+05:30`). This is the SAME instant migration 129's
triggers use (`date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'`),
verified by the live `chat_app` rows sitting at `18:30:00+00`. §4.5's IST rule applies because the
reset is user-visible ("midnight"), unlike slice 4's sub-day UTC buckets. Computed ONCE per request
at function scope (`const proWindowStart = istDayStartIso()`), next to `isVideo`.

Two keys, one call site each (`usage_quota_ledger` invariant: ONE quota_key ⇒ ONE call site ⇒ ONE
limit): `pro_image_daily` (`PRO_IMAGE_DAILY_CAP = 50`, the existing constant, unchanged value) and
`pro_video_daily` (`PRO_VIDEO_DAILY_CAP = 10`, new). Windowed rows age out via
`cleanup_usage_counters()` (7 days) — a 1-day window needs no retention change.

### Unit A/B — the gate (shape = slice 4's consume-first, placed after the Storage fetch)

**CHANGED BY ROUND 1 (P1).** The first draft copied slice 3b's advisory-read → deliver →
consume-after-delivery shape. That shape does not bound Gemini spend under concurrency, which is
the one thing the H-23 cap exists to do: N in-flight requests each read `used < 50`, all N reach
Gemini, and `consume_quota` (whose `WHERE uc.used < p_limit` guards only the increment,
`128:95-100`) merely returns `-1` to the late ones, which the draft only logged. A compromised
token defeats an advisory gate with parallelism alone. The atomic check-and-increment IS the gate:

1. `readFreeImageQuota` and the whole free path (`:508-579`, `:790-831`) are **untouched** — no
   generic reader, no rename. The dormant H-23 block (`:581-611`) and `countProImageAnalysesToday`
   (`:128-149`) are deleted.
2. Function-scope declarations next to `isVideo` (`:465`), so both the gate and the response body
   can see them (a block-scoped `const` inside `if (isPro) {` would be TS2304 at `deno check`,
   which only CI runs):
   ```ts
   const proWindowStart = istDayStartIso();
   const proQuotaKey = isVideo ? PRO_VIDEO_QUOTA_KEY : PRO_IMAGE_QUOTA_KEY;
   const proCap      = isVideo ? PRO_VIDEO_DAILY_CAP : PRO_IMAGE_DAILY_CAP;
   let proDailyUsed: number | null = null;
   ```
3. Immediately after `fetchImageAsBase64` returns (`:690-693`) and before `geminiChat` (`:702`):
   ```ts
   if (isPro) {
     const { data: proCount, error: proConsumeError } = await supabaseClient.rpc("consume_quota", {
       p_user_id: userId, p_quota_key: proQuotaKey, p_window_start: proWindowStart, p_limit: proCap });
     if (proConsumeError) → 200 gated, gate_reason "pro_quota_unavailable" (DISTINCT from the free path's "quota_unavailable" at `:538` — round 2: a shared literal makes T1's check membership, not association), reply = isVideo ? videoLedgerUnavailable : imageLedgerUnavailable   // fail CLOSED
     else if (proCount === -1) { console.warn(`[ai-media-proxy] PRO daily cap hit user=${userId} key=${proQuotaKey} cap=${proCap}`);   // round 2 L29: `-1` neither increments nor touches `updated_at` (128:97-100), so the ledger row cannot distinguish 51 refusals from 5,000 — the warn is the only refusal telemetry
       → 200 gated, gate_reason "pro_image_daily_limit_reached" | "pro_video_daily_limit_reached", reply = the cap copy, resets_at = istDayStartIso(<tomorrow>), pro_daily_used = proCap, pro_daily_limit = proCap }
     else proDailyUsed = proCount as number;
   }
   ```
   **Tier read fails CLOSED too (round 2 P2, pre-existing, fixed here because the plan's own
   claim about it was false):** `:407-416` discards the `subscriptions` read's `error`, so a
   PostgREST fault on THAT table alone (ledger fine) makes `isPro=false` — a paying user's photo
   then takes the FREE path, spends a lifetime `free_image_analysis` unit they do not own, and
   the reply ends "[Upgrade to PRO →]"; their video gets `video_pro_only`. Capture the error
   (`const { data: subscription, error: subscriptionError } = …`) and, once `isVideo` is known
   (`:465`) and before the first tier branch (`:477`): `if (subscriptionError) → 200 gated,
   gate_reason "tier_unavailable", reply = isVideo ? videoLedgerUnavailable :
   imageLedgerUnavailable` (rank-free, tier-neutral copy — the tier is exactly what is unknown).
   Cost: a free user is also refused, honestly, for the duration of a partial outage; the
   alternative silently mis-serves every paying user. Same reasoning as the ledger fail-closed
   below.
   Placement: after the fetch so a 5 MB reject, a Storage 404 race (client-retried, `:522-529`
   in `supabase_service.dart`) or a user-scope 403 never spends a unit; before Gemini so the
   spend is bounded. **What this charges for, stated:** a Gemini timeout/5xx (`!rawReply` → 502,
   `:715-729`) after a successful consume spends a unit — and the client retries 502 up to 3 times,
   so one photo during a Gemini outage can spend up to 4 units. There is no decrement RPC and none
   is added; a daily unit is cheap and the outage rare. The free path keeps its consume-after-
   delivery shape because its unit is LIFETIME.
   **Fail-CLOSED on an RPC error**, like slice 3b and verify-payment, unlike delete-account: in a
   full Postgres outage the `subscriptions` read (`:407-416`, error discarded) already yields
   `isPro=false` today and the free path refuses with `quota_unavailable`; after the tier-read
   guard above the refusal is `tier_unavailable` instead — same outcome, honest reason; in
   a partial fault (a grant/RLS regression on `usage_counters`, the OI-184 class) fail-open would
   run PRO analyses unmetered with a digest showing nothing wrong. The cost is honest copy to a
   paying user during a ledger fault.
4. No separate consume after the conversation-log insert for PRO: the unit is already spent, and
   the reply is returned whether or not that insert succeeds (existing behaviour, `:772-777`).
5. Response body on success gains `pro_daily_used` / `pro_daily_limit` (null / null for non-PRO);
   `free_image_*` unchanged. The client's `_buildResponse` (`ai_service.dart:288-298`) ignores
   unknown keys.
6. Delete: `countProImageAnalysesToday`, the `.in("channel", ["pro_image_analysis",
   "image_analysis"])` read, the 429 response with `code: "RATE_LIMITED"` and `Retry-After: 3600`.
   No new `channel` value is minted anywhere — OI-153's "enumerate every channel reader"
   blocker dissolves the same way it did for slice 4.

⚠ **Consequence for an existing contract, handled in T3, not discovered at push time:**
`media_free_image_lifetime_gate_writer_to_reader_test.dart:178-226` locates the free consume as
`src.indexOf('consume_quota')` — the FIRST occurrence in comment-stripped source. The PRO RPC now
sits ~70 lines ABOVE the free one, so both "the insert PRECEDES the consume" and "CONTAINED BY the
insert-succeeded guard" would go red. Repoint both to find the free call by its key
(`src.indexOf('p_quota_key: FREE_IMAGE_ANALYSIS_QUOTA_KEY')`, then the nearest preceding
`consume_quota`), which is STRONGER — it pins the free consume by identity rather than by
position.

### Unit C — response shape and copy (why no client behaviour change)

The refusal is **HTTP 200 with `gated: true`**, the file's own convention for a coach-voiced
refusal (`video_pro_only`, `free_image_limit_reached`, `quota_unavailable`; this batch adds
`pro_image_daily_limit_reached`, `pro_video_daily_limit_reached`, `pro_quota_unavailable`,
`tier_unavailable` — every gate_reason literal unique to ONE branch), NOT the 429 the dead
H-23 block used. Consequences, each load-bearing:
- The client already renders `reply` as a normal coach bubble and persists it
  (`ai_coach_provider.dart:666-677`), so **every installed APK shows the right message the moment
  the EF is deployed** — no APK build, no behaviour change in `lib/`.
- A 429 would need a new `errStr2.contains('RATE_LIMITED')` branch in `sendWithMedia`'s catch and
  an APK; until then every capped PRO user would see "Sorry, I couldn't analyse that photo" — the
  d8e5b3 shape — and the web fallback (`_directMediaHttpCall`, `AiServiceException` without the
  code in its string) would need a second, different match. Two client paths, one APK gate, for a
  message the server can carry itself.
- Distinguishability (`feedback_observability_silent_drop`): `gated: true` + a distinct
  `gate_reason` per cap + `resets_at`. `Retry-After` is dropped with the 429; `resets_at`
  (`istDayStartIso(<tomorrow>)`) replaces it for API consumers.
- **No server-side `ai_coach_interactions` row is written for the refusal** (the
  `quota_unavailable` precedent). Corrected reasoning after round 1: minting a channel is what
  OI-153 forbids without a census, and the client persists the turn to Hive and its orphan sync
  pushes it to the cloud as `in_app_orphan` regardless (`sync_coach.dart:144-157`) — which
  `founder_metrics_engagement()` counts (`120:125`, `_coachChatChannels` includes it). So a server
  row would only DOUBLE the row. Cap hits are reported by the digest from `usage_counters`
  (`used >= cap`), which needs no log row.

Copy — server-side in `_shared/coach_replies.ts` (imported ONLY by `ai-media-proxy`, verified;
no other bundle drifts), **mirrored on the client in
`lib/features/ai_coach/copy/coach_replies.dart`** — corrected after round 1: slice 3b did NOT
delete the client twin, it ADDED `CoachReplies.imageQuotaUnavailable` and
`coach_replies_test.dart:66-86` pins it byte-identical to the server. Nothing on the client reads
any of these constants (fallback copy), but the two files declare themselves mirrors and the test
enforces it for one key; this batch extends that test to iterate over EVERY mirrored key (a
membership check over one key cannot see a second key drift). Four new strings, Wardroom voice
(Bridge, terse, naval; rank-free because PRO users hold ranks; no upgrade CTA — a PRO user must
never be shown "[Upgrade →]"; the cap copies state the reset):

```
proImageDailyCapReached(cap):      // a FUNCTION, like freeImageCounter(remaining) — round 3:
  "Photo received. That is ${cap} image reads today — the PRO daily ceiling. Bridge resets the
   counter at midnight IST; send it again after 00:00 and it goes straight through."
proVideoDailyCapReached(cap):
  "Video received. That is ${cap} video reads today — the PRO daily ceiling. Bridge resets the
   counter at midnight IST; send it again after 00:00 and it goes straight through."
imageLedgerUnavailable:   (rank-free; used for BOTH the PRO ledger fault and the tier-read fault)
  "Photo received. Bridge cannot reach the quota log right now, so it is standing down rather
   than guessing. Try again in a moment — this is not a limit."
videoLedgerUnavailable:
  "Video received. Bridge cannot reach the quota log right now, so it is standing down rather
   than guessing. Try again in a moment — this is not a limit."
```
Plainer alternative for the two cap copies, if the founder prefers his own wording: *"Photo
received. You've reached today's PRO limit of 50 image reads. The counter resets at midnight IST —
try again tomorrow."* The numbers are interpolated from the constants, never typed twice —
**as function arguments** (round 3 P2): `PRO_IMAGE_DAILY_CAP` lives in `ai-media-proxy/index.ts:43`,
which IMPORTS `coach_replies.ts` (`:5`), so the shared copy file cannot read the constant without
an import cycle. The two cap copies are therefore `(cap: number) => string` on the server and
`static String proImageDailyCapReached(int cap)` on the client, exactly the shape
`freeImageCounter(remaining)` already has on both sides; the `-1` branch calls
`COACH_REPLIES.proImageDailyCapReached(proCap)` / `proVideoDailyCapReached(proCap)` (T1 pins that
the argument is `proCap`, never a literal), and T10 compares client `f(50)` / `f(10)` to the
server template rendered with `${cap}` substituted, the way it now does for `freeImageCounter`.
Also reworded on BOTH sides — **every** "unlimited" promise in the mirror pair, not one of them
(author's pre-round-2 pass; `grep -n unlimited` over both files finds THREE, the round-1-hardened
draft reworded one): `imagePaywallExhausted` promises "unlimited image + video reads" → "[Upgrade to
PRO →] for image + video reads every day." (the client test pins only 'Upgrade to PRO' and 'used
your 5', both kept); and `freeImageCounter`'s two CTA variants "[Upgrade for unlimited →]"
(`coach_replies.ts:27,30`, appended to EVERY free user's analysis at `index.ts:836`; client twin
`coach_replies.dart:17,20`) → "[Upgrade to PRO →]" (the `remaining == 0` variant already says
"[Upgrade →]" and is kept). Invariant pinned by T10 rather than by a per-string check: the
comment-stripped source of BOTH mirror files contains no substring `unlimited` (a PRO tier with a
visible daily ceiling must not be sold as unlimited anywhere the coach speaks), and
`freeImageCounter(3)`, `(1)`, `(0)` on the client equal the three server literals (regex-extracted
from the `.ts`), so the function twin is mirrored the way the constant twins are.

### Unit D — `founder-digest` (new cron Edge Function, read-only)

Dedicated EF rather than extending `compute-admin-metrics-daily`: that job runs at 23:45 IST
(its `*_today` fields are cumulative since IST midnight), writes a snapshot table, and is the
admin dashboard's source; the digest reads a different day (yesterday, complete), writes nothing
to the DB, and sends to Telegram. Coupling them would put a Telegram failure on the dashboard's
critical path.

Skeleton = `compute-admin-metrics-daily/index.ts:115-183` (copied, not composed): `OPTIONS` →
`isAuthorizedCronCall(req)` (401 otherwise) → `logCronStart("founder-digest")` AFTER the gate →
work → `logCronEnd(…)` on every exit → `export const handler` + `if (import.meta.main)
serve(handler)` so `index_test.ts` can import the pure pieces.

Reads (all bounded — `check_unbounded_cron_reads.dart` derives its roster from the registry row
this batch adds):
- `usage_counters` windowed rows for yesterday: `fetchAllPages` (`_shared/paged_fetch.ts`) over
  `.select("user_id, quota_key, window_start, used, updated_at").gte("window_start", yStart)
  .lt("window_start", tStart)`, `orderBy: [{ column: "user_id" }, { column: "quota_key" },
  { column: "window_start" }]` — the `OrderKey[]` form (`paged_fetch.ts:100-120`; a plain
  `string[]` is rejected by `orderKeys()` and by `deno check`), the PK, a total order.
- `usage_counters` lifetime rows touched yesterday: same, with `.eq("window_start", LIFETIME_WINDOW)
  .gte("updated_at", yStart).lt("updated_at", tStart)`. A lifetime row's `used` is cumulative, so
  the digest reports *users who moved* and *users at the ceiling*, never a "consumed yesterday"
  it cannot know.
- `alerts` detected yesterday: `.select("detected_at, source, severity, summary")…
  .order("detected_at").limit(50)`.
- Every column above exists in `backups/live_schema_columns.json` (gate `check_schema_column_refs`).

Yesterday's IST window, as ISO STRINGS (round 2: `Date − number` is a number, and a `Date`
handed to `.gte()` stringifies via `toString()` — non-ISO — which Postgres rejects, so the usage
section would read "unreadable" every single day): `const tStartMs =
Date.parse(istDayStartIso(now)); const yStartMs = tStartMs - 86_400_000; const tStart = new
Date(tStartMs).toISOString(); const yStart = new Date(yStartMs).toISOString();` (IST has no DST; an
IST day is always 86 400 s), label `istDateStr(new Date(yStartMs))`. T6 asserts both filter
values match `/^\d{4}-\d{2}-\d{2}T18:30:00\.000Z$/`. No `.toISOString().slice(0,10)` on a raw
`new Date()` (gate `check_local_date_key_drift`).

**Every quota_key the digest renders is ENUMERATED, and the enumeration is pinned both ways**
(round 1 P1 — a map of 4 caps over a template of 9 sections is membership without completeness;
a misspelt key returns 0 rows and renders "none", which the three-state rendering cannot see):
```ts
interface DigestKey { key: string; label: string; kind: "daily" | "subday" | "lifetime"; cap?: number }
// Explicit type, NOT `as const` (round 2 P1): with `cap` present on 6 of 9 literals, `as const`
// makes a union whose members disagree on `cap`, and `k.cap` is TS2339 under CI's
// `deno check supabase/functions/` (test.yml:176) — invisible locally (no Deno). Read it as
// `k.cap !== undefined`.
const DIGEST_KEYS: readonly DigestKey[] = [
  { key: "pro_image_daily",    label: "PRO image reads",   kind: "daily",    cap: 50 },
  { key: "pro_video_daily",    label: "PRO video reads",   kind: "daily",    cap: 10 },
  { key: "chat_app",           label: "Chat (free)",       kind: "daily",    cap: 10 },
  { key: "vision_analysis",    label: "Vision (scan/cart)", kind: "daily",   cap: 20 },
  { key: "food_text",          label: "Food text",         kind: "daily" },            // 10 free / 200 PRO — tier-dependent, no "at cap"
  { key: "delete_account",     label: "delete-account",    kind: "subday" },           // hourly buckets, totals only
  { key: "verify_payment",     label: "verify-payment",    kind: "subday" },           // 10-min buckets, totals only
  { key: "free_image_analysis", label: "Free image reads", kind: "lifetime", cap: 5 },
  { key: "weekly_report_free", label: "Weekly report (free)", kind: "lifetime", cap: 1 },
];
```
T7 asserts the key SET equals the union of every `p_quota_key` literal in
`supabase/functions/*/index.ts` — **resolved PER FILE** (round 2: `delete-account/index.ts:80`
and `verify-payment/index.ts:238` both declare `RATE_LIMIT_QUOTA_KEY`, with different values, so
a global name→literal map would collapse two keys into one; for each `.rpc("consume_quota"` block
take the identifier after `p_quota_key:` and resolve it in THAT file only — round 4: anchor on `p_quota_key:\s*(\w+)` (4 sites: `ai-media-proxy:796`,
`delete-account:173`, `verify-payment:251`, `weekly-report:693`), NOT on `.rpc("consume_quota"`,
which three of the four files split across lines as `.rpc(` / `"consume_quota",` — a one-line
anchor finds ONE file and T7 goes red on its first run; `const <ident> =
"<literal>"` directly, or, round 3: `const <ident> = <cond> ? <identA> : <identB>` one level deeper
to BOTH identifiers' literals, because the PRO site passes `proQuotaKey`, itself a ternary of
`PRO_VIDEO_QUOTA_KEY` / `PRO_IMAGE_QUOTA_KEY`; an unresolvable identifier FAILS the test rather
than being skipped, and a positive control asserts `ai-media-proxy/index.ts` contributes exactly
{`pro_image_daily`, `pro_video_daily`, `free_image_analysis`}) — and every `consume_quota(...,
'<key>'` literal in the highest migration defining each cap
trigger, in BOTH directions, and that every `cap` equals its source
(`PRO_IMAGE_DAILY_CAP`, `PRO_VIDEO_DAILY_CAP`, `FREE_IMAGE_ANALYSIS_LIMIT`,
`WEEKLY_REPORT_FREE_LIMIT`, and `readSingleCeiling(latestMigrationDefining(...))` for `chat_app` /
`vision_analysis`), and that `food_text` / `delete_account` / `verify_payment` carry NO cap.

Message (Telegram `sendMessage`, `parse_mode: "HTML"`; every dynamic string passes through
`escapeHtml` — alert summaries are untrusted text; ≤ 4096 chars, alerts capped at 10 lines with
"… +N more"):
```
📊 <b>Avya — daily digest</b> · Thu 11 Sep 2026 (IST day)

<b>Usage yesterday</b>
PRO image reads: 3 (2 users) · at cap 50: 0
PRO video reads: 0 · at cap 10: 0
Free image reads (lifetime meter): 1 user moved · at 5/5: 0
Chat (free, 10/day): 7 msgs · 3 users · at cap: 1
Weekly report (free lifetime): 0 new
Also: vision 0 · food text 0 · delete-account 0 · verify-payment 0

<b>Top users</b> (id prefix): 1a2b3c4d ×5 · 9f8e7d6c ×2

<b>Alerts yesterday</b>: none
```
Three states per section (`feedback_bad_news_vs_no_news`): data · "none" · **`⚠ usage ledger
unreadable: <message>`** — an unreadable section is never rendered as zeros (the marker
deliberately does not contain the table name, so `index_test.ts` never needs that literal; see
T2). The digest is sent EVERY day, including all-quiet days: its arrival is the liveness signal;
its absence means the cron or the bot is dead, which `alert_cron_function_dead` (8-day window)
would otherwise take a week to notice. Missing `TELEGRAM_BOT_TOKEN` / `FOUNDER_TELEGRAM_CHAT_ID`
→ `logCronEnd(logId, "failed", { httpStatus: 500, errorSummary })` (the real signature,
`cron_telemetry.ts:75-79`, copied from `compute-admin-metrics-daily:143`) + 500, never a silent
`return false` (the shape
`morning-alert:364` has). A Telegram non-2xx → failed + 502. A manual re-run sends a duplicate;
acceptable and stated.

Telegram send is a private function in the digest (twin of `morning-alert/index.ts:358-390`,
which stays untouched — extracting a shared helper would redeploy nothing but would make
`morning-alert`'s live bundle differ from git). **The twin differs in one deliberate way (round 1
P2):** the `fetch` is wrapped in its own try/catch and NEITHER the error object nor `String(err)`
is ever logged or passed to `logCronEnd` — a Deno fetch error embeds the request URL, which
carries the bot token. It logs `err.name` and, for a non-2xx, the HTTP status and the first 200
chars of the response body (Telegram's body never echoes the token). The skeleton's outer
`catch (err)` (`compute-admin-metrics-daily:173-175`, `String(err).slice(0, 500)`) therefore can
never see a fetch error from the send.

Migration `131_founder_digest_cron.sql` (four-tag header; **no definer-mode function** — the
per-job `_function_url()` convention is a definer-mode vault read whose fallback is the literal
URL; the vault has no `project_url` row and 10 live jobs already hardcode the URL, so the literal
is used directly; the two-word phrase itself must not appear in the file or its comments, or
`blast_radius_content_rules_lib.dart` forces catastrophic and a Hermes review):
```sql
select cron.schedule(
  'founder_digest_daily',
  '30 2 * * *',              -- 08:00 IST (pg_cron runs UTC)
  $job$
  select net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/founder-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.cron_get_secret()
    ),
    body := '{}'::jsonb
  );
  $job$
);
-- Rollback (inline, not executed): select cron.unschedule(<the job name scheduled above>);
-- ⚠ deliberately NOT written as cron.unschedule('founder_digest_daily') — see Ground truth, Gate 31 row.
```
`private.cron_get_secret()` already exists (migration 107) and is CALLED, not defined, here.
Registry row (Gate 31, `docs/operations/CRON_REGISTRY.md`), in the file's exact column shape —
backticked cells and the live jobid in parentheses, as `:46` has it (round 2:
`check_unbounded_cron_reads.dart:243` extracts the function slug ONLY from a backticked cell):
`| 131 | \`founder_digest_daily\` (<jobid>) | \`30 2 * * *\` | 08:00 | \`founder-digest\` |
\`cron_secret\` | Read-only usage + alerts digest to the founder's Telegram. Sends daily even when
all-quiet (liveness) |`. The jobid exists only after the apply, so the row lands in the apply
commit with the regenerated `backups/live_cron_jobs.json` (which also picks up jobid 37, see
Ground truth).

Deploy: `founder-digest` with **`verify_jwt=false`** (cron secret is the gate — a `true` would
reject the non-JWT Bearer at the gateway, the c3f8a1 class); `ai-media-proxy` with its CURRENT
`verify_jwt`, read from `GET /v1/projects/<ref>/functions/ai-media-proxy` at deploy time, never
from docs. Two deploy-tooling entries land in the code commit (round 1 P2): `SMOKE_TOLERATED_CODES`
in `.claude/deploy_via_api.js:657` gains `'founder-digest': [401]` (a healthy cron-only function
answers 401 to the unauthenticated smoke; the map's `?? []` default would print "Smoke FAIL" on a
correct deploy), and `expectedVerifyJwt` in `test/contracts/runbook_deploy_verify_jwt_test.dart:42`
gains `'founder-digest': false` (its "unknown slug fails" test would otherwise redden the first
runbook that names the function). Order: deploy `founder-digest` → apply 131 (+132) → deploy
`ai-media-proxy` (independent; the caps go live at that deploy). Each is its own explicit go.

Secrets used: `TELEGRAM_BOT_TOKEN`, `FOUNDER_TELEGRAM_CHAT_ID` (Edge Function secrets, present
since 2026-09-12), `CRON_SECRET` (existing), platform-injected `SUPABASE_URL` /
`SUPABASE_SERVICE_ROLE_KEY`. Two rows added to `docs/operations/SECRET_INVENTORY.md`.

### Unit F — migration `132_vision_trigger_null_channel_guard.sql`

`CREATE OR REPLACE FUNCTION public.enforce_vision_analysis_daily_limit()` — the 129 body verbatim
with one line changed: `IF NEW.channel IS NULL OR NEW.channel NOT IN ('scan_meal', 'cart_auditor')
THEN RETURN NEW;`. Preserves the P0001 identifier `vision_analysis_daily_limit_reached (cap=20)`
that `ai-proxy` greps, the IST expression, and INVOKER mode; the header uses the hyphenated
"definer-mode" wording 129 uses, for the content rule. Four-tag header, inline rollback (the 129
body). `test/helpers/migration_cap_reader.dart`'s `latestMigrationDefining` resolves to 132
afterwards and `readSingleCeiling` still reads 20 — T7 and `ai_message_limit_parity_test.dart:50-54`
depend on exactly that resolution.
**Ripple (round 2 P1 — the sibling census this unit had not run):** `grep -rln
latestMigrationDefining test/` → 4 files. `cap_triggers_use_usage_counters_test.dart:56-69`
resolves all THREE triggers in `setUpAll` and asserts `distinct hasLength(1)` — after 132 the set
is {129, 132, 129} and EVERY test in that file errors; redefining all three in 132 instead breaks
its `:147-159` backfill test (`INSERT INTO public.usage_counters` must precede the first `CREATE
OR REPLACE`). Repoint (T11): resolve each trigger to its OWN latest migration, assert its number
is ≥ 129 (none left behind on a pre-129 `count(*)` body — the property the old "all the same
file" check was a proxy for) and that its body from THAT file calls `consume_quota(` with its
`quotaKey`; pin the backfill test to
`File('supabase/migrations/129_cap_triggers_use_usage_counters.sql')` BY NAME — the backfill is
a one-time event that lives in 129 whatever is redefined later. `food_text_analysis_daily_cap_
writer_to_reader_test.dart:34` resolves one trigger (food) and is unaffected.

## Tests (every writer→reader chain; source-greps over comment-stripped source)

| # | Path | Pins |
|---|---|---|
| T1 | `test/contracts/pro_media_daily_caps_writer_to_reader_test.dart` (new) | `countProImageAnalysesToday`, `pro_image_analysis`, `.in("channel"`, `code: "RATE_LIMITED"`, `"Retry-After"` all ABSENT from code · constants `PRO_IMAGE_DAILY_CAP = 50`, `PRO_VIDEO_DAILY_CAP = 10`, keys `"pro_image_daily"` / `"pro_video_daily"` · BOTH ternaries pinned by regex (`isVideo ? PRO_VIDEO_QUOTA_KEY : PRO_IMAGE_QUOTA_KEY` and `isVideo ? PRO_VIDEO_DAILY_CAP : PRO_IMAGE_DAILY_CAP`) · PRO gate is `if (isPro)` and the literal `!isVideo && isPro` is gone · ordering: index of `p_quota_key: proQuotaKey` is AFTER `await fetchImageAsBase64(` (the CALL at `:690` — round 2: bare `fetchImageAsBase64(` first matches the DECLARATION at `:248`, which makes the assertion vacuous) and BEFORE `await geminiChat(` (`:702`, the only `await` of it); the free consume (`p_quota_key: FREE_IMAGE_ANALYSIS_QUOTA_KEY`) stays AFTER `channel: interactionChannel` · ASSOCIATIVE, not membership (round 2): the span from `if (proConsumeError)` to its `else if` contains `gate_reason: "pro_quota_unavailable"` and no other gate_reason; the span from `proCount === -1` (round 4: bare `=== -1` also matches the free path's `consumedCount === -1` at `:814`) to the next `else` contains `console.warn(` and BOTH `pro_image_daily_limit_reached` / `pro_video_daily_limit_reached`; the span from `if (subscriptionError)` to its closing contains `gate_reason: "tier_unavailable"`; each of the four new gate_reason literals occurs EXACTLY once in the file and on a `status: 200` response · `p_window_start: proWindowStart` and `resets_at` present · the four new copies exist in `coach_replies.ts`, the cap ones contain "midnight", "IST" and the template `${cap}` (round 4: they are functions since round 3, so the `.ts` never contains `50`/`10`), the `-1` branch calls `proImageDailyCapReached(proCap)` / `proVideoDailyCapReached(proCap)`, none contains "Upgrade" |
| T2 | `test/contracts/usage_quota_ledger_writer_to_reader_test.dart` (edit — the census that caught three slices) | `stillLegacy` → EMPTY, `hasLength(0)`, title "ZERO remaining legacy quota readers"; ai-media-proxy mirror gains the PRO half (no `countProImageAnalysesToday`, no `.in("channel"`) — and the WHOLE mirror block (`:331-346`) switches from `readAsStringSync()` to `_stripDartLikeComments(...)` (round 2: it reads the RAW file today, so a history comment naming the deleted function would redden it; the deleted function's name goes in the diagnose-doc, never in an `index.ts` comment); the DIRECT-`usage_counters` allowlist at `:152` gains `supabase/functions/founder-digest/index.ts` with the reason "read-only aggregate reader; decides no quota" (round 1 P1: `_appSources()` at `:71-81` scans EVERY `.ts` under `supabase/functions`, so the digest is an offender without it; `index_test.ts` is kept free of the literal instead of allowlisted); the `consume_quota` caller set at `:204` is unchanged — the digest must NOT appear there |
| T3 | `test/contracts/media_free_image_lifetime_gate_writer_to_reader_test.dart` (edit) | "ratcheted to 1" → **0**; the two position-based `indexOf('consume_quota')` lookups (`:184`, `:198`) → key-based lookup of the FREE consume (see the ⚠ under Unit A/B). Repoint, never delete; the free guard containment assertion is otherwise unchanged |
| T4 | `scripts/usage_counter_source_lib.dart` (edit) + `test/scripts/usage_counter_source_lib_test.dart` (edit) | ai-media-proxy `1 → 0`. ⚠ The two tests at `:107,121` do `firstWhere((e) => e.value >= 1)` over the PRODUCTION map; with every entry at 0 they throw `StateError` — the §4.9 "repairing enforcement breaks tests relying on it not enforcing" class, found by reading, not by running. Repoint both to inject a fixture via `sweep(allowedEf: {...})`, which the function already accepts |
| T5 | `test/contracts/cron_telemetry_adoption_test.dart` + `cron_auth_adoption_test.dart` (edit) | add `founder-digest` to both hand-maintained rosters |
| T6 | `supabase/functions/founder-digest/index_test.ts` (new, Deno, CI only) | `buildDigestText`: unreadable section renders the ⚠ marker and no number · empty day renders "none" · HTML escaping of `<`, `>`, `&` in summaries · id prefixes are 8 chars, no full uuid in output · `used >= cap` via `DIGEST_KEYS` · lifetime rows keyed by `updated_at`, windowed by `window_start` · ≤ 4096 chars · `istYesterdayWindow(now)` flips exactly at 18:30:00Z · `telegramErrorSummary(err)` never contains "bot" followed by the token shape |
| T7 | `test/contracts/founder_digest_caps_mirror_test.dart` (new) | `DIGEST_KEYS` set == union of every `p_quota_key` literal in `supabase/functions/*/index.ts` + every trigger key in the highest migration defining each trigger (both directions); every `cap` equals its source constant or `readSingleCeiling(latestMigrationDefining(...))`; `food_text` / `delete_account` / `verify_payment` have no cap |
| T8 | `test/sql/oi153_pro_media_caps_live_verify.sql` (new; run by hand via MCP inside `BEGIN … ROLLBACK`; CI has no credentials) | `consume_quota('pro_image_daily', <IST midnight>, 50)` returns 1…50 then −1; `pro_video_daily` 1…10 then −1; the two keys are independent rows; `has_function_privilege('anon', …, 'EXECUTE')` still false; after 132: an `ai_coach_interactions` insert with `channel = NULL` leaves `vision_analysis` untouched while a `scan_meal` insert consumes 1. Labelled as behaviour-invariants of `consume_quota` (proven in slices 2 and 4) plus the ONE 132-specific assertion — NOT evidence the EF landed; the EF's landing is proven by the deploy-time smoke |
| T9 | Deploy-time smoke (own go) | anon-Bearer boot probe → the module's own 401 for both EFs; `founder-digest` invoked once by hand (`select net.http_post(...)` with `private.cron_get_secret()`) — **this sends a real digest to the founder**, and is the only end-to-end proof of the Telegram path; a temp-PRO QA account per `.claude/skills/e2e-sim-testing/SKILL.md` sends ONE photo → one `pro_image_daily` row with `used = 1` (proves the writer; the 51st request is not exercised live) |
| T11 | `test/contracts/cap_triggers_use_usage_counters_test.dart` (edit — see Unit F "Ripple") | per-trigger resolution, each ≥ 129 and calling `consume_quota(` with its key from its OWN file; backfill pinned to 129 by name; the three P0001 texts read from each trigger's own latest body; **the vision block from its latest definer contains `NEW.channel IS NULL OR`** (round 3 — the CI-side pin for Unit F; M12). ⚠ 132 uses `--` line comments ONLY, with the rollback body BELOW the live statement: `stripSqlComments` (`migration_cap_reader.dart:49-55`) strips `--` and nothing else, so a `/* … */` block quoting the 129 body would be seen by the resolver's `CREATE … FUNCTION` regex |
| T10 | `test/contracts/coach_replies_test.dart` (edit) | the byte-identity test becomes a loop over EVERY key of the `COACH_REPLIES` object, DERIVED from the `.ts` source (round 4: a hand-enumerated list omitted `videoPaywall`, which is mirrored at `ts:5-8` / `dart:40-43` — the membership gap this row exists to close), each of which must have a Dart twin with identical rendered text, so a drifted or unmirrored key cannot hide. The extractor at `:73-81` is rewritten QUOTE-AWARE (round 2: its `[^'"]*` class stops at the apostrophe in "You've", so it returns null for `imagePaywallExhausted` — the very key the loop adds — and for `freeImageCounter(0)`): match a sequence of literals where each is `'…'` with no `'` inside, `"…"` with no `"` inside, or a backtick template, and join the pieces. `freeImageCounter` is mirrored too: the three server `return` literals (extracted from the function block, `${remaining}` → `3`) equal the client's `freeImageCounter(3)`, `(1)`, `(0)`. Plus the absent-pattern: neither mirror file's comment-stripped source contains `unlimited` |

SoT registry (`docs/sot_registry.yaml`): new concept `pro_media_daily_caps` (writer: the single
consume site; readers: the `-1` branch + `founder-digest`; `behavioral_test_path:` T1 +
`presence_only: true` with the Deno-EF reason the sibling concepts carry) and `founder-digest`
added to `usage_quota_ledger`'s readers (it has `reader_manifest_complete: true`). Glossary
(`docs/naming_conventions.md` §4.7): **founder digest** — a daily ops summary to the founder's
Telegram; NOT a user notification, NOT `morning-alert`.

Mutation plan (rule 21 — each confirmed APPLIED by `grep -c`, each leaves the file compiling):
M1 `if (isPro)` → `if (!isVideo && isPro)` (T1 red) · M2 swap the two quota keys in the key
ternary (T1 red) · M2b swap the two caps in the cap ternary (T1 red — the arrangement mirror on
the SECOND ternary; round 1 caught that M2 alone left video at 50) · M3 move the PRO RPC below
`await geminiChat(` (T1 ordering red) · M3b move it ABOVE `await fetchImageAsBase64(` (T1 red —
the other direction, which M3 alone never tests) · M4 `if (proConsumeError)` branch returns the cap copy instead of
`pro_quota_unavailable` (T1 red) · M4b delete the `if (subscriptionError)` branch (T1 red) · M5 `PRO_VIDEO_DAILY_CAP` 10 → 11 in ai-media-proxy only (T7 red) ·
M5b misspell one `DIGEST_KEYS` key (T7 completeness red) · M6 digest counts lifetime rows by
`window_start` (T6 red) · M7 remove `escapeHtml` (T6 red) · M8 chain `.in("channel", ["pro_image_analysis", "image_analysis"])` onto `readFreeImageQuota`'s
builder (`:114-120` — round 4: the bare fragment named no site and would not compile anywhere
else) (T2 + T1 red) · M9 ratchet back to 1 (T3 red) · M10 drift one mirrored
client copy by a character (T10 red) · M10b re-type "unlimited" into `freeImageCounter` on the
server only (T10 red) · M11 `return defs.last;` → `return defs.first;` in
`latestMigrationDefining` (`migration_cap_reader.dart:111` — round 3: the helper sorts by
`compareTo` and returns `defs.last`; there is no `>` to flip, so the earlier wording named a
mutation that could not be applied) so it returns the EARLIEST definer (T11 ≥129 assertion red,
`ai_message_limit_parity` red — proves the repointed test still detects a trigger left on an old
body) · M12 delete `IS NULL OR` from 132's vision guard (T11 red — round 3: without this, Unit F's
only test was the MANUAL T8, and deleting the guard reddened zero CI tests) · M13 remove `await
isAuthorizedCronCall(req)` from `founder-digest/index.ts` (T5 `cron_auth_adoption_test` red) ·
M14 `count > allowed` → `count > allowed + 1` at `usage_counter_source_lib.dart:253` (T4 red) —
round 4: T4 and T5 previously had no mutation at all. Every T1–T11 now has ≥1. ⚠ **M6/M7 need Deno**, which the dev machine does not have;
they are either run after `winget install DenoLand.Deno` (founder's call — a dev-tool install) or
run in CI only, in which case the plan-review record must say those two legs are unproven
locally. Stated here so it is decided, not discovered.

Docs touched: `docs/architecture/ai.md` (media proxy row: caps + response shape), `docs/
architecture/business-rules.md` (PRO media limits), `docs/architecture/functionality-flow.md`
(`COACH-12` still says photo upload is PRO-only — stale since slice 3b's 5 free reads; correct it and
add a `COACH-20` assertion for the two PRO caps + the 200/gated shape, verified by T1 — round 2: `COACH-14` already exists (error mapping) and the highest id is `COACH-19`), `supabase/functions/CLAUDE.md` (table row +
new function), `lib/features/ai_coach/CLAUDE.md:26-27` (says "photo / video upload" — there is
no video uploader; correct it), `docs/operations/CRON_REGISTRY.md`, `docs/operations/
SECRET_INVENTORY.md`, `docs/naming_conventions.md`, OI-153 board entry (CLOSED; Unit F closes the
slice-4 residue it carried), `docs/audit/oi153-pro-media-caps.closure.yaml` (≥4 units ⇒ §4.2
closure ledger), diagnose-doc
`docs/diagnoses/2026-09-12-pro-media-caps-dormant-and-video-uncapped-<id>.md` with
`related_bugs: [d3a7f1, e7c4b2, c4f9e2, f2c8d5]` and `recurrence:` (5th slice).

## Commits (feature-consolidated, one push)

1. `fix(ai-media-proxy): PRO image 50/day + video 10/day on usage_counters …` — Units A/B/C +
   T1–T4 + T10 + registry + diagnose-doc (`closes-diagnose:`). Platform.
2. `feat(founder-digest): daily usage + alerts digest to the founder's Telegram` — Unit D EF +
   T5–T7 + deploy-tooling entries + docs. Platform. (Migrations 131/132 are NOT in this commit —
   see 4.)
3. B-pass on the branch (self-initiated, before the merge); plan-review record
   `docs/plan-reviews/oi153-pro-media-caps.md` in its own docs commit citing the review by its
   `bpass_review:` field only (never the hash-named path in prose — instance 3 of
   `feedback_gates_unsatisfiable_at_merge`).
4. After the founder's apply go: `131_founder_digest_cron.sql` + `132_vision_trigger_null_channel_
   guard.sql` + `backups/applied_migrations.json` + regenerated `backups/live_cron_jobs.json` +
   the registry row, one commit (`check_migration_ledger_paired.dart` refuses a migration without
   its ledger entry, and the entry cannot be truthfully written before the apply).
5. Merge via `safe_merge.sh`, push via `safe_push.sh`; CI is the full-suite proof.

Split line, should a review round find material NEW issues (§4.12.1): A/B/C (+T1–T4, T10) first
and D (+T5–T7) second — they share no file except the census (T2); F is independent of both.

## Blast radius (classified with scratch copies of the NEW paths present, §4.9 row)

| Path | Tier | Why |
|---|---|---|
| `supabase/functions/ai-media-proxy/index.ts`, `_shared/coach_replies.ts`, `founder-digest/**` | platform | `supabase/functions/**` / `_shared/**` globs |
| `supabase/migrations/131_*.sql`, `132_*.sql` | platform | `supabase/migrations/**`; content rule does NOT fire (no definer-mode phrase — verified with a scratch copy AND a positive control that appended the phrase and flipped to catastrophic, so the detector was live) |
| `lib/features/ai_coach/copy/coach_replies.dart`, `lib/features/ai_coach/CLAUDE.md` | account | `lib/features/ai_coach/**` (`blast_radius.yaml:235`) — copy/doc parity only, no behaviour; account < platform so the batch tier is unchanged |
| tests, `scripts/usage_counter_source_lib.dart`, `.claude/deploy_via_api.js`, docs, backups | feature / per-registry | classified at execution as part of the staged set |

Batch tier: **platform**. No Hermes: nothing catastrophic by path (no payment/auth/admin
function, no `*rls*` / `*security_definer*` migration name) or by content.

## Rollback

`ai-media-proxy`: `deploy_via_api.js … --rollback previous` (the cap returns to dormant; no data
to unwind — `usage_counters` rows age out). `founder-digest`: `select cron.unschedule
('founder_digest_daily')` (inline in 131's rollback block) and leave or delete the function.
132: re-apply the 129 body (inline in its rollback block). Nothing touches user data.

## Rounds (§4.12 — two independent, context-blind reviews)

### Round 1 (2026-09-12, general-purpose/opus, lenses L1 L21 L22 L23 L29 L37 + guard-mirror +
fixture questions) — 14 REAL (0 P0, 4 P1, 10 P2), 6 FALSE_ALARM, "converge? NO"

| # | Finding | Disposition |
|---|---|---|
| 1 | P1 — advisory-read-then-consume-after-delivery does not bound Gemini spend under concurrency; `-1` was only logged | **ADOPTED — gate redesigned** to consume-first after the Storage fetch, before Gemini (Unit A/B). The free path stays untouched. Cost stated: a Gemini 5xx spends a unit, up to 4 per photo with the client's 3 retries |
| 2 | P1 — census direct-`usage_counters` allowlist (`:152`) not updated; `_appSources()` scans `_test.ts` too | **ADOPTED** — T2 allowlists `founder-digest/index.ts`; the rendered marker avoids the table name so `index_test.ts` never carries the literal |
| 3 | P1 — `DIGEST_CAPS` (4 keys) is membership, not completeness, over a 9-section template; `free_image_analysis`/`weekly_report_free`/`delete_account`/`verify_payment`/`food_text` literals unpinned | **ADOPTED** — `DIGEST_KEYS` enumerates all nine with kind + cap; T7 pins the set both ways and every cap to its source |
| 4 | P1 — `orderBy: ["user_id",…]` is `string[]`; `paged_fetch.ts:115` types `string \| OrderKey[]`, `deno check` rejects it | **ADOPTED** — `OrderKey[]` form written into the design |
| 5 | P2 — `SMOKE_TOLERATED_CODES` lacks `founder-digest` → a healthy 401 prints "Smoke FAIL"; `expectedVerifyJwt` lacks the slug | **ADOPTED** — both entries in the code commit (Deploy §) |
| 6 | P2 — M2 covered the key ternary only; swapping the cap ternary leaves T1 green | **ADOPTED** — both ternaries regex-pinned; M2b added |
| 7 | P2 — block-scoped consts referenced outside the `if (isPro)` block (TS2304, CI-only) | **ADOPTED** — function-scope declarations next to `isVideo` |
| 8 | P2 — `String(err)` on a Telegram fetch failure carries the URL and thus the token into `cron_call_log.error_summary`; `morning-alert:388` has the same shape | **ADOPTED** for the digest (send twin catches internally, logs name/status/body only); `morning-alert`'s instance is FILED for the board (not in this batch's deploy set) |
| 9 | P2 — "CLOSED except the trigger asymmetry" leaves an open item on a closed entry | **ADOPTED** — Unit F fixes it (migration 132) with a T8 assertion; the entry closes cleanly |
| 10 | P2 — prose said slice 3b deleted the client copy twin; it ADDED one, byte-identity-tested; `imagePaywallExhausted` promises "unlimited image + video reads" | **ADOPTED** — client mirrors added for all four new strings, T10 loops over every mirrored key, the "unlimited" claim reworded on both sides |
| 11 | P2 — rationale (d) moot: the client's orphan sync pushes the refusal as `in_app_orphan`, which `founder_metrics_engagement()` counts; the `[Photo]` vs `[Photo: image]` dedupe miss doubles every media turn | **ADOPTED** — decision kept (no server row), rationale rewritten; the dedupe defect FILED for the board |
| 12 | P2 — "vault secrets" is wrong; they are Edge Function secrets (`Deno.env`) | **ADOPTED** — reworded, and the Vault's actual contents stated |
| 13 | P2 — blast table said `lib/**` untouched while editing `lib/features/ai_coach/CLAUDE.md` | **ADOPTED** — row corrected (account; batch tier unchanged) |
| 14 | P2 — reusing `imageQuotaUnavailable` ("Photo received, Recruit") for a PRO video refusal | **ADOPTED** — a rank-free pair, named `proImage…`/`proVideo…QuotaUnavailable` at the time and RENAMED `imageLedgerUnavailable` / `videoLedgerUnavailable` in round 2 (tier-neutral, because the tier-read fault reuses them); the body and T10 use the round-2 names |
| 15–20 | FALSE_ALARM (verified by the reviewer): 200+gated needs zero client behaviour change; fail-closed reasoning; IST arithmetic; literal cron URL; PRO-consume-after-free ordering (moot after #1 — the ordering now changes and T3 is repointed); every numeric claim except one line-range citation | recorded; the line-range citation loosened |

Verified by the author before adopting (subagents hallucinate constants): `_appSources()` at
`:71-81` and the `allowed` set at `:152-155`; `paged_fetch.ts:100-120` `OrderKey`; the
byte-identity test at `coach_replies_test.dart:66-86` pinning ONE key; `SMOKE_TOLERATED_CODES`
at `deploy_via_api.js:657` with the `?? []` default at `:753`; `expectedVerifyJwt` at
`runbook_deploy_verify_jwt_test.dart:42`; `_coldStartBackoffsMs` = 3 entries; `channel` nullable
with default `'app'` (live `information_schema`); 129's three guard forms at `:99/:149/:183`.

### Author's pre-round-2 pass (main session, 2026-09-12 14:30 IST — NOT a review round)

Round 1's dispatch of round 2 died on an API usage limit (HTTP 429, resets 16:40 IST). Before
re-dispatching, the main session re-verified every file:line the hardened plan cites (all hold —
`ai-media-proxy` `:43/:133/:142/:385/:465/:477/:508/:587/:690/:702/:715/:751-754/:765-766/:794/:836`;
census `:71/:152/:204/:254-259`; free-image test `:178-212`; `usage_counter_source_lib.dart:153/:163`
+ its test `:107/:121`; `deploy_via_api.js:657/:753`; runbook test `:42/:46/:167`; 128 `:95-100`; 129
`:99/:149/:183`; 120 `:125`; `ist_date.ts:14/:36`; `paged_fetch.ts:99-140`; `cron_auth.ts:38/:98`;
`compute-admin-metrics-daily:115-181`; `morning-alert:111/:364/:368/:388`; `blast_radius.yaml:235`;
`ai_coach/CLAUDE.md:26-27`; `ai_coach_provider.dart:609/:625/:659-677/:752/:1019`;
`ai_service.dart:599`; `supabase_service.dart:381`) and found ONE gap of the guard-without-mirror
class: the "unlimited" reword covered one of THREE such strings in the mirror pair — `freeImageCounter`
(rendered to every free user after every analysis) still said "[Upgrade for unlimited →]" twice.
Fixed in Unit C + T10 above; `functionality-flow.md` `COACH-12` (stale) added to the docs list.

### Round 2 (2026-09-12, general-purpose/opus, same lenses + "did round 1's corrections introduce
defects?") — 13 REAL (0 P0, 2 P1, 11 P2), 8 FALSE_ALARM, "converge? NO"

Every claim re-verified by the author against the files before adoption (all 13 held).

| # | Finding | Disposition |
|---|---|---|
| 1 | P1 — Unit F (132) breaks `cap_triggers_use_usage_counters_test.dart` (`setUpAll` asserts all three triggers resolve to ONE migration; redefining all three in 132 breaks its backfill-precedes-CREATE test instead) | **ADOPTED** — T11 repoint (per-trigger ≥129 + backfill pinned to 129 by name), M11 |
| 2 | P1 — `DIGEST_KEYS … as const` with `cap` on 6 of 9 → `k.cap` is TS2339 at CI's `deno check` | **ADOPTED** — explicit `DigestKey` type |
| 3 | P2 — T10's extractor (`[^'"]*`) cannot parse `imagePaywallExhausted` ("You've") — the key the loop adds | **ADOPTED** — quote-aware extractor; `freeImageCounter` mirrored too |
| 4 | P2 — T1 anchor `fetchImageAsBase64(` first matches the declaration (`:248`) → vacuous | **ADOPTED** — `await fetchImageAsBase64(` / `await geminiChat(`; M3b |
| 5 | P2 — `gate_reason: "quota_unavailable"` already exists in the free path (`:538`) → T1 membership, M4 stays green | **ADOPTED** — `pro_quota_unavailable`, associative T1 spans |
| 6 | P2 — `:407-416` discards the `subscriptions` read error → a PRO user takes the FREE path, spends a free unit, sees "[Upgrade to PRO →]" (pre-existing; the plan's "nothing changes there" was false) | **ADOPTED** — `tier_unavailable` fail-closed branch, M4b |
| 7 | P2 — `-1` leaves the row untouched (128:97-100): the digest's "at cap" cannot count refusals; PRO branch had no telemetry | **ADOPTED** — `console.warn` on the PRO `-1`; the digest's "at cap" wording kept (it is a users-at-ceiling count, not a refusal count) |
| 8 | P2 — `COACH-14` already exists | **ADOPTED** — `COACH-20` |
| 9 | P2 — registry row quoted without backticks/jobid; `check_unbounded_cron_reads.dart:243` slugs only from a backticked cell | **ADOPTED** — exact column shape, row lands in the apply commit |
| 10 | P2 — T7's "union of constant literals" collides on `RATE_LIMIT_QUOTA_KEY` (two files, two values) | **ADOPTED** — per-file resolution |
| 11 | P2 — `tStart − 86 400 000` is a number; a `Date` in `.gte()` stringifies non-ISO → usage section unreadable daily | **ADOPTED** — ISO strings, T6 pins the shape |
| 12 | P2 — the census's ai-media-proxy mirror block reads the RAW file; a comment naming `countProImageAnalysesToday` reddens it | **ADOPTED** — block switched to comment-stripped source; name banned from `index.ts` comments |
| 13 | P2 — `logCronEnd("failed", errorSummary)` is not the signature | **ADOPTED** — real signature copied from the skeleton |
| 14–21 | FALSE_ALARM (verified by the reviewer): control flow `:690-702` has only comments between fetch and Gemini; `consume_quota` never returns NULL/0; IST window instant confirmed live; census strips comments and `p_quota_key: FREE_IMAGE_ANALYSIS_QUOTA_KEY` is unique at `:796`; `OrderKey` exact; 131's shape matches the live `compute_admin_metrics_daily` command; content-rule regex has 0 hits on 131/132 text; live vision body = 129 and the P0001 text is read only at `ai-proxy:524`; no test pins "Upgrade for unlimited"; zero live tests invoke `ai-media-proxy`; classifier says platform | recorded |

Round-1 corrections that introduced a defect (the §4.12 point-1 hazard, observed): #1 consume-first
→ r2 #4/#5/#7; #3 `DIGEST_KEYS` → r2 #2/#10; #9 Unit F → r2 #1; #10 T10 loop → r2 #3; the
author's pre-round-2 pass → r2 #8. None changed the mechanism; every one is a test-strength,
type, format or telemetry defect in the CORRECTION, which is exactly why round 2 runs on the
hardened plan.

### Round 3 (2026-09-12, general-purpose/opus, same lenses; brief = "check each round-2 correction
individually + weight Units D and F") — 5 REAL (0 P0, 0 P1, 5 P2), 3 FALSE_ALARM, 11 of 13
round-2 corrections "holds", "converge? NO"

Every claim re-verified by the author before adoption (all held: `defs.last` at
`migration_cap_reader.dart:111`; `stripSqlComments` `:49-55`; `check_cron_registry.dart:82-101`
raw scan + `128:161`; `coach_replies` import at `index.ts:5`; the jobid-30 silent miss re-queried
live — 0 `cron_call_log` rows on 09-11 vs 1 on 09-10 and 09-09, 27 other cron rows that evening).

| # | Finding | Disposition |
|---|---|---|
| r2 #1 residue | P2 — M11 named a `>` flip that does not exist in the helper | **ADOPTED** — `defs.last` → `defs.first` |
| r2 #10 residue | P2 — T7's per-file literal resolver cannot see through `proQuotaKey`'s ternary | **ADOPTED** — one level deeper, unresolvable = fail, positive control (3 keys from ai-media-proxy) |
| B1 | P2 — Unit F's NULL guard had no CI test (T8 is manual); `stripSqlComments` strips `--` only | **ADOPTED** — T11 pins `NEW.channel IS NULL OR`; M12; 132 comment discipline |
| B2 | P2 (scope fact) — Unit F is unreachable today (0 NULL rows, 12 guarded writers, authenticated NULL insert fails 42501 before consuming) | **RECORDED in Scope** — kept as a latent-guard fix; founder may strike |
| B3 | P2 — Gate 31 treats a COMMENTED `cron.unschedule('X')` as real (raw scan); 131's quoted rollback would join the ten migrations already invisible to input A | **ADOPTED** — 131 rollback phrased without a quoted name; ground-truth row corrected; gate blind spot FILED (Scope iii) |
| B4 | P2 — the shared copy file cannot interpolate `PRO_*_DAILY_CAP` (import cycle) | **ADOPTED** — cap copies are `(cap) => string` functions on both sides, `freeImageCounter`'s shape |
| B5 | P2 (doc) — r1 #14's disposition named the pre-rename identifiers | **ADOPTED** — disposition annotated |
| B6–B8 | FALSE_ALARM (holds): `maybeSingle()` cannot produce `subscriptionError` for a row-less free user (0 rows → `data: null`, no error); a Deno fetch `TypeError.message` embeds the URL and `err.name` cannot; no other test file pins the deleted tokens (9 files name ai-media-proxy, none greps them) | recorded |

Trend across rounds: 14 → 13 → 5 findings; mechanism-level findings 1 (r1 #1) → 0 → 0. Rounds 2
and 3 found only defects in test specifications, prose and the corrections themselves.

### Round 4 (2026-09-12, general-purpose/opus, BOUNDED to the test/spec layer) — 5 REAL (0 P0,
0 P1, 5 P2), 3 FALSE_ALARM, M11 "holds", **"converge? YES"**

Every claim re-verified by the author (the `.rpc(` / `"consume_quota",` split at
`delete-account:169-170`, `verify-payment:247-248`, `weekly-report:689-690`; `consumedCount === -1`
at `:814`; `count > allowed` at `usage_counter_source_lib.dart:253`; `videoPaywall` at `ts:5` /
`dart:40`).

| # | Finding | Disposition |
|---|---|---|
| 1 | P2 — T7 anchored on `.rpc("consume_quota"`, which 3 of 4 files split across lines → 1 file found, union 6 ≠ 9, red on first run | **ADOPTED** — anchor `p_quota_key:\s*(\w+)` |
| 2 | P2 — T1 still said the cap copies "contain the cap number" (stale after round 3 made them functions) | **ADOPTED** — pins `${cap}` + `(proCap)` at the call site |
| 3 | P2 — T10's hand-enumerated key list omitted `videoPaywall` | **ADOPTED** — keys derived from the `.ts` object |
| 4 | P2 — T1's `=== -1` span anchor also matches the free path's `consumedCount === -1` | **ADOPTED** — `proCount === -1` |
| 5 | P2 — T4/T5 had no mutation; M8 named a fragment with no compile site | **ADOPTED** — M13, M14; M8 re-sited |
| 6–8 | FALSE_ALARM: no substring collision among gate_reasons that any test pins; ordering anchors survive the multi-line RPC literal (token index compare); a `/* */` rollback would NOT be seen by `functionBlock` (`firstMatch` takes the live CREATE) — the `--`-only rule stays as hygiene | recorded |

Reviewer's clean list, kept because a converged verdict must show its input set: T1 anchors unique
post-edit and all named mutations compile (function-scope consts; no `deno.json`, so no
`noUnusedLocals`); 13 test files name ai-media-proxy and only T2/T3 grep the deleted tokens;
`weekly_report_free` (`weekly-report:32`) and `food_text` (`129:200`) confirmed; the existing
`coach_replies_test.dart:18-41, :62-63` stay green after both rewords; all 12 existing expects in
`cap_triggers_use_usage_counters_test.dart` pass under the T11 repoint and M11 reddens it via
111's `>= 15` (vision) and 026's 200/50 (food); T2's empty-map loop is a no-op; T3's key-based
lookup gives `:794 > :765` with no `if (` between; T4's `sweep(allowedEf:)` exists (`:229`); 131
mirrors `102:98-111`; the content rule is `security\s+definer` case-insensitive; no migration
header gate exists (`migrations/CLAUDE.md:177`); an unquoted `cron.unschedule(<…>)` escapes
`check_cron_registry.dart:83`.

**Verdict: CONVERGED after 4 rounds** (14 → 13 → 5 → 5 findings; mechanism findings 1 → 0 → 0 → 0;
round 4's five were one-line spec-precision corrections with no design choice). The plan-review
record (`docs/plan-reviews/oi153-pro-media-caps.md`, written at execution) will carry
`review_rounds: 4`, `ground_truth_verified: true`, `verdict: converged`, and — being platform
tier — `bpass: accepted` from the B-pass over the real diff before the merge.
