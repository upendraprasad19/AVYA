# Plan — OI-414: a metered call must not be re-sent after a gateway 502/503/504 (one tap = at most one spent unit)

**Version 3 (2026-10-25), after review round 2.** Round 1 = two context-blind Sonnet seats (A mechanism, B tests/gates/census) and one
read-only census agent over every Edge Function the client reaches through `callFunction`: 0 P1 on the fix, and the shared finding
that v1's "one OI for the other functions" was the §4.2 deferral shape. Round 2 = two fresh seats on the post-round-1 plan v2 (C
mechanism and tests: 0 P1, 6 P2 test-hardening; D governance and ledger: 1 P1 ledger row, 6 P2 bookkeeping). Every round-2 finding is folded
below; I re-read the code behind the two that changed ledger facts (food_text dedupe `ai-proxy/index.ts:385-393`; assess-body-composition
`index.ts:96-230`). **One design change after round 2:** the BOOT_ERROR carve-out for a 503 is REMOVED (never observed: 0 rows in
`client_errors` mention BOOT_ERROR; the repo holds only paraphrases), which strictly reduces the reviewed surface. Seat D disclosed one
command outside its allowed list (`git ls-remote --heads origin 'oi/*'`, read-only, changed nothing); it showed `oi/425..427` reserved on
origin, so new OIs are numbered above 427.
Branch and worktree `oi414-promo-no-gateway-retry`, from `origin/main` d1292a79 (`main` CI green on #171 and #172). Execution mode
(§4.12.7): **inline**, one worktree; review seats Sonnet only, at most 4 at once, read-only. Lenses (§4.8, `docs/audit/LENS_REGISTRY.md`): L1
writer/reader drift, L21 Edge Function semantic correctness, L29 endpoint rate-limit matrix, L36 idempotency replay completeness.
Fix tier (§4.12.6): **L**. RECURRENCE of c7e3b1 H1 (order endpoint), so the diagnose-doc takes the FULL template (§4.4 rule 22).
Blast-radius (`blast_radius_from_diff.dart` on positional paths, 2026-10-25): `supabase_service.dart` and `day_swap_allowance.dart` = account,
`paywall_sheet.dart` = feature, `docs/**` and `test/**` and `lib/features/nutrition/CLAUDE.md` = feature, `supabase/functions/CLAUDE.md` and
`docs/architecture/functions-detail.md` = **platform** (`docs/blast_radius.yaml:125`; the OI's own "done when" edits the first), so the PR is **platform**:
plan-review record with `bpass: accepted`. No catastrophic path, no hermes.
Commit 1 `fix(payments):` with `closes-diagnose: a6d2f9` (code, tests, docs, diagnose-doc, this plan). Commit 2 `docs(oi):` with
`closes-oi: OI-414` (board: OI-414 moved with a `**Status**: CLOSED` line, the minted OIs, the closure ledger).

## Founder decision (2026-10-25, this session)
Asked how far the batch goes, the founder chose "Promo + day-swap (Recommended)": the promo check (the OI) and the PRO day-swap call get the
protection now; the AI scan/cart/photo calls and the prediction card each get an OI carrying the exact question (they lose automatic
cold-start recovery); delete-account, weekly-report and the body-fat assessment get OIs for their own server-side defects. The full question
and answer text is copied verbatim into the ledger header. Rejected by that choice: promo only; promo plus all four adoptable calls.
Round 2 found `food_text_analysis` also belongs with the AI calls (below); it joins O1. That adds a row to an OI, it does not change the
batch, so the choice stands.

## The defect, with writers and readers named (§4.1)
- **Writer of the spend:** `supabase/functions/validate-promo/index.ts:88` calls `consume_quota` before the body is read (`:110`);
  `supabase/migrations/128_usage_counters.sql:95-100` counts every call that gets in below the limit. The function answers only 200, 401, 405
  and 500, so a 502/503/504 comes from the platform and can arrive after the handler ran. `consume-day-swap/index.ts:106` spends the same way
  (limit 1 free / 3 PRO per IST Mon-Sun week, `logic.ts:12-13`, window `:88-90`).
- **Amplifier (reader of the status):** `lib/core/services/supabase_service.dart` `retryColdStart` (`:507`), predicate `isColdStart`
  (`:527-529`), schedule `_coldStartBackoffsMs` 2 s, 6 s, 12 s (`:389`). `callFunction` (`:395`) forwards `retryOn500` only. One tap can
  invoke the function four times.
- **Callers:** `lib/shared/widgets/paywall_sheet.dart:216-217` (the ONLY `validate-promo` caller) and
  `lib/core/services/day_swap/day_swap_allowance.dart:118` (the ONLY `consume-day-swap` caller). The day-swap header (`:5-8`) already says
  "nothing retries — a retry after an ambiguous failure could double-count", yet `callFunction` re-sent it: a writer/reader drift instance
  for the diagnose-doc's `recurrence:`.
- **Effect:** promo, at 7 per fixed UTC-hour bucket (PR #168): two taps whose gateway error came after the handler ran can spend 7 units and
  lock the user out for up to 60 minutes. Day swap: one PRO swap can leave the week at 3 of 3.
- **Measured, read-only (`client_errors`, project `dedsavbjuwgarrhphgnl`, 2026-10-25):** the log spans 2026-09-25 to 2026-10-25 (7,142 rows);
  `edge_function_cold_start_retry` events: `ai-proxy` 502 x9 (one user, 2026-10-02), `log-client-error` 503 x4; none for `validate-promo` or
  `consume-day-swap`; rows mentioning BOOT_ERROR: 0. The event is LOW priority, dropped under a client cooldown
  (`error_telemetry.dart:394-398`) and fire-and-forget, so absence is evidence of rarity, not proof of never. NOT observed live.
- **Bug history (§4.1.5):** recurrence of c7e3b1 H1 (same class, order endpoint). The retry set comes from c01d57
  (`2026-05-15-ai-proxy-cold-start-budget-c01d57.md`, ai-proxy cold starts). `ai-media-proxy/index.ts:822-832` and
  `prediction_handler.ts:16-22` describe the same re-send hazard for the function's OWN 502 (not a gateway error after the handler); they
  support the O2/O3 OIs and are not prior statements of this mechanism.

## Design
One new optional parameter, default off, the mirror of `retryOn500`: `bool spendsQuotaPerCall = false` on `callFunction` and `retryColdStart`.
Meaning: this function spends a quota unit for every call that reaches its handler. When true, a **502, 503 or 504 is rethrown at once**
(a flagged call is never re-sent on a gateway status). `retryOn500` stays independent (an explicit 500 opt-in is respected); every other status
(400, 401, 403, 404, the storage-race 400) and `FunctionsFetchException` (status 0, the web CORS shape) are unchanged. Default false = the
old behaviour verbatim for every other caller; the old path is the omitted argument (§4.6, below).
**Deviation from the OI's wording ("the 503 boot-failure retry is unchanged"):** a BOOT_ERROR 503 means the handler never ran, so
re-sending it is free, but the repo has never observed the body (0 rows; prose only), so a carve-out keyed on `details['code']` would be
an unverified helper that fails silently into "never re-send". For these two functions the simple rule is chosen: no re-send on any
gateway status. Cost: a cold-start 503 on a promo APPLY shows "Network error. Try again."; the next tap is free. If a BOOT_ERROR body is ever observed,
a carve-out can be added with a real fixture.
**Where the code goes:** `isColdStart` (`:527-529`) stays byte-identical (three existing source pins read it). A SEPARATE early gate inside
the `on FunctionException catch (e)` block, before `if (isColdStart)`:

    if (spendsQuotaPerCall &&
        (e.status == 502 || e.status == 503 || e.status == 504)) {
      unawaited(ErrorTelemetry.logEvent('edge_function_no_retry_quota_call',
          message: 'fn=$functionName status=${e.status}'));
      rethrow;
    }

Short-circuit: with the flag false nothing after `&&` is read (seat C, reachability and default-false identity confirmed). The event exists
because `edge_function_cold_start_retry` fires only before a re-send, so a lockout from this class would otherwise be invisible; a new op_type
defaults to LOW priority server-side (`log-client-error/index.ts:148-151`), so no Edge Function change.
**Edit rules (existing pins):** do not run `dart format` on `supabase_service.dart`; keep `:528` byte-identical; no "retry" and no "401" in the
`///` doc between `/// Shortcut to invoke a Supabase Edge Function` and `callFunction(` (`retry_loop_guard_test.dart:46-56`): document the
parameter with `//` comments INSIDE the parameter list; no second `client.functions.invoke(` and no bare `e.status == 500` anywhere in the file
(`edge_function_503_retry_test.dart` reads the raw text, comments included). `callFunction` forwards `spendsQuotaPerCall: spendsQuotaPerCall`.
Call sites pass `true`: `paywall_sheet.dart:216-217` (a two-line comment naming OI-414) and `day_swap_allowance.dart:118`.
What the user sees: a thrown gateway error at the paywall shows the existing "Network error. Try again." (`:242-246`; `_promoValidating`
cleared, nothing stuck, the telemetry event is the only record); at the day swap `_consume` records `day_swap_allowance_consume` (non-fatal,
so one failure produces two events by design) and the phone copy stands.
**Rejected:** a client request id the function de-duplicates (server change plus a deploy); a global change (ai-proxy needs its cold-start
re-sends, `verify-payment` needs them to recover a paid user); a lazily read Hive kill switch (below).
**§4.6 reading, for the plan-review record and the B-pass to accept or reject explicitly:** payment is on §4.6's list and the platform tier
lists `feature_flag` (not mechanically enforced: `safe_push.sh:132-136` says so). The default-false parameter plus the per-call argument is the
gate: the old path is the omitted argument, reachable verbatim. It is a compile-time switch, so rolling it back needs a new build (revert the PR
or drop the argument). The direction is the safe one (less re-sending), the fault mode is a second tap, and the app is not live. If the B-pass
rejects this, the fallback is a lazily read Hive key `disable_no_gateway_resend` (pattern: `disableRefreshJoin`, `supabase_service.dart:296`)
which then owes a removal OI (§4.6 step 4) and a `docs/ship_dark_pending_review.yaml` line.

## Change set
Commit 1 (`fix(payments):`)
1. `supabase_service.dart` (parameter, gate, forward, `//` comments); `paywall_sheet.dart:216-217`; `day_swap_allowance.dart:118`.
2. Tests (below); diagnose-doc `docs/diagnoses/2026-10-25-promo-check-gateway-retry-a6d2f9.md` (FULL template; `touched_layers_checked`: tiers
   1 and 2 fixed/verified, 4/6/12 stated; `recurrence:` cites c7e3b1 H1 and the day-swap header; `related` note for the `day_swap_allowance`
   concept; says plainly that a gateway error costs 0 or 1 unit per tap and the user cannot tell which, so it NEVER claims "the handler did not
   run" or "a failed check costs nothing"; states the 503 deviation and the duplicate day-swap telemetry).
3. Docs: SoT registry (`promo_validate_rate_limit`: description and reader `line_range`; sibling key `behavioral_test_path_client_retry:
   test/contracts/edge_function_cold_start_retry_behavioral_test.dart` with an inline `#` comment saying it pins the client half of a
   server-gated concept; `day_swap_allowance`: description; no backticked symbol outside the cited range, `check_sot_registry_parity.dart:177-185`);
   `supabase/functions/CLAUDE.md` row 179 names the rule (keep "COMBINED with" / "20/day COMBINED", pinned by
   `vision_analysis_daily_cap_test.dart:93-107`); one clause in `docs/architecture/payment.md` rule 11; `docs/naming_conventions.md`
   (`spendsQuotaPerCall`, `edge_function_no_retry_quota_call`); the stale ai-proxy call-site line numbers (`supabase/functions/CLAUDE.md:145`,
   `lib/features/nutrition/CLAUDE.md:83`, `docs/architecture/functions-detail.md:143,152`) are replaced by the method names (no test or
   script reads those literals).
4. Review artifacts: this plan (committed, not untracked), `docs/plan-reviews/oi414-promo-no-gateway-retry.md` (states the §4.6 deviation and the
   503 deviation in words), the B-pass `docs/reviews/<hash>-review.md` with its dated `## Tuning entry` (`check_skill_tuning_history.dart`)
   which states acceptance or rejection of the §4.6 reading.
Commit 2 (`docs(oi):`, `closes-oi: OI-414`)
- OI-414 moves to `closed_issues.md` with `**Status**: CLOSED` (the load-bearing part: `check_closes_oi_cited.dart` fires only on an in-place flip,
  `check_closes_oi_performed.dart` reads the merged boards); the closing text says which halves are behavioural (below) and corrects the OI's
  "never a unit" to "at most one unit per tap".
- Seven new OIs, minted FIRST, with the founder's go (it pushes remote refs): run `sh scripts/mint_oi.sh` from THIS worktree, with network and an
  authenticated `gh`; each stub is a skeleton, so the seven bodies are written by hand; numbers are above 427 (`oi/427` is reserved on origin).
  O1 ai-proxy scan_meal + cart_auditor (one shared free budget of 4/day) + food_text_analysis (10/day free; dedupe covers only a still-pending row,
  `ai-proxy/index.ts:385-393`, so a re-send after completion spends a second unit); O2 ai-media-proxy + the web fallback loop `_retryHttpColdStart`
  in `ai_service.dart`; O3 ai-proxy prediction (3/day, never refunded, founder call); O4 delete-account (a re-send after the account is gone meets a
  401 that hides the first success); O5 weekly-report (consumes after generation; a re-send meets 403 NOT_PRO and the free user's only report
  becomes a paywall); O6 assess-body-composition: TWO facets, verified at `assess-body-composition/index.ts:105-115,185-230` — it authors its own
  502s (AI failed / unparseable / unrealistic values) before it stamps `last_bf_assessed_at`, so `callFunction` re-runs Gemini up to 4 times per tap
  (cost only, no quota; the c7e3b1 H1 fix class: answer 500), and after a lost success the stamp makes every replay a 429 for 30 days while only the
  timestamp, never the result, is stored; O7 the paywall's `_validatePromoCode` has no `mounted` check after its awaits (pre-existing, found by the
  B-pass; not caused by this change).
- `docs/audit/oi414-promo-no-gateway-retry.closure.yaml` with the real OI numbers (written after the mint, so no row cites an OI that does not
  exist); an OI-348 post-build line (promo APPLY valid and invalid, one day swap, on the build that carries this change).

## Tests (new behaviour; each mutated, §4.4 rule 21)
A new `group('OI-414 spendsQuotaPerCall')` in `test/contracts/edge_function_cold_start_retry_behavioral_test.dart` (mock invoker into
`retryColdStart`; events captured through `ErrorTelemetry.debugOnLogEventForTests`, set in `setUp` and nulled in `tearDown`, before any
`expect` that can fail). A compile error before the fix is NOT proof; the proofs are the mutants. Rows marked (control) pass with and without the fix.
- T1 flag, 502, `backoffsMs: const [60000, 60000, 60000]` under a 2 s `.timeout`: expect a `FunctionException` (a `TimeoutException` means the
  gate is missing or late), exactly one invocation recorded, and the event list EQUAL to `['edge_function_no_retry_quota_call:fn=test-fn status=502']`
  (no `edge_function_cold_start_retry`). Never an empty backoff list (it rethrows at attempt 1 even without the gate).
- T2 flag, 504: same, `status=504`. T3 flag, 503: same, `status=503` (a 503 is no longer re-sent).
- T5 (control) flag false, 504 then 200 -> two invocations; flag false, 503 with string details `'boot error'` -> re-sent (old behaviour verbatim).
- T6 flag + `retryOn500: true`, 500 then 200 -> re-sent. T7 (control) flag, 400 and 401 -> rethrown at once, no event.
- T7b flag, storage-race 400 (`{'error_type': 'storage'}`) then 200 -> still re-sent. T7c flag, `FunctionsFetchException` (status 0) -> once, no event.
- E2E (landed as its own file `test/contracts/call_function_spends_quota_per_call_behavioral_test.dart`, 2 tests incl. the unflagged control) end to end through the real `SupabaseService.callFunction`: a local `dart:io` HttpServer answering the functions path with 502 and counting
  requests, `SupabaseService.clientOverrideForTest` pointing a bare `SupabaseClient` at it with a session from `client.auth.setInitialSession(json)`
  (expiry > 5 min so `ensureFreshToken` does no network refresh); `callFunction('validate-promo', spendsQuotaPerCall: true)` -> request count 1 within a
  short `.timeout` (unforwarded it would take 20 s of real waits). This makes FORWARDING behavioural; the session helper proved reasonable.
- T8 (B-pass) a flagged call over EVERY status 100-599 with `retryOn500` false: one attempt each, a stop event only for 502/503/504 (a status added to
  the cold-start predicate, such as 520, cannot be re-sent on a flagged call unnoticed). T9 (B-pass) flag + `retryOn500: true` + 502: one attempt and the
  stop event (the two switches stay independent).
Source pins (presence only, said so in the test header), in the NEW file `test/contracts/spends_quota_per_call_source_pins_test.dart` (7 pins; the two
existing writer_to_reader files stay untouched): the declaration is anchored by slicing from
`Future<FunctionResponse> callFunction(` to its first `) async {` (same for `retryColdStart`) and asserting `bool spendsQuotaPerCall = false` in each
slice (a lazy cross-function regex lets a `callFunction` default of `true` survive); forwarding `spendsQuotaPerCall:\s*spendsQuotaPerCall`;
`unawaited\(\s*ErrorTelemetry\.logEvent\(\s*['"]edge_function_no_retry_quota_call`; `callFunctionAnonymous` does not mention the flag; for each of
`validate-promo` and `consume-day-swap`: scan only `lib/**/*.dart`, strip comments with `(?<!:)//`, whitespace-tolerant
`callFunction\(\s*['"]NAME['"]`, take the paren-matched argument list of each site, assert sites >= 1 and flagged sites == sites (v1's one-line
literal matched 0 sites, so 0 == 0).
Existing pins that stay green UNCHANGED: `edge_function_503_retry_test.dart`, `retry_loop_guard_test.dart`, `food_ai_telemetry_retry_test.dart`,
`edge_function_storage_race_retry_test.dart`, plus the whole `test/contracts/` directory.
Mutants (each confirmed APPLIED with `grep -c`, source restored with an equal sha256; the script computes before it writes):
M1 gate removed; M2 drops the 504 arm; M3 drops the 502 arm; M4 drops the 503 arm; M5 `callFunction` default true; M6 `retryColdStart` default true;
M7 `callFunction` does not forward; M8 forward swapped to `retryOn500: spendsQuotaPerCall`; M9 paywall drops the argument; M10 day swap drops the
argument; M11 gate placed after the backoff; M12 gate also suppresses the explicit 500 re-send; M13 telemetry removed; M14 telemetry message loses `fn=`;
M15 `unawaited` becomes `await`; M16 top-level `&&` becomes `||`; M17 flag ignored (gate fires for unflagged calls); M18 call-site pin counts a
commented-out flagged call; M19 the anonymous telemetry lane carries the flag; M20 a status (520) added to the `isColdStart` predicate only; M21 gate
also requires `!retryOn500`. (`rethrow` -> `throw e` is behaviourally equivalent and not claimed.) The script is session-local and not retained; the
diagnose-doc carries the table. The mutated set includes `edge_function_storage_race_retry_test.dart` (it exercises the same loop).

## Accepted properties (stated so no check is read as proving more)
- A1 A gateway error on a metered call costs 0 or 1 unit per tap and the user cannot tell which: the guarantee is "at most one unit per tap", not
  "a failed check costs nothing". The OI's "never a unit" is corrected in the closure text.
- A2 The OI's "done when" (a behavioural test that the promo call is not re-sent) is met by composition and the closing record says which halves are
  which: the re-send LOOP is behavioural (T1-T7c); FORWARDING from `callFunction` is behavioural if T9 lands, else source-pinned; the two call-site
  arguments are source-pinned only (a widget-level run needs the paywall provider tree; the day-swap behavioural file's `debugConsumeForTests` bypasses
  `_callServer`).
- A3 A cold-start 5xx on these two functions no longer re-sends by itself; the user taps again (promo) or the phone copy stands (swap).
- A4 Not observed live: a gateway error after the handler ran. It cannot be forced from a device, so there is no device row for it; the device check
  is only that APPLY and one day swap still behave on normal answers.
- A5 `callFunctionAnonymous` (telemetry lane) is untouched and pinned not to carry the flag. With the server kill switch `DISABLE_ORDER_ABUSE_GUARDS`
  on, `validate-promo` spends nothing but still loses the re-send (harmless).
- A6 The web direct-HTTP fallback in `ai_service.dart` has its own 502/503/504 loop; it serves only `ai-proxy`/`ai-media-proxy`, which this batch does not
  change (O2).
- A7 Day swap, under-count direction: every swap whose call fails without reaching the handler leaves the server one more behind the phone (one per failed
  call, not one in total); only another swap's reply (it spends a unit) overwrites the phone copy, downward (`DaySwapAllowance._consume`), so a PRO user can
  reach limit+N swaps in the week (N = failed calls that did not reach the handler), and a second device can swap past a free limit. Small and rare; it is
  the recoverable direction (`weekly-report/index.ts:724-728` makes the same choice), and a free user at 1/1 cannot swap again on this phone, so no reply
  arrives and the server simply stays behind.
- A8 `create-razorpay-order` is NOT flagged on purpose: 30 per fixed hour, a re-send yields at worst a second unpaid order (no charge), and the re-send
  recovers a cold start at the moment of payment. The flagged set today is `validate-promo` and `consume-day-swap`; every other per-call-spending call is
  classified in the closure ledger, and the docs say so rather than imply a general rule.

## Closure ledger (§4.2): every census row has a terminal state
`docs/audit/oi414-promo-no-gateway-retry.closure.yaml` (every key indented: the Gate 40 parser stops at any column-0 key; `closed_count:` = ALL entries,
`blocked_on_user` included, 20: 3 closed_in_commit (the two calls and the B-pass), 10 verified_clean, 7 blocked_on_user). The header quotes the founder's question and answer verbatim. The `verified_clean` evidence is a census reading,
self-attested, not a proof; the B-pass re-reads it. Entries:
- `closed_in_commit` (3): validate-promo; consume-day-swap; the B-pass row.
- `verified_clean` (10, `evidence:` per row): create-razorpay-order (30 per fixed hour; own refusals answer 500 with the guards on; a replay yields a
  second unpaid order, no charge); verify-payment (20 per 10 min; replay idempotent; the re-send is REQUIRED to recover a paid user; 16 worst-case units
  < 20); daily-snapshot (`coach_extraction` 1 per 6 h; upsert idempotent; re-send wanted, H3); ai-proxy chat (30 s dedupe replays a delivered reply +
  refund; holds for fast-failing shapes, a very slow attempt can land outside the window); redeem-referral (idempotent, no units); restore-user-snapshot,
  verify-subscription, get-community-review-items, admin-dashboard-data (read-only); log-client-error (no quota unit; a 2000 per 24 h per-user row budget).
- `blocked_on_user` (7 entries: 6 OIs plus the post-build phone check; each `reason:` names the specific user action): scan_meal, cart_auditor, food_text_analysis -> O1; ai-media-proxy -> O2;
  prediction -> O3 (the founder's call: cold-start recovery vs units lost; the Edge Function-free client change is ready to apply on a yes);
  delete-account -> O4; weekly-report -> O5; assess-body-composition -> O6 (O4-O6: each is a separate Edge Function defect with its own server-side fix;
  the user-only step is the founder's Edge Function deploy go (§4.3), plus for O6 the choice of what to store; filing the OI is agent work and is done).
  O7 (paywall `mounted` check) is an OI, not a ledger row: it is not a census entry.

## Verification, merge, rollout
Local before review: whole-project `flutter analyze --no-fatal-infos`; `TZ=Asia/Kolkata flutter test --exclude-tags golden` (the report says WHICH suite
ran); `PRE_COMMIT_GATE_JOBS=1 sh scripts/pre-commit.sh`; no Deno change. Plan-review record: `review_rounds: 2`, `ground_truth_verified: true`,
`verdict: converged`, `bpass: accepted` with the cited review file (a `verdict: accepted` line in it); it states the single post-round-2 design change
(the BOOT_ERROR carve-out removed). Rollout: **no live step** (no migration, no Edge Function deploy). Reaches testers with the founder's next
`/build-apk` from CI-green `main`. Rollback: revert the PR, or drop the argument at the two call sites.

## Out of scope (stated)
An idempotent per-tap spend; any `validate-promo` or `consume-day-swap` source change; changing the retry set or schedule for any other caller; the seven
filed OIs; OI-410 (a separate catastrophic-tier unit, next).
