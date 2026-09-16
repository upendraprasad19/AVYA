---
bug_id: b7c9e2
date: 2026-09-16
batch: cron-ai-removal
status: fixed
blast_radius: platform
symptom: |
  `proactive-coach-promotion` (fired by the `trg_dispatch_proactive_coach_promotion`
  Postgres trigger on every rank_promotions INSERT) composed its congrats
  copy with a raw `fetch()` call straight to the Gemini REST endpoint,
  bypassing `_shared/gemini.ts`'s Flash→Flash-Lite retry/fallback helper
  entirely, and had NO fallback template of its own. A Gemini 4xx/5xx, an
  empty-content response, or the same project-wide 429 quota exhaustion
  that motivated this whole batch (see the batch's committed spec,
  `docs/superpowers/specs/2026-09-16-proactive-cron-ai-removal-design.md`)
  threw inside `composeCongrats`, was caught by the outer handler's bare
  `catch (e)`, and returned a plain `{error: msg}` 500 — no chat message
  written to `ai_coach_interactions`, no OneSignal push sent. A user's
  rank-up (an earned, one-time celebration moment) was silently dropped
  with no retry path, since the trigger fires once per INSERT.
concept: proactive_coach_promotion_congrats
sot_registry_entry: |
  No existing docs/sot_registry.yaml entry covered this concept as a
  writer/reader contract (`composeCongrats` previously appeared only in
  the OI-47 prompt-injection-sanitisation list, removed by this same
  commit since there is no longer a prompt to sanitise for — see the
  sibling commit diff). Not adding a new registry entry: this is a
  same-process synchronous composition (congrats.ts → index.ts call site
  → one INSERT), not a cross-layer writer/reader pair the registry exists
  to pin.
writers:
  - { file: supabase/functions/proactive-coach-promotion/congrats.ts, method_or_widget: "composeCongrats — synchronous, deterministic 3-variant congrats copy (no network I/O, cannot throw on an external failure)", line: 63 }
readers:
  - { file: supabase/functions/proactive-coach-promotion/index.ts, method_or_widget: "call site — congrats value written to ai_coach_interactions.ai_response and passed to sendOneSignalPush", line: 116 }
hive_key_prefix: "n/a"
hive_key_formula: "n/a — server-side Edge Function, no Hive involvement. ai_coach_interactions is a cloud-only proactive-message write; the client-side coach sync (sync_coach.dart) reads it down on its own schedule, unmodified by this fix."
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [ai_response]
contract_test_path: supabase/functions/proactive-coach-promotion/index_test.ts
ist_handling:
  - "Not applicable — no date keys, cloud `date` columns, or counter resets involved. composeCongrats's deterministic variant pick is keyed on rank_code length + total_workouts_done, not a clock."
provider_invalidations: []
telemetry_op_types:
  success: [proactive_coach_promotion_dispatched]
  failure: [proactive_coach_promotion_failed]
cross_account_guard: "Not applicable — composeCongrats operates entirely on the single triggering user's own context (full_name/primary_goal/streak/workout-count), fetched by loadUserContext scoped to that one user_id; no cross-user read or write."
forbidden_patterns_checked:
  - { pattern: "await composeCongrats( (async call surviving from the Gemini-era signature)", absent: true }
  - { pattern: "generativelanguage.googleapis.com (raw Gemini REST fetch)", absent: true }
proposed_fix: |
  Rewrite composeCongrats into a pure, synchronous function
  (supabase/functions/proactive-coach-promotion/congrats.ts) implementing
  a 3-variant rotation using the founder-approved templates from the
  batch's committed spec — no network I/O at all, so there is nothing
  left in this path that can throw on an external failure. This is a
  side effect of the same removal every other function in this batch
  gets (cut Gemini call volume), but for this one function it ALSO closes
  a genuine reliability gap: previously, "no fallback" meant a Gemini
  hiccup dropped the celebration outright; now the celebration always
  ships, deterministically, from the trigger alone.
regression_test_planned:
  - supabase/functions/proactive-coach-promotion/index_test.ts (new file, 7 Deno tests — all 3 approved variants pinned verbatim including the founder's dropped-"report" edit on variant 2, unknown-rank-code fallback to the raw code, null-full_name fallback to "soldier", and a determinism check that an unpinned variantIndex is still stable across repeat calls for the same input)
impact_analysis: |
  Scope: this fix touches every rank-up celebration for every user tier —
  proactive-coach-promotion is explicitly platform-tier in
  docs/blast_radius.yaml (confirmed, not assumed). It does not touch the
  trigger itself (trg_dispatch_proactive_coach_promotion, migration 073)
  or the OneSignal push path (sendOneSignalPush, unchanged) — only how
  the congrats TEXT is produced. Before this fix, composeCongrats was
  `async`, called via raw `fetch()` to
  generativelanguage.googleapis.com, and threw on `!res.ok` or empty
  content with no try/catch anywhere in its own body — the outer
  handler's catch (index.ts, then at what is now line 159, unchanged by
  this fix) was the only thing standing between a Gemini hiccup and a
  bare 500 with no chat message and no push. After this fix,
  composeCongrats never performs I/O and cannot itself fail; the
  remaining failure surface (the ai_coach_interactions INSERT, the
  OneSignal push) is unchanged and was already correctly handled
  per-step by the existing code (index.ts:148-164, :169-175).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "Server-side Edge Function only; no Flutter client code touched by this fix." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "supabase/functions/proactive-coach-promotion/index.ts and the new congrats.ts changed in this worktree but NOT yet deployed — deploy requires separate explicit founder authorization per CLAUDE.md §4.3. deno check --node-modules-dir=none passed clean on index.ts; deno test --no-check --allow-all --node-modules-dir=none supabase/functions/proactive-coach-promotion/ passed 7/7." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "ai_coach_interactions.ai_response's shape (a plain string) is unchanged — the client-side sync/restore/render path that reads this column cannot distinguish AI-generated text from template text; no contract change." }
---

## Summary

Removing `proactive-coach-promotion`'s Gemini call (in scope for every
function in this batch, per the batch spec) has a second, independent
effect here specifically: it closes a genuine reliability bug the spec's
audit phase surfaced — this function had no fallback template at all, and
bypassed the shared `_shared/gemini.ts` retry helper via a raw `fetch()`
call the other 8 functions in this batch don't use.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "proactive", "coach-promotion",
"gemini fallback" — no prior diagnose-doc covers this specific function's
missing-fallback shape. `supabase/functions/CLAUDE.md`'s AI Architecture
section lists `proactive-coach-promotion` among the 9 cron functions that
call Gemini, with no note of a fallback gap — this batch's own audit
phase (recorded in the committed spec) is the first place this was
identified, not a recurrence of a previously-diagnosed bug.

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer:** `composeCongrats` (pre-fix, `supabase/functions/proactive-coach-promotion/index.ts`)
called `fetch()` directly against
`https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent`
— not `_shared/gemini.ts`'s `geminiChat()`, which is the ONLY place the
Flash→Flash-Lite fallback and bounded retry logic live. It threw on
`!res.ok` or empty `text`, with no local try/catch.

**Reader:** the outer `serve()` handler's `catch (e)` block (unchanged by
this fix) caught that throw, logged failure telemetry, and returned a
bare `{error: msg}` 500 — never reaching the `ai_coach_interactions`
insert or the OneSignal push.

The gap was a MISSING FALLBACK, not a writer/reader field-name drift:
every other function in this 9-function batch already shipped a working
hardcoded template that ran on Gemini failure; this one never had one.

## Fix

Replaced the async, network-calling `composeCongrats` with a pure,
synchronous function in a new `congrats.ts` sibling file (matching the
non-serving-file pattern used across this whole batch, so
`index_test.ts` can import it without risking a `Deno.serve()` port
collision — see the batch's committed implementation plan,
`docs/superpowers/plans/2026-09-16-proactive-cron-ai-removal.md`, Task 8).
It rotates deterministically through 3 founder-approved variants keyed on
`rankCode.length + totalWorkoutsDone`, so a retry of the same promotion
event produces the same message rather than a different one each time.

## Verification

`deno test --no-check --allow-all --node-modules-dir=none supabase/functions/proactive-coach-promotion/`
— 7/7 passed (3 variant-copy pins, unknown-rank-code fallback, null-name
fallback, determinism check, and a source-shape guard that the raw
Gemini fetch endpoint and `GEMINI_API_KEY` reference are both gone).
`deno check --node-modules-dir=none supabase/functions/proactive-coach-promotion/index.ts`
— clean.

**Mutated and run** (rule 21): changed `RANK_LABELS.LS` from
`"Leading Seaman"` to `"Landing Signalman"` in `congrats.ts` — reddened
exactly 3 of 7 tests (the three variant-copy pins that interpolate the
rank label), the other 4 (unrelated to the rank label) stayed green.
Confirmed real detection, not a compile-error false positive — the file
still type-checked and ran. Reverted; re-ran green (7/7).

## Related

Sibling fixes in the same batch (`cron-ai-removal` branch): 7 other cron
functions (pr-detection, streak-guardian, plateau-alert,
protein-gap-alert, re-engagement, workout-window-closing, morning-alert)
each had their Gemini call removed in favour of an ALREADY-WORKING
fallback template — those are `refactor:` commits, not `fix:`, since
nothing was broken in them individually; this function is the one
exception where the removal also closes a genuine defect.
