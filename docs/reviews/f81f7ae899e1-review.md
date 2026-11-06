---
reviewed_at: 2026-09-21T12:09:03Z
staged_against: f81f7ae899e1
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
---

# Code Review — f81f7ae899e1

> Renamed FIVE times since the original review. (1) `6f688776ce48` →
> `7aff4322b5ac` after all 3 findings were fixed in place, which changed the
> staged diff's hash — see "Founder triage notes" below for the full fix
> trail. No re-review was dispatched for that rename; the fixes are the SAME
> findings' remediation, triaged and verified by the implementing session per
> this skill's §4. (2) `7aff4322b5ac` → `f52dbb8ddc2b` after the founder
> authorized this verdict and the live-apply of migrations 138/139
> ("Accept the review and apply migrations 138 and 139", 2026-09-21) — staging
> the resulting `backups/applied_migrations.json` + `backups/live_schema_columns.json`
> ledger updates changed the staged diff's hash again. No code covered by
> this review changed between the two renames; only post-apply bookkeeping
> (unrelated to any finding) was staged in between. (3) `f52dbb8ddc2b` →
> `d37b5f18b623` after a SECOND, independent B-pass round (see "Round 2"
> below) was dispatched against the full accumulated batch — including a
> self-triggered Hermes pass's own fix-round, which this file's original
> lenses never saw — and its 6 findings were fixed in place. This rename
> DOES cover new reviewed content, unlike renames (1) and (2). (4)-(5)
> `d37b5f18b623` → `86195c3cc274` → `f81f7ae899e1`, both same-day, both the
> hash-fixed-point trap this file's own 2026-09-11 entries already
> document: running the full `pre-commit.sh` gate loop regenerates and
> re-stages `docs/diagnoses/INDEX.md` / `docs/audit/OPEN_INDEX.md` /
> `docs/audit/GATE_INDEX.md`, and (separately) `docs/plan-reviews/` is NOT
> excluded from the hash the way `docs/reviews/` and this skill's own
> `SKILL.md` are — so citing this file's name from the plan-review record
> moved the hash every time the citation was corrected. Broken by moving
> the plan-review record to its OWN separate, later commit (this file's own
> 2026-09-11 "second entry today" precedent) rather than staging it
> alongside this diff at all. No reviewed code changed across renames (3)
> through (5); only generated-index content and the (now unstaged)
> plan-review record moved.

## Finding 1 — P0 — guard_without_its_mirror (+ writer_reader_drift)
- **file:line:** `lib/features/ai_coach/providers/ai_coach_provider.dart:233-237`
- **claim:** The new A2c render-time channel allowlist added to `ChatHistoryNotifier.build()` —
  ```dart
  final channel = interaction['channel'] as String?;
  if (channel != null &&
      !CoachInteractionRepository.coachChatChannels.contains(channel)) {
    continue;
  }
  ```
  reuses `coachChatChannels = {'app', 'chat', 'in_app_orphan'}` verbatim from `recentHistoryExchanges` (the reader that decides what gets replayed **to Gemini as conversation history**). That set is too narrow for this **different** reader, whose job is "what should the **user** see in their chat thread." Three currently-shipping, currently-live server-side writers insert directly into `ai_coach_interactions` with channels that are **not** in this allowlist, and whose own code comments state they are meant to be rendered in this exact chat thread via this exact restore path:
  - `supabase/functions/proactive-coach-promotion/index.ts:127` — `channel: "in_app"` — a rank-promotion congratulations message. Its own comment (lines 90-96) says an earlier draft "silently deleted the coach's congratulation **from the user's chat history**" by skipping this insert, and was fixed specifically so the chat message is *always* kept.
  - `supabase/functions/evaluate-rank-promotions/index.ts:326` — `channel: "promotion_ceremony"`. The comment immediately above the insert (lines 290-292) says, verbatim: *"The client surfaces these via `_restoreCoachInteractions → coachBox → ChatHistoryNotifier`."* That is precisely the path this new filter now blocks for this channel.
  - `supabase/functions/i-see-you-callout/index.ts:120` — `channel: "proactive_i_see_you"` — a proactive coach callout, same shape.

  Before this diff, `ChatHistoryNotifier.build()` had **no** channel filter at all, so every one of these rows rendered as an AI-only bubble (their `user_message` is `""`, so only the `aiResponse != null && aiResponse.isNotEmpty` branch fired — that branch still runs today for anything that gets past the new filter). After this diff, because `'in_app'`, `'promotion_ceremony'`, and `'proactive_i_see_you'` are not in `coachChatChannels`, the `continue;` fires and the **entire row is dropped** — silently, with no error, no telemetry, no crash. The regression test added for A2c (`test/contracts/coach_chat_history_render_channel_filter_writer_to_reader_test.dart`) only exercises `food_text_analysis` / `scan_meal` / `cart_auditor` / `weekly_report` / `null` / `in_app_orphan` — it never seeds a row with any of these three real channels, so it cannot catch this. The registry entry added for this concept (`docs/sot_registry.yaml`, `coach_chat_history_render_channel_filter`) itself states "anything else... is skipped entirely — it never belonged in the chat thread," naming only the four nutrition/report channels as examples — the three proactive channels above were never considered.
  This is the exact "guard mirrored from a narrower sibling reader, silently wrong for the broader reader it was copied onto" shape the review explicitly asked for.
- **verification:**
  ```bash
  grep -n "channel" lib/features/ai_coach/providers/ai_coach_provider.dart | sed -n '1,5p'
  grep -rn 'channel: "in_app"\|channel: "promotion_ceremony"\|channel: "proactive_i_see_you"' supabase/functions/
  sed -n '285,335p' supabase/functions/evaluate-rank-promotions/index.ts   # comment names the exact render path this filter now blocks
  grep -n "channel:" test/contracts/coach_chat_history_render_channel_filter_writer_to_reader_test.dart   # confirms in_app/promotion_ceremony/proactive_i_see_you are never seeded
  ```
- **suggested-fix:** Do not reuse `recentHistoryExchanges`'s allowlist for the render path. Either (a) invert to a **blocklist** of the known tool-output/report channels that must never render as chat (`food_text_analysis`, `scan_meal`, `cart_auditor`, `weekly_report`, and any future ones), or (b) give the render path its own, broader allowlist that is a strict superset of `coachChatChannels` and explicitly includes `in_app`, `promotion_ceremony`, `proactive_i_see_you` (and anything else that writes a user-visible proactive message to this table — worth a repo-wide grep for every distinct `channel:` literal written to `ai_coach_interactions` before picking the final set, since this review found three just by grepping the diff's own neighborhood). Add a regression test seeding a `promotion_ceremony` (or `in_app`) row and asserting it **does** render.
- **status:** accepted — fixed via option (a), a denylist (`CoachInteractionRepository.nonChatAnalysisChannels`), not (b). A repo-wide grep of every `channel:` literal written server-side (per the suggested-fix's own advice) found not just the 3 named channels but an 8th one this finding's own grep missed: `image_paywall`/`video_paywall` (`ai-media-proxy/index.ts:322,367`), plus a 9th, client-side `app_event` (`AppEventsService`) that correctly belongs on the exclude side. That asymmetry (9 legitimate channels to enumerate vs. 5 known-bad ones, and the "good" set demonstrably incomplete twice over) is why a denylist was chosen over option (b)'s allowlist. `coachChatChannels` reverted to Gemini-history-only (unchanged from before A2c). 6 new regression tests added (the 3 named here + `image_paywall`/`video_paywall`/`app`), plus an `app_event`-exclusion test and 2 rewritten source-pin tests — 16 tests total (was 7). Mutation-proof: reverted the render-path filter to the exact allowlist shape this finding describes — reddened exactly 6 of 16 (the 5 new proactive/paywall tests + 1 source-pin test), nothing else. Full detail: `docs/diagnoses/2026-09-21-coach-chat-history-channel-filter-d3f7b2.md` (updated in place with an "A2d correction" section) and `docs/sot_registry.yaml`'s `coach_chat_history_render_channel_filter` entry.

## Finding 2 — P1 — guard_without_its_mirror
- **file:line:** `scripts/gemini_retry_coverage_lib.dart:66` and `:157`
- **claim:** The new mechanical gate `check_gemini_retry_and_telemetry_coverage.dart` (shipped in this same diff to prevent exactly this class of regression) implements both of its checks as raw substring containment on the **unmodified, comment-inclusive** source text:
  - Part (a), line 66: `else if (!block.contains('retries:'))` — `block` is the raw balanced-braces slice of a `geminiChat({...})` call, comments and all.
  - Part (b), line 157: `if (catchBody != null && _telemetryMarkers.any(catchBody.contains))` — `catchBody` is the raw balanced-braces slice of a `catch (e) {...}` block, comments and all.

  Neither the lib nor the runner (`scripts/check_gemini_retry_and_telemetry_coverage.dart`, which reads both the `.ts` and `.dart` files via plain `readAsStringSync()`) strips comments before these checks. This repo has a documented, explicitly-cited recurring bug class for exactly this shape (`feedback_source_grep_strip_comments_first.md` / `feedback_green_check_input_set_width.md`), and this very diagnose-doc's own `forbidden_patterns_checked` section (`docs/diagnoses/2026-09-21-ai-failure-telemetry-gap-oi226-f7a2c9.md`) records discovering the identical failure mode live — a comment-based neuter of a **test's** `ErrorTelemetry.logEvent(...)` call left the searched substring intact and the test stayed falsely green — and explicitly says this was "documented here so a future mutation-proof on a source-grep test doesn't repeat it." That lesson was applied to the test-mutation methodology but not to the **gate's own detection logic**, which has the same defeatable shape: a future edit that deletes a real `retries: 2` argument or a real `ErrorTelemetry.recordNonFatal(...)` call but leaves behind an explanatory comment mentioning the same literal (e.g. `// removed retries: 2, see OI-NNN` or `// used to call ErrorTelemetry.logEvent here`) would make the gate report `OK` while the actual protection is gone.
  Confirmed this exact gap is not covered by the gate's own mutation-proof: `docs/audit/gate_test_ledger.yaml`'s new entry for this gate records only two mutations — forcing each of `findGeminiChatMissingRetries` / `findAiEntryPointsMissingTelemetry` to `return const []` (i.e. disabling detection entirely) — never a "leave a comment behind" partial-defeat mutation. `test/scripts/gemini_retry_coverage_lib_test.dart` likewise has no such case (grepped for `comment` — no hits).
- **verification:**
  ```bash
  sed -n '60,70p;150,162p' scripts/gemini_retry_coverage_lib.dart
  grep -n "readAsStringSync" scripts/check_gemini_retry_and_telemetry_coverage.dart   # no comment-strip step anywhere in the pipeline
  grep -n "comment" test/scripts/gemini_retry_coverage_lib_test.dart                   # no hits — the defeat case is untested
  sed -n '/check_gemini_retry_and_telemetry_coverage.dart:/,/^$/p' docs/audit/gate_test_ledger.yaml   # mutation evidence = "return const []" only
  ```
- **suggested-fix:** Strip `//` and `/* */` comments (the repo already has this exact helper inline in `test/contracts/coach_chat_history_render_channel_filter_writer_to_reader_test.dart`'s `_stripComments`, and in `test/contracts/support_contact_email_writer_to_reader_test.dart`'s pattern) from both `block` and `catchBody` before the `.contains()` checks in the gate's own lib, then add a mutation test that comments-out (rather than deletes) a `retries: 2` argument and a telemetry call and asserts the gate still fails.
- **status:** accepted — fixed exactly as suggested. Added a `stripComments()` helper (block + line comments → single space, same shape as the pattern already used elsewhere in this repo's gates) applied to the extracted `block`/`catchBody` at both call sites — never to the raw source used for brace-matching or line-number computation. 2 new tests added (one per part, exactly the "comment-out rather than delete" case suggested), now 19 total (was 17). Mutation-proof: reverted both call sites to the raw `.contains()` — reddened exactly the 2 new tests, nothing else. `docs/audit/gate_test_ledger.yaml`'s evidence block and the OI-226 diagnose-doc's Verification section both updated with the correction.

## Finding 3 — P1 — blast_radius_mismatch
- **file:line:** `supabase/migrations/139_alert_cron_failures.sql:50-80`
- **claim:** The new `alert_cron_failures` pg_cron job (runs every 15 min) counts `cron_call_log` rows with `status='failed'` OR a stuck `status='started'` over a **24-hour** lookback window, and gates re-insertion with only a **1-hour** dedup window (`NOT EXISTS (... acknowledged = false AND detected_at > now() - interval '1 hour')`), always at `severity = 'critical'` (unconditional paging via `trg_dispatch_critical_alert_notify`, no info/warn tier).
  Because the lookback (24h) is 24× longer than the dedup window (1h), a **single, already-resolved** cron failure keeps `cnt >= 1` true for the full 24 hours it remains inside the lookback window. Once the previously-inserted alert's `detected_at` ages past 1 hour (whether or not the founder ever acknowledges it — an acknowledged alert satisfies `acknowledged = false` as *false*, so it stops blocking a new insert on the very next tick after acknowledgement too), the very next 15-minute tick re-inserts a **new critical, paging** alert for the same one-off event. This repeats roughly hourly for up to 24 hours after a single incident — an alert-storm risk for exactly the kind of event (a transient cron hiccup) this system is supposed to page on sparingly.
  This is a materially worse ratio than every comparable pre-existing job this migration's own header claims to mirror ("same acknowledged-based convention the 5 existing jobs share"):
  - `alert_client_errors_spike` / `alert_edge_function_health` (migration 076): 1h / 30min lookback vs. 1h dedup — lookback ≤ dedup, so a resolved spike ages out of the lookback at roughly the same time the dedup would have allowed a repeat, largely avoiding repeat storms.
  - `alert_payment_flow_health` (migration 076): 24h lookback vs. 6h dedup — a 4:1 ratio, itself already the widest pre-existing gap, allowing up to ~4 repeats/day worst case.
  - **`alert_cron_failures` (this migration): 24h lookback vs. 1h dedup — a 24:1 ratio**, allowing up to ~24 repeat critical pages/day for one static, non-recurring failure.
  The migration's own header discusses overlap with `alert_cron_silence`/`alert_cron_function_dead` (different jobs, different time horizons) as an accepted tradeoff, but never discusses or accepts this self-repeat behavior — it appears to be an unconsidered gap, not a stated decision. The new test (`test/contracts/alert_cron_failures_sync_test.dart`) only pins the SQL's literal shape (threshold value, dedup column names, severity string, "no Edge Function") — it never exercises or asserts anything about repeat-firing cadence for a single failure.
- **verification:**
  ```bash
  sed -n '50,80p' supabase/migrations/139_alert_cron_failures.sql
  grep -n "interval '" supabase/migrations/076_alert_detection_crons.sql   # compare lookback:dedup ratios for the 3 pre-existing jobs it claims to mirror
  grep -n "dedup\|window_hours" alerts/_thresholds.yaml   # confirms 24h window_hours / 1h dedup_window_hours side by side, undiscussed
  grep -n "cnt >= 1\|acknowledged" supabase/migrations/139_alert_cron_failures.sql
  ```
- **suggested-fix:** Either shrink the lookback window to something close to the detection cadence (e.g. match `alert_edge_function_health`'s pattern: a short rolling window so a resolved failure ages out on its own), or widen the dedup window to be closer to the lookback (mirroring `alert_payment_flow_health`'s 4:1 ratio at worst, i.e. a dedup window of many hours, not 1). Add a test (can be a plain SQL/logic assertion, doesn't need live Postgres) that a single failure inserted once does not produce more than one alert within a reasonable re-check horizon.
- **status:** accepted — fixed via the first option (shrink lookback to match dedup), with a structural correction the suggested-fix didn't anticipate: a single shared outer bound for BOTH branches (tried first, by hand-tracing before touching the file) turns out to be unfixable by picking better numbers alone — any shared bound ≥ the 1h stuck-threshold makes a genuinely-still-stuck job permanently invisible once its `started_at` ages past that bound, which is a worse defect than the one being fixed. Rewrote the WHERE clause as two independently-time-bounded branches instead of one shared bound: `(status='failed' AND started_at >= now()-1h)` — self-resolving, 1h:1h ratio matching `alert_client_errors_spike`'s working precedent exactly — OR `(status='started' AND started_at < now()-1h)` — no upper bound, correct for an ongoing condition that should keep paging roughly hourly for as long as it is genuinely still stuck. Migration 139 was NOT yet applied to prod (confirmed before editing), so this was a direct in-place edit, not a follow-up migration. `alerts/_thresholds.yaml`'s `cron_failures` entry and description updated to match (`window_hours: 24` → `failed_window_hours: 1`). 2 new tests added to `test/contracts/alert_cron_failures_sync_test.dart` (now 7, was 5) proving the per-branch independent bounds, the failed-window/dedup-window equality, and the absence of any shared 24h bound. Mutation-proof: reverted to the original shared-24h-bound query — reddened exactly 3 of 7 (the rewritten shape-check test plus the 2 new tests), the other 4 (fire_at, dedup convention, severity, cron.schedule-not-EF) correctly unaffected.

## Lenses checked with no findings

- **writer_reader_drift** (beyond Finding 1, which is itself a drift-shaped mirror-guard issue): checked every Hive field this diff touches. A1 (swap-undo), A2a (JSON-reply stripping), A4 (restore-invalidation listener) and A7 (support email) add no new Hive/cloud fields at all — they are UI-lifecycle, pure-render, or literal-string changes. A5 adds only outbound telemetry calls, no new persisted field. The one new cloud column (`subscriptions.cancelled_at`, migration 138) has exactly one writer (the trigger) and one reader path (the digest's `cancelledYesterday` query, `gte/lt` on the exact same column name) — verified by grep that both sides spell the column identically.
- **function_exception_swallow**: `grep -n "functions.invoke\|callFunction" ` over the full staged diff returns exactly one hit (`nutrition_provider.dart:2243`, `CartAuditorNotifier.analyseCart`'s `SupabaseService.instance.callFunction(...)`), and that call site is **pre-existing**, unchanged by this diff — the diff only adds telemetry calls around its existing status/error handling, never touches the invoke/catch structure itself. No new `.functions.invoke(`/`callFunction(` call sites were introduced.
- **blast_radius_mismatch** (migration 138 specifically): the `BEFORE UPDATE` `SECURITY DEFINER` trigger only mutates `NEW` within the same row being updated (no external table access, no privilege-escalating side effect), lives in `private` schema (PostgREST-invisible, consistent with migration 133's established pattern), is idempotent (`ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `DROP TRIGGER IF EXISTS` before `CREATE TRIGGER`), always `RETURN NEW` (never silently blocks a write), and correctly guards against a no-op re-save via `OLD.status IS DISTINCT FROM 'cancelled'` (verified by reading the trigger body directly — re-saving an already-cancelled row with an unrelated field edit does NOT re-stamp `cancelled_at`; a genuine transition OUT of and back INTO `'cancelled'` correctly re-stamps to the latest event). Inline rollback DDL present at file-end. No issue found here (migration 139's issue is reported separately as Finding 3).
- **secrets_in_tree**: `git diff --cached -G'sk-|rzp_live_|AKIA|BEGIN (RSA|EC|OPENSSH|PGP)? ?PRIVATE KEY|api[_-]?key.{0,5}=.{0,5}[A-Za-z0-9]{20,}' -- .` over the entire staged diff returned no matches.
- **unawaited_no_error_sink**: `git diff --cached | grep -nE "unawaited\("` finds 6 new call sites in the code diff (excluding prose in the design-spec doc that merely discusses the pattern). All 6 wrap either `ErrorTelemetry.logEvent(...)` or `ErrorTelemetry.recordNonFatal(...)` — the codebase's established client-side telemetry sink, used unawaited in hundreds of other call sites already, and (per `lib/core/services/CLAUDE.md`) documented to never throw back to its caller. No new unawaited call lacks an error sink.
- **guard_without_its_mirror** (beyond Findings 1 and 2): checked A1's dual dismissal hooks (`ref.listen` on completion + `dispose()` backstop) for their own mirror cases — an already-null `_swapUndoMessenger` (no-op `hideCurrentSnackBar()`, safe), a second swap reassigning the same messenger instance (idempotent), and a disposed screen before the async `onCreated` callback completes (guarded by the pre-existing `if (!context.mounted) return;`, which gates on the same State's own context) — no gap found. Checked A2c's null-channel branch (`channel != null && !allowlist.contains(channel)`) for the "local write, no channel key at all" mirror case — correctly always renders, confirmed by the dedicated test case in the new contract test.
- **missing_input**: verified `fetchAllByIds` is defined and exported at `supabase/functions/_shared/paged_fetch.ts:286` (used by B2's new user-name batch lookup). Verified all 3 new RPC names referenced in `founder_digest_content.ts`'s `gatherDigestInput` are real, live-defined functions: `founder_metrics_for_admin_api` (migration 101, `create or replace function public.founder_metrics_for_admin_api()`), `founder_metrics_ops` (migrations 101/135/136/137, latest definition in 137), `founder_metrics_engagement` (migration 101, superseded by migration 120's `drop function ...; create function public.founder_metrics_engagement()`, which is the LIVE definition per the append-only "last CREATE OR REPLACE wins" convention) — and cross-checked migration 120's actual `returns table (...)` column list against the new `EngagementMetricsRow` TypeScript interface field-for-field: identical (`workouts_logged_today, food_logs_today, ai_messages_today, streak_maintained_current_week, holds_started_today, holds_started_7d, holders_total, generated_at`).
- **asserted_fixture_value**: ⚠ **CORRECTED 2026-09-21 (Round 2, Reviewer A F3) — this bullet verified a value the shipped code no longer computes.** It originally read: hand-verified the `"New MRR: ₹3697"` assertion in `founder_digest_content_test.ts` against its own fixture (2× `monthly` @ ₹349 + 1× `yearly` @ ₹2999 = 698 + 2999 = 3697 — correct, treating a yearly plan's FULL price as monthly-recurring revenue). That math was internally consistent with the code as it stood AT THE TIME this lens ran — but a separate, self-triggered Hermes pass on this same batch (running concurrently, its findings landed in a later commit within this same review cycle) found `computeNewMrr`'s full-yearly-price treatment was itself a bug (a yearly subscription's MRR contribution is `price/12`, not `price`) and fixed it. The shipped code and test now compute/assert `"New MRR: ₹948"` (698 + 2999/12 ≈ 947.92 → 948), and `founder_digest_content_test.ts` carries its own comment noting the prior value. This lens correctly checked internal consistency (test vs. its own fixture) but did not — and structurally could not, since lens 8 verifies a value against DATA, not against a separate correctness-of-formula question — catch that the FORMULA itself was wrong; that was Hermes L1/L21's finding, not this B-pass's. Left here uncorrected-in-place (rather than silently rewritten) so the record shows what was actually checked and when, matching this repo's "don't let it silently stay wrong" convention for the "Note on migration 138" section of a sibling diagnose-doc. Verified the B1 "never render" tests (`999`/`777`/`888`/`111`/`222`/`333`/`444` sentinel values in `founder-digest/index_test.ts`) are deliberately implausible values chosen specifically so a regression (accidentally rendering the unsafe field) would be caught, not merely coincidentally-passing. Verified B2's `private_mode`/empty-`full_name` test (`gatherDigestInput`'s `userNames` wiring test) asserts against explicit, self-contained fixture data (a hand-built fake client), not shared or live mutable state. No new test in this diff depends on shared/live external state — all Dart tests use isolated temp Hive directories (`setUpHiveForTests`/`tearDownHiveForTests`) and all Deno tests use hand-rolled fake Supabase clients.

## Founder triage notes

All 3 findings triaged and fixed by the implementing session immediately
after this review, before merge — each with a mutation-proof confirming the
NEW regression test(s) actually catch the specific defect found (not just
that the fix runs green). No finding was dismissed as a false alarm.

- Finding 1 (P0): fixed via a denylist redesign — see the finding's own
  `status:` line for the full trail; the fix additionally caught an 8th
  affected channel (`image_paywall`/`video_paywall`) the review itself had
  not named.
- Finding 2 (P1): fixed exactly as suggested (comment-stripping).
- Finding 3 (P1): fixed via lookback-window correction, restructured into
  two independently-bounded branches after hand-tracing showed the
  suggested-fix's "pick better numbers" framing alone would trade the
  original bug for a worse one (a permanently-invisible stuck job).

Per this skill's own contract, blast_radius=catastrophic requires the
**founder** to set `verdict: accepted` (not advisory, unlike account/
platform tier) — held `pending` until the founder explicitly said "Accept
the review and apply migrations 138 and 139" (2026-09-21), not because any
finding was unresolved.

Separately, and NOT a code-review finding: this same batch's migrations 138
and 139 were written but not yet applied at the time of the original review.
The founder authorized the live apply in the same instruction as the verdict
above. Both migrations were applied to `dedsavbjuwgarrhphgnl` on 2026-09-21
(cloud versions `20260921172242` / `20260921172347`), each live-verified
post-apply (138: `information_schema.columns` + a rolled-back trigger-fire
test; 139: `cron.job` row confirmed active), and recorded in
`backups/applied_migrations.json` with `backups/live_schema_columns.json`
regenerated for the new `subscriptions.cancelled_at` column. The apply was
delayed by an unrelated live Supabase disk-IO-budget-exhaustion incident on
this same project, resolved by the founder on a separate thread before the
retry succeeded — see `backups/applied_migrations.json`'s entries for 138/139
for the full detail. `check_migration_ledger_paired.dart` /
`check_migrations_applied.dart` / `check_schema_column_refs.dart` should now
be green; confirmed by the pre-commit gate loop re-run after this file was
accepted.

## Round 2 — B-pass on the accumulated batch (2026-09-21)

Dispatched after a self-triggered Hermes pass (`docs/audit/2026-09-21-hermes-observation-batch-and-digest-redesign.md`)
landed 11 more fixes on top of the state Round 1 above reviewed — including
migration 140, `gemini.ts`'s new `redactSecrets`, `tool-loop.ts`'s
`hadQueuedIntent`, `rolling-context`'s retry reduction, and
`founder_digest_content.ts`'s privacy/MRR hardening — none of which had had
an independent adversarial pass. Two fresh context-blind reviewers, split
lenses 1-5 / 6-8 per this skill's own "split above ~15 files" guidance
(69 files staged). **6 findings (1 P1, 2 P2, 3 P3); 0 false_alarm — all 6
accepted, 5 fixed in-batch with mutation-proofs, 1 (F4 below) accepted with
no code fix, reasoning recorded.**

### Round 2, Finding 1 — P2 — blast_radius_mismatch (Reviewer A)
- **file:line:** `alerts/_thresholds.yaml:68-76`
- **claim:** The `cron_failures` threshold entry still described the
  stuck-job branch as having "no upper bound," but migration 140 (landed by
  the Hermes pass, AFTER this entry's description was last written) added a
  6-hour upper bound specifically because the unbounded version was already
  misfiring live. Neither this diagnose-doc's own migration-140 doc nor the
  Hermes report mentioned `alerts/_thresholds.yaml` — the drift survived
  both.
- **verification:** `sed -n '68,76p' alerts/_thresholds.yaml`;
  `grep -n "interval '6 hours'\|stuck_window_hours" supabase/migrations/140_hermes_pass_fixes_138_139.sql`;
  grepped both migration-140 docs for `thresholds` — zero hits in either.
- **status:** accepted — fixed. Description updated to state the 6-hour
  bound, new `stuck_window_upper_bound_hours: 6` field added mirroring the
  migration's own `jsonb_build_object`, `defined_in_migration` now names
  both 139 and 140. See `docs/diagnoses/2026-09-21-hermes-pass-migration-138-139-fixes-h1a2b3.md`'s
  own AMENDMENT section.

### Round 2, Finding 2 — P2 — secrets_in_tree (Reviewer A)
- **file:line:** `supabase/functions/_shared/gemini.ts` (`_callOnce` and
  `_callOnceWithTools`'s `!response.ok` branches)
- **claim:** Both branches sliced the raw response body to 200 chars BEFORE
  calling `redactSecrets`, backwards from the file's two catch/transport-error
  branches (redact-then-slice). A key straddling the 200-char cut would
  truncate to an incomplete fragment `redactSecrets`'s exact-literal match
  can't find, leaking that fragment un-redacted — inconsistent with the
  function's own "every point" completeness claim.
- **verification:** `grep -n "preview = (await response.text()).slice\|redactSecrets(preview)\|redactSecrets(String(err))" supabase/functions/_shared/gemini.ts`.
- **status:** accepted — fixed. Both branches now redact the full response
  text before truncating. Mutation-proven with 2 new tests constructing a
  body where the key straddles exactly that boundary — reverting the fix
  reddens exactly those 2 (23 passed / 2 failed), with the actual leaked
  10-char fragment (`test-key-n`) visible in the failure output. See
  `docs/diagnoses/2026-09-21-gemini-secret-leak-and-retry-telemetry-hardening-f9d3b7.md`'s
  `mutation_proven_redact_before_slice` block.

### Round 2, Finding 3 — P3 — asserted_fixture_value (Reviewer A)
- **file:line:** `docs/reviews/f52dbb8ddc2b-review.md:99` (this file's own
  prior name, now this file)
- **claim:** This review's OWN "Lenses checked with no findings" section
  verified the pre-Hermes-fix `"New MRR: ₹3697"` value as "correct" — stale
  the moment the Hermes pass's `computeNewMrr` fix (÷12 for yearly plans)
  landed and changed the assertion to `₹948`.
- **status:** accepted — fixed by correcting the bullet in place (see the
  `## Lenses checked with no findings` section above) rather than silently
  rewriting it, per this repo's "correct the record, don't let it silently
  stay wrong" convention.

### Round 2, Finding 4 — P3 — blast_radius_mismatch, audit-trail (Reviewer A)
- **file:line:** `backups/applied_migrations.json` (migration 138/139 `note` fields)
- **claim:** The immutable apply-ledger cites `docs/reviews/7aff4322b5ac-review.md`
  by name — a file that no longer exists (renamed twice since, per this
  file's own header note). Traceable forward (the header explains the
  rename chain) but not backward from the ledger alone.
- **status:** accepted, no code fix — the reviewer's own assessment ("None
  strictly required — low-severity, self-explained") is correct: the
  rename chain is fully documented in this file's own header, and rewriting
  an "immutable" applied-migration ledger's prose after the fact for a
  citation-only issue was judged not worth the precedent of editing that
  file post-apply.

### Round 2, Finding 5 — P1 — guard_without_its_mirror (Reviewer B)
- **file:line:** `supabase/functions/_shared/gemini.ts:561-562` (the
  `geminiChatWithTools` per-attempt `console.warn`)
- **claim:** This log line's ONLY protection was `_callOnceWithTools`'s
  inner `redactSecrets` call, one layer away. Mutating that inner call away
  left the raw key leaking into this log line on every retriable failure
  while **all 22 pre-existing tests stayed green**, because every one
  inspects only the FINAL thrown/alerted message — which stays clean
  because `geminiChatWithTools` separately re-redacts `lastReason` when
  building THAT message. Reproduced live: `deno test` after the mutation
  reported `ok | 22 passed | 0 failed` with the raw key visible in the
  captured console.warn output.
- **verification:** Backed up `gemini.ts`, reverted the inner redaction at
  the catch-block reason (`gemini.ts:783` at review time), ran
  `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini_backoff_retry_test.ts` —
  `22 passed | 0 failed`, leak visible in output. Restored.
- **suggested-fix:** Add independent redaction at the `console.warn` call
  site itself, rather than relying on the inner call staying correct.
- **status:** accepted — fixed exactly as suggested: a second,
  independent `redactSecrets` call added at the `console.warn` site
  (defense-in-depth). Mutation-proven with a new test capturing
  `console.warn` output directly; the three-way mutation
  (inner-only-reverted / both-reverted) exactly reproduces the finding:
  with both layers gone, this new test is the ONLY one of 25 that reddens
  (24 passed / 1 failed), while the pre-existing "never leaks into the
  thrown Error's message" test stays green throughout — proving it was
  genuinely blind to this sink. See
  `docs/diagnoses/2026-09-21-gemini-secret-leak-and-retry-telemetry-hardening-f9d3b7.md`'s
  `mutation_proven_console_warn_defense_in_depth` block for the full 3-way
  result.

### Round 2, Finding 6 — P3 — missing_input / test-coverage gap (Reviewer B)
- **file:line:** `supabase/migrations/140_hermes_pass_fixes_138_139.sql:96-101`
  (the `TG_OP = 'INSERT'` branch); `test/sql/migration_140_stuck_alert_and_cancelled_at_live_verify.sql`
- **claim:** Migration 140 fixes TWO defects — a reactivation-clear (UPDATE
  path) and widening the trigger to `BEFORE INSERT OR UPDATE` so a row
  INSERTed directly with `status='cancelled'` also gets stamped. The
  live-verify SQL's original 3 cases only exercised the UPDATE path,
  leaving the INSERT path — one of the migration's two named reasons for
  existing — with zero live coverage.
- **verification:** Read the migration's `TG_OP = 'INSERT'` branch and the
  live-verify SQL end-to-end; confirmed no `INSERT ... status = 'cancelled'`
  case exists anywhere in the file.
- **status:** accepted — fixed. Added Case 3
  (`cancelled_at_stamps_on_direct_insert`) to the live-verify SQL, re-ran
  all 4 cases live against `dedsavbjuwgarrhphgnl` inside the same
  rolled-back transaction — all 4 returned `status='ok'`, including the new
  case; a follow-up query confirmed zero residual rows for both synthetic
  user ids. See the migration-140 diagnose-doc's own AMENDMENT section.

### Round 2 — Founder triage notes

All 6 findings triaged and fixed (or, for F4, correctly closed with no code
change) by the implementing session immediately after this B-pass, before
merge — matching the same self-triage-then-mutation-proof discipline Round
1 used. Per this skill's own established practice for a same-batch,
self-driven second B-pass round (see e.g. the 2026-09-13 "second entry
today" and 2026-09-11 "second entry today" precedents in
`.claude/skills/code-review/SKILL.md`'s Tuning history), this round did not
require a fresh founder accept/reject decision separate from the standing
"commit push merge in the order which our discipline states" instruction —
none of these 6 findings reopened or contradicted the founder's original
catastrophic-tier decision to accept Round 1 and authorize the live apply;
they hardened code that was added AFTER that decision.
