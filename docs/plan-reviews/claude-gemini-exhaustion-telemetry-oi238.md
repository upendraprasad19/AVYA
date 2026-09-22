---
branch: claude/gemini-exhaustion-telemetry-oi238
date: 2026-09-22
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/50ef49a5910c-review.md
---

# Plan-review record — OI-238 Gemini exhaustion telemetry, 5 remaining Edge Functions (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Platform-tier because it touches `supabase/functions/**` across 5 distinct Edge
Functions and adds a new server-side alert-source design decision; no schema/EF
deploy/payment/auth surface touched, so not catastrophic → no Hermes.

## Scope

OI-238 (sibling of OI-226/f7a2c9): wire `reportGeminiExhaustion` into the 5
Gemini-calling Edge Functions OI-226's own fix did not cover — `weekly-report`,
`ai-media-proxy`, `assess-body-composition`, `daily-snapshot`, `rolling-context`.
Each previously called `geminiChat()` with no server-side exhaustion alert of
any kind (none even destructured `lastError` from `GeminiResult`).

## Ground truth verified before proposing a fix (§4.1)

Re-verified live rather than trusted from the OI's filed text:
`grep -n "geminiChat\|reportGeminiExhaustion" supabase/functions/{weekly-report,ai-media-proxy,assess-body-composition,daily-snapshot,rolling-context}/index.ts`
confirmed all 5 call `geminiChat`, none reference `reportGeminiExhaustion`, none
destructure `lastError`. Named writer (each `geminiChat()` call site) and reader
(`reportGeminiExhaustion` in `_shared/gemini_failure_alert.ts:32`) by file:line
for all 5 functions before drafting any fix — see the diagnose-doc's `writers`/
`readers` fields. Read the full sibling diagnose-doc
(`docs/diagnoses/2026-09-21-ai-failure-telemetry-gap-oi226-f7a2c9.md`) and
`supabase/functions/CLAUDE.md`'s `gemini_failure_alert` row and AI Architecture
section before drafting, per §4.1.5.

## Review round 1 — initial design, self-critique before writing code

Drafted the mechanical fix (destructure `lastError`, call `reportGeminiExhaustion`
in each `!content`-shaped branch, mirroring OI-226's pattern exactly) and then
adversarially questioned three design choices before implementing, as if a fresh
reviewer:

1. **Dedup-source question: does the OI's own "the endpoint/dedup semantics may
   need adjustment" note mean anything concrete here, or is it just cover for
   copy-pasting the same source string everywhere?** Considered three options:
   (a) reuse `"ai_proxy_gemini_exhausted"` uniformly across all 5 — simplest,
   but ignores that `rolling-context` is structurally different (a nightly cron
   loop over every user with >50 messages, not a single live request); (b) give
   EVERY function its own source — maximally precise but defeats the whole
   point of a dedup window (a real Gemini-wide outage would page the founder 5
   separate times); (c) split by TRAFFIC SHAPE — the 4 live user-invoked sites
   share the ai-proxy source (same quota, same live-traffic urgency), the 1
   cron site gets its own (its failure mode is "many failures in one run", which
   would otherwise suppress a same-day live alert to "warn" for 30 minutes).
   Chose (c) — rejected (a) because it has a real, describable failure mode
   (not just "less thorough"), rejected (b) because it defeats OI-226's own
   stated rationale for a shared source.
2. **Testing-approach question: should I refactor 4 of the 5 functions (all but
   `ai-media-proxy`, which already exports `handleRequest`) to expose a testable
   seam, so I can write behavioral tests like `tool-loop_gemini_exhaustion_alert_test.ts`
   instead of source-greps?** Checked whether `daily-snapshot` already had
   established precedent for this exact situation — it does: its own
   `index_test.ts` header explicitly documents why source-grep is the accepted
   pattern when `serve(...)` runs unguarded at module scope. Checked
   `ai-media-proxy`'s existing tests too, expecting them to reach further than
   the other 4 — found instead that even `handleRequest`'s own test file never
   drives a request past the auth boundary (a real, unmockable
   `createClient(...).auth.getUser()` call), so it has the SAME limitation in
   practice. Rejected doing a 4-function `import.meta.main`-guard refactor
   (CLAUDE.md's own "extraction breaks source-grep contracts elsewhere"
   pitfall row + rule 21's mutate-it warning both counsel against enlarging a
   telemetry-wiring batch into an architecture change) in favour of the
   established, precedented source-grep style, applied uniformly across all 5
   for consistency — including `ai-media-proxy`, despite it technically having
   an exported `handleRequest`, since its test seam doesn't actually reach the
   branch either.
3. **Gate-extension question: should `check_gemini_retry_and_telemetry_coverage.dart`
   be widened to registry-enforce these 5 new server-side call sites too?**
   Read the gate's own doc comment and OI-226's closed entry: part (b) of that
   gate is explicitly CLIENT-side only (Dart `ErrorTelemetry` calls), and
   OI-226's closure explicitly scoped server-side `reportGeminiExhaustion`
   wiring OUT of any mechanical gate ("5 call sites judged too small a surface
   to warrant one"). This fix doubles that count to 10 but doesn't change the
   calculus stated — rejected inventing a new registry-based gate as
   out-of-scope for what this OI actually asked for (telemetry wiring, not
   gate infrastructure); noted the decision explicitly in the diagnose-doc's
   `proposed_fix` rather than silently doing nothing.

No material defect found in round 1's own draft; round 1 converged on decisions
1-3 above and confirmed the mechanical pattern (destructure + call in the
existing failure branch, before the existing return) needed no per-function
adjustment beyond the source/endpoint values.

## Review round 2 — on the HARDENED plan, after implementation + mutation-proving

Re-examined the round-1 decisions and the actual landed code for defects a
second, independent pass might catch — per §4.12.1, round 2 runs on the
POST-round-1 (hardened, now-implemented) state, not a re-read of the same
prose:

- **Re-checked the dedup-source split was actually APPLIED, not just decided.**
  `grep -n "ai_proxy_gemini_exhausted\|rolling_context_gemini_exhausted"` across
  all 5 files confirmed `rolling-context` uses ONLY its own source (no stray
  reuse of the shared one), and the other 4 use ONLY the shared one — a typo
  or copy-paste slip here would have been invisible to the type-checker and
  silently defeated the whole design rationale from round 1.
- **Checked whether `lastError ?? null` was doing real work or dead code.**
  Traced every `geminiChat()`/`_callOnce()` return path in `gemini.ts`
  end-to-end: `lastError` is populated on every failure branch and the final
  give-up return (`lastFailure?.lastError ?? null`), so it is never `undefined`
  when `content` is null. The `?? null` is therefore defensive-but-redundant,
  not masking a real gap — worth stating plainly rather than leaving it looking
  load-bearing when it isn't.
- **Checked `rolling-context`'s signature change for orphaned callers.**
  `summarizeMessages` gained a new required parameter — grepped the WHOLE repo
  (`grep -rn "summarizeMessages"`, not scoped to the one file) for any other
  caller or test using the old 1-arg form. Found exactly one call site total
  (the definition + the one call at `:446`), both already updated together in
  the same commit-to-be.
- **Checked the new source-grep tests' boundary computations for the exact
  fragile-match failure mode this repo's own `CLAUDE.md` and
  `gemini_retry_coverage_lib.dart` warn about** (an early nested closing brace
  narrowing the search window to the wrong block). Hand-walked each of the 5
  boundary patterns (`"\n    }\n"`, `"return null;\n  }"`,
  `"\n  }\n\n  return content;"`) against the live file text; none matches an
  earlier nested brace before the real one.
- **Mutation-proved all 5 new/extended wiring sites independently** (not just
  one, despite the task brief's singular framing — CLAUDE.md rule 21 requires
  every NEW test protection to be mutated, not a representative sample):
  deleted each `reportGeminiExhaustion(...)` call in turn, confirmed exactly
  its own test reddened while every other test in that file's suite stayed
  green, reverted, confirmed green again. See the diagnose-doc's
  `mutation_proven` field for exact pass/fail counts per site.

No material defects surfaced in round 2 — the findings were confirmations
(source split applied correctly, no orphaned caller, boundary math sound,
mutations clean) rather than new issues, which is the §4.12.1 convergence
signal.

## B-pass (independent, context-blind, dispatched fresh)

A THIRD, genuinely independent check beyond the two self-critique rounds above:
dispatched a fresh Sonnet subagent with no conversation context per
`.claude/skills/code-review/SKILL.md`, applying all 8 lenses. It independently
re-ran `deno check` + `deno test` (44/44, matching claimed counts rather than
trusting them), re-traced the `gemini.ts` return paths itself, re-grepped the
whole repo for `summarizeMessages` callers itself, and re-walked the test
boundary computations itself — arriving at the same conclusions as round 2
through independent verification rather than reading round 2's own notes.
0 findings. Review: `docs/reviews/50ef49a5910c-review.md`. Verdict set to
`accepted` (0 findings vacuously satisfies "all findings non-pending").

## Convergence

Round 2 found no NEW material issues — only independent confirmations of round
1's decisions holding up against the implemented code. The B-pass, dispatched
with zero context from either round, reached the same clean result through its
own independent verification. Three independent passes (2 self-critique + 1
context-blind) converging on the same conclusion, with real verification work
(not just re-reading) behind each, is the signal this unit does not need
splitting or a further round.

## Verification

- `deno check --node-modules-dir=none` clean on all 5 touched `index.ts` files.
- `deno test --no-check --allow-all --node-modules-dir=none` across all 5
  `index_test.ts` files: 44/44 passed (21 pre-existing ai-media-proxy tests +
  5 pre-existing daily-snapshot tests unaffected; 18 new OI-238 assertions).
- All 5 new/extended wiring sites mutation-proven live (see diagnose-doc).
- `sh scripts/pre-commit.sh` full gate loop: PASS (Gate 40, Gate-SDB, Gate-DEU,
  gate-index regen, tech-debt audit gates, `check_skill_tuning_history.dart`,
  `check_code_review_pass_exists.dart`).
- `dart run scripts/validate_diagnose_doc.dart` PASS on the new diagnose-doc.
- `dart run scripts/blast_radius_from_diff.dart` (staged, bare `-` stdin form)
  confirms `platform`, matching this record's own frontmatter.

## Residual, stated rather than hidden

- No live Edge Function redeploy performed or requested — a separate,
  founder-authorized action per §4.3's "live prod apply needs its own explicit
  go", not requested this session. The 5 functions' NEW telemetry is inert in
  production until deployed.
- No mechanical gate added for server-side `reportGeminiExhaustion` wiring
  (round-1 decision 3 above) — an explicit, stated scope boundary matching
  OI-226's own precedent, not an oversight.
- The 5 new source-grep tests are inherently coupled to exact source
  formatting, same documented tradeoff this repo already accepts for
  `daily-snapshot/index_test.ts`'s pre-existing tests — a future reformat of
  these blocks needs a matching test update.
