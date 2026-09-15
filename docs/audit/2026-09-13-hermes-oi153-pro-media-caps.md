---
hermes_pass_id: 2026-09-13-hermes-oi153-pro-media-caps
ran_at: 2026-09-13T11:23:00+05:30
batch_scope: branch oi153-pro-media-caps — 67ba6ba4 + f15fad75 + 8f6f96c1 over main 39111d1e (333 KB diff) PLUS the staged apply commit (197 KB diff, migrations 131/132, ledgers, board)
lens_set: [L1, L14, L21, L22, L23, L31, L35, L40]
agents_dispatched: 8
findings_total: 19
findings_by_severity: { P0: 1, P1: 2, P2: 16, false_alarm: 0, partial: 3 }
verdict: accepted
---

# Hermes Pass — OI-153: PRO media caps on the ledger + the founder's daily digest

Required, not elective: the batch classifies **catastrophic** by content — applied migration
131's comment carries the phrase "SECURITY DEFINER" (it explains why the file does NOT use a
definer-mode URL helper), and `scripts/blast_radius_content_rules_lib.dart` reads comments. The
migration is applied and immutable (`supabase/migrations/CLAUDE.md`), so the tier stands and this
pass is the review the tier requires (`check_plan_review_record_exists.dart`: catastrophic ⇒
`hermes: accepted`).

8 fresh, context-blind **Opus** lens agents, one per lens, each given the common brief
(`scratchpad/hermes_brief.md` — the discipline preamble, the two diffs, the 800-word cap, "find
bugs, do not validate, propose no fixes") plus its lens charter from `docs/audit/LENS_REGISTRY.md`.
Read-only, live Postgres allowed for SELECTs. Wall-clock ≈ 25 min from dispatch to the last report;
cost is not metered by the harness — with two diffs of 333 KB + 197 KB read per agent it sits
above the skill's 8-lens estimate, logged as such under Self-evolution.

Every finding below was re-verified by the consolidating session before action: the P0 was
reproduced with a Deno probe before a line of the fix was written, and every in-batch fix carries
its own mutation run (rule 21).

## Summary

- **1 P0, 2 P1, 16 P2; 0 false alarms; 3 PARTIAL (record-only).**
- **Ship-blocker (P0): H1 — ai-media-proxy path traversal through the OI-28 guard.** Pre-existing
  since 2026-05-17; the guard read the URL as SENT, `fetch` requests it as RESOLVED. **Fixed in this
  batch, deployed as ai-media-proxy v25**, diagnose `c7e2a4`.
- **In-batch fixes:** H1, H2, H18 (ai-media-proxy v25); H4, H5, H6, H7, H8, H11, H12, H13, H14
  (founder-digest v2); H9, H10, H15 (docs / board).
- **Filed, with the founder's authorisation needed to ship:** H3 (fleet-wide `cron_call_log`
  start-insert loss) → OI-194, repair candidate (d), reaches every cron function only on its own
  redeploy.
- **Record-only PARTIALs:** H16, H17, H19 — each stated below with why it is not a defect of this
  batch and where its class is tracked.

## Findings by lens

### L23 — authorization defence-in-depth on service-role paths — 3 FINDINGS (P0, P1, P2)

**H1 — F1 — P0 — REAL — FIXED (v25).** `supabase/functions/ai-media-proxy/index.ts`
`parseStorageUrl` split the RAW string on "/" and `fetchImageAsBase64` compared
`parsed.path.startsWith(`${authUserId}/`)`; `fetch` then requested the URL as the WHATWG parser
resolves it. `…/authenticated/chat-media/<own>/../<victim>/x.jpg` passed the guard and fetched
the victim's object with the service role (`%2e%2e`, `.%2e`, `%2e.` identical); six `..` reached
`/rest/v1/users` and `/auth/v1/admin/users` with the service-role bearer, the bytes base64'd into
the Gemini prompt. Reproduced: `new Request(u).url` pathname = `/rest/v1/users` while the guard
said yes. Fix: parse with `new URL()`, prefix-check the normalised href, read bucket/path from
`url.pathname`, fetch `parsed.href` — one value for guard and request. 16 Deno tests
(`ai-media-proxy/index_test.ts`, incl. a property test at the fetch seam); mutation M1 (the exact
pre-fix body) reddens 6/16. Live v25: `..` → 403, `%2e%2e` → 403, the `/rest` escape → 400
(not a Storage URL), the caller's own absent object → reaches Storage (positive control).
Diagnose `docs/diagnoses/2026-09-13-ai-media-proxy-storage-path-traversal-c7e2a4.md`.

**H2 — F2 — P1 — REAL — FIXED (v25).** The cap KEY, the cap and the free-tier video paywall were
selected by the client's `media_type` while Gemini is told Storage's content-type. A free caller
labelling a video "image" walked it past the PRO-only paywall for one lifetime image unit; a PRO
caller drew a video from the 50/day image bucket. Fix: after the fetch `isVideo` becomes the
served type when the claim disagrees (warn logged), the paywall is re-checked through the same
helper, and only then are `proQuotaKey`/`proCap` derived. Dart T1 +2 tests; mutations M3/M4
redden 1 and 2. Residual stated in the diagnose-doc: the content-type is the uploader's — a lie
there reaches Gemini as a lie and is refused by the model; the proxy does not sniff magic bytes.

**H18 — F3 — P2 — REAL — FIXED (v25).** `proDailyUsed = proCount as number` read a `null` RPC
result as GRANTED. The refusal condition is now `proConsumeError || typeof proCount !== "number"`
with the arriving shape in the log line; the cast is gone (pinned absent). Mutation M5 reddens 1.

### L31 — cron job efficiency / liveness — 4 FINDINGS

**H3 — F1 — P1 — REAL — FILED (OI-194), blocked on the founder for the fleet redeploy.**
`_shared/cron_telemetry.ts` `logCronStart` swallows its insert failure → `null` → `logCronEnd(null)`
is a no-op, so a tick whose START insert loses the race at a burst slot leaves NO `cron_call_log`
row even when the function succeeds. Measured on this batch's own first natural fire: 02:30:00Z,
three EFs boot together, one `POST /rest/v1/cron_call_log` 504s, `founder-digest` completes
`200` at 02:30:20Z and the message arrives — and the table has no row. 46 of 50 such start
failures in 24 h across the fleet. Board: OI-194 rewritten with the mechanism and repair candidate
(d) (`logCronEnd(null)` inserts a terminal row / retry the start once). Not fixed here because the
helper is bundled into every cron function and reaches each only on its own redeploy — twenty
functions, not two — which the founder's 2026-09-12 authorisation (digest + media-proxy) does not
cover.

**H8 — F2 — P2 — REAL — FIXED (v2).** The digest header cited `alert_cron_function_dead` as the
backstop that would "take a week to notice" a dead digest; that alert cannot fire at all (OI-179:
threshold above the log's retention). Header rewritten: arrival is the liveness signal, nothing
else watches this function, and the 02:30Z telemetry loss is named. Board OI-179 carries a
"cited as a live backstop while inert" note.

**H9 — F3 — P2 — REAL — FIXED (docs).** CRON_REGISTRY row 131 wording: unit letter, the alert
count/order claim, the three disagreeing records (`cron.job_run_details` succeeded, `net._http_response`
timed_out 5000 ms, `cron_call_log` absent), the unquoted rollback (OI-193). Rewritten; Gate 31 PASS.

**H7 — F4 — P2 — REAL — FIXED (v2).** The digest's three reads ran sequentially and unbounded.
Now `Promise.all` over three independent `readSection`s (each still fails alone) with
`maxPages: MAX_PAGES` (200 × 1000 rows) so a runaway ledger becomes an "unreadable" section rather
than an unbounded loop. Live v2 manual run: 200, `chars: 401`, `cron_call_log` row present.

### L22 — schema-vs-payload parity — 2 FINDINGS

**H4 — F1 — P2 — REAL — FIXED (v2).** The alerts read was `.limit(50)` and the header printed
`rows.length` — "(50)" on a 73-alert day, and the "+N more" tail counted against the page. Now
`.select(…, { count: "exact" }).limit(MAX_ALERT_LINES)`; `SectionRead` carries `total`; the header
and the tail use the server count, falling back to the page only when no count arrives. Tests: the
recording fake gained `counts`; mutations m1 (header counts the page) and m4 (limit back to 50)
redden 1 each.

**H13 — F3 — P2 — REAL — FIXED (tests).** The Deno fixtures used severities `P0/P1/P2`; the live
`alerts.severity` CHECK is `info | warn | critical`. Fixtures now use the live values, so the
rendering tests exercise strings the table can actually hold.

### L21 — Edge Function semantic correctness — 1 FINDING

**H5 — F1 — P2 — REAL — FIXED (v2).** Truncation was a raw `slice` at 4096 − marker, which can cut
inside `<b>…</b>` or an `&amp;` entity; Telegram rejects unbalanced HTML with a 400 and the whole
digest is lost rather than shortened. Now cuts at the last newline at or before the limit (raw
slice only when a single line exceeds it). Test: every surviving alert line is a whole line
verbatim, no dangling entity; mutation m2 reddens 1.

### L40 — PII / privacy in telemetry — 3 FINDINGS

**H6 — F1 — P2 — REAL — FIXED (v2).** The token guard in `sendTelegram` (`err.name` only) was
structural: a one-token edit to `String(err)` would have leaked the bot URL with every test green.
`sendTelegram` is exported with an injectable `fetchImpl`; a test drives the catch arm with a
URL-bearing `TypeError` and asserts no token, no host, no chat id in the summary; a second test
pins the non-2xx arm (status + bounded description) and the request shape. Mutation m3
(`String(err)`) reddens 1.

**H14 — F2 — P2 — REAL — FIXED (v2).** The header did not say what leaves the project. It now
does: per-key totals, counts, up to five 8-char user-id PREFIXES with usage, alert
source/severity/summary (templated, no user data); the prefix is a correlation key, not
anonymisation, at 22 users. No message text, health data, media or email.

**H15 — P2 — REAL — BOARD.** `morning-alert`'s Telegram sender logs the raw fetch error (the
token-bearing URL) — already filed as OI-196; widened on the board 2026-09-13 with the two further
lines the lens found (the `chatId` and `errorBody` logs).

### L1 — writer/reader drift — 2 FINDINGS

**H11 — F2 — P2 — REAL — FIXED (v2).** A `quota_key` the ledger carries but `DIGEST_KEYS` does not
enumerate was silently dropped — indistinguishable from "none" on the message, which is the
opposite of what a digest of the ledger is for. Now rendered as `⚠ unlisted keys: <key> <total> …
— add to DIGEST_KEYS` (windowed and lifetime sections each), and unlisted usage still ranks the
user. Mutation m5 reddens 1.

**H12 — F3 — P2 — REAL — FIXED (v2).** The lifetime line said "at 5/5: N" over rows filtered to
yesterday's MOVERS; a refusal past the cap never touches `updated_at` (128), so a mover at the
ceiling REACHED it yesterday — the users already parked there are not in view. Label is now
"reached 5/5 yesterday: N". Mutation m6 reddens 1.

### L14 — onConflict natural-key live arbiter — CLEAN, 1 PARTIAL

**H16 — PARTIAL — RECORD-ONLY.** `cron.job`'s uniqueness arbiter is `(jobname, username)`, not
`jobname` alone — a second scheduler role could create a same-named job. Every job here is
scheduled as `postgres` through `cron.schedule`, which upserts by name for the calling role;
migration 131's `cron.unschedule('founder_digest_daily')` guard is correct for that role. Recorded
in the registry row; nothing to change in this batch.

### L35 — migration reversibility / forward-compat — 1 PARTIAL

**H17 — PARTIAL — RECORD-ONLY.** Both migrations' rollback comments are prose (131's unquoted
`cron.unschedule(<name>)`, 132's "re-apply 129's body") rather than runnable statements — the
files are applied and immutable, so the fix is the registry row's exact rollback SQL and OI-193
(Gate 31's commented/unordered-unschedule blind spot), both done/filed.

### Cross-lens (raised in consolidation; per-lens F-numbers not retained)

**H10 — P2 — REAL — FIXED (docs).** Unit lettering disagreed across the migration header ("Unit
E"), the ledger note and the closure YAML ("Unit D"); the diagnose-doc's tier-6 line lagged the
deploy twice (said v23 after v24 had shipped). Ledger note now names the mislabel as frozen by
immutability; the tier-6 line carries the deploy evidence and now says v25.

**H19 — PARTIAL — RECORD-ONLY.** The ledger's grants (`usage_counters` / `consume_quota`
EXECUTE) are the OI-184 class already on the board (INFRA-14 carried as a gate gap); this batch
adds two new keys to the same table under the same grants and changes nothing about them.

## Founder triage

Founder pre-authorised (2026-09-12, verbatim intent): "we should definitely set a goal and current
till completion. and I will authorize merge and EF deploys and migrations right now." Consolidation
applied that authorisation: every in-batch finding fixed and deployed (ai-media-proxy v25,
founder-digest v2); H3 filed with the fleet-redeploy decision stated for the founder; the three
PARTIALs recorded. No finding was marked false_alarm.

## Action items

Every finding takes exactly ONE terminal state (§4.2); the closure ledger
`docs/audit/oi153-pro-media-caps.closure.yaml` carries the same 19 as entries H1–H19.

- [x] H1, H2, H18 — fixed in this batch, ai-media-proxy v25 (verify_jwt=true; byte-identical to
  the committed `index.ts`; real-user traversal probe → 403) — consolidating session
- [x] H4, H5, H6, H7, H8, H11, H12, H13, H14 — fixed in this batch, founder-digest v2
  (verify_jwt=false; byte-identical; manual run 200 / cron_call_log row / message delivered) —
  consolidating session
- [x] H9, H10, H15 — docs and board, this commit — consolidating session
- [ ] H3 — filed as **OI-194** on `docs/audit/open_issues.md` (mechanism measured, repair (d)
  named); blocked_on_user: the fleet-wide cron-function redeploy the fix requires — founder
- [x] H16, H17, H19 — verified_clean for this batch, recorded where their class lives (registry
  row 131 / OI-193 / OI-184) — consolidating session

## Self-evolution (per skill §7)

- **2026-09-13 — batch `oi153-pro-media-caps` — lens set L1, L14, L21, L22, L23, L31, L35, L40
  (8 Opus agents) — 19 findings (1 P0, 2 P1, 16 P2), 0 false alarms, 3 PARTIAL — wall-clock
  ≈ 25 min — cost not metered (two diffs, 333 KB + 197 KB, read per agent; assume above the skill's
  8-lens estimate).** Signal-to-noise per lens: L23 3/3 · L31 4/4 · L22 2/2 · L21 1/1 · L40 3/3 ·
  L1 2/2 · L14 0/1 (partial) · L35 0/1 (partial) · cross-lens 1 real + 1 partial. **Lesson 1 — run L23 on ANY batch that
  redeploys a service-role function, even when the batch did not touch the guard:** the P0
  pre-dated the batch by four months and two B-passes; only a lens whose charter is "for each
  service-role path, try to reach another user's data" went looking. **Lesson 2 — a guard and its
  consumer must read the SAME representation:** the OI-28 fix checked the string the client sent
  while `fetch` used the parsed URL; the tell is a guard on a raw string feeding a call that
  parses. Added to the code-review skill's lens 6 as the representation mirror. **Lesson 3 —
  scope the pass to the deployed FUNCTION, not the diff:** the brief gave agents the diffs; L23
  found the P0 by reading the whole file. For a redeploy, hand the lens the full function.
