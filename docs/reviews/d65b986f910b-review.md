---
reviewed_at: 2026-09-26T15:10:00+05:30
staged_against: d65b986f910b  # reviewed at c5d659f52986; renamed after the remediation below moved the staging hash
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (2 context-blind agents — A: read-only lenses 1-5, 7, 9, 10 + rebase_semantic_drift / decision_boolean_as_explanation / tool_action_side_effects; B: mutation lenses 6, 8 in an isolated worktree with the staged patch applied)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, modelled_on_is_a_checkable_claim, self_attesting_artifact, rebase_semantic_drift, decision_boolean_as_explanation, tool_action_side_effects]
findings_count: 7
verdict: accepted
---

# Code Review — d65b986f910b (single-owner batch a, unit a1)

> Dispatched against staging hash **c5d659f52986**. Fixing the seven findings
> below changed the staged diff, so the file carries the post-remediation hash
> the gate keys on (`docs/reviews/` and the code-review SKILL.md are excluded
> from it). The remediation itself is reviewed next by the catastrophic-tier
> Hermes pass.

Scope: ai-proxy `prediction` metering + server-owned prompt (diagnose 125b81), request-size
limits hoisted into `_shared/ai_proxy_input_limits.ts`, delete-account purging every
user-owned bucket through `USER_OWNED_BUCKETS` + extracted `purgeUserStorage` (diagnose
40054f), digest key `prediction_daily`.

Reviewer A's findings 1 (P1) and reviewer B's finding 3 (P2) describe the same defect from
two sides; they are merged as Finding 1 below. Every finding was re-verified against the
code by the coordinator before triage (file reads cited per finding).

## Finding 1 — P1 — function_exception_swallow / guard_without_its_mirror
- **file:line:** lib/core/services/ai_service.dart:387-409 (`predict`); lib/core/services/prediction_service.dart:20-72 (`regeneratePrediction`); lib/features/profile/screens/profile/screen.dart:163-190 (`_refreshPrediction`); lib/features/profile/screens/edit_profile_screen.dart:2078-2088 (PRO auto-regenerate)
- **claim:** `client.functions.invoke` THROWS on any non-2xx (`retryColdStart` catches `FunctionException`, supabase_service.dart:512-518), so `predict()`'s `if (response.status != 200)` branch is dead for real errors; the generic `catch (e)` rethrows `AiServiceException('Prediction request failed: $e')` with no `statusCode`. `regeneratePrediction()` collapses every failure to `false`. The new 429 (the 3/day cap this diff introduces) therefore shows "Could not refresh prediction. Please try again later." — wrong advice, retrying cannot work until the next IST day — and the PRO auto-regenerate on a goal change (edit_profile_screen) silently does nothing on failure, leaving an unmarked stale prediction (the FREE branch marks it stale unconditionally).
- **verification:** `sed -n 387,409p lib/core/services/ai_service.dart`; `sed -n 505,520p lib/core/services/supabase_service.dart`; `sed -n 2078,2088p lib/features/profile/screens/edit_profile_screen.dart`
- **suggested-fix:** catch `FunctionException` in `predict()` and keep `e.status` + the server's `error` string; return an outcome (success / daily limit / failed) from `regeneratePrediction()`; show the daily-limit case distinctly; mark the prediction stale when the PRO regenerate does not succeed.
- **status:** accepted — fixed: `predict()` catches `FunctionException` into `AiService.predictionFailure` (status + server text kept); `regeneratePrediction()` returns `PredictionRefreshOutcome` and no longer sends the cap to telemetry as a fault; Profile says "Daily prediction limit reached. Try again tomorrow."; a PRO goal-change regenerate that does not land marks the prediction stale; coach auto-refresh invalidates on success only. Tests: test/services/prediction_refresh_outcome_test.dart (6, behavioural), test/contracts/prediction_refresh_outcome_wiring_test.dart (4). Mutations Mb4–Mb8 in diagnose 125b81.

## Finding 2 — P1 — guard_without_its_mirror
- **file:line:** supabase/functions/_shared/prediction_handler_test.ts:101; supabase/functions/_shared/ai_proxy_input_limits_test.ts:86; supabase/functions/ai-proxy/index.ts:714
- **claim:** the "system prompt is the server's" test never supplies a `context.system_prompt`, so it only proves the default path. Reintroducing the EXACT pre-fix defect (handler reads `input.context?.system_prompt ?? PREDICTION_SYSTEM_PROMPT`, ai-proxy passes `context: body.context`) left all 15 tests in both files green.
- **verification:** reviewer B's mutation — 0/8 + 0/7 red, reverted clean.
- **suggested-fix:** attempt the attack in the test (hostile `context.system_prompt`, assert it never reaches Gemini); pin the ai-proxy call's first argument to exactly `{ message }`.
- **status:** accepted — fixed: hostile `context.system_prompt` test (+ two sibling fields) and the ai-proxy call pinned to exactly `{ message }`. The reviewer's exact regression now reddens 3 / 18 (Mb1, diagnose 125b81).

## Finding 3 — P1 — guard_without_its_mirror / asserted_fixture_value
- **file:line:** test/contracts/delete_account_purges_all_user_buckets_test.dart:34-52 (`_clientBuckets`)
- **claim:** discovery recognises only a literal in `storage.from('x')` / `bucket: 'x'`, or a const whose NAME ends in `bucket`/`Bucket`. A new bucket written through a const named anything else (reviewer B: `_exportsLocation = 'user-exports'`) is invisible, so "every bucket the client writes to is purged" passes while delete-account leaves that bucket behind — a recurrence of the exact defect 40054f fixes. Live today the 5-bucket set is complete (storage.buckets holds exactly those 5); the gap is forward-looking.
- **verification:** reviewer B's probe file — 0/3 red, removed clean.
- **suggested-fix:** resolve identifier arguments through same-file string constants and FAIL CLOSED on anything unresolvable (an enumerated pass-through allowlist for `UserRepository.uploadImage`'s `bucket` parameter, whose callers are scanned by the named-argument form).
- **status:** accepted — fixed: discovery resolves bucket arguments by VALUE through same-file constants, fails closed on anything unreadable (expression, qualified name, aliased `.storage` handle), one enumerated pass-through (`UserRepository.uploadImage`'s `bucket`) that must stay in use. The reviewer's probe now reddens 1 / 5 (Mb9); reverting to name-keyed resolution reddens 1 / 5 (Mb10). Diagnose 40054f.

## Finding 4 — P1 — blast_radius_mismatch
- **file:line:** docs/blast_radius.yaml:26-34 (catastrophic `requires: feature_flag`); supabase/functions/_shared/prediction_handler.ts:82-99
- **claim:** the new prediction quota fails closed for every user on any `consume_quota` misbehaviour, with no mitigation short of a redeploy; CLAUDE.md §4.6 and the tier's `requires:` both call for a kill switch.
- **verification:** `grep -n "DISABLE_" supabase/functions/_shared/prediction_handler.ts supabase/functions/ai-proxy/index.ts` → none.
- **suggested-fix:** `DISABLE_PREDICTION_QUOTA` env switch that skips the ledger only (the server-owned prompt stays — restoring the caller-supplied prompt would re-open the P0), read at call time, tested both ways. Delete-account has no safe "old path" (it IS the DPDP defect); record that deviation and the version-pinned rollback in 40054f.
- **status:** accepted — fixed: `DISABLE_PREDICTION_QUOTA=true` (Edge Function secret, read per call) skips the ledger only; the prompt stays server-owned. Tests: kill switch ON, and the default reading the env per call (Mb2 1 / 11, Mb3 2 / 11). Delete-account deliberately has none — its only old path is the DPDP defect; recorded with the version-pinned rollback in 40054f.

## Finding 5 — P2 — writer_reader_drift
- **file:line:** test/contracts/founder_digest_caps_mirror_test.dart:125-135 (`_efSites`)
- **claim:** the widened scan lists `_shared/` non-recursively; `_shared/tools/` is a real subdirectory, so a future `consume_quota` caller there would escape the "no caller left behind" mirror. No live false negative today.
- **verification:** `find supabase/functions/_shared -maxdepth 1 -type d` → `_shared`, `_shared/tools`
- **suggested-fix:** `listSync(recursive: true)`.
- **status:** accepted — fixed: the mirror scans every non-test module in the functions tree recursively. A probe caller in `_shared/tools/` reddens it (Mb11); the same probe with the old non-recursive scan stays green (Mb12, the control).

## Finding 6 — P3 — self_attesting_artifact
- **file:line:** docs/diagnoses/2026-09-26-ai-proxy-prediction-unmetered-caller-prompt-125b81.md (frontmatter `blast_radius`)
- **claim:** that doc's own files classify `platform` (ai-proxy/**, _shared/**, CLAUDE.md); `catastrophic` comes only from the delete-account half (40054f) in the same commit.
- **verification:** `printf '%s\n' supabase/functions/ai-proxy/index.ts supabase/functions/_shared/prediction_handler.ts | dart run scripts/blast_radius_from_diff.dart -`
- **suggested-fix:** declare `platform`, note the commit's catastrophic tier comes from 40054f.
- **status:** accepted — fixed: 125b81 declares `platform`, with the note that the commit's catastrophic tier comes from 40054f.

## Finding 7 — P3 — stale comment
- **file:line:** lib/features/profile/screens/profile/screen.dart:147-148
- **claim:** "calls AI via the prediction route (bypasses daily limits + interaction logging)" — false now: the route has a 3/day cap shared by onboarding, the coach auto-refresh and this button.
- **verification:** `sed -n 147,148p lib/features/profile/screens/profile/screen.dart`
- **suggested-fix:** correct the comment.
- **status:** accepted — fixed: the comment now states the shared 3/day cap.

Setup disclosure: reviewer B's isolated worktree was created at main's tip
`5c4d89ff` rather than the branch base `9939750b`; it applied the staged patch
with `--exclude=docs/diagnoses/INDEX.md` (an auto-generated index main had
regenerated) and reviewed the same 24 files. main's 3 extra commits touch no file
in this diff except that index, so the findings are unaffected. Its worktree was
removed after the pass (only the patch and build artifacts were in it).

## Checked and clean (from both reviewers, condensed)
- Live `usage_counters` columns and `consume_quota(uuid,text,timestamptz,integer)` INVOKER signature match `consumePredictionQuota` exactly; RLS on, zero policies.
- All 5 buckets exist live with the public flags 40054f states; no 6th bucket; avatars 7 objects / 6 orphaned, banners 7 / 6 — matches 40054f.
- `purgeUserStorage` is a faithful extraction of the pre-fix loop (`git show 9939750b:…`); `PREDICTION_SYSTEM_PROMPT` byte-identical to the old default.
- Every test count and "N of M" mutation claim in both diagnose-docs re-derived and matched.
- No secrets, no `unawaited(` added; per-bucket error isolation re-run green.
- rebase: main's c43733d9 (migration 144) restores `cleanup_usage_counters()`; no conflict with `prediction_daily`.
- `consume_quota` return states (number / -1 / null+error / null+null / non-number) all fail closed or 429 correctly.
- Coordinator addition: the PRO monthly `_autoRefresh` (ai_coach_provider.dart:1387-1395) re-fires on each provider rebuild while the prediction is >30 days old; with the cap, repeated failures are bounded at 3 Gemini calls/day and a 429 costs no Gemini call — bounded, not a new spend path.

## Founder triage notes
All 7 findings accepted and fixed by the coordinator (0 false alarms). Accepted by
the founder 2026-09-26.
