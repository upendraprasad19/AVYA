---
reviewed_at: 2026-07-27T20:54:07+05:30
staged_against: 3275c28e6a5b
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, hardcoded_delimiter, gate_defeat]
findings_count: 5
verdict: accepted
---

# Code Review — 3275c28e6a5b

B-pass over the `sdk-identity-prompt-safety` branch (11 commits at review time,
blast-radius platform), run before the `--no-ff` merge per §4.3. Five findings,
two P0. **All five accepted and fixed in-batch** (`57d9dfb8`); none deferred.

## Finding 1 — P0 — hardcoded_delimiter — FIXED

- **file:line:** `supabase/functions/ai-media-proxy/index.ts:561-578`
- **claim:** Still fenced client-controlled `snapshot_json` in a HARDCODED
  `<user_snapshot>` / `</user_snapshot>` pair while `ai-proxy` had been migrated
  to the nonce fence for the identical concatenation. `sanitizeJsonForPrompt`
  only re-escapes U+2028/2029/0085; `<`, `>` and `/` are `\p{P}`/`\p{S}` and are
  allowed through by design, so a field containing the literal closing tag
  survives verbatim and closes the fence early. Separately, the file had **no
  `snapshot_json` size cap at all**, though CLAUDE.md §4.4 rule 18 requires one
  on every AI endpoint and `ai-proxy` has one.
- **verification:** `grep -n "user_snapshot\|fenceAsData" supabase/functions/ai-media-proxy/index.ts`
- **status:** accepted — nonce fence applied + 10,000-char cap added, throwing a
  typed 400 `HttpError`. Third occurrence in this batch of "sanitised the
  content, left the boundary".

## Finding 2 — P0 — gate_defeat — FIXED

- **file:line:** `supabase/functions/_shared/prompt_sites_sanitized.test.ts` (v3
  top-level RHS checks)
- **claim:** The scanner built its window as `lines.slice(i, i+3).join(" ")` and
  none of the top-level checks were anchored, so a quote or marker belonging to
  an ADJACENT key laundered a genuinely raw assignment on the current line.
  Demonstrated live by the reviewer: an unsafe `systemPrompt: qqqUnbound,`
  followed two lines later by `userPrompt: "probe"` passed 2/2.
- **verification:** revert a real fix and re-run the gate; it must FAIL.
- **status:** accepted — the gate was rebuilt (v4). It no longer traces at all: a
  prompt value must be visibly safe at its own assignment. Value extraction is a
  balanced-expression scan rather than a window, a DECLARATION is now itself a
  site (which removes the ES6-shorthand ambiguity), and the file carries a SELF
  test feeding it every historical false-pass shape.

## Finding 3 — P1 — gate_defeat — FIXED

- **file:line:** `prompt_sites_sanitized.test.ts` (v3 bare-identifier tracer)
- **claim:** Accepted a traced declaration the instant its RHS started with a
  quote, with no check for `+` concatenation afterwards — inconsistent with the
  template-literal branch, which demanded its `${...}` pieces be handled.
  `const evilPrompt = "SYSTEM: " + rawUserInput;` passed.
- **status:** accepted — moot in v4, which has no tracer. The equivalent shape
  (`systemPrompt: "SYSTEM: " + rawUserInput,`) is one of the six SELF-test cases
  asserted to be rejected.

## Finding 4 — P1 — gate_defeat — FIXED

- **file:line:** `prompt_sites_sanitized.test.ts` (v3 typed-parameter fallback)
- **claim:** Searched the WHOLE FILE for `<name>: string` with no requirement it
  be the identifier's own declaration. Because parameter names like `message` and
  `description` are common, an unrelated signature satisfied it. Verified twice
  by reverting real fixes — `userPrompt: description` in `food_parser.ts` passed
  because `description: string` is `parseFoodText`'s own parameter.
- **status:** accepted — the fallback is deleted outright, not narrowed. An
  identifier the gate cannot see as safe now FAILS, and the author must wrap it
  at the call site.

## Finding 5 — P1 — blast_radius_mismatch (documentation) — FIXED

- **file:line:** `docs/audit/sdk-identity-prompt-safety.closure.yaml` entry B5
- **claim:** B5 was `terminal_state: closed_in_commit` and asserted "Both now
  carry both [halves]" — false per Finding 1. Under §4.2's closed==N invariant a
  terminal state asserts real resolution, so the ledger was over-reporting
  closure on a platform-tier security finding.
- **status:** accepted — the underlying code is fixed and B5 is split into B5a
  (ai-proxy) / B5b (ai-media-proxy) so a partial fix cannot hide behind a merged
  claim again.

## Lenses returning clean

- **writer_reader_drift** — `renderCoachMemoryBlock`'s read fields traced against
  `daily-snapshot`'s writer (`patch.preferred_name` etc.); names match exactly.
- **function_exception_swallow** — the diff adds no `.functions.invoke(` sites.
  The two new try/catch blocks are deliberate and documented:
  `releaseDeviceSessionIdentity` must not throw into a zone handler, and
  `sanitizeJsonForPrompt` degrades a BigInt/circular throw to an inert
  placeholder rather than crashing the request it exists to protect.
- **blast_radius_mismatch (tier)** — both diagnose-docs' `blast_radius:` fields
  match `docs/blast_radius.yaml`: `lib/features/auth/**` → account,
  `supabase/functions/**` → platform.
- **secrets_in_tree** — no credential-shaped literals in the diff.
- **unawaited_no_error_sink** — the diff introduces no `unawaited(` calls.

## Founder triage notes

All five accepted; all fixed in `57d9dfb8`. Nothing deferred, consistent with
§4.2. Verification after the fixes: 288/288 Deno, `deno check` exit 0,
`flutter analyze` clean, and FOUR negative controls — each reverting a real fix
— now cause the gate to fail by name. Two of those four passed silently before
this review.
