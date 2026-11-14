---
bug_id: f0b6d8
date: 2026-10-11
batch: oi321-orphan-media-pro-check (OI-321)
status: fixed_in_code_deploy_pending
tier: l_fix
blast_radius: platform
symptom: >-
  `clean-orphan-media` (daily cron, 03:00 UTC) rechecked "is this user PRO?" with a `.maybeSingle()` that kept only `data`
  and ignored `error`. `.maybeSingle()` over two unexpired active rows (an ordinary renewal) answers PGRST116 with
  `data: null`, and ANY read failure also leaves `data` null; both read as "free" and the next line removed the user's
  `chat-media` Storage object. OI-321 named only the two-row case; the unreadable-read case is the larger hole. The
  removal result was also never read, so a failed removal was counted as deleted.
concept: clean_orphan_media_pro_recheck — an object is removed only when the subscription read SUCCEEDED and found no active unexpired row.
sot_registry_entry: clean_orphan_media_pro_recheck
writers:
  - { file: supabase/functions/clean-orphan-media/logic.ts, method_or_widget: "removeFromBucket: the ONLY Storage .remove( in the function folder", line: 66 }
  - { file: supabase/functions/clean-orphan-media/index.ts, method_or_widget: "serve handler: the call to runSweep and the cron_call_log end row", line: 94 }
readers:
  - { file: supabase/functions/_shared/subscription.ts, method_or_widget: "readProState: the three-state PRO read the sweep decides on", line: 309 }
  - { file: supabase/migrations/071_rename_orphan_media_rpc.sql, method_or_widget: "find_orphan_chat_media: the candidate pre-filter (excludes every user with an active unexpired subscription)", line: 18 }
  - { file: lib/features/ai_coach/repositories/coach_media_repository.dart, method_or_widget: "saveForLater doc comment: relies on the cron never removing a PRO user's object", line: 52 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [user_id, status, end_date]
contract_test_path: supabase/functions/clean-orphan-media/logic_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: ["cron_call_log.status=success with error_summary 'skipped_unknown=N failed=M first=<code>' when a candidate could not be decided or removed"]
  failure: ["cron_call_log.status=failed (the candidate-RPC error leg and the outer catch, unchanged) and, NEW, a SYSTEMIC run: at least 5 candidates undecided (skippedUnknown + failed) AND a majority of those scanned => failed/HTTP 500 with the same error_summary, which pages through alert_cron_failures"]
cross_account_guard: "each candidate's PRO check keys on its own user_id, and a candidate whose path is not under that user_id is skipped as unknown, so a drifted RPC cannot separate the PRO check from the object it removes."
forbidden_patterns_checked:
  - "reusing isProUser for the recheck — REJECTED: it answers false on a read error and on a thrown rejection, the safe direction for notification copy and the DESTRUCTIVE one before a delete. It would have fixed the two-row case and left the error case. The OI's own suggestion (read the active rows with a limit and test for any) has the same flaw."
  - "a NAIVE escalation (any unreadable candidate => a `failed` cron row) — REJECTED in plan review round 2: a failed row creates a critical alert within the hour (alert_cron_failures, migration 147, then migration 133 to the founder's Telegram), so one transient read blip, or one permanently unremovable object every day, would page. Replaced by a RATIO rule after the B-pass (finding 1): `isSystematicFailure` ends the run failed only when >= 5 candidates AND a majority were undecided, the same idea as weekly-recalc/index.ts:415-420 (errors > processed). Never ending a systematic outage `success` was the opposite error: zero deletions every day with the free tier's 30-day TTL silently unenforced."
  - "a per-run cache of the PRO state — REJECTED: the recheck exists for 'the user upgraded since the scan'; a cache re-opens that window for every later object of the same user."
  - "a second Storage .remove( or the coach-media bucket anywhere in the sweep — pinned absent (coach-media is long-term consented retention, migration 070, c1ea30)."
proposed_fix: >-
  `_shared/subscription.ts` gains `readProState(client, userId, now = new Date())` returning `pro` / `free` / `unknown`:
  an array read with `.limit(1)` (never `.maybeSingle()`); `unknown` for a populated error, a thrown rejection, a
  non-array result, an invalid `now`, or an empty/non-string `userId` (answered without querying). New
  `clean-orphan-media/logic.ts`: `sweepOrphans` removes ONLY when the state is exactly `free` (anything else, including a
  value outside the union or a malformed candidate, leaves the object), counts `deleted` / `skippedPro` /
  `skippedUnknown` / `failed` / `alreadyGone`, and does not stop on one bad object; `removeFromBucket` is the one
  `.remove(` and converts a thrown call into `{ error }`; `runSweep` binds the real dependencies to the `chat-media`
  bucket; `runErrorSummary` builds the `cron_call_log.error_summary` text (counts and one code, never an id or a path).
  `index.ts` calls `runSweep`, records the summary on the cron row and returns the counts; `isSystematicFailure`
  (>= 5 undecided AND a majority) ends the run `failed`/500 so a systematic outage pages. `failureCode` reads `code`,
  then `statusCode`, then `status` (a storage-js `StorageApiError` has a numeric `status` and no `code`); the summary
  adds `already_gone=N` when nothing was removed because every object was already gone. The stale lib comment that named the
  deleted `rechecksIsPro` is rewritten, and no longer claims the cron "never" removes a PRO user's object.
regression_test_planned:
  - "supabase/functions/_shared/subscription_test.ts (11 new: pro with one and with TWO rows, free on zero/expired/other-user/cancelled/expired-status, unknown on error with and without a message, on throw, on null and non-array data, on an empty or non-string id without querying, the end_date == now boundary, the default clock, an invalid now; a fake that evaluates .eq/.gt/.gte/.limit/.maybeSingle with PostgREST semantics, and the verbatim pre-fix body as a regression anchor)"
  - "supabase/functions/clean-orphan-media/logic_test.ts (35: removeFromBucket, sweepOrphans in every outcome, Storage-shaped failure codes, an end-to-end runSweep over one fake client incl. the two-row user, an unreadable read, a systemic failure and a non-systemic one, runErrorSummary incl. already_gone and no uuid, the isSystematicFailure boundaries)"
  - "test/contracts/clean_orphan_media_pro_recheck_test.dart (14, presence only: the wiring, exactly one .remove(, the chat-media literal and the RPC name, both failed legs by position, each .gt(end_date) form once, a derived sweep over every user-keyed subscriptions chain with positive and negative controls)"
  - "test/contracts/progress_photos_pro_insert_rule_test.dart (the third copy of the PRO predicate gets its own pin)"
mutation_proof: >-
  50 mutants (M0-M48 less the unused M15, plus M11b and M34b) applied one at a time against the FINAL tree, after the
  B-pass fixes (each confirmed applied by an exact-one-match replace, every edit computed before any write, originals
  backed up by FULL PATH and byte-compared after the run, `weekly-report` byte-compared against git); 50 of 50 applied
  and 50 of 50 reddened at least one test, restore check empty. The verbatim pre-fix body restored (M0: 3 suites); read
  error -> free; `.limit(1)` -> `.maybeSingle()`; non-array -> free; thrown -> free; status filter dropped; end_date
  filter dropped; `gt` -> `gte` (the boundary row); a one-hour grace on `now`; a stale default clock; the `nowIso` token
  changed; an empty userId queried (and a guard that only checks the empty string); unknown falling through to remove;
  pro branch removed; the exact-free guard swapped for a blacklist; a removal error counted as deleted; a thrown storage
  call not converted; the wrong bucket; `removeFromBucket` dropping the error; a per-run cache; the path-prefix check
  removed; `removed: 0` counted as deleted; `index.ts` regaining a local `.maybeSingle()` recheck; a constant-`free`
  dependency in `runSweep`; `runErrorSummary` ignoring `failed`; the failure-code filter relaxed so an id can leak;
  `weekly-report` losing `.limit(1)` (the derived sweep, a mirror-side mutant); `firstFailure` keeping the last code;
  unknown stopping the run; a throwing readProState dependency read as free; a throwing removeObject dependency not
  caught; a second `.remove(` in `index.ts`; the bucket constant used twice; the summary not recorded on the cron row;
  both `failed` legs flipped to `success`. THE B-PASS ADDED 13 MORE, all red: the systemic rule's minimum 5 -> 4, its
  majority `>` -> `>=`, ignoring failed removals, ignoring unreadable subscriptions; `index.ts` never ending a run
  `failed`; `httpStatus` hard-coded 200; the response status ignoring the run status; `failureCode` ignoring a Storage
  `status`; the summary dropping `already_gone`; `already_gone` reported alongside real removals; and three on the derived
  sweep itself (the payment-id exemption widened to any mention, the generic type argument no longer skipped, an
  extractor that matches nothing).
  FIRST PASS HAD ONE SURVIVOR, M34 (the outer catch flipped to `success`): the pin was a bare `contains("logCronEnd(logId,
  'failed'")`, satisfied by the OTHER failed leg. It is now two assertions by position (exactly two legs, one after the
  candidate-RPC call and one after the outer catch); M34 and its sibling M34b (the RPC leg) both redden. RUNNER INCIDENTS:
  (1) the first full run backed originals up by basename and two mutated files are both named index.ts, so the second
  backup overwrote the first and the first index.ts mutant "restored" the wrong file; the end-of-run byte-compare caught
  it, the tree was rebuilt from git plus the same edit, the runner was fixed to key by full path, and ALL mutants were
  re-run. (2) The B-pass round's extra mutant definitions had bad escaping and the runner did not parse; a pre-check
  that counts every anchor (exactly one match each) ran before the final run. Self-attested, like every rule-21 proof.
impact_analysis: >-
  Behaviour change, deliberate: an unreadable subscription read, or a malformed candidate, now LEAVES the object for the
  next daily run where it used to delete it. A free user's object is removed exactly as before (zero unexpired active rows
  and a successful read). The new removal set is a strict SUBSET of the old one (the old code removed on any null; the new
  code removes only on an empty array with no error and a valid candidate). The response gains skipped_pro, skipped_unknown,
  failed, already_gone (additive; the only reader is the cron's net.http_post result row, which does not parse counts);
  scanned and deleted keep their names. `cron_call_log.error_summary` is now populated when something was skipped or failed
  (precedent: weekly-recalc/index.ts:415-420, which also writes errorSummary on a success row and flips to failed/500 when
  errors > processed; the first draft of this doc cited re-engagement, which is WRONG: its success legs pass no
  errorSummary), and the run ends `failed`/500 only when >= 5 candidates AND a majority were undecided. `readProState` is additive in _shared/subscription.ts; nothing above line
  276 changed, so the SoT line ranges (fetchLatestActiveEndByUser 236-262, fetchProUserIds 59) hold. The deploy carries two
  behaviour-identical diffs since live v14: `_shared/cron_auth.ts` exports `timingSafeEqual` (bfc1bc11) and
  `_shared/cron_telemetry.ts` has a comment change. Readers of the removed `rechecksIsPro`: none (git grep over lib, test,
  scripts, supabase, docs/naming_conventions.md; the only other hit was the lib comment, rewritten).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/features/ai_coach/repositories/coach_media_repository.dart doc comment only (named the deleted rechecksIsPro); flutter analyze lib/ has 60 pre-existing infos, no warning or error, none in that file" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "no migration. Live 2026-10-11: subscriptions.status values are active/cancelled/expired and 0 rows have a NULL end_date, so the end_date > now predicate has no NULL hole" }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "live clean-orphan-media is v14 (ezbr_sha256 9994c32968031c6f034bf50979c6b5ca29c23df16c1eac69a0f921f220e61156, updated 2026-08-01) and its deployed index.ts is the same code as git; the DEPLOY of this fix is NOT done (needs the founder's go) — see the closure ledger rows D1/V1" }
  - { tier: 7, name: "Cron jobs", status: verified, evidence: "docs/operations/CRON_REGISTRY.md:37 and backups/live_cron_jobs.json: clean_orphan_media_daily '0 3 * * *' UTC dispatching this function; the next scheduled run after the deploy is the live confirmation (V1)" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "the function uses the service-role client; the RPC find_orphan_chat_media is SECURITY INVOKER with EXECUTE granted to service_role (migration 071/090/117)" }
  - { tier: 9, name: "Storage buckets + objects", status: verified, evidence: "the only removal targets bucket chat-media (pinned); coach-media is long-term consented retention (migration 070). Storage's response to removing an already-missing object is believed to be success with empty data and was NOT verified live (a live delete)" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the cron is the only caller (pg_net.http_post with the cron secret); an unauthenticated POST gets 401 from the module before logCronStart, so the post-deploy smoke deletes nothing" }
recurrence: "Direct recurrence of f2b9d4 (2026-09-03, ai-proxy checkPro: .maybeSingle() with no .order().limit(1), a paying user with two overlapping active rows read as not PRO) and bug class 2.49 (an error fallback picks the DESTRUCTIVE default). f2b9d4's fix was applied to every GATE read; this destructive reader was the one left. WHY MY FIRST BUG-HISTORY SEARCH MISSED IT: I grepped INDEX for the token `maybeSingle` and for `clean-orphan-media` (hits c1ea30 and e1b7d4, both different defects) and wrote 'no recurrence' in the plan; f2b9d4's INDEX line names `checkPro` and 'a PAYING PRO user silently loses every PRO coach tool', never the token. A context-blind plan reviewer found it by opening a test header. The lookup must search the concept and the failure shape as well as the token (memory: feedback_bug_history_search_the_concept_not_only_the_token)."
related_bugs:
  - f2b9d4
  - c1ea30
---

# `clean-orphan-media` deleted a PRO user's object whenever the subscription read was unreadable

## What was wrong

The daily sweep takes the candidates from `find_orphan_chat_media` (migration 071), which already leaves out every user with an active unexpired subscription, and then rechecks each one at delete time, because the user may have upgraded since the scan. The recheck (`rechecksIsPro`, `index.ts:120-129`) selected `end_date` with `.maybeSingle()` and kept only `data`. Two things make `data` null for a user who IS PRO: two unexpired active rows (PGRST116, the ordinary shape of a renewal) and any read failure (`error` was never read). Both read as "free", and the next line called `storage.remove`.

How narrow: the RPC pre-filter means the recheck only matters when the user upgrades between the scan and the delete; both holes need that, and the error case also a failed read in that window. The harm is irreversible (a PRO user's chat photo; `coach_media_repository_test.dart:18` records "PRO users must keep BOTH copies"). OI-321 as filed understated the first hole (it named only the two-row case) and overstated the reach (it did not account for the pre-filter); both are corrected in the OI.

The shared `isProUser` helper was not the answer: it returns `false` on a read error and on a thrown rejection. That is the right default for choosing notification copy and `consume-day-swap`'s quota tier, and the wrong one in front of a delete.

## Writer and reader

Writer of the destructive act: `logic.ts` `removeFromBucket` (the one `.remove(` in the folder), reached from `sweepOrphans`. Reader of the entitlement: `readProState` (`_shared/subscription.ts:309`), with the RPC pre-filter (`071:18-39`, live body identical) before it. Reader of the outcome: the `cron_call_log` row (`status`, `error_summary`) and the log line; the cron's `net.http_post` result row ignores the counts. The object itself is read by `ai-media-proxy` (signed URL) and `WardroomChatBubble`.

## The fix

See `proposed_fix`. Plan: `docs/plans/oi321-orphan-media-pro-check.md` (v3, consolidated after two review rounds). Registry: concept `clean_orphan_media_pro_recheck`. Ledger: `docs/audit/oi321-orphan-media-recheck.closure.yaml`.

## How it was verified

Two plan-review rounds by fresh context-blind readers (round 1: 0 P1, 7 P2; round 2: 0 P1, 6 P2; no mechanism problems, mostly pins, gates and process; the one structural fold in round 2 was REMOVING the naive `failed`-status escalation that would page the founder on one blip). The live RPC body, the live `subscriptions` status values and NULL count, and the deployed function version were read read-only from project `dedsavbjuwgarrhphgnl` on 2026-10-11. Tests above; `deno check` over the whole `supabase/functions/` tree (CI's hard gate) exits 0; the whole Deno tree is 1096 passed, 0 failed with the two files that bind port 8000 excluded (`future-prediction/index_test.ts` and `re-engagement/index_test.ts` fail locally with `AddrInUse` because a docker-proxy holds :8000, a documented VPS quirk, CI has no conflict, and this branch touches neither file); the Dart tests above pass; 50 of 50 mutants reddened on the final tree. Then a code-level B-pass on the real staged diff (one fresh Sonnet reader, `docs/reviews/`): no P0 or P1, one P2 and seven P3, all verified against the code by the main thread and accepted: the P2 re-introduced escalation as a RATIO rule (a systematic outage must not end `success` with zero deletions every day; and the precedent I had cited, re-engagement, was wrong, the real one is weekly-recalc); the P3s fixed a Storage error shape the real client never produces (storage-js `StorageApiError` has `status`, no `code`), a derived-sweep exemption that was too wide and a generic-type blind spot (the new control for it caught a second hole in my own fix, the `calls` regex), an `already_gone` silence, a count and line-range drift, a misplaced docblock and an overclaiming lib comment. Finding 6 (the blast-radius registry does not list this function as catastrophic) is a founder decision and is a ledger row, not a code change.

## Candid notes

- Not verified live, and stated so: PostgREST's PGRST116 on two rows is documented semantics (and what OI-321 itself asserts), proven here only against a fake that models it; a read ERROR cannot be produced live on demand; Storage's answer to removing an already-missing object is SDK knowledge.
- Residual gap, by decision: a PARTIAL persistent `unknown` state (fewer than five undecided candidates, or not a majority of those scanned) raises no alert; it is recorded on the cron row's `error_summary`, the log line and the response and the objects are retained. A systemic one (>= 5 and a majority) ends the run `failed`/500 and pages through `alert_cron_failures`.
- Not changed: `isProUser`, `fetchProUserIds`, the RPC, migrations, and the other 26 `subscriptions` read sites (sweep result in the ledger: every one refuses, throws, aggregates, is keyed by the UNIQUE payment id, or proceeds on purpose (`delete-account`, DPDP §17); this was the only one whose unknown branch is destructive).
- The first run of the mutation runner corrupted `clean-orphan-media/index.ts` (basename-keyed backups colliding between two `index.ts` files); caught by the end-of-run byte-compare, rebuilt from git plus the same edit, and every mutant re-run. First-pass survivor M34 was a real pin gap and is closed.
- The deploy is a separate live action that needs the founder's explicit go; until it happens the OI stays OPEN and the fix is not live.
