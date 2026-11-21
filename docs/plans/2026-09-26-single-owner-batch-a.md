# Batch (a) — server money / security (single-owner remediation, P0 #4 #5 #6 + same-class findings)

Base `9939750b` (= origin/main). Source audit: `docs/audit/2026-09-26-single-owner-audit-pass2.md`
(branch `claude/login-email-spam-issue-a19jt4`, 82473d9). Founder approved the remediation plan 2026-09-26
("proceed"); prediction cap = recommended 3/day.
**Revision 3 — SPLIT (§4.12.1).** Review round 2 (verdict needs-changes) raised 7 material findings, 6 of them
NEW and all introduced by Revision 2's refund mechanism (A0/A6) and the two units added in round 1 (A4, A5).
Successive rounds surfacing new material issues is the §4.12.1 signal: ship the smallest converged piece.

| Piece | Branch / worktree | Units | Review state |
|---|---|---|---|
| **a1** | `single-owner-a` (this worktree) | A2 prediction + input limits, A3 delete-account buckets | converged — round 2's findings on these units were all mechanical (F8 mirror scope, F9 ledger scan, anchors); `mechanical_only: true`. B-pass c5d659f52986: 7 findings, all accepted and fixed (see "a1 B-pass dispositions") |
| **a2** | `single-owner-a2` | A4 daily-snapshot extraction meter (Revision 4, after round 3) | round 4: needs-changes, 3 material findings all in the read window → SPLIT per §4.12.1 (see "Round-4 disposition") |
| **a3** | `single-owner-a3` | A0 refund (redesigned per F1/F2/F7/F8/F10), A1 vision per-channel caps, A5 body-composition, A6 food_text, client 429/422 mapping | re-planned after a1 merges, then ×2 review |
| **a4** | `single-owner-a4` | Deleted-user Storage sweep (Hermes a1 L23-F1 + the L37-F1 residual), which also removes the 12 existing orphans | APPROVED by the founder 2026-09-26 ("Approve a4, sweep the 12": the orphans wait for the sweep). Next: ×2 plan review + Hermes (catastrophic: deletes Storage objects); its deploy needs its own go |

Order: a1 → a2 → a3, each merged before the next starts implementing (a3 edits ai-proxy, which a1 also edits).
Execution mode (§4.12.7): **inline**, per piece. Every live step (DDL on prod incl. rollback-wrapped probes,
migration apply, EF deploy, data cleanup) needs its OWN explicit founder go.

---

# a1 — prediction quota + input limits + delete-account buckets

**Blast radius: CATASTROPHIC** (`docs/blast_radius.yaml:43` pins `supabase/functions/delete-account/**`) → B-pass +
**Hermes pass** (lens agents in waves of ≤4) before merge. No migration in a1.

## Unit A2 — ai-proxy input limits + `prediction` path (P0 #5)
Ground truth: prediction branch `ai-proxy/index.ts:700-757` honours `context.system_prompt` (`:716-720`), has no
length limit (chat's checks at `:757-762` come after it), no cap, no tier check. Callers: `ai_service.dart:383`
`predict()` → `SupabaseService.callFunction` → `retryColdStart` (auto-retries 502/503/504, and 500 only with
`retryOn500`, which `predict()` does not set) ← `prediction_service.dart:52-55` (3 `regeneratePrediction` call
sites incl. the PRO 30-day auto-refresh `ai_coach_provider.dart:1407`) and `onboarding_provider.dart:797-800`;
both send the server-default prompt; both catch. Prediction `message` is ~700 chars (built at
`prediction_service.dart:42-50`). No test calls prediction live (`test/edge_functions/ai_proxy_test.dart` has none).
Current senders verified in round 1: chat snapshot ≤9500, prediction `{system_prompt}` only, food_text `text` only,
vision neither → a shared up-front validator changes no current behaviour.
- `_shared/ai_proxy_input_limits.ts` — pure `validateAiProxyInput(body)`: `message` ≤5000, `text` ≤5000,
  `snapshot_json` ≤10000, SAME error strings as today; called once before the first `if (type ===`. Per-branch
  duplicates of these three removed; the vision image check stays in its block.
- `_shared/prediction_handler.ts` — `handlePrediction({userId, message}, deps)` with injected `consume` +
  `geminiChat` (behaviourally testable). Owns `PREDICTION_SYSTEM_PROMPT` (today's default, verbatim; the caller's
  prompt is IGNORED), `PREDICTION_QUOTA_KEY = "prediction_daily"` (not bare `prediction` — §4.7 glossary collision
  with "prediction card", `naming_conventions.md:282`; glossary entry appended), `PREDICTION_DAILY_CAP = 3`, and
  `consumePredictionQuota(supabase, userId)`, the ONE `consume_quota` call, written as
  `const windowStart = istDayStartIso();` + `{ p_user_id, p_quota_key: PREDICTION_QUOTA_KEY, p_window_start:
  windowStart, p_limit: PREDICTION_DAILY_CAP }` (key / window / limit order, so the digest mirror resolves it).
  The RPC name is exported as `CONSUME_QUOTA_RPC` so the handler's test fakes never contain the literal (the ledger
  test scans every `.ts`, test files included).
- **What the cap counts: attempts, not results — decided, no refund.** Order: validate message → consume
  (RPC error or non-number → **500** fail-closed; `-1` → **429**) → `geminiChat(… retries: 2)` unchanged → empty →
  `reportGeminiExhaustion(…, "prediction")` + **500** "AI temporarily unavailable" (was 502) → 200 shape unchanged.
  Why 500 and not 502: a 502 is auto-retried by `retryColdStart` three more times, and each retry would consume a
  unit — one Gemini outage would spend the whole day's cap in one tap. The EF already retries Gemini itself
  (`retries: 2`); the client's retries exist for gateway cold starts, which happen BEFORE the handler runs and so
  never consume. With 500, a failure costs exactly one of the 3 daily attempts. No refund path is needed, so a1
  creates no new RPC and no migration.
- ai-proxy keeps the `if (type === "prediction") {` line as a thin delegation.
- Client: drop the dead `system_prompt` from both context maps (`prediction_service.dart:52-55`,
  `onboarding_provider.dart:797-800`); update doc comments `ai_service.dart:377-382` ("bypasses daily limits" is
  now false) and `onboarding_provider.dart:801-802`. Old app versions still send it; the server ignores it.

## Unit A3 — delete-account purges every user-owned bucket (P0 #6)
Ground truth: `delete-account/index.ts:398` purges 3 buckets; the client writes 5 (`profile_provider.dart:119,197`;
`coach_media_repository.dart:27-28`; `progress_photo_repository.dart:40` `_bucket`; `media_picker.dart:232`);
exactly those 5 buckets exist live; avatars/banners hold 7 objects each, 6 orphaned, all public.
- `_shared/user_owned_buckets.ts` `USER_OWNED_BUCKETS` (the 5) + `_shared/purge_user_storage.ts`
  `purgeUserStorage(storage, userId, buckets)` (the existing recursive list + chunked remove, extracted verbatim);
  delete-account calls it.
- `docs/architecture/payment.md:55` (says 3 buckets) updated.
- Orphan cleanup (12 objects under deleted users' folders): Storage dashboard (founder, from a path list) or a
  service-role one-shot — founder picks; **explicit go**. Never SQL on `storage.objects`.

## a1 dependents (value-semantics sweep §4.1.5.6)
- `_shared/founder_digest_content.ts:65-80` DIGEST_KEYS: add `{ key: "prediction_daily", label: "Prediction",
  kind: "daily", cap: 3 }` → **founder-digest AND telegram-admin-bot redeploys** (both import `buildDigestText`,
  `telegram-admin-bot/index.ts:20,594`).
- `test/contracts/founder_digest_caps_mirror_test.dart`: `_efSites` (`:120-163`) scans `<fn>/index.ts` only →
  also scan `_shared/*.ts` excluding `*_test.ts` (same resolver); pinned literals (`:308-318`) gain
  `prediction_daily` = 3; the ai-media-proxy positive-control stays.
- `test/contracts/usage_quota_ledger_writer_to_reader_test.dart:243-258`: allowlist gains
  `supabase/functions/_shared/prediction_handler.ts` with its reason (a prediction is an HTTP attempt with no row
  for a trigger to hang off — the weekly-report shape).
- `supabase/functions/_shared/gemini_backoff_retry_test.ts`: the prediction `retries: 2` pin (`:235-259` family)
  and the OI-226 exhaustion test (`:345-379`) are REPOINTED to `_shared/prediction_handler.ts`; the exhaustion
  test's `return err(502, …)` anchor becomes the handler's 500 return (same assertions: `lastError` destructured,
  report BEFORE the return, endpoint `"prediction"`).
- Prose: `ai-proxy/index.ts:15-17,697-699`, `supabase/functions/CLAUDE.md` prediction lines,
  `docs/architecture/payment.md:55`, `docs/naming_conventions.md` glossary.
- SoT registry: UPDATE `usage_quota_ledger` (`docs/sot_registry.yaml:~11442`) with the `prediction_daily` key and
  its consume site; add `ai_proxy_input_limits` and `user_owned_storage_buckets` (names satisfy Gate 9's
  `<concept>_writer_to_reader_test.dart` rule where it applies). New entries written as VALID YAML.

## a1 tests (rule 21 — every new test mutated once; confirm the mutation applied; red must be an assertion, not a
compile error; a zero-red mutation is investigated, not accepted)
- Deno `_shared/ai_proxy_input_limits_test.ts` (pure: each limit at N and N+1, same strings) + WIRING test: in
  `ai-proxy/index.ts` the validator call precedes the first `if (type ===` and the prediction branch delegates to
  `handlePrediction` (mutation: delete the call → red).
- Deno `_shared/prediction_handler_test.ts` (fakes): `-1` → 429, Gemini not called; consume error → 500, Gemini not
  called; non-number → 500; caller `system_prompt` ignored (fake Gemini sees PREDICTION_SYSTEM_PROMPT); Gemini
  empty → report called with `"prediction"` + 500 (NOT 502); happy path → 200 shape; consume called exactly once
  and before Gemini; `consumePredictionQuota` passes key / IST-day window / limit 3 to `CONSUME_QUOTA_RPC`.
  Mutations: remove consume (→ red), fail-open on RPC error (→ red), pass the caller prompt (→ red), return 502
  on empty (→ red).
- Deno `_shared/purge_user_storage_test.ts` (fake storage): every USER_OWNED_BUCKETS entry listed + removed,
  nested paths included (mutation: skip one bucket → red).
- Dart `test/contracts/delete_account_purges_all_user_buckets_test.dart`: discovered client buckets (forms
  `storage.from('x')`, `bucket: 'x'`, `[_a-zA-Z]*[bB]ucket = 'x'`) ⊆ USER_OWNED_BUCKETS; positive control =
  exactly the 5 live buckets; delete-account wires `purgeUserStorage(…, USER_OWNED_BUCKETS)`.
- `deno check --node-modules-dir=none` on ai-proxy, delete-account, founder-digest, telegram-admin-bot;
  `deno test --node-modules-dir=none --allow-all supabase/functions/_shared/`.

## a1 process
- Diagnose-docs (rule 22), validated: prediction unmetered + caller-controlled system prompt (A2); delete-account
  bucket gap (A3).
- Full gate loop before the B-pass; B-pass; Hermes (≤4 agents per wave); founder go for commit/merge; then founder
  go per live step: EF deploys ai-proxy, delete-account, founder-digest, telegram-admin-bot — **blocked on a fresh
  Management API token** (the repo token returns 401) — with ai-proxy preceded by a deployed-v87-vs-git diff
  (commit 0dcab614 is newer than v87); then the orphan cleanup.
- Post-deploy: real-user-token smoke of prediction (prompt ignored); a 4th call in one IST day returns 429.
- Rollback: SHA-pinned previous EF versions (no schema change in a1).

---

# a2 — daily-snapshot: meter the Gemini extraction (Revision 4, after review round 3)

Round 3 (verdict needs-changes, 4 material) found: no specified test seam; nothing testing the bound itself; a
channel-blind early return plus a whole-day read that would make a one-unit meter DROP later chats; and rule 18
reinterpreted instead of applied. All folded in below.

Ground truth (verified by rounds 2 and 3): the 6 h guard (`daily-snapshot/index.ts:431-440`) reads
`coach_memory.last_extraction_at`, written only by `mergeCoachMemoryFields` when a coach-memory field was extracted
and private mode is off (`:276`, `:286-290`) — so an empty extraction (the normal case), a Gemini failure or a parse
failure never stamps it, and Gemini Flash runs on every `pushSnapshot` that finds ANY same-day
`ai_coach_interactions` row. That query has no channel filter (`:62-69`): live 60 days, chat rows are
`in_app_orphan` 67 + `app` 15, while `app_event` (52), `in_app`, `promotion_ceremony`, `food_text_analysis`,
`scan_meal`, `weekly_report` also trigger it. 30 of 36 `last_extraction_at` values are null. `extractCoachingNotes`
has one caller (`:442`); no return sits between `:71` and the Gemini call (`:148`); the client is service-role
(`:326`). Nothing displays `last_extraction_at` (only `coach_memory.dart:125` parses it).

- **Test seam.** `serve(` moves under `if (import.meta.main)` (the ai-media-proxy / founder-digest shape, deployed
  in prod). `extractCoachingNotes` is exported with an injectable last parameter
  `{ geminiChat = realGeminiChat, consume = consumeExtractionQuota, now = Date.now } = {}` — destructured under the
  SAME name, so the call stays `await geminiChat({` and the OI-238 anchors hold.
- **The meter (one owner).** Exported `consumeExtractionQuota(supabase, userId, nowMs)` holds the ONE
  `supabase.rpc("consume_quota", {...})` call — the literal stays in `index.ts` code, and the three consts plus the
  rpc object sit in that file in key / window / limit order (digest mirror + ledger test). `EXTRACTION_QUOTA_KEY =
  "coach_extraction"`, `EXTRACTION_CAP = 1`, `EXTRACTION_WINDOW_MS = 6 h`, buckets **IST-aligned**:
  `bucketStartMs = Math.floor((nowMs + IST_OFFSET_MS) / W) * W - IST_OFFSET_MS` → 00:00 / 06:00 / 12:00 / 18:00 IST,
  so exactly **≤4 extraction units per user per IST day** and the digest attributes each to the right day. Each unit
  can cost up to 6 Gemini HTTP calls (`retries: 2` × Flash→Lite) — stated, not hidden.
- **No lost chats.** Order inside `extractCoachingNotes`: private mode on → return (no read, no consume, no Gemini;
  closes round 3 #9: `mergeCoachingNotes` and the embedding ignored private mode — latent, 0 rows, no writer sets
  it) → read chat channels only (`app`, `chat`, `in_app_orphan`, mirroring
  `CoachInteractionRepository.coachChatChannels`, `coach_interaction_repository.dart:315`) with
  `created_at >= bucketStart − EXTRACTION_WINDOW_MS` (the previous bucket AND this one — a chat after a bucket's
  spend is read by the next bucket, across midnight too), newest 30 turns then re-ordered oldest-first → none →
  return without consuming → consume (RPC error or non-number → skip, fail closed, one log line; `-1` → skip) →
  Gemini. Re-reading an overlapping turn is harmless: extracted facts overwrite the same keys.
- The `isStale` guard (`:431-440`) is removed; the serve handler still fetches coach memory, now only to pass
  `private_mode`. `last_extraction_at` keeps being written where it is; its comment stops calling it a guard.
- **Kill switch** (platform tier needs a `feature_flag`, `docs/blast_radius.yaml:25,58,61`):
  `DISABLE_COACH_EXTRACTION=true` skips extraction entirely — no read, no consume, no Gemini.
- **Rule 18 (founder decision, asked 2026-09-26).** The stored `snapshot_json` reaches no model (round 3 verified
  every EF and `_shared` module), but it is otherwise unbounded and re-read in batch. Live: stored max 10,844 B, p95
  9,031, 3 of 238 over 10,000. Recommended: request `snapshot_json` > **64 KiB** serialised → **413**; the literal
  10K would reject real pushes. Either way `docs/sot_registry.yaml:~843` ("server limit 10K") is corrected.
- Dependents: DIGEST_KEYS gains `{ key: "coach_extraction", label: "Coach extraction", kind: "subday" }` (capless —
  the mirror requires it) and its "ten sections / 7 of 10" comment → "eleven / 7 of 11"; ledger allowlist gains
  `daily-snapshot/index.ts` and pins `"coach_extraction"` like slice 4's keys; `daily-snapshot/index_test.ts`
  header `:3-9` and anchors `:94/:108/:130` re-checked; `supabase/functions/CLAUDE.md:127` and `:194` (testing note
  says daily-snapshot boots `serve` at import); `docs/architecture/ai.md:87,182-185`; `docs/architecture/sync.md:93`;
  `index.ts` comments `:162-163,:429-431`; SoT `usage_quota_ledger` (new reader) and `coaching_notes`
  (`sot_registry.yaml:~5030`, add the EF writer). Deploy order: founder-digest + telegram-admin-bot BEFORE
  daily-snapshot, or the digest prints "⚠ unlisted keys".
- Tests (Deno, no file spells `consume_quota`): `consumeExtractionQuota` with a fake rpc — key, `p_limit` 1, and
  `p_window_start` at `nowMs` either side of the 06:00 IST boundary; `extractCoachingNotes` with fakes — private mode
  → nothing called; only non-chat rows → no consume; `-1` / RPC error / `data: null` → no Gemini; happy path →
  consume once, before Gemini; the read filters chat channels and the two-bucket window; kill switch honoured.
  Mutations: cap 1→50, window 6 h→60 s, UTC-floor instead of IST, consume above the chat-rows return, fail-open,
  channel filter dropped, window back to the whole IST day.
- Process: diagnose-doc (full template — recurrence of the OI-162 unmetered-Gemini class); blast radius measured
  on the written diff; gate loop; review round 4 on this section; B-pass; founder go; deploys blocked on the token.

---

# a3 — AI-quota refunds, vision per-channel caps, body-composition, food_text (re-planned after a1 merges)

Scope carried from Revisions 1–2, to be re-planned from current code and reviewed ×2 before any code:
- **A1** vision quota per channel by tier (P0 #4): `vision_scan_meal` PRO 10 / free 3, `vision_cart_auditor`
  PRO 10 / free 1; guard-first; `ELSIF` + `ELSE RAISE`; client 429 → limit copy + local counter set to the limit.
- **A0** refund of Gemini-unavailable failures, redesigned for round 2:
  F1 — release only when THIS request consumed (`consumedHere`; food_text dedup reuses a pending row and never
  consumed); F2 — refund only on provider-side failure (Gemini 429/5xx/network/timeout), never on a
  request-induced one (4xx, safety block, empty text) — needs a failure `kind` on `GeminiResult`
  (`_shared/gemini.ts:292-372`; `geminiChatWithTools` already classifies at `:708-710`); F7 — migration split:
  144a `release_quota` first, 144b cap switch only after the ai-proxy that calls it is live; rollback restores
  bodies before dropping anything, release calls best-effort; F8 — the digest mirror must accept a
  `release_quota` call (no `p_limit`); F10 — capture the window once before the insert and reuse it,
  schema-qualified `search_path`, reject lifetime / rate-limit keys, state where A5's consume sits.
- **A5** assess-body-composition: `body_composition_attempt` 3/day, image cap, parse / unrealistic outcomes → 422
  (F3), and the client unit that makes the status codes reachable (F4: `user_repository.dart:939-950` dead branch,
  `edit_profile_screen.dart:1697/1742`).
- **A6** food_text: refund / 422 per the A0 rules.
- **Hermes a1 L29-F1 (pre-existing, confirms round-1 F1 for the nutrition sites):** food_text, scan_meal and
  cart_auditor return **502** on Gemini failure and on invalid JSON (`ai-proxy/index.ts` — grep
  `err(502, "Food analysis`, `"Image analysis`, `"Cart analysis`; six sites). `retryColdStart` retries a 502
  three times, and food_text also retries a 500 (`nutrition_provider.dart` `retryOn500: true`), so one tap can
  spend up to 4 units. A0's design must cover all six sites — a non-retried status, a refund of what THIS
  request consumed, or both — with a test that a retried failure spends at most one unit. (The chat path's
  502 is covered in a1: e5c9d2 makes the retry replay the failure without a new reservation.)
- F9 dependents: `ai_proxy_placeholder_resolution_test.dart:52-99` (keep "Food analysis returned invalid JSON"),
  ledger test scan of Deno fakes, `gemini_backoff_retry_test.ts` sole-call-site pins for daily-snapshot and
  assess-body-composition plus their `index_test.ts`, `docs/architecture/ai.md:149-151`, and the digest's
  "unlisted keys: vision_analysis" line on the day after the key switch.

---

# a4 — deleted-user Storage sweep (NEW, from the a1 Hermes pass; founder-approved 2026-09-26)

Why: delete-account purges `<userId>/` in the five `USER_OWNED_BUCKETS`, but two things escape it and nothing
catches them — (1) a failed list/remove (recorded only in `account_deletion_log.storage_purge_status`, which
nothing reads; a1 now keeps what was listed, L37-F1), and (2) an upload made AFTER the purge with the user's
still-valid access token (up to its expiry, ~1 h) into the PUBLIC `avatars`/`banners` buckets (L23-F1).
`clean-orphan-media` sweeps only chat-media, by age. The 12 live orphans (6 avatars + 6 banners of users
deleted 17–29 Apr) are the same class.
Shape to plan and review (not yet reviewed): a cron-dispatched sweep over each bucket in `USER_OWNED_BUCKETS`
that lists top-level `<uid>/` folders, keeps those whose uid exists in `auth.users`, and purges the rest through
the same `purgeUserStorage`, with a grace window after `account_deletion_log.deleted_at` long enough to outlive
the token; `_shared/cron_telemetry.ts` (§4.5), CRON_REGISTRY row, bounded reads (paged), dry-run first, kill
switch, alert on errors. Catastrophic tier: ×2 plan review, B-pass, Hermes, and a per-action deploy go.
Founder decision (2026-09-26): a4 approved; the 12 orphans wait for the sweep rather than a manual dashboard
cleanup.

---

## a1 Hermes dispositions (docs/audit/2026-09-26-hermes-single-owner-a1.md — 5 lenses, 15 findings, 12 distinct)
Fixed in a1: L1-F1 stale PRO dead end (`refreshEnabled`) · L1-F3 / L29-F4 / L21 automatic refreshes spend the
cap (`PredictionAttemptGate`) · L1-F2 digest "none" under the kill switch (UNMETERED) · L37-F3 any 429 read as
the cap (`RATE_LIMITED`) · L37-F2 snapshot measured before sanitising · L37-F1 purge discards listed paths on a
failed list · L29-F3 chat dedup replays the failure marker (e5c9d2) · L21-F1 unused import · L29-F5 stale
migration/cap citations. Routed: L29-F1 → a3 (above) · L23-F1 → a4 (above, blocked on founder approval).
Verified clean: L21-F2 (validator error strings — no app client sends the shapes that read oddly).

## Round-1 disposition (Revision 2)
F1 retry amplification → a1: prediction failure is a non-retried 500 (no refund); a3: A0 redesign · F2 → a2 ·
F3 → a3 (A5) · F4 → a1 dependents (digest `_efSites`, ledger allowlist) · F5 → anchors repointed · F6 → dependents
completed per piece · F7 → catastrophic stated, Hermes (a1) · F8 → registry entries valid YAML; first-ready merges,
the other rebases · F9 → wiring tests + purge extraction + bucket positive control · F10 → a3 · F11 → validate
before consume (a1); guard-first, ELSIF+RAISE (a3) · F12 → key renamed `prediction_daily`; lines corrected.

## a1 B-pass round 2 dispositions (0d1abba92408, 2 context-blind reviewers over the Hermes remediation delta, 2 findings, 0 false alarms)
F1 P1 (client) — `PredictionService` was the one singleton in its family never registered with `SingletonLifecycleRegistry`; the new gate's join semantics let a post-switch account's own tap join the OLD account's stale future and, worse, the original call's own write resolves the CURRENT (new) userBox at write time regardless of joining → `_regenerate` captures `HiveUserSession.currentOwnerFullId` before `predict()` and refuses to write if it changed (`PredictionService.safeToWriteForTest`, pure, tested); `PredictionService` now registers with `SingletonLifecycleRegistry` and clears the gate's in-flight future on account change (`PredictionAttemptGate.clearInFlightForAccountChange`). Real behavioral test against `SingletonLifecycleRegistry.registeredNames()` + a real `HiveUserSession.openForUser` cycle, plus the isolated-harness join test against the real gate class.
F2 P2 (server) — the client's own snapshot budget (`_maxSnapshotBytes = 9500`) measured plain `json.encode(...).length`, while the server's cap (this same batch's L37-F2 fix) now measures the length AFTER `sanitizeJsonForPrompt`, which turns each raw U+2028/U+2029/U+0085 into 6 characters. A snapshot near the client ceiling carrying ~100+ of those rare characters could pass the client and be rejected server-side → `AiService._compactContext`'s `size()` now measures the same sanitised length (`_sanitizedLength`, ported as a length-delta, not a full port of the TS function). Both margins of the regression test's fixture were computed with a probe script, not guessed.
Mutation proofs: see 125b81's "B-pass round 2 remediation" section.

## a1 B-pass dispositions (c5d659f52986, 2 context-blind reviewers, 7 findings, 0 false alarms)
F1 P1 client collapsed the 429 into a generic failure (`invoke` throws on non-2xx) → `predict()` keeps status + server text, `PredictionRefreshOutcome`, Profile daily-limit message, PRO goal-change regenerate marks stale · F2 P1 prompt test never attempted the attack → hostile `context.system_prompt` test + `{ message }` argument pin · F3 P1 bucket discovery keyed on const names → resolve by value, fail closed, one enumerated pass-through · F4 P1 no kill switch → `DISABLE_PREDICTION_QUOTA` (ledger only); delete-account deviation recorded in 40054f · F5 P2 mirror scan non-recursive → recursive over the functions tree · F6 P3 125b81 tier → `platform` · F7 P3 stale "bypasses daily limits" comment. Mutation proofs in 125b81 / 40054f.

## Round-4 disposition (a2) — split per §4.12.1
Round 4 (context-blind, needs-changes) found 3 material defects, all in how the extraction READS chat turns: the two-bucket window drops chats written after a bucket's spend when no push follows (live: 52 of 85 chat turns in 60 days are not first in their bucket); the chat allowlist drops free-tier photo chats (`free_image_analysis`); re-reading an overlapping turn is not harmless (a new `memory_embeddings` row per extraction, and profile fields re-applied over later edits). It verified the rest: IST 6-hour buckets, ≤4/day, EXECUTE grants, `import.meta.main` safety, digest/mirror/ledger shape, retry pins, deploy order. Fourth consecutive round with new material findings ⇒ split:
- **a2a** (converged in round 4): `import.meta.main` seam + injected `geminiChat`, kill switch `DISABLE_COACH_EXTRACTION` (read per call), private-mode skip before any read (read error stated as failing open, latent: 0 rows), dependents (#7: the three "same shape" test headers, `sot_registry.yaml` guard note, `user_preferences.coaching_notes` as its own concept). No change to what is read or metered.
- **a2b** (own ×2 review): watermark read (`coach_memory.last_extraction_at`, newer-than-mark, oldest-first, `.limit(30)`, 48 h floor, advanced only after a non-null Gemini result), consume only when a turn exists, daily-snapshot's own chat allowlist incl. `free_image_analysis` and non-empty `user_message`, `coach_extraction` meter with `CONSUME_QUOTA_RPC` pinned, exact-value window tests, rule-18 size bound (founder decision: 64 KiB/413 vs literal 10K; the 413 path must not strand `pushSnapshotNow`).

## Round-3 disposition (a2, Revision 4)
#1 seam → import.meta.main + injected `geminiChat` · #2 bound untested → `consumeExtractionQuota` + fake-rpc tests · #3 lost chats → chat-channel filter + two-bucket read · #4 rule 18 → founder decision, 64 KiB/413 recommended · #5 kill switch · #6 IST-aligned buckets, ≤4/day · #7/#8 dependents + ledger/mirror shape · #9 private mode → skip before consume; display-stamp wording fixed.

## Round-2 disposition (Revision 3)
F1, F2, F7, F10 (refund mechanism) → a3 redesign · F3, F4 (A5) → a3 · F5, F6 (A4) → a2 redesign · F8 → a1
(mirror scans `_shared/`; no release call in a1) and a3 (release shape) · F9 → split per piece: ledger scan of
test fakes → a1 (`CONSUME_QUOTA_RPC` const); the rest → a2 / a3 as listed.
