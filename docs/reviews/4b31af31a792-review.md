---
reviewed_at: 2026-09-09T01:20:00+05:30
staged_against: 4b31af31a792
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, guard_without_its_mirror, function_exception_swallow, missing_input, asserted_fixture_value, blast_radius_mismatch, secrets_in_tree, stale_or_wrong_citation]
findings_count: 3
verdict: accepted
---

# Code Review (B-pass) — 4b31af31a792

OI-162 slice 3b — `ai-media-proxy`'s free-image lifetime meter onto `usage_counters`.
15 files, ~1280 insertions. **3 findings: 0 P0, 0 P1, 1 P2, 2 P3. 0 false alarms.
All three fixed in-batch.**

Every finding was re-derived by the author before acting, per §4.8.

## Finding 1 — P2 — stale_or_wrong_citation

- **file:line:** `supabase/functions/CLAUDE.md`, the new `ai-media-proxy` tier row
- **claim:** The row cited the free gate at `:465-466`. That was correct against the PRE-diff file
  and wrong in the same commit that shipped it: this diff inserts ~83 lines above the check (two
  new consts with comment blocks, the expanded `readFreeImageQuota` docstring, and the 44-line
  fail-closed block), moving it to `:549`.
- **verification:** `git show HEAD:supabase/functions/ai-media-proxy/index.ts | sed -n '460,475p'`
  → the check at 466 pre-diff. `grep -n "usedSoFar >= FREE_IMAGE_ANALYSIS_LIMIT"` on the staged
  tree → `549:`. Confirmed independently by the author.
- **suggested-fix:** cite the symbol, not the line.
- **status:** FIXED — the row now names the `usedSoFar >= FREE_IMAGE_ANALYSIS_LIMIT` check and
  records, in place, that it already drifted once and why.
- **note:** this is OI-167's class — *a citation derived against the pre-edit file is invalidated
  by the edit that ships it* — recurring in a session that had already hit it once today.

## Finding 2 — P3 — stale_or_wrong_citation

- **file:line:** `test/sql/oi46_daily_cap_triggers_live_verify.sql:707`
- **claim:** the new `slice3b` header cited `media_free_image_lifetime_meter_test.dart`, a file
  that does not exist — the test was renamed to `..._gate_writer_to_reader_test.dart` to satisfy
  Gate 9.
- **verification:** `ls test/contracts/ | grep -i media_free_image` → only the `_gate_writer_to_reader`
  name exists.
- **status:** FIXED.
- **⚠ WHY IT SURVIVED, which is the real lesson.** The author DID run a post-rename sweep and it
  reported "none". That sweep was `grep -rn ... --include=*.md --include=*.yaml`, which **excludes
  `.sql`** — the only remaining file type holding the stale name. A verification narrower than the
  thing being verified returns zero and reads as proof. **Fourth instance of that exact shape in
  this one session** (the others: a `lib/`-scoped grep in the plan, a `^\s+`-anchored warning
  count that missed a warning with no leading space, and a blast-radius invocation whose answer was
  deleted by a `grep -v` filter). Re-verified here with `git grep` over all tracked files, no
  extension filter.

## Finding 3 — P3 — missing_input / coverage gap

- **file:line:** `lib/features/ai_coach/copy/coach_replies.dart` +
  `supabase/functions/_shared/coach_replies.ts`, the new `imageQuotaUnavailable`
- **claim:** the new fail-closed copy shipped with ZERO assertions on either side, and nothing
  pinned the client/server pair — both files call themselves a mirror of the other and nothing
  enforced it. This is the exact string a real production refusal displays.
- **verification:** `grep -n "imageQuotaUnavailable" test/contracts/coach_replies_test.dart` → 0.
- **status:** FIXED — two tests added. One pins the *absence* of the paywall's claims (it must not
  say "used your 5", must not upsell on an infrastructure failure) with a MIRROR asserting the real
  paywall still says both, so merging the strings back together cannot pass. The second extracts
  the concatenated TS literal and asserts byte-identity with the Dart constant.
  **Mutation-proven:** shortening one phrase in the TS copy reddens the mirror test and prints both
  strings; restored green 8/8.

## What the reviewer checked that came back CLEAN

Recorded because a short findings list is only meaningful with the negative space shown.

- **writer_reader_drift** — writer and reader both use the same TS constants
  (`FREE_IMAGE_ANALYSIS_QUOTA_KEY`, `LIFETIME_WINDOW`), not duplicated literals, so there is no
  drift surface. RPC parameter names checked byte-for-byte against `128_usage_counters.sql:69-75`.
- **the epoch equality** — verified live: `select 'epoch'::timestamptz = '1970-01-01T00:00:00+00:00'::timestamptz` → `true`.
- **guard_without_its_mirror** — all four mirror cases traced in source: PRO and video never enter
  the branch (`isFreeImageAnalysis = !isVideo && !isPro`); an RPC failure under-counts by one and
  still delivers the analysis; an insert failure skips the consume via `!interactionLogError` and
  still delivers. No case where the new code is worse than the old for its mirror, except the
  deliberate fail-open→fail-closed flip, which is the point.
- **-1 handling** — treated as a successful exhaustion signal, never logged as an error, matching
  migration 128's stated contract.
- **RLS / cross-account** — `usage_counters` has RLS enabled with **0** policies; `consume_quota`
  is SECURITY INVOKER; the EF's client uses `SUPABASE_SERVICE_ROLE_KEY` and bypasses RLS by design.
  Every read/write scoped by the JWT-derived `userId`, never request-body-controlled.
- **blast_radius** — recomputed `platform`. No migration in the diff, so the `SECURITY DEFINER`
  content rule cannot fire.
- **secrets_in_tree** — one hit, the env-var NAME in prose. No values.
- **dead-code deletion** — `getFreeImageAnalysisCount` has zero remaining references outside docs.
- **allowlist ratchet** — 2→1 matches the one genuinely remaining counter site
  (`countProImageAnalysesToday`), confirmed by grep and by running the gate.
- **gates run against the staged tree** — `check_usage_counter_source` PASS (3 EF counters),
  Gate 42 PASS (127 concepts, 7 `presence_only`), `check_sot_registry_parity` PASS (one
  pre-existing unrelated WARN), `check_reader_manifest_complete` OK.
- **tests EXECUTED, not read** — 16/16 across the new contract test and the ledger test.
- **live-data claims** — independently re-queried: 0 `free_image_analysis` rows, 0 ledger rows,
  `ai-media-proxy` live at **v21**, all matching the diagnose-doc verbatim.
- **client response-shape safety** — no client reads `gate_reason` / `free_image_*`; the client
  consumes only `data['reply']` (`ai_service.dart:288`), so the new JSON fields are inert.
- **TypeScript read-through** — no orphaned references, no use-before-declaration, no shadowing;
  the `usedSoFar === null` early return narrows correctly for the later comparison.

## Founder triage notes

All three accepted and fixed in-batch; none deferred. Verdict `accepted`.
