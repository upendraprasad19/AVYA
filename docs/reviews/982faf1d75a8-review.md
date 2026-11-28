---
reviewed_at: 2026-10-11
staged_against: 7c0f3481d18d (reviewed), 982faf1d75a8 (the tree with every fix below applied; the file name)
blast_radius: platform
reviewer: claude-sonnet-via-skill (1 fresh context-blind reader, read-only, exhaustive command list)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, L21, L23, L24, L25, L27, L34, L37, L41, L50, L53]
findings_count: 8
verdict: accepted
---

# Code Review - OI-321 (clean-orphan-media: an unreadable PRO check must not delete)

Diff reviewed: the staged change on branch `oi321-orphan-media-pro-check` (19 files): `readProState` appended to
`_shared/subscription.ts`, the new `clean-orphan-media/logic.ts`, the rewired `index.ts`, 3 test files, the registry,
the diagnose-doc `f0b6d8`, the plan, the closure ledger. One fresh reader, read-only. Headline: **no way for the new
product code to delete a PRO user's object that the old code kept** (traced `runSweep` -> `sweepOrphans` ->
`readProState` -> `removeFromBucket` by hand and ran the allowed test commands). One P2 (telemetry design, with a wrong
precedent cited), seven P3. No P0, no P1. Every finding was verified against the code by the main thread before it was
accepted (a reviewer's suggested fix can be wrong though the finding is right). A mutation pass on the FINAL tree (50
mutants, 50 applied, 50 reddened, restore check empty) ran after the fixes.

## Checked and clean (what the reader ran, and why the lens came back clean)

- **guard_without_its_mirror / every way a PRO object is still removed.** `sweepOrphans` reaches `deps.removeObject` only
  through `state === 'pro'` -> continue and `state !== 'free'` -> continue. A throwing `readProState` dependency becomes
  `'unknown'`; a value outside the union, a null candidate, an empty or non-string field and a path not under
  `user_id + '/'` all skip. `readProState` returns `free` only on `!error` and an array of length 0; an empty id, an
  invalid `now`, non-array data, a populated `error` (even `{}`) and a rejection all return `unknown`. The query is an
  ARRAY read (`.limit(1)`), so it cannot raise PGRST116, and its predicate matches the RPC (`status='active' AND
  end_date > NOW()`, strict `>`).
- **Success while doing nothing.** `removeFromBucket` returns the error rather than swallowing it; a thrown call becomes
  `{ error }`; `failed` is never counted as `deleted`; `removed === 0` becomes `alreadyGone`.
- **`index.ts` top to bottom.** The candidate-RPC error leg and the outer catch still end `failed`; `SupabaseClient` is
  no longer imported; `candidates ?? []` is safe; no reader of the response body exists (`git grep`); the only deploy
  tooling reference is the smoke map, which tolerates 401.
- **Deploy bundling (`.claude/emit_payload.js` read-only).** `findRelativeImports` over the new files resolves
  `./logic.ts`, `../_shared/subscription.ts` and the existing `../_shared/*`; a comment containing `from "no row"` is
  harmless (the specifier does not start with `.`). Rollback is the pre-deploy cloud snapshot; the v1 backup payload is
  tracked.
- **Could the Deno tests pass for the wrong reason.** The fakes evaluate `eq/gt/gte/limit/maybeSingle` against real rows
  and `.maybeSingle()` over more than one row returns PGRST116 as postgrest-js does; the regression anchor runs the
  verbatim old body on the same fake and gets `false` for two rows; the end-to-end `runSweep` tests assert
  `removeCalls` equals `[]` for the two-row user and for error/throw; the mid-run upgrade test mutates the rows through
  `onSubsRead` and asserts the exact removed path.
- **asserted_fixture_value, counted against the tree.** 27 `from("subscriptions")` sites after the change (26 siblings
  plus `readProState`); 7 user-keyed chains ending in `.maybeSingle()`/`.single()`; each opened at its cited line and
  all carry `.limit(1)`; the G1-G6 ledger file:line lists match grep exactly.
- **L21 / L23 / L27 / L37 / L41 / L50 / L53.** Cron auth untouched; one bucket constant, one caller; no module state;
  `data: null` with no error is `unknown` (tested); `alert_cron_failures` (migration 147) pages on a `failed` row; SoT
  ranges re-checked; `CRON_REGISTRY.md` row accurate; rollback documented. Secrets scan of the staged diff found nothing.

## Finding 1 - P2 - L34 telemetry coverage on async failure legs (and L41 cross-document consistency)
- **file:line:** `supabase/functions/clean-orphan-media/index.ts:103-107`, `logic.ts:177-181`; wrong precedent cited in the diagnose-doc and plan.
- **claim:** a SYSTEMATIC unreadable-subscription state (revoked grant, rotated service key, PostgREST outage at 03:00) made the run `success` with zero deletions every day; the only trace was `error_summary` on a success row and a `console.warn`; nothing reads `error_summary`. The old code deleted in this state, so the failure mode is new, and the "residual gap, by decision" had no ledger row. The doc also cited `re-engagement` as precedent for populating `error_summary` on a success row: false (its success legs pass no `errorSummary`); the real precedent is `weekly-recalc/index.ts:415-420`, which escalates to `failed`/500 when `errors > processed` - a ratio rule that refutes "any escalation would page on one blip".
- **verification:** the main thread re-read both files and migration 147 (`alert_cron_failures` pages on any `failed` row in the last hour).
- **status:** accepted - fixed. `logic.ts` `isSystematicFailure(r)`: `undecided = skippedUnknown + failed`, systemic when `undecided >= 5` AND `undecided * 2 > scanned`; `index.ts` ends the run `failed`/500 then, otherwise `success` with the summary; the precedent is corrected to `weekly-recalc` in the plan, the diagnose-doc, `functions-detail.md` and bug class 2.49. The reviewer's version counted only unreadable reads; counting failed removals too is deliberate (an outage that makes every `.remove()` fail is as systemic), while the 5-minimum and the majority keep one blip or one stuck object at `success`. Boundaries pinned in `logic_test.ts`; mutants M36-M41 and M45 red.

## Finding 2 - P3 - L25 intra-document drift (wrong test count, ledger numbering)
- **file:line:** diagnose-doc and closure ledger said `subscription_test.ts (12 new)`; plan section 5 numbered the ledger rows differently.
- **verification:** `git diff --cached -- supabase/functions/_shared/subscription_test.ts | grep -c '^+Deno.test'` = 11; HEAD has 12; the file now has 23.
- **status:** accepted - fixed (11 new; plan numbering aligned to the ledger; the counts are re-measured at the end: 23 / 35 / 14).

## Finding 3 - P3 - L25 intra-document drift (registry line ranges, pitfall wording)
- **file:line:** `docs/sot_registry.yaml` (`96-165`, `94-110`), `supabase/functions/CLAUDE.md` pitfall row.
- **claim:** `sweepOrphans` ends at its closing brace, not at the next doc comment; the index.ts range ran past the call; the pitfall row said the derived sweep pins `.order(...)` when it pins only `.limit(1)`.
- **status:** accepted - fixed (ranges re-derived from the final files; `check_sot_registry_parity` PASS; the row now says `.limit(1)` is what the sweep pins).

## Finding 4 - P3 - L34 observability (summary under-reports; a fixture models a shape production never emits)
- **file:line:** `logic.ts` `failureCode`, `runErrorSummary`; `logic_test.ts` fixtures.
- **claim:** (a) storage-js errors expose `status`/`statusCode`, not `code`, so every Storage failure collapsed to `first=remove_error` and the fixtures used a shape the client does not produce; (b) a `readProState` failure's real cause is logged only by the shared helper's `console.error`; (c) `alreadyGone` was absent from `runErrorSummary`, so a run where every removal was a no-op left a clean cron row (and previously counted as `deleted`).
- **verification:** (a) was UNVERIFIED locally by the reviewer; the main thread read storage-js 2.5.5 and 2.7.x in the Deno cache: `StorageApiError { message, status: number }`, no `code`.
- **status:** (a) accepted - fixed: `failureCode` reads `code`, then `statusCode`, then `status`, through the same short-token filter; Storage-shaped fixtures added. (c) accepted - fixed: `already_gone=N` when nothing was removed and everything scanned was already gone. (b) accepted as a DECISION, not changed: the cause is in the function log (code and message, never the user id); returning it from the shared helper would change a three-state union used by two callers for a line that already exists; recorded as ledger row B4b. Mutants M42-M44 red.

## Finding 5 - P3 - L24 gate strictness (the derived sweep is defeatable)
- **file:line:** `test/contracts/clean_orphan_media_pro_recheck_test.dart` `_chainAfter`, `exempt`, the floor.
- **claim:** the payment-id exemption matched any mention of the column; a generic type argument (`.maybeSingle<Row>()`) ended the chain before the call; the `>= 7` floor equalled today's exact count.
- **status:** accepted - fixed: `exempt` narrowed to `.eq("razorpay_payment_id"...)`; `_chainAfter` skips a balanced `<...>` and the `calls` regex sees generic calls; floor lowered to 5; negative controls for the generic and select-only forms. The new generic control caught a second hole in my own fix (the `calls` regex). Mutants M46-M48 red.

## Finding 6 - P3 - blast_radius_mismatch
- **file:line:** `docs/blast_radius.yaml` has no glob for `supabase/functions/clean-orphan-media/**`; `CRON_REGISTRY.md` calls it "highest-consequence endpoint behind the shared secret".
- **claim:** a registry gap, not a defect in this diff (the new removal set is a strict subset of the old one). Adding the glob as catastrophic would make this and every later batch demand a hermes pass and a feature flag.
- **status:** accepted - founder decision. Ledger row B6 is `blocked_on_user`; nothing in the code depends on the answer.

## Finding 7 - P3 - missing_input (dangling process pointers)
- **file:line:** the ledger, the diagnose-doc and the plan point at `docs/plan-reviews/oi321-orphan-media-pro-check.md`; the review file and tuning-history entry did not exist at staging time.
- **status:** accepted - fixed in two steps by design. This review file and the code-review tuning-history entry land in the batch commit (`check_skill_tuning_history` gates that); the plan-review record lands in the NEXT commit on the branch because it names this file, whose name is the staged-diff hash. `check_plan_review_record_exists` demands it at the merge to main.

## Finding 8 - P3 - L25/L41 (overclaim in a shipped comment, misplaced JSDoc)
- **file:line:** `lib/features/ai_coach/repositories/coach_media_repository.dart:55-59`, `supabase/functions/_shared/subscription.ts`.
- **claim:** the comment said the cron "never" removes a PRO user's object (untrue until the redeploy, and untrue across the read-then-remove window); the large `readProState` JSDoc sat above `export type ProState`.
- **status:** accepted - fixed: comment reworded (an unreadable subscription => no removal; a purchase between the recheck and the removal is not covered; live only after the redeploy); the JSDoc moved directly above `readProState`.

## UNVERIFIED by the reader (and what the main thread did about each)

- Whole-tree `deno check supabase/functions/`: run by the main thread, exit 0.
- The `dart run` gates (SoT parity, citations, Gate 42, context budget, diagnose validator, Gate 40): run by the main thread, all PASS.
- Live facts (deployed version v14 and its sha, the live RPC body, status values, NULL `end_date` count): read-only against project `dedsavbjuwgarrhphgnl` on 2026-10-11 in the plan phase; the deploy step re-reads the version first.
- Whole-tree Deno suite, `flutter analyze lib/`, mutation results: re-run on the final tree (CI-form `deno test supabase/functions/` with the two port-8000 files ignored: 1108 passed, 0 failed; `flutter analyze lib/`: 60 pre-existing infos, no warnings or errors; 50/50 mutants red).
- Storage client error shape: closed by reading storage-js in the Deno cache (Finding 4a).

## Founder triage notes
Finding 6 (blast-radius tier for `clean-orphan-media/**`) is the only open decision; see ledger row B6.
