---
reviewed_at: 2026-09-16T00:00:00+05:30
staged_against: 247d945d1ba0
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
---

# Code Review — cron-ai-removal (247d945d1ba0)

## Finding 1 — P1 — blast_radius_mismatch
- **file:line:** `supabase/functions/future-prediction/index.ts` (whole file, this batch's commits `5b8d96be`, `3df63d73`, `593094e3`, `0f9033f3`), `supabase/functions/future-prediction/trend.ts` (new file)
- **claim:** `future-prediction` appears to have **zero current callers anywhere in the shipped app** — not the client, not a cron job. `lib/core/constants/app_constants.dart:26` declares `futurePredictionFunction = 'future-prediction'` but that constant is never referenced again anywhere in `lib/`. It is not in `docs/operations/CRON_REGISTRY.md`, and no `supabase/migrations/*.sql` schedules it via `pg_cron`. Meanwhile the two places that actually build what the user sees as the "90-day prediction" — `lib/core/services/prediction_service.dart`'s `regeneratePrediction()` (manual/PRO-monthly refresh) and `lib/features/onboarding/providers/onboarding_provider.dart`'s onboarding-completion prediction (every new signup) — both call `AiService.instance.predict(prompt, context)`, which routes through `ai-proxy`'s **separate, untouched, still-Gemini-calling** "predict" path with its own hand-written prompt ("Be specific with numbers but realistic — Reply in plain English... DO NOT return JSON"). That code was not touched by this batch at all. If this reading is correct, roughly a quarter of this batch's commits (the real-trend-math rewrite, the zero-schedule-history fix, the IST-vs-UTC schedule-probe fix, and their 3 diagnose-docs) were spent hardening a function that nothing in the app calls, while the highest-frequency prediction generator in the whole app (every onboarding completion) is untouched and still makes an uncapped Gemini call — directly contradicting this batch's own stated motivation (a production 429 quota-exhaustion incident from Gemini calls in the proactive-notification surface).
- **verification:**
  `grep -rn "futurePredictionFunction" lib/` → only the declaration at `app_constants.dart:26`, no call site.
  `grep -rn "future-prediction" lib/ test/` → only that same declaration plus one unrelated deploy-config test entry (`test/contracts/runbook_deploy_verify_jwt_test.dart:60`).
  `grep -n "future-prediction" docs/operations/CRON_REGISTRY.md` → no match.
  `grep -rln "future-prediction" supabase/migrations/*.sql` → no match.
  `grep -n "AiService.instance.predict" lib/core/services/prediction_service.dart lib/features/onboarding/providers/onboarding_provider.dart` → both call sites confirmed, both independent of `future-prediction`.
- **suggested-fix:** Before trusting this batch's `future-prediction` work as having reduced live Gemini pressure, confirm with the founder whether `future-prediction` is genuinely dead (candidate for deletion, or for actually wiring up in place of the `AiService.instance.predict()` calls) or whether there's a caller this grep missed (e.g. a webhook, an admin tool, a not-yet-shipped client release). If it's dead, the 429-quota-reduction goal for the *prediction* surface specifically is unmet — `prediction_service.dart` and `onboarding_provider.dart`'s Gemini calls are the ones actually firing on every user action and are outside this batch's scope entirely.
- **status:** accepted — presented to founder with 4 options; founder chose to leave this batch's future-prediction work as-is (real, harmless improvement regardless of reachability) and defer the wire-up-vs-delete decision. Tracked as **OI-210**, not fixed in this batch — this is a product-scope decision, not a code defect this batch's own diff introduced.

## Finding 2 — P1 — missing_input / asserted_fixture_value
- **file:line:** `supabase/functions/future-prediction/trend.ts:32-40` (`predictWeight`), `:42-50` (`predictLift`)
- **claim:** Neither `predictWeight` nor `predictLift` clamps its linear-regression output to any physiologically sane range. A short, noisy-but-entirely-plausible history extrapolates to a nonsensical 90-day forecast. This is a real regression from BOTH things it replaced: the old Gemini prompt explicitly instructed "Be realistic and conservative — do not over-promise," and the preserved static-formula fallback (`weightFallback = current + (target-current)*0.3`) can never leave the current↔target range. The new regression path has no such guard in either direction.
- **verification:** Ran the real, in-tree `predictWeight`/`predictLift` against two realistic fixtures via `deno run --allow-read` on a standalone probe importing `supabase/functions/future-prediction/trend.ts` directly:
  - 5 weigh-ins over 14 days, 70kg → 65kg (a plausible bad-week/illness dip, satisfies both the `rows.length>=5` and `span>=14 days` gates that route it into the regression instead of the fallback): `predictWeight` → **32.2 kg** as the "90-day forecast."
  - 2 PR rows 8 days apart, 100kg → 80kg (satisfies `rows.length>=2` and `span>=7 days`): `predictLift` → **-145 kg** — a negative predicted squat/bench/deadlift.
  Reproduce with:
  ```ts
  import { predictWeight, predictLift } from "./supabase/functions/future-prediction/trend.ts";
  console.log(predictWeight([
    { date: "2026-08-01", weight_kg: 70 }, { date: "2026-08-04", weight_kg: 68.7 },
    { date: "2026-08-08", weight_kg: 67.2 }, { date: "2026-08-11", weight_kg: 66.0 },
    { date: "2026-08-15", weight_kg: 65.0 },
  ], 999));
  console.log(predictLift([
    { completed_at: "2026-08-01T00:00:00Z", weight_kg: 100 },
    { completed_at: "2026-08-09T00:00:00Z", weight_kg: 80 },
  ], 999));
  ```
  (run with `deno run --allow-read <file>`)
- **suggested-fix:** Clamp both outputs to a sane band before returning — e.g. `predictWeight` to something like `[currentWeight * 0.5, currentWeight * 1.5]` (or simply refuse to move more than N% from the last observed value over 90 days) and `predictLift` to `[0, lastObservedPR * <reasonable multiplier>]`. Given Finding 1, this is lower real-world urgency than it looks, but the code is shipped and deployed regardless of whether it's currently reachable, and any future wiring-up of this path (or a direct authenticated POST) would surface it immediately.
- **status:** fixed — `predictWeight` clamped to `[lastWeight*0.7, lastWeight*1.3]`, `predictLift` to `[0, lastLift*2.0]`, both relative to the last observed row rather than a hardcoded absolute. `docs/diagnoses/2026-09-16-future-prediction-unbounded-regression-forecast-b2f7c4.md`, commit `2d6738c7`. 2 new regression tests using this review's exact fixtures; mutated (reverted both clamps) and re-ran — reddened exactly the 2 new tests, reproducing the cited -145kg.

## Finding 3 — P2 — writer_reader_drift
- **file:line:** `docs/sot_registry.yaml:9841-9853` (concept `notification_cron_eligibility_and_pro_gate`, description prose)
- **claim:** The concept description still reads: *"Removing it from the TITLE alone is insufficient — it must also leave the Gemini userState, or the model narrates the stale PR into the body."* — describing streak-guardian's old Gemini-based composition. This batch's own `6200dbb5` removed the Gemini call (and the `userState` object) from streak-guardian entirely (confirmed: `grep -c "userState\|geminiChat" supabase/functions/streak-guardian/index.ts` → 0). The sentence is now factually wrong about the current code, and it sits in the exact area this batch spent 3 commits (`bd543f34`, `f57e8339`, `97fc6594`) sweeping for stale Gemini references — but in a sibling concept block (`notification_cron_eligibility_and_pro_gate`) rather than the one that was actually swept (`llm_prompt_input_sanitization`, same file, ~200 lines earlier).
- **verification:** `sed -n '9841,9853p' docs/sot_registry.yaml` shows the "Gemini userState" sentence; `grep -c "userState\|geminiChat" supabase/functions/streak-guardian/index.ts` returns `0` on the current branch tip.
- **suggested-fix:** Update the prose to describe the current template-only composition (e.g. "recent_pr_exercise is banned from this function's message.ts inputs entirely" instead of the Gemini-userState framing), matching the correction already applied to `llm_prompt_input_sanitization` elsewhere in the same file.
- **status:** fixed — prose corrected in `docs/sot_registry.yaml`, commit `2f0203d1`. No diagnose-doc (no test asserts on this prose; pure documentation-accuracy correction, no runtime behavior involved).

## Finding 4 — P3 — missing_input
- **file:line:** `scripts/check_sot_registry_parity.dart:140-141` (blockRegex)
- **claim:** The gate's only `line_range:` parser is `RegExp(r'file:\s*([^\n]+)\n\s*line_range:\s*(\d+)-(\d+)(?:\n\s*method:\s*([^\n]+))?')` — it requires a **dash-separated range**. Any registry entry written as a bare number (`line_range: 214`, no dash) never matches this regex and is silently skipped by the stale-citation check entirely. There are 30 such bare-number entries in `docs/sot_registry.yaml` today, including `docs/sot_registry.yaml:9882` (`streak-guardian/index.ts`, `line_range: 214`, method `streakDays`) which is genuinely stale — the actual `const streakDays = user.current_streak_days as number;` statement is at `streak-guardian/index.ts:264` today (and was already at line 266 on `main` before this branch, so this predates the batch — but it means `dart run scripts/check_sot_registry_parity.dart` cannot be trusted to have verified any of this batch's own SoT-registry citation cleanup for entries written in this format, since it structurally can't see them.
- **verification:**
  `grep -cE "^\s*line_range:\s*[0-9]+\s*$" docs/sot_registry.yaml` → 30.
  `grep -n "const streakDays" supabase/functions/streak-guardian/index.ts` → line 264.
  `dart run scripts/check_sot_registry_parity.dart` → reports `PASS — 0 errors`, i.e. does not flag the above.
- **suggested-fix:** Extend the parser to also accept a bare `line_range: N` as a 1-line range (`N-N`), the same way the file already handles single-line `line: N` inline maps elsewhere. Separately, correct `docs/sot_registry.yaml:9882` to `line_range: 264`.
- **status:** partially fixed — the one entry this finding concretely verified as stale (`streak-guardian/index.ts` `line_range: 214`→`264`) was corrected directly, commit `2f0203d1`. The parser-widening half was DRAFTED and then reverted: it's a repo-wide pre-commit gate that runs unconditionally on every commit (`scripts/pre-commit.sh:324`, not in the case-skip allowlist); widening it surfaces 14 MORE stale citations across subsystems this batch never touched (auth, sync, notification-inbox, day-rollover), none introduced or worsened by this batch, and landing it half-done would fail pre-commit for every future commit repo-wide until all 14 are cleared. Filed as **OI-209** rather than folded into this batch (precedent: OI-207, same shape).

## Finding 5 — P3 — guard_without_its_mirror
- **file:line:** `supabase/functions/proactive-coach-promotion/congrats.ts:71-75` (`composeCongrats`), `index.ts:112,117` (call site)
- **claim:** The comment above the deterministic variant-index formula claims: *"Deterministic default when the caller doesn't pin one: stable across repeat calls for the same rank-up (keyed on rank code + workout count, not a clock or RNG, so a retry never surfaces a different message)."* This isn't strictly true: `total_workouts_done` is read fresh from `user_progress` on every invocation via `loadUserContext` (`index.ts:112`), not pinned to the `rank_promotions` trigger payload. If the underlying `pg_net` dispatch genuinely retries the SAME promotion event (network hiccup, timeout) after the user has logged another workout in the interim, `idx = (rankCode.length + ctx.total_workouts_done) % 3` can select a *different* variant than the first attempt — contradicting the comment's literal claim. Impact is cosmetic only (a different but equally-approved copy variant, not a duplicate/incorrect send), and the new determinism test (`index_test.ts:44-48`) doesn't exercise this because both calls in it reuse the identical `CTX` object.
- **verification:** `sed -n '58,76p' supabase/functions/proactive-coach-promotion/congrats.ts` shows the comment and formula; `grep -n "total_workouts_done" supabase/functions/proactive-coach-promotion/index.ts` shows it's populated by a live `user_progress` read, not the trigger payload.
- **suggested-fix:** Either soften the comment to "stable within a single invocation, not guaranteed identical across a genuine retry if the user's stats changed in between" or, if true cross-retry idempotency is wanted, thread `rank_promotions.id` (or the trigger's `achieved_at`) into the variant-index formula instead of a value that can change between retries.
- **status:** fixed — comment softened to accurately describe the live-read behavior, no functional change (impact remains cosmetic-only, matches the P3 rationale for not threading a new id through). `supabase/functions/proactive-coach-promotion/congrats.ts`, commit `2f0203d1`.

## Finding 6 — P3 — writer_reader_drift (minor)
- **file:line:** `supabase/functions/morning-alert/index.ts:106`
- **claim:** `const CONCURRENCY = 20; // Parallel AI calls within each chunk` — this comment is now stale. This batch's `aa4c827f` removed the only AI (Gemini) call `generateAndStoreAlert` used to make; `CONCURRENCY` now bounds parallel Hive-free template composition and (in `deliverAlerts`) push/Telegram delivery, not "AI calls." Trivial, but it's exactly the class of stale-comment drift this same batch caught and fixed several instances of elsewhere in this file (e.g. the `fetchProUserIds` comment a few lines below, which this batch *did* correct in the same diff).
- **verification:** `git diff main...cron-ai-removal -- supabase/functions/morning-alert/index.ts | grep -n "CONCURRENCY"` shows no hunk touching that line — it's untouched context, still reading "Parallel AI calls within each chunk" on the current branch tip.
- **suggested-fix:** Reword to `// Parallel alert composition + delivery within each chunk` or similar.
- **status:** fixed — exactly the suggested wording applied. `supabase/functions/morning-alert/index.ts`, commit `2f0203d1`.

## Lenses checked with no findings

- **function_exception_swallow** — no `.functions.invoke(` call sites anywhere in this diff (it's entirely Supabase Edge Function / Deno-side code, not client Flutter code); N/A for this branch. `git diff main...cron-ai-removal | grep -c "functions.invoke("` → 0.
- **secrets_in_tree** — swept the full branch diff for `sk-`, `rzp_live_`, `AKIA`, `-----BEGIN`, and bare JWT-shaped tokens; zero matches. `git diff main...cron-ai-removal | grep -nE "sk-[A-Za-z0-9]{10,}|rzp_live_|AKIA[0-9A-Z]{10,}|-----BEGIN|eyJhbGciOi[A-Za-z0-9_-]{10,}"` → no output.
- **unawaited_no_error_sink** — no `unawaited(` call sites in this diff (Dart-specific pattern; this branch touches no `lib/` files). `git diff main...cron-ai-removal | grep -c "unawaited("` → 0.
- **blast_radius_mismatch (tier itself)** — recomputed independently via the documented invocation (`git diff main...cron-ai-removal --name-only | dart run scripts/blast_radius_from_diff.dart -`) → `platform`, matching the branch's own claim. (Finding 1 above is a *different* blast-radius concern — real-world reachability of the changed code, not the classifier's tier.)
- **guard_without_its_mirror (prefs-before-dedup ordering)** — all 6 cron functions that gate on both a notification preference and a once-per-day dedup slot (`pr-detection`, `plateau-alert`, `protein-gap-alert`, `re-engagement`, `streak-guardian`, `workout-window-closing`) consistently check the preference FIRST and the dedup gate SECOND, so an opted-out user never burns their one proactive slot on a push that gets discarded. Verified by reading all 9 `index.ts` files directly; no function in this batch got the order backwards.
- **asserted_fixture_value (Deno + Flutter test suites)** — ran both test suites for real rather than trusting the batch's stated counts: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/` → **513 passed, 0 failed** (matches the batch's claim exactly); `flutter test test/contracts/proactive_coach_promotion_test.dart test/contracts/streak_guardian_eligibility_test.dart` → **29 passed** (the two files most affected by this batch's extraction fixes). Also independently re-derived the arithmetic in `future-prediction/index_test.ts`'s `generateLocalPrediction` fallback test (`78.5` = `80 + (75-80)*0.3`; `10` = `min(4>=4?10:8,13)`) — both correct. Also ran `deno check --node-modules-dir=none` on all 9 touched `index.ts` files plus the untouched `evaluate-rank-promotions/index.ts` (the other caller of the shared `rank_engine.ts` this batch edited) — all type-check clean, confirming the `_shared/rank_engine.ts` extraction (`completionRateOverWindow`'s inline date computation → the new exported `windowSinceDateUtc` helper) is behaviourally byte-identical for the untouched caller.

## Founder triage notes

All 6 findings independently re-verified against live code before acting
(not trusted from the review's prose) — every `verification` command above
was re-run, plus the two P1 fixtures were reproduced exactly via
`deno run`/`deno test` before any code changed.

- **Finding 1** (future-prediction reachability): presented to founder with
  4 options via AskUserQuestion. Founder chose to leave this batch's
  future-prediction work as-is and defer the wire-up-vs-delete decision.
  Tracked as **OI-210**.
- **Finding 2** (unbounded regression forecast): fixed. `b2f7c4`,
  commit `2d6738c7`.
- **Finding 3** (stale Gemini-userState prose): fixed, commit `2f0203d1`.
- **Finding 4** (parser blind spot + stale citation): the one concretely
  verified stale entry fixed directly (commit `2f0203d1`); the parser
  widening was drafted, found to surface 14 unrelated pre-existing
  violations across subsystems this batch never touched, reverted, and
  filed as **OI-209** rather than shipped half-done against a gate that
  runs unconditionally on every commit repo-wide.
- **Finding 5** (variant-selection comment): fixed, commit `2f0203d1`.
- **Finding 6** (stale CONCURRENCY comment): fixed, commit `2f0203d1`.

Verdict: **accepted**. 4 of 6 findings fixed directly in this batch; 2
(Findings 1 and 4) resolved via an explicit founder decision + OI filing
rather than an in-batch code fix, since both are genuinely out of this
batch's scope (a product-reachability question and a repo-wide,
unrelated-subsystem gate gap respectively) rather than defects this
batch's own diff introduced.
