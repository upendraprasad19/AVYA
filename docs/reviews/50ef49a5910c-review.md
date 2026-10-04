---
reviewed_at: 2026-09-22T15:46:17Z
staged_against: 50ef49a5910c
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 0
verdict: accepted
---

# Code Review — 50ef49a5910c

No findings survive verification. This diff wires `reportGeminiExhaustion` into 5 Edge Functions
(`weekly-report`, `ai-media-proxy`, `assess-body-composition`, `daily-snapshot`,
`rolling-context`) that call Gemini directly, mirroring the pattern OI-226 established for
`ai-proxy`. It is additive/observability-only: the shared helper is unchanged, never throws
(try/catch-wrapped), and every new call site fires strictly inside the pre-existing
`if (!content)`-shaped failure branch, before the pre-existing error response is returned.

I independently ran `deno check --node-modules-dir=none` on all 5 touched `index.ts` files
(clean, zero errors) and `deno test --no-check --allow-all --node-modules-dir=none` on all 5
`index_test.ts` files (44/44 passed: 3 weekly-report, 24 ai-media-proxy, 3
assess-body-composition, 8 daily-snapshot, 6 rolling-context) — this matches the diagnose-doc's
own claimed counts exactly. I also attempted a live mutation (deleted the
`reportGeminiExhaustion(...)` call from `rolling-context`'s `!content` branch) to spot-check the
diagnose-doc's mutation-proof claim; the harness's auto-mode classifier blocked the `deno test`
re-run on the mutated tree ("Irreversible Local Destruction"), so I could not execute that half
myself. I reverted the mutation immediately via `git checkout --`, confirmed the file matches the
staged index exactly (`git status --porcelain` clean), and instead verified correctness by
hand-tracing the affected test's boundary computation against the real source (see Lens 8 below),
which independently confirms the assertion would in fact fail without the call site present.

## Lens checked, no findings — writer_reader_drift
`_shared/gemini_failure_alert.ts` (the `reportGeminiExhaustion` function and its `public.alerts`
writes) is NOT part of this diff — confirmed via `git diff --cached --stat -- supabase/functions/_shared/`
(empty output). All 5 new call sites reuse the existing, unchanged function signature
(`client, source, lastError, endpoint?`). No new Hive/cloud field names are introduced by this
diff; the only "writer" behavior added is 5 more call sites into an already-established sink.

## Lens checked, no findings — function_exception_swallow
`git diff --cached | grep -n "functions.invoke\|FunctionException"` returned nothing — this diff
touches no `.functions.invoke(` call sites (this is server-side Edge Function code, not a client
caller). Lens not applicable to this diff.

## Lens checked, no findings — blast_radius_mismatch
`docs/blast_radius.yaml` has explicit `platform` entries for `ai-proxy/**`, `daily-snapshot/**`,
and `_shared/**`, plus a catch-all `{ glob: "supabase/functions/**", tier: platform }` (line 375)
that covers `weekly-report`, `ai-media-proxy`, `assess-body-composition`, and `rolling-context`
(none of which have a more specific, lower-tier entry). Every touched path in this diff resolves
to `platform`, matching the diff's own `blast_radius: platform` frontmatter in both the diagnose-doc
and this review's own header.

## Lens checked, no findings — secrets_in_tree
`git diff --cached | grep -inE "api[_-]?key|secret|token|password|bearer|sk-|AIza"` returns only
prose mentions of `GEMINI_API_KEY`/`SUPABASE_SERVICE_ROLE_KEY` (env var names, not values) and one
test fixture literal `"test-service-role-key"` in `ai-media-proxy/index_test.ts` (a placeholder
used to assert a request header equals a known fake string — not a real credential). No
credential-shaped literal in the diff.

## Lens checked, no findings — unawaited_no_error_sink
`git diff --cached | grep -n "reportGeminiExhaustion("` shows every actual call site (as opposed
to prose/test-string references) is `await reportGeminiExhaustion(...)` — confirmed at
`weekly-report:573`, `ai-media-proxy:941`, `assess-body-composition:178`,
`daily-snapshot:167`, `rolling-context:127`. No fire-and-forget call was introduced.

## Lens checked, no findings — guard_without_its_mirror
Read `supabase/functions/_shared/gemini.ts` in full (not changed by this diff, but the contract
every new call site depends on). Traced every return path of `geminiChat()`/`_callOnce()`:
- `!GEMINI_API_KEY` → `lastError` set (line 148).
- non-`response.ok` HTTP status → `lastError` set (line 314).
- missing/blocked candidate → `lastError` set (line 331).
- empty text in candidate → `lastError` set (line 346).
- thrown/aborted request → `lastError` set (line 371).
- the outer `geminiChat` retry-loop's final give-up return → `lastError: lastFailure?.lastError ?? null` (line 215), so it is always present (object or `null`), never `undefined`, whenever `content` is `null`.
- The only path that omits `lastError` from the returned object (line 352-356, success) is exactly
  the path where `content` is non-null and no caller's `if (!content)` branch runs.
So `lastError` is provably always populated whenever any of `rawReply`/`rawText`/`content`/
`aiContent` is null — the mirror case (null content with no lastError) does not exist in the
current implementation. `lastError ?? null` at each call site is therefore redundant but not
wrong (defensive coding against a contract that already holds).
Also checked: every new `await reportGeminiExhaustion(...)` fires only inside the pre-existing
failure branch (never on the happy path) and always BEFORE the branch's existing `return`/error
response — confirmed by direct read of all 5 call sites (`weekly-report:565-583`,
`ai-media-proxy:936-960`, `assess-body-composition:173-185`, `daily-snapshot:159-174`,
`rolling-context:115-133`), so it cannot delay or alter the happy-path response and cannot cause a
double-response (each is a single sequential `await` before a single `return`, no earlier
response is sent). `reportGeminiExhaustion` itself is fully try/catch-wrapped and has its own
`DISABLE_GEMINI_FAILURE_ALERT` kill-switch, so a DB hiccup on the alerts insert cannot propagate an
exception into any of these 5 handlers — confirmed by reading `gemini_failure_alert.ts` in full.
For `rolling-context` specifically: `summarizeMessages`'s new `supabase: SupabaseClient` parameter
has exactly one caller in the whole repo (`grep -rn "summarizeMessages" --include="*.ts" .` across
the full tree, not just this file — 2 real occurrences: the definition and the one call site at
`rolling-context/index.ts:446`, both already updated to the new 2-arg signature) and no test or
other function calls it with the old 1-arg signature.

## Lens checked, no findings — missing_input
Checked import correctness for all 5 files (`import { reportGeminiExhaustion } from
"../_shared/gemini_failure_alert.ts";` present and correctly relative-pathed in each). Checked
that the `supabase`/`supabaseClient` variable passed at each call site is the SAME instance already
in scope and used earlier in that function, not a shadowed/different client:
- `ai-media-proxy`: single `const supabaseClient = createClient(...)` at `handleRequest:540`, used
  consistently through line 1024 including the new call at 942 (`grep -n "^async function\|supabaseClient"` shows no second declaration inside `handleRequest`).
- `assess-body-composition` / `weekly-report`: single `const supabase = createClient(...)`
  declaration each, no shadowing (`grep -n "const supabase\b"` returns exactly one hit per file).
- `daily-snapshot`: `extractCoachingNotes(supabase: SupabaseClient, ...)` is an existing typed
  parameter (not a module global); its sole caller at `index.ts:442-446` passes the outer
  `serve()` scope's `supabaseClient`, matching the pre-existing pattern already used for
  `mergeCoachingNotes` two lines below.
- `rolling-context`: `summarizeMessages`'s new `supabase: SupabaseClient` parameter is threaded
  from the loop's own `supabaseClient` at its one call site (`:446`).
`deno check --node-modules-dir=none` (run by me, not just claimed) is clean on all 5 files,
which would have caught a missing/mistyped import, a wrong-typed parameter, or a destructured
field that doesn't exist on `GeminiResult` (`lastError` is declared at `gemini.ts:117`, matching
every destructure).

## Lens checked, no findings — asserted_fixture_value
For each of the 5 new/extended `index_test.ts` source-grep tests, manually traced the boundary
computation against the ACTUAL current source (not just the test's own claim) to check for the
exact fragile-match failure mode the task description warned about (an early nested `}` narrowing
the search window):
- `ai-media-proxy` / `assess-body-composition`: bound via `source.indexOf("\n    }\n", branchIdx)` — walked every line inside each `if` block by hand; every nested brace inside those blocks (e.g. `}),` closing a `JSON.stringify({...})` call, `},` closing a response-options object) sits at 6-8 space indent with trailing characters after `}`, so none can match the exact 4-space-then-bare-`}` pattern before the real closing brace. First match is the real one in both files.
- `weekly-report`: same `"\n    }\n"` pattern; the intervening `{ error: "..." },` object literal is single-line (open+close brace on the same line), so it cannot produce a false 4-space-newline match either. First match is the real one.
- `daily-snapshot`: bound via `source.indexOf("return null;\n  }", branchIdx)` — the literal text `return null;` immediately followed by the 2-space closing brace appears exactly once in the file, immediately after the new call site.
- `rolling-context`: bound via `source.indexOf("\n  }\n\n  return content;", branchIdx)` — matched the real closing `}` of the `if` block followed by the blank line and `return content;`, confirmed char-for-char against the live file.
All 5 boundary computations correctly bound the intended block in the CURRENT source — none is a
false-positive match on an earlier/wrong closing brace. I additionally ran (not just read) all 44
tests and they pass against the real code, and `deno check` proves the files as tested actually
compile — so these are not vacuous "always green" fixtures (unlike this repo's own documented
history of that failure mode in `feedback_green_check_input_set_width.md`). The dedup-source
negative assertion in `rolling-context`'s test (`assertEquals(block.includes('"ai_proxy_gemini_exhausted"'), false, ...)`) is a genuine, falsifiable check that a typo'd or copy-pasted source
string would catch — confirmed the literal in the source really is
`"rolling_context_gemini_exhausted"` with no stray reuse of the shared string anywhere in that
file (`grep -n "gemini_exhausted" rolling-context/index.ts` shows exactly one live occurrence of
the correct string plus one comment mention of the OTHER string for contrast).
These tests ARE inherently coupled to exact source formatting (acknowledged by the diagnose-doc's
own `forbidden_patterns_checked` entry and this repo's `CLAUDE.md` common-pitfalls row on
extraction breaking source-grep contracts) — a future refactor that reformats these blocks would
need to update the tests, but that is a documented, accepted tradeoff already named by the
authors, not an unnoticed defect in this diff.

## Founder triage notes
No findings to triage (0 P0/P1/P2) — the fresh-agent reviewer independently ran `deno check` +
`deno test` (44/44) and hand-verified the 8 lenses above, including the two most likely to catch
something real in this shape of diff (guard_without_its_mirror, asserted_fixture_value). Verdict
set to `accepted` on that basis by the implementing agent, per §4 of the skill ("when ALL
findings have non-pending status") — vacuously satisfied with zero findings.
