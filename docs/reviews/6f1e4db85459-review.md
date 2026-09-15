---
reviewed_at: 2026-09-16T01:10:00+05:30
staged_against: 6f1e4db85459
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 3
verdict: pending
---

# Code Review — 6f1e4db85459

Batch: `apk43-obs-fixes` — Obs 1 (nutrition save-meal silent-catch telemetry,
diagnose `d8e2f4`) + Obs 2 (AI coach history-poisoning hard-failure flag,
diagnose `a1c6b9`). Blast radius computed via
`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
→ **platform** (driven by `supabase/functions/ai-proxy/**` and
`supabase/functions/_shared/**`, both pinned `platform` in
`docs/blast_radius.yaml:54,61`; `error_telemetry.dart` alone is `account`,
`lib/features/nutrition/**` alone is `feature` — consistent with the
diagnose-docs' own self-declared tiers, `account` for Obs 1 / `platform` for
Obs 2).

## Finding 1 — P1 — guard_without_its_mirror

- **file:line:** `supabase/functions/_shared/tool-loop.ts:500-513` (mirror of
  the fixed site at `:269-272`); `supabase/functions/ai-proxy/index.ts:1120,1161`
  (the two places `hadHardFailure` gates replay/embed)
- **claim:** `hadHardFailure` is set `true` in exactly ONE of the file's TWO
  hardcoded, non-model apology paths — the one triggered when a Gemini API
  call itself throws (`catch (e)` at `:257`, apology set at `:270`, flag set
  at `:271`). The OTHER hardcoded apology — set when `runToolLoop` exhausts
  `MAX_ROUNDS` (3) without ever producing a terminal text response AND
  without queuing any write intent (`:508-512`: `"Recruit — I had trouble
  pinning that down. Try asking again with a bit more specificity..."`) —
  never sets `hadHardFailure`. This is a documented, pre-existing code path
  (see the function's own header comment at `:30-32`), not something this
  diff invents, but this diff introduces the exact mechanism ("mark a
  hardcoded apology so it can't replay into history / get embedded") that
  this second apology also needs and does not get. Concretely: if this path
  fires, `ai-proxy` still returns HTTP 200 with `had_hard_failure: false`
  (`index.ts:1161` — the flag stays `false` because `loop.hadHardFailure`
  was never set), the client's `AiChatResponse.hadHardFailure` parses to
  `false`, `updateInteractionWithResponse` writes `entry['failed'] = false`,
  `recentHistoryExchanges`'s `map['failed'] == true` filter does NOT exclude
  it, and it gets replayed into the user's next-turn history exactly as a
  genuine model reply would — the identical self-perpetuation shape this
  batch's diagnose-doc `a1c6b9` documents for the OTHER apology (model
  "echoed the apology as if it were a normal continuation"). The
  semantic-memory embed guard at `index.ts:1120`
  (`!loop.hadHardFailure && (cleanReply.trim().length > 0 || ...)`) is
  equally blind to it — this apology text (non-empty, `intents.length===0`)
  gets embedded into `memory_embeddings` too, so a future retrieval pass can
  surface it back into the system prompt, which is precisely the "one layer
  further out" risk the diff's own `index.ts:1116-1119` comment calls out
  for the OTHER apology.
  Also note the response-body comment at `index.ts:1158-1160` — *"true when
  `reply` is the hardcoded **exhaustion** apology"* — is itself imprecise:
  `hadHardFailure` is true for the Gemini-call-**failure** apology, not the
  loop-**exhaustion** apology (which is the literal text this comment's own
  word "exhaustion" better describes). The comment's wording is exactly the
  kind of thing that would make a future reader assume this case is already
  covered.
- **verification:** `grep -n "I had trouble" supabase/functions/_shared/tool-loop.ts`
  → two distinct hardcoded strings, one at `:270` (flagged) and a second,
  differently-worded one at `:511` (`"Recruit — I had trouble pinning that
  down..."`, unflagged). No Deno test exercises the `MAX_ROUNDS`-exhausted /
  zero-intents / zero-error path at all — confirmed by reading
  `tool-loop_hard_failure_flag_test.ts` (3 cases: always-fail-fetch,
  happy-path, FC2 queued-intent-then-fail) and the pre-existing
  `tool-loop_intent_apology_test.ts` / `tool-loop.test.ts` (neither touches
  `runToolLoop`'s post-loop fallback text at all). Also reproduced the
  DIFFERENT (already-fixed) mirror case myself: reverted `tool-loop.ts:271`
  (`hadHardFailure = true;` → deleted) and re-ran
  `deno test --no-check --allow-all --node-modules-dir=none
  supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts` — reddened
  exactly 1 of 3 with `Expected: true / Actual: false`, matching the
  diagnose-doc's own mutation claim exactly (restored; hash unchanged,
  confirmed via `git diff --cached | git hash-object --stdin` ==
  `6f1e4db854591364c07e7c216910a9b4abd65f62` before and after).
- **suggested-fix:** set `hadHardFailure = true` in the `if (!finalText)` /
  `else` branch at `tool-loop.ts:508-512` (the no-intents, rounds-exhausted
  arm) as well — mirroring the same "this text is not real model output"
  semantics the Gemini-call-failure branch now carries. The `intents.length
  > 0` arm right above it (`:505-507`, "Copy that, Recruit — I've queued
  that below...") is legitimately real/positive and should stay unflagged.
- **status:** accepted — fixed in-batch. `tool-loop.ts:520` now sets
  `hadHardFailure = true` in exactly the suggested branch (the
  `intents.length > 0` arm above it stays untouched). Added a 4th Deno test
  (`tool-loop_hard_failure_flag_test.ts`, the `installAlwaysReadToolCallFetch`
  scenario) driving `runToolLoop` through a real `maxRounds`-exhausted,
  zero-intent, zero-terminal-text path via a read-only tool call
  (`getFormCues`) on every round. Mutation-proven independently: deleting
  ONLY the new `hadHardFailure = true;` line reddened exactly the new test
  (`Expected: true / Actual: false`), the other 3 (incl. the original
  catch-block positive control) stayed green — confirms the two apology
  sites are independently covered, not accidentally aliased. `docs/diagnoses/
  2026-09-16-coach-history-poisoning-hard-failure-a1c6b9.md` updated to
  document both sites + this finding.

## Finding 2 — P3 — asserted_fixture_value (diagnose-doc citation accuracy)

- **file:line:** `docs/diagnoses/2026-09-16-coach-history-poisoning-hard-failure-a1c6b9.md:37-38`
  (frontmatter: `cloud_table: ai_coach_interactions`, `cloud_columns:
  [ai_response, failed]`)
- **claim:** the diagnose-doc's frontmatter claims `failed` is one of the two
  affected cloud columns on `ai_coach_interactions`, but that table has no
  `failed` column at all. Live schema snapshot
  `backups/live_schema_columns.json` → `tables.ai_coach_interactions` =
  `[id, user_id, snapshot_id, channel, user_message, ai_response, model_used,
  tokens_used, was_helpful, created_at, summarized, tool_calls]` — no
  `failed`. Confirmed independently by reading the actual writer/reader code:
  `sync_coach.dart`'s `_syncCoachInteractions` upsert body (`:149-157`) never
  includes `failed`, and `_restoreCoachInteractions`'s Hive-row reconstruction
  (`:204-217`) never sets it either — so a cloud-restored row has no `failed`
  key and is (correctly, since it was never actually a hard-failure turn from
  the *restoring* device's perspective, and there is no cloud data to
  recover it from) treated as not-failed by `recentHistoryExchanges`'s
  `map['failed'] == true` filter. `failed` is Hive-local only. The
  **`docs/sot_registry.yaml` entry itself does not make this claim** — its
  writer/reader description for `coach_chat_history_replay` stays entirely
  within `CoachInteractionRepository` (Hive) and never asserts a cloud
  column — so this is scoped to the diagnose-doc's frontmatter only, not a
  registry error, and does not affect the fix's actual correctness (which is
  Hive-only and verified correct — see the green mutation run under Finding
  1's verification / the main report).
- **verification:** `python3 -c "import json; d=json.load(open('backups/live_schema_columns.json')); print(d['tables']['ai_coach_interactions'])"`
  → column list above, no `failed`. `grep -n "'failed'" lib/core/services/sync/sync_coach.dart`
  → zero hits.
- **suggested-fix:** correct the diagnose-doc's frontmatter to
  `cloud_columns: [ai_response]` (drop `failed`), or add a one-line note that
  `failed` is Hive-local-only and never synced. Cosmetic/documentation only —
  no code or test change needed.
- **status:** accepted — fixed in-batch. Corrected to `cloud_columns:
  [ai_response]`; added an explicit `tier: 3 "Postgres schema"` entry to
  `touched_layers_checked` stating `failed` is Hive-local only, citing
  `backups/live_schema_columns.json`.

## Finding 3 — P3 — asserted_fixture_value (vacuous negative control)

- **file:line:** `test/contracts/ai_breakdown_notifier_save_meal_telemetry_test.dart:91-111`
  (test: *"saveMeal does NOT call ErrorTelemetry.recordNonFatal when no
  exception is thrown (negative control)"*)
- **claim:** this negative control sets no `AiBreakdownData` state, so
  `saveMeal` short-circuits at `nutrition_provider.dart:936-938`
  (`if (data == null) return WriteResult.noState();`) — a return that
  happens *before* the `try` block the Obs-1 fix touches, and that existed,
  unchanged, long before this batch. The test therefore proves only that the
  telemetry hook doesn't fire on a path that structurally can't reach it
  either way, regardless of whether `ErrorTelemetry.recordNonFatal` were
  wired up at all, removed entirely, or even if `saveMeal` didn't exist —
  the sharper "would this pass if the feature did nothing at all?" question
  from the skill's lens-8 method answers yes. No test anywhere in this diff
  (or in the complementary `test/features/nutrition/ai_breakdown_save_confirmation_test.dart`,
  whose fake notifiers override `saveMeal` wholesale and so never reach the
  real catch block either — confirmed by that file's own header note, which
  this diagnose-doc also cites) exercises the actually-relevant negative
  case: state IS set, `logMeal` succeeds WITHOUT throwing — does
  `recordNonFatal` correctly stay silent on the real success path through
  the real try block? Low severity because the call is textually only
  reachable inside the `catch` block (`nutrition_provider.dart:990-991`), so
  there is no live risk of over-firing, only an untested claim.
- **verification:** read `nutrition_provider.dart:934-963` — two early
  returns (`data == null` at `:936`, `items.isEmpty` at `:960`) both precede
  the `try` at `:965`; the negative-control test only exercises the first.
  `grep -rln "throwBeforeLogMealForTest" test/` confirms only this one test
  file uses the fault-injection seam, and it never exercises a
  state-present, non-throwing path.
- **suggested-fix:** add a third case (or extend the existing negative
  control) that sets real `AiBreakdownData` state, leaves
  `throwBeforeLogMealForTest` null, and — if a lightweight way to make
  `NutritionWriteService.instance.logMeal` succeed in this harness doesn't
  already exist elsewhere in the test suite — at minimum re-label the
  existing test's name/comment to say what it actually proves (the no-state
  early return doesn't fire telemetry), rather than "no exception is thrown"
  which reads as covering the try/catch's happy path.
- **status:** accepted — fixed in-batch. Relabeled the original test
  "(early-return control, no try block reached)" and added a third test in
  a new `group('real Hive — REAL NutritionWriteService.instance.logMeal')`
  reusing `test/nutrition_write_service/helpers/nws_test_setup.dart` (the
  same real-Hive helper the `NutritionWriteService` unit suite already
  uses) — real state, real successful save, asserts an `nlog_*` row landed
  AND the telemetry hook never fired. Mutation-proven: moved the
  `recordNonFatal` call to fire unconditionally right after entering the
  `try` block — reddened exactly the new test (`Expected: false / Actual:
  <true>`), the other 2 stayed green.

## Lens-by-lens notes (clean lenses, method shown)

- **writer_reader_drift** — traced the full `failed` (Hive) ↔
  `had_hard_failure` (JSON) pipeline hop-by-hop and verified every citation
  against the actual line numbers: `tool-loop.ts:114` (field decl),
  `:271` (set true), `ai-proxy/index.ts:1161` (`had_hard_failure:
  loop.hadHardFailure`) and `:1120` (embed guard), `ai_service.dart:41`
  (field decl) / `:316` (`data['had_hard_failure'] as bool? ?? false`
  parse), `coach_interaction_repository.dart:202-228`
  (`updateInteractionWithResponse`, writes `entry['failed'] =
  hadHardFailure`) and `:297-347`/`:315` (`recentHistoryExchanges`'s
  pre-existing `map['failed'] == true` filter, unchanged). All match. Grepped
  `ai_coach_provider.dart` for `hadHardFailure:` → exactly 3 call sites
  (`:677` media path uses `aiResponse.hadHardFailure`, `:910` primary chat
  uses `aiResponse.hadHardFailure`, `:980` auth-retry uses
  `retryResponse.hadHardFailure` — NOT `aiResponse.hadHardFailure`, correct,
  confirmed by reading the surrounding function body). `ai_coach_repository.dart`'s
  shim forwarder passes `hadHardFailure` through unchanged. Only drift found
  is Finding 2 (a documentation claim, not a code/data drift). See Finding 1
  for the one real gap this lens's method (name every writer + reader) led
  to, filed under `guard_without_its_mirror` instead since it's a missing
  SIGNAL, not a name/shape mismatch.
- **function_exception_swallow** — zero `.functions.invoke(`/`callFunction(`
  call sites are touched anywhere in this diff:
  `git diff --cached | grep -n "functions.invoke\|callFunction("` → no
  output. Nothing to check.
- **blast_radius_mismatch** — computed tier (platform) matches the
  diagnose-docs' self-declared tiers per-file (`account` for the
  `error_telemetry.dart`-touching Obs 1 diff alone, `platform` for the
  `ai-proxy`/`_shared`-touching Obs 2 diff) and the combined staged diff.
  `docs/blast_radius.yaml:54` (`ai-proxy/**` → platform), `:61`
  (`_shared/**` → platform), `:247` (`error_telemetry.dart` → account),
  `:316` (`nutrition/**` → feature) all read directly, not inferred. Obs 2's
  own diagnose-doc correctly marks tier 6 (Edge Function deploy) as
  `not_applicable` — server code is changed but NOT yet deployed, live prod
  apply needs its own explicit go per CLAUDE.md §4.3, consistent with what's
  actually in this diff. The one thing under-scrutinized for a platform-tier
  fix is exactly Finding 1 — a second code path with the identical
  blast-radius-affecting symptom left unaddressed.
- **secrets_in_tree** — `grep -rn "rzp_live_\|sk-\|AKIA\|-----BEGIN\|SERVICE_ROLE_KEY\s*=\s*['\"]\|eyJhbGciOi" <staged files>` →
  no hits. The Deno test file's `Deno.env.set("GEMINI_API_KEY",
  "test-key-not-a-real-secret")` is an explicitly-labeled placeholder, not a
  real credential.
- **unawaited_no_error_sink** — one new `unawaited(` call in the diff
  (`nutrition_provider.dart:990`, `unawaited(ErrorTelemetry.recordNonFatal(...))`).
  Read `recordNonFatal`'s full body (`error_telemetry.dart:231-317`): both
  its Crashlytics leg and its `log-client-error` POST leg are individually
  wrapped in `try { } catch (_) { }`, and its own doc comment states "Fire-
  and-forget — never throws." A declared, self-contained error sink — safe
  to `unawaited`. No other `unawaited(`/`.logEvent(`/`.recordNonFatal(` call
  sites are touched by this diff.
- **missing_input** — `debugOnRecordNonFatalForTests` mirrors
  `debugOnLogEventForTests`'s exact pattern (nullable static function field,
  checked-and-early-returned as the first line of the real method,
  `@visibleForTesting`, doc comment says "reset in setUp/tearDown") —
  confirmed by reading both definitions and both call sites side-by-side.
  `throwBeforeLogMealForTest` is a plain nullable static field, null-checked
  once at the top of the `try` block; in production it is always null (no
  test-only import reaches it), so it changes behavior in NO path other than
  a test that explicitly sets it — confirmed by `grep -rln
  "throwBeforeLogMealForTest" lib/` returning only the one definition site.
  Both seams are reset in `setUp` AND `tearDown` of the one test file that
  uses them (`ai_breakdown_notifier_save_meal_telemetry_test.dart:35-43`),
  and `grep -rln "debugOnRecordNonFatalForTests\|throwBeforeLogMealForTest"
  test/` confirms no OTHER test file references either seam, so there is no
  cross-file leak risk even beyond the reset discipline (flutter test runs
  each file in its own VM isolate).
- **asserted_fixture_value** — see Findings 2 and 3. Everything else
  checked: the `(a)`/`(b)`/`(c)`/`empty`/`excludeKey`/`Hermes P2`/`server
  reader seam`/`provider threads history` tests in
  `coach_chat_history_replay_writer_to_reader_test.dart` are pre-existing
  (confirmed via `git diff --cached` on that file — only ONE new test block
  was added, the APK +43 obs 2 case at `:199-257`); its literal expected
  values (exact apology string, `pending:false`/`failed:true`/`error_text:
  null`) were checked against the actual `updateInteractionWithResponse`
  body and match exactly. `ai_service_had_hard_failure_parse_test.dart`'s 3
  literals (`true`→`true`, `false`→`false`, missing→`false`) were checked
  against `_buildResponse`'s exact parse expression
  (`data['had_hard_failure'] as bool? ?? false`) and match. None of these
  tests depend on shared mutable/live state — all use isolated temp Hive
  dirs or pure static calls.

## Verification run (this review, pre-fix)

- `flutter test test/contracts/ai_breakdown_notifier_save_meal_telemetry_test.dart
  test/features/nutrition/ai_breakdown_save_confirmation_test.dart
  test/contracts/coach_chat_history_replay_writer_to_reader_test.dart
  test/ai_coach/ai_service_had_hard_failure_parse_test.dart` → **17/17
  passed** (2 + 3 + 9 + 3).
- `deno test --no-check --allow-all --node-modules-dir=none
  supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts` → **3/3
  passed**.
- `deno check --node-modules-dir=none supabase/functions/_shared/tool-loop.ts
  supabase/functions/ai-proxy/index.ts` → clean, both files.
- `flutter analyze` on all 6 touched Dart files → 1 pre-existing `info`
  (`depend_on_referenced_packages` on an untouched `import 'package:meta/meta.dart';`
  line in `ai_coach_repository.dart`), zero warnings/errors.
- Reproduced two of the diagnose-docs' own mutation claims independently
  (not merely re-read from prose): (1) removed `hadHardFailure = true;` from
  `tool-loop.ts:271` → reddened exactly 1/3 Deno tests
  (`Expected: true / Actual: false`); (2) reverted
  `entry['failed'] = hadHardFailure;` to `entry['failed'] = false;` in
  `coach_interaction_repository.dart:225` → reddened exactly 1/9 Dart tests,
  with the apology text visibly leaking into `recentHistoryExchanges()`'s
  output at index `[0]`. Both restored; `git diff --cached | git
  hash-object --stdin` confirmed identical to the original staging hash
  (`6f1e4db854591364c07e7c216910a9b4abd65f62`) before writing this file.

## Post-triage verification (all 3 findings fixed same session)

- `flutter test test/contracts/ai_breakdown_notifier_save_meal_telemetry_test.dart
  test/features/nutrition/ai_breakdown_save_confirmation_test.dart
  test/contracts/coach_chat_history_replay_writer_to_reader_test.dart
  test/ai_coach/ai_service_had_hard_failure_parse_test.dart` → **18/18
  passed** (3 + 3 + 9 + 3, +1 for the new real-Hive negative control).
- `deno test --no-check --allow-all --node-modules-dir=none
  supabase/functions/_shared/tool-loop_hard_failure_flag_test.ts` → **4/4
  passed** (+1 for the loop-exhaustion `hadHardFailure` case).
- `deno check --node-modules-dir=none supabase/functions/_shared/tool-loop.ts
  supabase/functions/ai-proxy/index.ts` → clean, both files.
- Both new tests mutation-proven independently (see each finding's `status:`
  above for the exact reddening result).
- `dart run scripts/validate_diagnose_doc.dart` on both diagnose-docs → OK,
  both, after the Finding-2 correction.

## Founder triage notes
<filled in by founder during triage>
