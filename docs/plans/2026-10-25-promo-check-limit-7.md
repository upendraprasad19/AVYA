# Plan — validate-promo check limit 20 → 7 per fixed UTC-hour bucket (OI-366 follow-on)

**Version 3 (2026-10-25), after review round 2.** Round 1 (two context-blind seats, 0 P1, 10 P2) and round 2 (two
seats on the post-round-1 plan, 0 P1, 11 P2) changed no design decision; every P2 was a test-hardening or rollout /
bookkeeping detail and is folded below. Branch and worktree `promo-limit-7`, from `origin/main` 25fb8a7f. Execution mode
(§4.12.7): **inline**, one worktree, two commits in one PR (code + number docs; board bookkeeping). The bookkeeping stays
in the same PR on purpose: it edits the OI-348 rows next to the B6 wording this change also edits, and two PRs touching
adjacent lines of `open_issues.md` would conflict.
Fix tier (§4.12.6): **L** (an Edge Function on the payment path): ×2 plan review, plan-review record, B-pass.
Blast-radius tier (`docs/blast_radius.yaml`, first match wins): `supabase/functions/validate-promo/**` is **account**
(`:409`); `supabase/functions/_shared/**` is **platform** (`:106`, reached by the digest comment edit);
`supabase/functions/CLAUDE.md` falls to the `supabase/functions/**` catch-all, **platform** (`:593`; the `CLAUDE.md`
glob at `:118` is root-only); `docs/**` and `test/**` are feature. Max = platform, no catastrophic path (the content
rule reads only `.sql` migrations), so no hermes. The tier is computed at merge over the whole PR (`sha^1..sha`) under
the base and HEAD registries; it is re-measured with `blast_radius_from_diff.dart` on the positional path set of the
real diff and written into the record. Drop either platform path and the tier is account (record still needs rounds >= 2
and converged, no bpass); the B-pass is run either way.
Commit 1 type: **`feat(payments):`** (a founder policy change, not a bug): no diagnose-doc, no `closes-diagnose:`, no
`closes-oi:`. Commit 2 (`docs(oi):`) carries `closes-oi: OI-406`. §4.6 (feature-flag protocol for payment changes): no new
code path is added; the value is one constant; the existing `DISABLE_ORDER_ABUSE_GUARDS` switch gates the whole path
(and is NOT a limit-only rollback: it also turns off the order limit and the strict promo rule); the old value is
restored by forward-deploying the pinned pre-change payload.

## Founder decision (2026-10-25)
After running OI-348 B6 on a free account (20 checks allowed, the 21st refused with "Too many attempts. Try again in 32
minutes." at 9:58 IST; counters read afterwards by the coordinator: `promo_validate used = 20`, `create_order used = 1`;
these live reads are the coordinator's, reviewers could not verify them) the founder said: "I don't want to give user
20+ attempts, only 7 attempts and retry after an hour." Asked what "retry after an hour" means, the founder chose
**"7 per clock hour (smallest change)"**: only the limit changes; the window stays the fixed 1-hour UTC bucket (the wait
is 1 to 60 minutes; **the bucket is the UTC hour, so it ends at :30 IST**, not at :00), message "Too many attempts. Try
again in N minutes.". Rejected by that choice: a rolling hour anchored on the first check; a 60-minute lockout after the
7th. In the board text the bucket is called "UTC clock hour (it ends at :30 IST)".

## Commit 1 — change set (code, tests, number docs)
1. `supabase/functions/validate-promo/index.ts:34`: `const PROMO_QUOTA_LIMIT = 20;` → `= 7;`. Passed as `p_limit` at
   `:92`, logged at `:104`; the header comment (`:11`) names the constant, not a number. Nothing else in the function
   changes: bucket (`PROMO_RATE_WINDOW_MS`), refusal shape (HTTP 200 `{valid:false, reason}`), reason text, the kill
   switch, the order limit (30, `create-razorpay-order/index.ts:78`), the client (`reason` shown verbatim,
   `paywall_sheet.dart:237`).
2. No migration. `consume_quota` is defined ONLY by `supabase/migrations/128_usage_counters.sql:69-113` (130 changes the
   ACL, 129/132/153 only call it). The limit is a plain argument; the guard is `ON CONFLICT ... DO UPDATE ... WHERE
   uc.used < p_limit` (`:95-100`) and no row back means `-1` (`:107-109`); `p_limit = 0` returns `-1` (`:91-93`) and a null or negative limit raises (`:84-86`). A
   bucket row at `used >= 7` is refused at once, a refusal touches neither `used` nor `updated_at`, and a row cannot rise
   above the limit. No trigger, CHECK or default mentions a promo limit.
3. Pins and statements of the number (same commit):
   - `supabase/functions/validate-promo/index_test.ts`: `:122` title (number-free: "one counter call per check: the
     key, a 1-hour UTC bucket and the configured limit"), `:129` `assertEquals(args.p_limit, 7)`, `:133` title
     (number-free: "over the limit (the counter answers -1)"; the new Test 1 owns the "8th").
   - `test/contracts/promo_validate_rate_limit_writer_to_reader_test.dart`: `:4` comment, `:28`
     `contains('const PROMO_QUOTA_LIMIT = 7;')`.
   - `test/contracts/usage_quota_ledger_writer_to_reader_test.dart:275` comment "(limits 30 and 20)" → "(limits 30 and 7)".
   - `supabase/functions/_shared/founder_digest_content.ts:116-117` comment "promo checks (limit 20)" → "(limit 7)",
     SAME line count (registry ranges 88-137, 289-309, 971-997, 1083-1095 stay valid). Comment-only: importers
     `founder-digest/index.ts:69,98`, `telegram-admin-bot/index.ts:20` and `alert-critical-notify/index.ts:16` are NOT
     redeployed (the 2026-10-24 plan took the same position for `alert-critical-notify`); no gate or documented rule
     requires a deployed bundle to equal git. Note for the next deployer of those three: the newest commit whose whole
     import closure equals their live bundle is the commit before this one.
   - Docs: `docs/naming_conventions.md:460`; `docs/sot_registry.yaml:17190` (description text, same line count);
     `supabase/functions/CLAUDE.md:179`; `docs/architecture/payment.md:48` rule 11(d); `docs/operations/SECRET_INVENTORY.md:45`.
   - Board lines in `docs/audit/open_issues.md` (these ride in COMMIT 2 with the rest of the board edits, because a file cannot be split across commits without an interactive add; they are listed here because they describe this change): (i) OI-348 B6 check (3) at
     `:6132` rewritten: "the 8th code check within one UTC clock hour (it ends at :30 IST), counting the checks of steps
     (1) and (2) and any earlier ones in that hour; use an INVALID code such as `NOPE` so the field stays editable (after
     a VALID answer the paywall shows APPLIED and the button is disabled, `paywall_sheet.dart:229-233,672-674`); if the
     bucket already holds 7 or more, the first tap is refused and the row is unchanged; run it after the limit-7
     deploy"; (ii) a NEW "Update 2026-10-25" line on OI-366 (the existing `:6353` Update keeps its text as history):
     "promo-check limit lowered 20 → 7 per UTC-hour bucket by founder decision; merged <PR>; deploy of `validate-promo`
     pending the founder's go, the previous limit 20 is live until then" (the deploy result is added by the post-deploy
     docs PR below).
4. Historical records that state 20 are LEFT UNCHANGED (they say what shipped on 2026-10-24/25):
   `docs/audit/payment-hardening.closure.yaml:38`, `docs/audit/2026-10-25-hermes-payment-hardening.md:60`,
   `docs/diagnoses/*`, `docs/reviews/*`, `docs/plan-reviews/payment-hardening.md:18`. In
   `docs/plans/2026-10-24-payment-hardening.md` (20 at `:34`, `:45`, `:318`, `:342`) ONE dated note is added beside the
   ratified decision at `:34`: "superseded 2026-10-25: 7 per UTC-hour bucket (plan `2026-10-25-promo-check-limit-7.md`)".
5. One OI filed with `sh scripts/mint_oi.sh` (from this worktree; minted as OI-414, its body is written in commit 2) for the gateway-retry amplification (Accepted
   properties), with a "Done when" (the paywall's promo call does not retry 502/504 after the counter was spent, or the
   spend is made idempotent) so the known gap is tracked, not left as an intention.

## Commit 2 — board bookkeeping (docs only; `closes-oi: OI-406`)
- OI-348: record the 2026-10-25 live results with their evidence (9:58 IST, 20 allowed, the 21st refused with 32
  minutes, `used = 20`, `create_order used = 1`): B5 passed, B6 (1) and (2) passed, B6 (3) passed at the OLD limit and
  is re-run at 7 after the deploy; edit the B5 row (`:6131`) and the Flips sentence (`:6152`, "OI-406 after B5 and its
  merge (then the OI closes)") that this makes dangling.
- OI-406 (B5 was its last open condition; migration 163 is in `backups/applied_migrations.json:1262` and commit 36e594c8
  is an ancestor of HEAD): move the section to the end of `closed_issues.md` in the recent-entry format (heading
  `## OI-406 — <same title>`, `- **Status**: CLOSED · 2026-10-25 · diagnose a6c2e9 · branch promo-limit-7 ...` with the
  leading `- ` and the colon outside the bold, `- **Blocked on**: — (resolved)`, Verified and Identified lines, the
  original body, a `**CLOSED 2026-10-25 (...)**` paragraph). The new paragraph must not contain either form
  `check_*.dart (Gate N` or `Gate N (check_*.dart` (the gate-index parser reads `closed_issues.md`,
  `gate_index_lib.dart:241-266`). `open_issues.md` ends with 0 CLOSED entries.
- Stale rows the 2026-10-25 deploys made wrong, corrected here with the real facts (read from the board and the
  closure ledger at edit time): `docs/audit/payment-hardening.closure.yaml` row PH-DEPLOYS (still
  `blocked_on_user`), the OI-366 `:6353` "Stays OPEN until the two deploys" sentence (add a dated Update, do not rewrite
  history). PH-DEVICE-CHECKS stays `blocked_on_user` (B6 (3) re-runs at 7). `docs/audit/payment-hardening.closure.yaml`
  PH-U4 "OI-406 stays open until it" is a history line and stays.
- After editing: `dart run scripts/check_context_artifact_budget.dart` (`open_issues.md` and `supabase/functions/CLAUDE.md`
  are tracked; expected change is small or negative) and `--record` if intended.

## Tests (new behaviour, not a re-pin)
The existing over-limit test answers `-1` from a fake that ignores the limit (`fallbackRpc: () => ...`, `index_test.ts:54`),
so only the `p_limit` assertion and the Dart pin guard the number today.
- Reuse `withFrozenNow(iso, fn)` (`index_test.ts:241-259`; its `FrozenDate` controls the three clock reads: `Date.now()`
  at `index.ts:86`, the `secondsLeftInBucket` default at `_shared/order_abuse_guards.ts:17`, `promoUsableAt`'s
  `new Date()` at `_shared/promo_rules.ts:24`). Do NOT redeclare it, do NOT nest it; each test runs inside its own
  scope and shares the counter created outside. `FrozenDate` accepts only 0 or 1 constructor arguments; the handler uses
  only those forms and the emulator uses no `Date` at all. New tests go after `:259`. Freeze Test 1 at
  `2026-10-24T18:31:00Z` (`MINUTE_AFTER_IST_MIDNIGHT`, `:238`), inside the UTC hour 18:00 to 19:00Z.
- Scenario plumbing: `run()` (`:50-75`) builds a NEW `FakeServer` per call and hard-codes the user and token, so add to
  `Sc` an optional `counterRows` (a `Map` created OUTSIDE `run()` and shared across calls) and an optional token/user pair
  (import `OTHER_USER` from `_shared/payment_writer_harness.ts:25`, with a second token mapped to it in `users`). When
  `counterRows` is set, `fallbackRpc` emulates the counter: key `(p_user_id, p_quota_key, p_window_start)`; a missing,
  non-integer or negative `p_limit` THROWS (the real function raises; the handler answers "couldn't check"); if
  `p_limit = 0` or `used >= p_limit` answer `-1`; else increment and return the POST-increment count (1..limit; the
  handler fails closed on anything below 1 other than -1, `index.ts:98`). It reads `args.p_limit` (via `Number(...)`,
  `args` is `Record<string, unknown>`), never a literal 7. The emulator's "row stays at 7" assertion is a sanity check of
  the emulator (the handler never writes the counter); the real guarantee is the SQL (`128:97-100`).
- The quota census (`test/contracts/usage_quota_ledger_writer_to_reader_test.dart:80-90,145-196,270-290`) scans every `.ts`
  under `supabase/functions/` including `_test.ts`, strips comments but not strings, and fails on ANY non-allowlisted file
  containing `consume_quota` OR `usage_counters`: neither may appear in code, titles or strings of `index_test.ts`
  (comments only). Use `CONSUME_QUOTA_RPC` (`index_test.ts:17`) and the name `counterRows`. After editing, `grep -n
  "consume_quota\|usage_counters" supabase/functions/validate-promo/index_test.ts` must show only comment lines.
  `check_local_date_key_drift.dart` bans `.toISOString().slice(0, 10)` in any TS file: use string constants for window
  starts.
- Test 1: user A checks 1 to 7 for an active code each answer `valid:true` with the code's discount and each counter call
  carries `p_window_start === "2026-10-24T18:00:00.000Z"` (so a 30-minute window cannot hide behind the same literal);
  A's check 8 answers `{valid:false, reason: "Too many attempts. Try again in 29 minutes."}` (literal; 1740 s left at
  18:31:00Z, `retryMinutes` = 29) with NO `promo_codes` read on that call; THEN user B's check 1 is allowed (the order
  matters: a handler that sends a fixed `p_user_id` is only caught when B is checked after A has hit 7).
- Test 2 (pins the fixed UTC-hour bucket): after A's refusal, in a SEPARATE `withFrozenNow` scope at
  `2026-10-24T19:05:00Z`, A is allowed again and the counter call carries `p_window_start === "2026-10-24T19:00:00.000Z"`.
- Tests that move with the constant: only `:122/:129/:133` (`payment_log_safety...:151` allowlists the identifier;
  `founder_digest_caps_mirror_test.dart` resolves `const PROMO_QUOTA_LIMIT = (\d+);` and a limit of 7 resolves; the
  kill-switch golden uses the origin fixture which has no limit; the digest tests carry no number).

**Mutation proof (rule 21), run before the tests are believed; results are written into the plan-review record and the
commit-1 body (a `feat` commit has no diagnose-doc).** Each mutant is computed and anchor-asserted before it is written,
restored in `finally` with a sha256 compare, and confirmed APPLIED with `grep -c`: constant `= 8`, `= 6`, `= 20` must each
redden Test 1, the `p_limit` assertion and the Dart pin; a handler that sends a fixed `p_user_id` must redden Test 1's B
assertion; a handler that reads `promo_codes` before the counter must redden the "no `promo_codes` read" assertion;
`PROMO_RATE_WINDOW_MS` of 30 minutes must redden Test 1 (the window-start literal) and Test 2; a 2-hour bucket formula
(`floor(now / 7_200_000)`) must redden Test 2.

## Accepted properties (stated so no later reviewer re-flags them and no check is read as proving more)
- **Fixed UTC-hour bucket, not rolling:** the bound is 7 per bucket; 7 at xx:29 IST plus 7 at xx:31 IST is 14 checks in
  about two minutes. The founder chose this. The post-deploy check proves 7 per bucket, not a rolling hour.
- A unit is spent before the body is read (`index.ts:88` before `:110`): a malformed body, an empty code and an unknown
  code each cost one. The shipped client cannot send an empty code (`paywall_sheet.dart:203`).
- The 7th check carries no "last attempt" hint; the 8th refusal does not extend the lockout (`used` is not touched).
- **Gateway-retry amplification:** `callFunction` retries only 502/503/504 (`supabase_service.dart:528`, 2 s, 6 s, 12 s,
  up to 4 invocations per tap); only the gateway emits those, and a 502/504 after the handler ran has already spent a
  unit. At 20 this was harmless; at 7 two such taps lock a user out for the rest of the bucket. Rare; tracked by
  OI-414 (commit 1, item 5); no client change in this batch.
- A normal tester (a few typos, then a valid code) uses about 6; the OI-348 B6 walk spends 2 to 3 before its limit step.

## Verification before the B-pass (local, in this worktree)
`NO_COLOR=1 TZ=Asia/Kolkata $HOME/.deno/bin/deno check --node-modules-dir=none supabase/functions/validate-promo/index.ts
supabase/functions/validate-promo/index_test.ts`; the validate-promo Deno tests; ONE whole-tree
`deno test --no-check --allow-all --node-modules-dir=none supabase/functions/` (a `_shared` file is edited; ~21 s;
known VPS quirk: tests that bind :8000 may fail AddrInUse, judge by the same test on a clean `main`); CI also runs a
whole-tree `deno check` (`.github/workflows/test.yml:262`), so run it too if the local run is cheap. Then the §4.12.8
loop: `flutter analyze --no-fatal-infos`, the touched contract tests, `TZ=Asia/Kolkata flutter test --exclude-tags
golden`, `PRE_COMMIT_GATE_JOBS=1 sh scripts/pre-commit.sh`.

## Merge artifacts and the merge gate
The PR carries: this plan, the B-pass review `docs/reviews/<staged-hash>-review.md` (with a `## Tuning entry`, a literal
`verdict: accepted` line) and the plan-review record `docs/plan-reviews/promo-limit-7.md` (`branch: promo-limit-7`,
`review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`, `bpass_review:` the review
path), landed in its own LATER commit so its citation does not move the review hash. The record gate
(`check_plan_review_record_exists.dart`) runs only on the push to `main` (`.github/workflows/test.yml:414-439`;
`safe_pr_merge.sh` counts it as skipped-ok), so before the merge it is replayed in a scratch clone with
`scratchpad/u4/replay.sh <branch> <base-sha>`; a red there is fixed before `safe_pr_merge.sh`.

## Rollout (every live step has its own founder go)
1. Merge via `sh scripts/safe_pr_merge.sh <pr>` after CI is green.
2. Deploy tree: THIS worktree after `git fetch origin main && git merge --ff-only origin/main`, never the integration-only
   primary. Require `git status --porcelain` empty and `git diff --name-only HEAD...origin/main -- supabase/functions`
   empty (a stale branch would roll back main's live code). Re-read the deploy-rollback skill (§1.1 project id
   `dedsavbjuwgarrhphgnl`, §1.3 token check: `GET /v1/projects/dedsavbjuwgarrhphgnl/functions` returns 200, §6.9, §6.12,
   §6.13) and OI-405 at deploy time.
3. Rollback preparation, before the forward deploy: `git log f58db308..HEAD` shows no change to `validate-promo/` or
   to any `_shared` file it imports (`subscription_stacking`, `payment_log_safe`, `promo_rules`, `order_abuse_guards`,
   `ist_date`), so the pre-change closure is identical at 25fb8a7f and at f58db308; that is NOT assumed live. Read the
   live `verify_jwt` (`GET /v1/projects/dedsavbjuwgarrhphgnl/functions/validate-promo`), fetch the live bundle
   (`Accept: multipart/form-data`) and compare the six files by sha256 with `git show 25fb8a7f:<path>`; choose the
   rollback SHA only after that comparison. Build the rollback payload with `node .claude/deploy_via_api.js --rollback
   validate-promo <sha> --dry-run` (it builds from `git show`, writes `.claude/_payload_validate-promo_rollback_<sha7>.json`;
   copy it to the scratchpad; without `--dry-run` git-SHA mode defaults `verify_jwt` to true). No version number is
   hard-coded; the live version is read at deploy time.
4. ONE deploy: `validate-promo`, `verify_jwt` true stated explicitly, `--yes` (the tool prompts and exits 2 without a
   TTY). Rollback = `node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl validate-promo <copied payload> true --yes`.
5. Boot proof: the deploy tool prints "Smoke FAIL 401" for this function (not in its tolerated set; it still exits 0 so an
   unattended run will not notice): expected. Probe with the anon key as Bearer: the module's own 401 "Invalid or expired
   token" (`index.ts:78-79`) is a pass, a 503 means the module did not boot. The founder's signed-in check is the real proof.
6. Post-deploy hygiene (OI-405): delete the new archive file(s) and `.claude/_payload_*.json` (covers the rollback
   payload), `.claude/_snapshots/` if present; `backups/edge_function_payloads/validate-promo/` is not in git so the
   `git checkout` of that path is a no-op; confirm `git status --porcelain` is empty before worktree retirement.
7. Counters need no touching, on deploy or rollback. At deploy time any bucket row with `used >= 7` is refused until its
   bucket ends (at most 60 minutes); rows below 7 continue toward the new limit.
8. Founder check (a free account, after the deploy): the coordinator first reads that account's current `promo_validate`
   bucket row (a read-only live SELECT, its own go if asked) because the founder cannot read the table; if `used_before
   >= 7` the first tap is refused and the row is unchanged, so wait for the next bucket (it starts at :30 IST). Otherwise
   the founder taps APPLY with an invalid code (`NOPE`): the (7 - used_before + 1)th tap shows "Too many attempts. Try
   again in N minutes." and the row reads `used = 7`.
9. Post-deploy docs PR (docs only, after the founder's B6 (3) re-run): record the deployed version, date, boot-probe result
   and the B6 (3) result on OI-366 and OI-348, and update the closure ledger's PH-DEVICE-CHECKS if it then closes.
   This cannot be written earlier because the result does not exist yet.

## Out of scope (stated)
The order limit (30), the 200/429 shapes, a rolling or lockout window, the paywall copy and a "last attempt" hint, a
client change for the retry amplification (tracked by the OI above), OI-407's switch removal.
